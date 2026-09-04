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
        let sky = SKSpriteNode(imageNamed: "FlappyTielSky")
        sky.size = size
        sky.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -10
        addChild(sky)

        let cloudRows: [(height: CGFloat, scale: CGFloat, offset: CGFloat, speed: CGFloat)] = [
            (0.85, 0.82, 0, 18),
            (0.73, 0.64, 0.46, 14),
            (0.61, 0.58, 0.22, 16),
            (0.48, 0.42, 0.68, 12)
        ]

        for index in 0..<8 {
            let row = cloudRows[index % cloudRows.count]
            let column = CGFloat(index / cloudRows.count)
            addCloud(
                at: CGPoint(
                    x: size.width * (row.offset + column * 0.62),
                    y: size.height * row.height
                ),
                scale: row.scale,
                speed: row.speed
            )
        }
    }

    private func addCloud(at position: CGPoint, scale: CGFloat, speed: CGFloat) {
        let cloud = SKSpriteNode(imageNamed: "FlappyTielCloud")
        cloud.position = position
        cloud.zPosition = -4
        cloud.alpha = 0.82
        cloud.size = CGSize(width: 190 * scale, height: 80 * scale)
        addChild(cloud)

        let leftEdge = -cloud.size.width / 2 - 60
        let rightEdge = size.width + cloud.size.width / 2 + 60
        let firstDistance = max(cloud.position.x - leftEdge, 1)
        let loopDistance = rightEdge - leftEdge
        let pointsPerSecond = max(speed, 1)

        cloud.run(.sequence([
            .moveTo(x: leftEdge, duration: TimeInterval(firstDistance / pointsPerSecond)),
            .repeatForever(.sequence([
                .run { cloud.position.x = rightEdge },
                .moveTo(x: leftEdge, duration: TimeInterval(loopDistance / pointsPerSecond))
            ]))
        ]))
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

        let bird = SKSpriteNode(imageNamed: "FlappyTielBird")
        bird.size = CGSize(width: 60, height: 44)
        bird.anchorPoint = CGPoint(x: 0.52, y: 0.5)
        bird.zPosition = 1
        tiel.addChild(bird)
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

        let topPipe = pipe(height: topHeight, width: pipeWidth, position: .top)
        topPipe.position = CGPoint(x: 0, y: size.height - topHeight / 2)

        let bottomPipe = pipe(height: bottomHeight, width: pipeWidth, position: .bottom)
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

    private enum PipePosition {
        case top
        case bottom
    }

    private func pipe(height: CGFloat, width: CGFloat, position: PipePosition) -> SKNode {
        let node = SKNode()
        let lidHeight = min(max(height * 0.32, 52), 74)
        let shaftHeight = max(height - lidHeight + 12, 24)
        let isTopPipe = position == .top
        let texture = SKTexture(imageNamed: isTopPipe ? "FlappyTielPipeBlue" : "FlappyTielPipeGreen")
        let shaftRect = position == .top
            ? CGRect(x: 0, y: 0.25, width: 1, height: 0.75)
            : CGRect(x: 0, y: 0, width: 1, height: 0.75)
        let lidRect = position == .top
            ? CGRect(x: 0, y: 0, width: 1, height: 0.25)
            : CGRect(x: 0, y: 0.75, width: 1, height: 0.25)
        let shaftVisibleRatio: CGFloat = isTopPipe ? 328 / 724 : 303 / 724
        let lidVisibleRatio: CGFloat = isTopPipe ? 588 / 724 : 498 / 724
        let shaftHitboxWidth = width * 0.44
        let lidHitboxWidth = width + 4

        let shaft = SKSpriteNode(texture: SKTexture(rect: shaftRect, in: texture))
        shaft.size = CGSize(width: shaftHitboxWidth / shaftVisibleRatio, height: shaftHeight)
        shaft.position = CGPoint(
            x: 0,
            y: position == .top ? height / 2 - shaftHeight / 2 : -height / 2 + shaftHeight / 2
        )
        shaft.zPosition = 1

        let lid = SKSpriteNode(texture: SKTexture(rect: lidRect, in: texture))
        lid.size = CGSize(width: lidHitboxWidth / lidVisibleRatio, height: lidHeight)
        lid.position = CGPoint(
            x: 0,
            y: position == .top ? -height / 2 + lidHeight / 2 : height / 2 - lidHeight / 2
        )
        lid.zPosition = 2

        node.addChild(shaft)
        node.addChild(lid)

        let shaftBody = SKPhysicsBody(rectangleOf: CGSize(width: shaftHitboxWidth, height: shaftHeight), center: shaft.position)
        let lidBody = SKPhysicsBody(rectangleOf: CGSize(width: lidHitboxWidth, height: lidHeight), center: lid.position)
        node.physicsBody = SKPhysicsBody(bodies: [shaftBody, lidBody])
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        node.physicsBody?.contactTestBitMask = PhysicsCategory.tiel
        node.physicsBody?.collisionBitMask = PhysicsCategory.tiel
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
