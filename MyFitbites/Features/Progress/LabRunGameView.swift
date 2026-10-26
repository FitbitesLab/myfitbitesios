import AudioToolbox
import SpriteKit
import SwiftUI
import UIKit

struct LabRunGameCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var bestScore = UserDefaults.standard.integer(forKey: "LabRunBestScore")
    @State private var completionMessage: String?
    @State private var hasSubmittedDailyReward = false
    let onBack: () -> Void

    private let dailyIdentifier = "lab_run"
    private let rewardScore = 18

    private var dailyRewardAmount: Int {
        appState.tooLabProgress.dailyGameXP
    }

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: dailyIdentifier) || hasSubmittedDailyReward
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LabRunSpriteView(
                rewardScore: rewardScore,
                onScoreChanged: { score in
                    if score > bestScore {
                        bestScore = score
                        UserDefaults.standard.set(score, forKey: "LabRunBestScore")
                    }
                },
                onRewardReached: { score in
                    guard !hasClaimedDailyReward else {
                        completionMessage = "Daily reward already claimed."
                        return
                    }

                    hasSubmittedDailyReward = true
                    completionMessage = "Score \(score). Claiming LXP..."

                    Task {
                        let awarded = await appState.completeTooLabGame(identifier: dailyIdentifier, score: score)
                        completionMessage = awarded > 0 ? "Score \(score). Daily +\(awarded) LXP awarded." : "Daily reward already claimed."
                    }
                }
            )
            .ignoresSafeArea()

            VStack(alignment: .leading) {
                HStack {
                    LabArcadeBackButton(onBack: onBack)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("BEST")
                            .font(.custom("AvenirNext-DemiBold", size: 9))
                            .tracking(1.1)
                        Text("\(bestScore)")
                            .font(.custom("AvenirNext-DemiBold", size: 17))
                    }
                    .foregroundStyle(FBColors.charcoal)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(.white.opacity(0.88), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.68)))
                }

                Spacer()

                if let completionMessage {
                    Text(completionMessage)
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.88), in: Capsule())
                } else {
                    Text(hasClaimedDailyReward ? "Daily reward claimed" : "+\(dailyRewardAmount) LXP at \(rewardScore)")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(FBColors.charcoal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.78), in: Capsule())
                }
            }
            .padding(.top, 54)
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

private struct LabRunSpriteView: UIViewRepresentable {
    let rewardScore: Int
    let onScoreChanged: (Int) -> Void
    let onRewardReached: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScoreChanged: onScoreChanged, onRewardReached: onRewardReached)
    }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.backgroundColor = .clear
        view.allowsTransparency = false
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if let scene = view.scene as? LabRunScene {
            scene.rewardScore = rewardScore
            scene.onScoreChanged = context.coordinator.onScoreChanged
            scene.onRewardReached = context.coordinator.handleRewardReached
            return
        }

        let scene = LabRunScene(size: view.bounds.size == .zero ? CGSize(width: 390, height: 720) : view.bounds.size)
        scene.scaleMode = .resizeFill
        scene.rewardScore = rewardScore
        scene.onScoreChanged = context.coordinator.onScoreChanged
        scene.onRewardReached = context.coordinator.handleRewardReached
        view.presentScene(scene)
    }

    final class Coordinator {
        let onScoreChanged: (Int) -> Void
        let onRewardReached: (Int) -> Void
        private var hasReportedReward = false

        init(onScoreChanged: @escaping (Int) -> Void, onRewardReached: @escaping (Int) -> Void) {
            self.onScoreChanged = onScoreChanged
            self.onRewardReached = onRewardReached
        }

        func handleRewardReached(_ score: Int) {
            guard !hasReportedReward else { return }
            hasReportedReward = true
            onRewardReached(score)
        }
    }
}

private final class LabRunScene: SKScene, SKPhysicsContactDelegate {
    var rewardScore = 18
    var onScoreChanged: ((Int) -> Void)?
    var onRewardReached: ((Int) -> Void)?

    private let runner = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let instructionLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let overlayNode = SKNode()
    private var laneIndex = 1
    private var score = 0
    private var lastSpawnTime: TimeInterval = 0
    private var gameState: GameState = .ready
    private var didReachReward = false
    private var spawnInterval: TimeInterval = 0.92
    private var worldSpeed: CGFloat = 270

    private enum GameState {
        case ready
        case running
        case gameOver
    }

