import AudioToolbox
import SpriteKit
import SwiftUI
import UIKit

struct FlappyTielGameCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var bestScore = UserDefaults.standard.integer(forKey: "FlappyTielBestScore")
    @State private var completionMessage: String?
    @State private var hasSubmittedDailyReward = false

    private let dailyIdentifier = "flappy_tiel"
    private let rewardScore = 5

    private var dailyRewardAmount: Int {
        appState.tooLabProgress.dailyGameXP
    }

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: dailyIdentifier) || hasSubmittedDailyReward
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.purple.opacity(0.82))
                            .frame(width: 16, height: 16)

                        Text("LAB GAME")
                            .font(.custom("AvenirNext-DemiBold", size: 11))
                            .tracking(1.7)
                            .foregroundStyle(FBColors.charcoal)
                    }

                    Text("Flappy Tiel")
                        .font(.custom("AvenirNext-DemiBold", size: 20))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(1)

                    Text("Tap to dodge the lab pipes.")
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(FBColors.muted)
                        .lineLimit(1)
                }

                Spacer()

                Button("Reset") {
                    completionMessage = nil
                    hasSubmittedDailyReward = false
                }
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(Color.purple)
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                LabPuzzleStatPill(title: "Best", value: bestScore > 0 ? "\(bestScore)" : "--")
                LabPuzzleStatPill(title: "Goal", value: "\(rewardScore)")
                LabPuzzleStatPill(title: "Daily", value: hasClaimedDailyReward ? "Claimed" : "+\(dailyRewardAmount) LXP")
            }

            FlappyTielSpriteView(
                rewardScore: rewardScore,
                onScoreChanged: { score in
                    if score > bestScore {
                        bestScore = score
                        UserDefaults.standard.set(score, forKey: "FlappyTielBestScore")
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
            .frame(maxWidth: .infinity)
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(FBColors.line.opacity(0.58)))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)

            if let completionMessage {
                Text(completionMessage)
                    .font(.custom("AvenirNext-Regular", size: 12))
                    .foregroundStyle(FBColors.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(FBSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}

private struct FlappyTielSpriteView: UIViewRepresentable {
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
        if let scene = view.scene as? FlappyTielScene {
            scene.rewardScore = rewardScore
            scene.onScoreChanged = context.coordinator.onScoreChanged
            scene.onRewardReached = context.coordinator.handleRewardReached
            return
        }

        let scene = FlappyTielScene(size: view.bounds.size == .zero ? CGSize(width: 390, height: 520) : view.bounds.size)
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

private final class FlappyTielScene: SKScene, SKPhysicsContactDelegate {
    var rewardScore = 5
    var onScoreChanged: ((Int) -> Void)?
    var onRewardReached: ((Int) -> Void)?

    private let tiel = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let messageLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var score = 0
    private var gameState: GameState = .ready
    private var lastObstacleTime: TimeInterval = 0
    private var didReachReward = false

    private enum GameState {
        case ready
        case running
        case gameOver
    }

    private enum PhysicsCategory {
        static let tiel: UInt32 = 1 << 0
        static let obstacle: UInt32 = 1 << 1
        static let score: UInt32 = 1 << 2
        static let world: UInt32 = 1 << 3
    }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -7.5)
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
            flap()
        case .running:
            flap()
        case .gameOver:
            resetGame()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard gameState == .running else { return }

        if currentTime - lastObstacleTime > 1.55 {
            spawnObstaclePair()
            lastObstacleTime = currentTime
        }

        tiel.zRotation = min(max(tiel.physicsBody?.velocity.dy ?? 0, -380), 260) / 900
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if categories & PhysicsCategory.score != 0, categories & PhysicsCategory.tiel != 0 {
            if contact.bodyA.categoryBitMask == PhysicsCategory.score {
                contact.bodyA.categoryBitMask = 0
                contact.bodyA.node?.removeFromParent()
            } else if contact.bodyB.categoryBitMask == PhysicsCategory.score {
                contact.bodyB.categoryBitMask = 0
                contact.bodyB.node?.removeFromParent()
            }

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

        if categories & PhysicsCategory.tiel != 0 {
            endGame()
        }
    }

    private func setupWorld() {
        removeAllChildren()
        backgroundColor = UIColor(red: 0.51, green: 0.82, blue: 1.0, alpha: 1)
        addSky()
        addGround()
        addTiel()
        addHud()
    }

    private func addSky() {
        let sky = SKShapeNode(rectOf: size)
        sky.fillColor = UIColor(red: 0.51, green: 0.82, blue: 1.0, alpha: 1)
        sky.strokeColor = .clear
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -10
        addChild(sky)

        for index in 0..<7 {
            addCloud(
                at: CGPoint(
                    x: CGFloat(index) * size.width / 3.2 + 40,
                    y: size.height * CGFloat.random(in: 0.58...0.9)
                ),
                scale: CGFloat.random(in: 0.72...1.25)
            )
        }
    }

    private func addCloud(at position: CGPoint, scale: CGFloat) {
        let cloud = SKNode()
        cloud.position = position
        cloud.zPosition = -4

        for offset in [CGPoint(x: -26, y: -2), CGPoint(x: 0, y: 8), CGPoint(x: 28, y: -3)] {
            let puff = SKShapeNode(ellipseOf: CGSize(width: 48, height: 30))
            puff.fillColor = .white
            puff.strokeColor = .clear
            puff.alpha = 0.82
            puff.position = offset
            cloud.addChild(puff)
        }

        cloud.setScale(scale)
        addChild(cloud)

        let travel = size.width + 180
        cloud.run(.repeatForever(.sequence([
            .moveBy(x: -travel, y: 0, duration: TimeInterval(20 / max(scale, 0.5))),
            .moveBy(x: travel, y: 0, duration: 0)
        ])))
    }

    private func addGround() {
        let groundHeight: CGFloat = 46
        let ground = SKShapeNode(rectOf: CGSize(width: size.width, height: groundHeight))
        ground.fillColor = UIColor(red: 0.42, green: 0.76, blue: 0.30, alpha: 1)
        ground.strokeColor = UIColor(red: 0.22, green: 0.58, blue: 0.21, alpha: 1)
        ground.lineWidth = 3
        ground.position = CGPoint(x: size.width / 2, y: groundHeight / 2)
        ground.zPosition = 5
        ground.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: groundHeight))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = PhysicsCategory.world
        addChild(ground)
    }

    private func addTiel() {
        tiel.removeAllChildren()
        tiel.position = CGPoint(x: size.width * 0.3, y: size.height * 0.56)
        tiel.zPosition = 10

        let body = SKShapeNode(ellipseOf: CGSize(width: 44, height: 34))
        body.fillColor = UIColor(red: 1.0, green: 0.89, blue: 0.23, alpha: 1)
        body.strokeColor = UIColor(red: 0.86, green: 0.62, blue: 0.04, alpha: 1)
        body.lineWidth = 2

        let wing = SKShapeNode(ellipseOf: CGSize(width: 22, height: 14))
        wing.fillColor = UIColor(red: 0.18, green: 0.52, blue: 1.0, alpha: 1)
        wing.strokeColor = .clear
        wing.position = CGPoint(x: -6, y: -4)

        let beak = SKShapeNode()
        let beakPath = CGMutablePath()
        beakPath.move(to: CGPoint(x: 20, y: 4))
        beakPath.addLine(to: CGPoint(x: 36, y: 0))
        beakPath.addLine(to: CGPoint(x: 20, y: -6))
        beakPath.closeSubpath()
        beak.path = beakPath
        beak.fillColor = UIColor(red: 0.95, green: 0.39, blue: 0.12, alpha: 1)
        beak.strokeColor = .clear

        let eye = SKShapeNode(circleOfRadius: 4)
        eye.fillColor = .black
        eye.strokeColor = .clear
        eye.position = CGPoint(x: 10, y: 8)

        [body, wing, beak, eye].forEach { tiel.addChild($0) }
        addChild(tiel)
    }

    private func addHud() {
        scoreLabel.fontSize = 42
        scoreLabel.fontColor = .white
        scoreLabel.text = "0"
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 82)
        scoreLabel.zPosition = 30
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.shadowed()
        addChild(scoreLabel)

        messageLabel.fontSize = 18
        messageLabel.fontColor = .white
        messageLabel.text = "Tap to fly"
        messageLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.5)
        messageLabel.zPosition = 30
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        messageLabel.shadowed()
        addChild(messageLabel)
    }

    private func startGame() {
        gameState = .running
        messageLabel.text = ""
        lastObstacleTime = 0
        tiel.physicsBody?.isDynamic = true
    }

    private func flap() {
        tiel.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
        tiel.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 15.5))
        LabArcadeSound.playBounce()
    }

    private func resetGame() {
        gameState = .ready
        score = 0
        didReachReward = false
        scoreLabel.text = "0"
        messageLabel.text = "Tap to fly"
        children
            .filter { $0.name == "obstacle" }
            .forEach { $0.removeFromParent() }

        tiel.position = CGPoint(x: size.width * 0.3, y: size.height * 0.56)
        tiel.zRotation = 0
        tiel.physicsBody = SKPhysicsBody(circleOfRadius: 18)
        tiel.physicsBody?.allowsRotation = false
        tiel.physicsBody?.isDynamic = false
        tiel.physicsBody?.categoryBitMask = PhysicsCategory.tiel
        tiel.physicsBody?.contactTestBitMask = PhysicsCategory.obstacle | PhysicsCategory.score | PhysicsCategory.world
        tiel.physicsBody?.collisionBitMask = PhysicsCategory.obstacle | PhysicsCategory.world
    }

    private func endGame() {
        guard gameState == .running else { return }
        gameState = .gameOver
        messageLabel.text = "Score \(score). Tap again."
        LabArcadeSound.playReveal()

        children
            .filter { $0.name == "obstacle" }
            .forEach { $0.removeAllActions() }
    }

    private func spawnObstaclePair() {
        let gapHeight: CGFloat = 150
        let pipeWidth: CGFloat = 62
        let minGapY = size.height * 0.34
        let maxGapY = size.height * 0.78
        let gapCenterY = CGFloat.random(in: minGapY...maxGapY)
        let topHeight = max(40, size.height - gapCenterY - gapHeight / 2)
        let bottomHeight = max(60, gapCenterY - gapHeight / 2 - 46)
        let startX = size.width + pipeWidth

        let pair = SKNode()
        pair.name = "obstacle"
        pair.zPosition = 6
        pair.position = CGPoint(x: startX, y: 0)

        let topPipe = pipe(height: topHeight, width: pipeWidth, color: UIColor(red: 0.16, green: 0.55, blue: 0.96, alpha: 1))
        topPipe.position = CGPoint(x: 0, y: size.height - topHeight / 2)

        let bottomPipe = pipe(height: bottomHeight, width: pipeWidth, color: UIColor(red: 0.20, green: 0.70, blue: 0.28, alpha: 1))
        bottomPipe.position = CGPoint(x: 0, y: 46 + bottomHeight / 2)

        let scoreGate = SKNode()
        scoreGate.position = CGPoint(x: pipeWidth / 2 + 20, y: size.height / 2)
        scoreGate.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 8, height: size.height))
        scoreGate.physicsBody?.isDynamic = false
        scoreGate.physicsBody?.categoryBitMask = PhysicsCategory.score
        scoreGate.physicsBody?.contactTestBitMask = PhysicsCategory.tiel
        scoreGate.physicsBody?.collisionBitMask = 0

        pair.addChild(topPipe)
        pair.addChild(bottomPipe)
        pair.addChild(scoreGate)
        addChild(pair)

        pair.run(.sequence([
            .moveBy(x: -(size.width + pipeWidth * 2), y: 0, duration: 4.3),
            .removeFromParent()
        ]))
    }

    private func pipe(height: CGFloat, width: CGFloat, color: UIColor) -> SKNode {
        let node = SKNode()
        let body = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 10)
        body.fillColor = color
        body.strokeColor = UIColor.white.withAlphaComponent(0.35)
        body.lineWidth = 2
        body.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: width, height: height))
        body.physicsBody?.isDynamic = false
        body.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        body.physicsBody?.contactTestBitMask = PhysicsCategory.tiel
        body.physicsBody?.collisionBitMask = PhysicsCategory.tiel

        let cap = SKShapeNode(rectOf: CGSize(width: width + 16, height: 24), cornerRadius: 8)
        cap.fillColor = color
        cap.strokeColor = UIColor.white.withAlphaComponent(0.38)
        cap.lineWidth = 2
        cap.position = CGPoint(x: 0, y: height / 2 - 12)

        node.addChild(body)
        node.addChild(cap)
        return node
    }
}

private extension SKLabelNode {
    func shadowed() {
        let shadow = SKLabelNode(fontNamed: fontName)
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = UIColor.black.withAlphaComponent(0.22)
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        addChild(shadow)
    }
}
