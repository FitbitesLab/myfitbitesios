import AudioToolbox
import SpriteKit
import SwiftUI
import UIKit

struct FlappyTielGameCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var bestScore = UserDefaults.standard.integer(forKey: "FlappyTielBestScore")
    @State private var completionMessage: String?
    @State private var hasSubmittedDailyReward = false
    let onBack: () -> Void

    private let dailyIdentifier = "flappy_tiel"
    private let rewardScore = 5

    private var dailyRewardAmount: Int {
        appState.tooLabProgress.dailyGameXP
    }

    private var hasClaimedDailyReward: Bool {
        appState.tooLabProgress.hasClaimed(game: dailyIdentifier) || hasSubmittedDailyReward
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
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
            .ignoresSafeArea()

            VStack(alignment: .leading) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))

                        Text("Back")
                            .font(.custom("AvenirNext-DemiBold", size: 13))
                    }
                    .foregroundStyle(FBColors.charcoal)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.white.opacity(0.86), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.68)))
                }
                .buttonStyle(.plain)

                Spacer()

                if let completionMessage {
                    Text(completionMessage)
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(FBColors.charcoal)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.86), in: Capsule())
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
    private let introOverlay = SKNode()
    private let gameOverOverlay = SKNode()
    private let finalScoreLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
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
            startGame()
            flap()
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
        addIntroOverlay()
        addGameOverOverlay()
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
        ground.fillColor = .clear
        ground.strokeColor = .clear
        ground.position = CGPoint(x: size.width / 2, y: groundHeight / 2)
        ground.zPosition = 5
        ground.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: groundHeight))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = PhysicsCategory.world
        addChild(ground)

        let grassHeight: CGFloat = 92
        let tileWidth = grassHeight * 3
        let tileCount = Int(ceil(size.width / tileWidth)) + 2
        let grassLayer = SKNode()
        grassLayer.zPosition = 24
        addChild(grassLayer)

        for index in 0..<tileCount {
            let grass = SKSpriteNode(imageNamed: "FlappyTielGrass")
            grass.anchorPoint = CGPoint(x: 0, y: 0)
            grass.size = CGSize(width: tileWidth, height: grassHeight)
            grass.position = CGPoint(x: CGFloat(index) * tileWidth, y: 0)
            grassLayer.addChild(grass)
        }

        let obstacleSpeed = (size.width + 62 * 2) / 4.3
        grassLayer.run(.repeatForever(.sequence([
            .moveBy(x: -tileWidth, y: 0, duration: TimeInterval(tileWidth / obstacleSpeed)),
            .moveBy(x: tileWidth, y: 0, duration: 0)
        ])))
    }

    private func addTiel() {
        tiel.removeAllChildren()
        tiel.position = CGPoint(x: size.width * 0.3, y: size.height * 0.56)
        tiel.zPosition = 20

        let bird = SKSpriteNode(imageNamed: "FlappyTielBird")
        bird.size = CGSize(width: 60, height: 44)
        bird.anchorPoint = CGPoint(x: 0.52, y: 0.5)
        bird.zPosition = 1
        tiel.addChild(bird)
        addChild(tiel)
    }

    private func addHud() {
        scoreLabel.fontSize = 24
        scoreLabel.fontColor = UIColor(red: 0.15, green: 0.12, blue: 0.1, alpha: 1)
        scoreLabel.text = "0"
        scoreLabel.position = CGPoint(x: 22, y: size.height - 88)
        scoreLabel.zPosition = 1000
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        addChild(scoreLabel)

        messageLabel.fontSize = 18
        messageLabel.fontColor = .white
        messageLabel.text = ""
        messageLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.5)
        messageLabel.zPosition = 1000
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        messageLabel.isHidden = true
        addChild(messageLabel)
    }

    private func addIntroOverlay() {
        introOverlay.removeAllChildren()
        introOverlay.zPosition = 900

        let artwork = fullScreenSprite(imageNamed: "FlappyTielIntro")
        artwork.zPosition = 0
        introOverlay.addChild(artwork)

        let button = callToActionButton(title: "TAP TO PLAY")
        button.position = CGPoint(x: size.width / 2, y: max(78, size.height * 0.17))
        button.zPosition = 3
        introOverlay.addChild(button)

        addChild(introOverlay)
    }

    private func addGameOverOverlay() {
        gameOverOverlay.removeAllChildren()
        gameOverOverlay.zPosition = 950

        let artwork = fullScreenSprite(imageNamed: "FlappyTielGameOver")
        artwork.zPosition = 0
        gameOverOverlay.addChild(artwork)

        finalScoreLabel.fontSize = 24
        finalScoreLabel.fontColor = .white
        finalScoreLabel.horizontalAlignmentMode = .center
        finalScoreLabel.verticalAlignmentMode = .center
        finalScoreLabel.position = CGPoint(x: size.width / 2, y: max(118, size.height * 0.25))
        finalScoreLabel.zPosition = 3
        finalScoreLabel.text = "SCORE 0"
        gameOverOverlay.addChild(finalScoreLabel)

        let button = callToActionButton(title: "TRY AGAIN")
        button.position = CGPoint(x: size.width / 2, y: max(70, size.height * 0.15))
        button.zPosition = 3
        gameOverOverlay.addChild(button)

        gameOverOverlay.isHidden = true
        addChild(gameOverOverlay)
    }

    private func fullScreenSprite(imageNamed: String) -> SKSpriteNode {
        let texture = SKTexture(imageNamed: imageNamed)
        let sprite = SKSpriteNode(texture: texture)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.size = aspectFillSize(for: texture.size(), in: size)
        return sprite
    }

    private func aspectFillSize(for imageSize: CGSize, in targetSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, targetSize.width > 0, targetSize.height > 0 else {
            return targetSize
        }

        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func callToActionButton(title: String) -> SKNode {
        let node = SKNode()
        let buttonSize = CGSize(width: min(size.width - 72, 230), height: 54)
        let shape = SKShapeNode(rectOf: buttonSize, cornerRadius: 27)
        shape.fillColor = UIColor(red: 1.0, green: 0.83, blue: 0.26, alpha: 1)
        shape.strokeColor = UIColor(red: 0.47, green: 0.22, blue: 0.08, alpha: 1)
        shape.lineWidth = 4
        shape.zPosition = 0
        node.addChild(shape)

        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = title
        label.fontSize = 20
        label.fontColor = UIColor(red: 0.28, green: 0.12, blue: 0.04, alpha: 1)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -1)
        label.zPosition = 1
        node.addChild(label)

        return node
    }

    private func startGame() {
        gameState = .running
        messageLabel.text = ""
        introOverlay.isHidden = true
        gameOverOverlay.isHidden = true
        scoreLabel.isHidden = false
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
        scoreLabel.isHidden = true
        messageLabel.text = ""
        messageLabel.isHidden = true
        introOverlay.isHidden = false
        gameOverOverlay.isHidden = true
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
        messageLabel.text = ""
        scoreLabel.isHidden = true
        finalScoreLabel.text = "SCORE \(score)"
        gameOverOverlay.isHidden = false
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
        let bottomHeight = max(60, gapCenterY - gapHeight / 2)
        let startX = size.width + pipeWidth

        let pair = SKNode()
        pair.name = "obstacle"
        pair.zPosition = 10
        pair.position = CGPoint(x: startX, y: 0)

        let topPipe = pipe(height: topHeight, width: pipeWidth, position: .top)
        topPipe.position = CGPoint(x: 0, y: size.height - topHeight / 2)

        let bottomPipe = pipe(height: bottomHeight, width: pipeWidth, position: .bottom)
        bottomPipe.position = CGPoint(x: 0, y: bottomHeight / 2)

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
        let capHeight = width * (574.0 / 713.0)
        let bodyOverlap: CGFloat = 1
        let bodyHeight = max(height - capHeight + bodyOverlap, 1)
        let collisionWidth = width * 0.98

        let body = SKSpriteNode(imageNamed: "FlappyTielPipeBlueBody")
        body.size = CGSize(width: width, height: bodyHeight)
        body.zPosition = 0

        let cap = SKSpriteNode(imageNamed: "FlappyTielPipeBlueCapDown")
        cap.size = CGSize(width: width, height: capHeight)
        cap.zPosition = 1

        switch position {
        case .top:
            cap.position = CGPoint(x: 0, y: -height / 2 + capHeight / 2)
            body.position = CGPoint(x: 0, y: cap.position.y + capHeight / 2 - bodyOverlap + bodyHeight / 2)
        case .bottom:
            cap.position = CGPoint(x: 0, y: height / 2 - capHeight / 2)
            cap.yScale *= -1
            body.position = CGPoint(x: 0, y: cap.position.y - capHeight / 2 + bodyOverlap - bodyHeight / 2)
        }

        node.addChild(body)
        node.addChild(cap)

        node.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: collisionWidth, height: height))
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        node.physicsBody?.contactTestBitMask = PhysicsCategory.tiel
        node.physicsBody?.collisionBitMask = PhysicsCategory.tiel
        return node
    }
}