    private enum PhysicsCategory {
        static let runner: UInt32 = 1 << 0
        static let obstacle: UInt32 = 1 << 1
        static let treat: UInt32 = 1 << 2
    }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        setupWorld()
        resetGame()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        removeAllActions()
        setupWorld()
        resetGame()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch gameState {
        case .ready:
            startGame()
        case .running:
            jump()
        case .gameOver:
            resetGame()
            startGame()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard gameState == .running else { return }

        if currentTime - lastSpawnTime > spawnInterval {
            spawnRow()
            lastSpawnTime = currentTime
            spawnInterval = max(0.54, spawnInterval - 0.01)
            worldSpeed = min(430, worldSpeed + 2)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if categories & PhysicsCategory.treat != 0, categories & PhysicsCategory.runner != 0 {
            let treatBody = contact.bodyA.categoryBitMask == PhysicsCategory.treat ? contact.bodyA : contact.bodyB
            treatBody.categoryBitMask = 0
            treatBody.node?.removeFromParent()
            score += 1
            scoreLabel.text = "\(score)"
            onScoreChanged?(score)
            LabArcadeSound.playMatch()

            if score >= rewardScore, !didReachReward {
                didReachReward = true
                onRewardReached?(score)
            }
            return
        }

        if categories & PhysicsCategory.obstacle != 0, categories & PhysicsCategory.runner != 0 {
            endGame()
        }
    }

    private func setupWorld() {
        removeAllChildren()
        backgroundColor = UIColor(red: 0.09, green: 0.06, blue: 0.15, alpha: 1)
        addBackground()
        addTrack()
        addRunner()
        addHud()
        addOverlay()
        addGestures()
    }

    private func addBackground() {
        let gradient = SKSpriteNode(color: UIColor(red: 0.16, green: 0.08, blue: 0.28, alpha: 1), size: size)
        gradient.position = CGPoint(x: size.width / 2, y: size.height / 2)
        gradient.zPosition = -20
        addChild(gradient)

        let hero = SKSpriteNode(imageNamed: "TooLabHero")
        hero.size = aspectFillSize(for: hero.texture?.size() ?? size, in: size)
        hero.position = CGPoint(x: size.width / 2, y: size.height / 2)
        hero.alpha = 0.2
        hero.zPosition = -18
        addChild(hero)
    }

    private func addTrack() {
        let trackWidth = min(size.width * 0.78, 360)
        let track = SKShapeNode(rectOf: CGSize(width: trackWidth, height: size.height + 80), cornerRadius: 28)
        track.fillColor = UIColor(red: 0.97, green: 0.91, blue: 0.78, alpha: 0.96)
        track.strokeColor = UIColor.white.withAlphaComponent(0.62)
        track.lineWidth = 2
        track.position = CGPoint(x: size.width / 2, y: size.height / 2)
        track.zPosition = -8
        addChild(track)

        for lane in 0..<3 {
            let x = laneX(lane)
            let stripe = SKShapeNode(rectOf: CGSize(width: 4, height: size.height + 80), cornerRadius: 2)
            stripe.fillColor = UIColor(red: 0.48, green: 0.21, blue: 0.62, alpha: lane == 1 ? 0.26 : 0.16)
            stripe.strokeColor = .clear
            stripe.position = CGPoint(x: x, y: size.height / 2)
            stripe.zPosition = -6
            addChild(stripe)
        }

        for index in 0..<9 {
            addMovingDash(y: CGFloat(index) * 118)
        }
    }

    private func addMovingDash(y: CGFloat) {
        let dash = SKShapeNode(rectOf: CGSize(width: 88, height: 10), cornerRadius: 5)
        dash.fillColor = UIColor.white.withAlphaComponent(0.42)
        dash.strokeColor = .clear
        dash.position = CGPoint(x: size.width / 2, y: y)
        dash.zPosition = -5
        addChild(dash)

        let distance = size.height + 160
        dash.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: -distance, duration: TimeInterval(distance / 190)),
            .run { dash.position.y += distance }
        ])))
    }

    private func addRunner() {
        runner.removeAllChildren()
        runner.position = CGPoint(x: laneX(laneIndex), y: runnerY)
        runner.zPosition = 20

        let too = SKSpriteNode(imageNamed: "AvatarToo")
        too.size = CGSize(width: 76, height: 76)
        too.position = CGPoint(x: -14, y: 4)
        too.zPosition = 2
        runner.addChild(too)

        let tiel = SKSpriteNode(imageNamed: "AvatarTiel")
        tiel.size = CGSize(width: 48, height: 48)
        tiel.position = CGPoint(x: 32, y: 22)
        tiel.zPosition = 3
        runner.addChild(tiel)

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 74, height: 18))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.18)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -38)
        shadow.zPosition = 0
        runner.addChild(shadow)

        runner.physicsBody = SKPhysicsBody(circleOfRadius: 28)
        runner.physicsBody?.isDynamic = true
        runner.physicsBody?.affectedByGravity = false
        runner.physicsBody?.allowsRotation = false
        runner.physicsBody?.categoryBitMask = PhysicsCategory.runner
        runner.physicsBody?.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.treat
        runner.physicsBody?.collisionBitMask = 0
        addChild(runner)
    }

    private func addHud() {
        scoreLabel.fontSize = 25
        scoreLabel.fontColor = UIColor.white
        scoreLabel.text = "0"
        scoreLabel.position = CGPoint(x: 22, y: size.height - 88)
        scoreLabel.zPosition = 1000
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        addChild(scoreLabel)

        instructionLabel.fontSize = 14
        instructionLabel.fontColor = UIColor.white.withAlphaComponent(0.78)
        instructionLabel.text = "SWIPE LANES · TAP TO HOP"
        instructionLabel.position = CGPoint(x: size.width / 2, y: size.height - 88)
        instructionLabel.zPosition = 1000
        instructionLabel.horizontalAlignmentMode = .center
        instructionLabel.verticalAlignmentMode = .center
        addChild(instructionLabel)
    }

    private func addOverlay() {
        overlayNode.removeAllChildren()
        overlayNode.zPosition = 900

        let plate = SKShapeNode(rectOf: CGSize(width: min(size.width - 48, 312), height: 178), cornerRadius: 26)
        plate.fillColor = UIColor.white.withAlphaComponent(0.92)
        plate.strokeColor = UIColor.white.withAlphaComponent(0.74)
        plate.lineWidth = 2
        plate.position = CGPoint(x: size.width / 2, y: size.height * 0.54)
        overlayNode.addChild(plate)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "TOO & TIEL LAB RUN"
        title.fontSize = 22
        title.fontColor = UIColor(red: 0.16, green: 0.08, blue: 0.21, alpha: 1)
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.57)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        overlayNode.addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        subtitle.text = "Dodge burgers. Collect potions."
        subtitle.fontSize = 14
        subtitle.fontColor = UIColor(red: 0.42, green: 0.38, blue: 0.33, alpha: 1)
        subtitle.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
        subtitle.horizontalAlignmentMode = .center
        subtitle.verticalAlignmentMode = .center
        overlayNode.addChild(subtitle)

        let button = SKShapeNode(rectOf: CGSize(width: 192, height: 46), cornerRadius: 23)
        button.fillColor = UIColor(red: 0.68, green: 0.18, blue: 0.72, alpha: 1)
        button.strokeColor = UIColor.white.withAlphaComponent(0.7)
        button.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        overlayNode.addChild(button)

        let buttonLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        buttonLabel.text = "TAP TO RUN"
        buttonLabel.fontSize = 16
        buttonLabel.fontColor = .white
        buttonLabel.position = button.position
        buttonLabel.horizontalAlignmentMode = .center
        buttonLabel.verticalAlignmentMode = .center
        overlayNode.addChild(buttonLabel)

        addChild(overlayNode)
    }

    private func addGestures() {
        view?.gestureRecognizers?.forEach { recognizer in
            if recognizer.name == "LabRunSwipe" {
                view?.removeGestureRecognizer(recognizer)
            }
        }

        for direction in [UISwipeGestureRecognizer.Direction.left, .right, .up, .down] {
            let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            recognizer.direction = direction
            recognizer.name = "LabRunSwipe"
            view?.addGestureRecognizer(recognizer)
        }
    }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard gameState == .running else { return }

        switch recognizer.direction {
        case .left:
            moveLane(by: -1)
        case .right:
            moveLane(by: 1)
        case .up:
            jump()
        case .down:
            duck()
        default:
            break
        }
    }

    private func startGame() {
        gameState = .running
        overlayNode.isHidden = true
        scoreLabel.text = "0"
        instructionLabel.text = "SWIPE LANES · TAP TO HOP"
        lastSpawnTime = 0
    }

    private func resetGame() {
        gameState = .ready
        score = 0
        didReachReward = false
        laneIndex = 1
        spawnInterval = 0.92
        worldSpeed = 270
        scoreLabel.text = "0"
        instructionLabel.text = "SWIPE LANES · TAP TO HOP"
        overlayNode.isHidden = false
        children
            .filter { $0.name == "hazard" || $0.name == "treat" }
            .forEach { $0.removeFromParent() }
        runner.removeAllActions()
        runner.position = CGPoint(x: laneX(laneIndex), y: runnerY)
        runner.setScale(1)
    }

    private func endGame() {
        guard gameState == .running else { return }
        gameState = .gameOver
        instructionLabel.text = "SCORE \(score) · TAP TO TRY AGAIN"
        overlayNode.isHidden = false
        LabArcadeSound.playReveal()
        children
            .filter { $0.name == "hazard" || $0.name == "treat" }
            .forEach { $0.removeAllActions() }
    }

    private func moveLane(by offset: Int) {
        let nextLane = min(max(laneIndex + offset, 0), 2)
        guard nextLane != laneIndex else { return }
        laneIndex = nextLane
        runner.run(.moveTo(x: laneX(laneIndex), duration: 0.12))
        LabArcadeSound.playBounce()
    }

    private func jump() {
        guard runner.action(forKey: "jump") == nil else { return }
        runner.run(.sequence([
            .group([
                .moveTo(y: runnerY + 92, duration: 0.18),
                .scale(to: 1.08, duration: 0.18)
            ]),
            .group([
                .moveTo(y: runnerY, duration: 0.22),
                .scale(to: 1.0, duration: 0.22)
            ])
        ]), withKey: "jump")
        LabArcadeSound.playBounce()
    }

    private func duck() {
        guard runner.action(forKey: "duck") == nil else { return }
        runner.run(.sequence([
            .scaleX(to: 1.08, y: 0.72, duration: 0.08),
            .wait(forDuration: 0.18),
            .scale(to: 1, duration: 0.1)
        ]), withKey: "duck")
    }

    private func spawnRow() {
        let blockedLane = Int.random(in: 0...2)
        let hasTreat = Bool.random()

        for lane in 0..<3 {
            if lane == blockedLane {
                spawnHazard(in: lane)
            } else if hasTreat, lane != blockedLane, Int.random(in: 0..<100) < 38 {
                spawnTreat(in: lane)
                return
            }
        }
    }

    private func spawnHazard(in lane: Int) {
        let node = SKSpriteNode(imageNamed: Bool.random() ? "ScratchBurger" : "LabMemoryCookie")
        node.name = "hazard"
        node.size = CGSize(width: 58, height: 58)
        node.position = CGPoint(x: laneX(lane), y: size.height + 48)
        node.zPosition = 12
        node.physicsBody = SKPhysicsBody(circleOfRadius: 24)
        node.physicsBody?.isDynamic = true
        node.physicsBody?.affectedByGravity = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        node.physicsBody?.contactTestBitMask = PhysicsCategory.runner
        node.physicsBody?.collisionBitMask = 0
        addChild(node)
        moveWorldNode(node)
    }

    private func spawnTreat(in lane: Int) {
        let node = SKSpriteNode(imageNamed: "LabMemoryPotion")
        node.name = "treat"
        node.size = CGSize(width: 48, height: 48)
        node.position = CGPoint(x: laneX(lane), y: size.height + 48)
        node.zPosition = 13
        node.physicsBody = SKPhysicsBody(circleOfRadius: 20)
        node.physicsBody?.isDynamic = true
        node.physicsBody?.affectedByGravity = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.treat
        node.physicsBody?.contactTestBitMask = PhysicsCategory.runner
        node.physicsBody?.collisionBitMask = 0
        addChild(node)
        node.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.2)))
        moveWorldNode(node)
    }

    private func moveWorldNode(_ node: SKNode) {
        let distance = size.height + 120
        node.run(.sequence([
            .moveBy(x: 0, y: -distance, duration: TimeInterval(distance / worldSpeed)),
            .removeFromParent()
        ]))
    }

    private var runnerY: CGFloat {
        max(112, size.height * 0.18)
    }

    private func laneX(_ lane: Int) -> CGFloat {
        let trackWidth = min(size.width * 0.78, 360)
        let spacing = trackWidth / 3
        return (size.width / 2) - spacing + (CGFloat(lane) * spacing)
    }

    private func aspectFillSize(for imageSize: CGSize, in targetSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, targetSize.width > 0, targetSize.height > 0 else {
            return targetSize
        }

        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
