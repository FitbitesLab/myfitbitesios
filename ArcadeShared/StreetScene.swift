import SpriteKit
import UIKit

@MainActor
final class StreetScene: SKScene {
    private var encounter = ArenaEncounter()
    private(set) var stageNumber = 1
    var onEncounter: ((Int, Int, Bool) -> Void)?
    private var lastEncounterState = ""
    private let background = SKSpriteNode(imageNamed: "neighborhood-panorama")
    private var stageCleared: Bool { enemies.allSatisfy { $0.spawned && $0.health.defeated } }
    private var nado = TooNado()
    private var legCombo = TooLegCombo()
    var onKickReady: ((Bool) -> Void)?
    private var lastKickReady = false
    private var canKick: Bool { ready && !lineup && !isPaused && lift == 0 && !damage.locked(at: time) && !legCombo.locked(at: time) && !combat.locked(at: time) && !weaponCombo.locked(at: time) && !nado.locked(at: time) }

    private let nadoWind = SKSpriteNode(imageNamed: "too-nado-wind")
    var onHeavyReady: ((Bool) -> Void)?
    private var lastHeavyReady = false
    private var canHeavy: Bool { !legCombo.locked(at: time) && ready && !lineup && !isPaused && lift == 0 && !damage.locked(at: time) && !combat.locked(at: time) && !weaponCombo.locked(at: time) && !nado.locked(at: time) }
    var viewport: CGSize = .zero
    var onScore: ((Int) -> Void)?
    var onLineup: ((Bool) -> Void)?
    var onHealth: ((Int) -> Void)?
    var onSpatula: ((Bool, Bool, Bool) -> Void)?
    private var carryingSpatula = false
    private let spatula = SKSpriteNode(imageNamed: "spatula-pickup-trimmed")
    private let spatulaShadow = SKShapeNode(ellipseOf: CGSize(width: 70, height: 10))
    private var lastSpatulaState = ""
    private var canUseItem: Bool { !legCombo.locked(at: time) && !nado.active(at: time) && ready && !lineup && !isPaused && lift == 0 && !damage.locked(at: time) && !combat.locked(at: time) && !weaponCombo.locked(at: time) }
    private var canPickUp: Bool { canUseItem && !carryingSpatula && abs(too.position.x - spatula.position.x) <= 78 }
    var showHitboxes = false
    private let boxOverlay = SKNode()
    private final class Enemy {
        let kind: KitchenEnemyKind
        var ranged = KitchenRangedAttack()
        var moving = false
        var spawned = false
        var entering = false
        init(kind: KitchenEnemyKind = .goblin) { self.kind = kind }
        let sprite = SKSpriteNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 62, height: 12))
        let warning = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        let meter = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        var health = GoblinHealth()
        var attack = GoblinAttack()
        var hitUntil: TimeInterval = 0
        var hitStarted: TimeInterval = -.infinity
        var animationKey = ""
    }
    static let enemyCount = ArenaEncounter.count
    private let enemies = (0..<StreetScene.enemyCount).map { Enemy(kind: ArenaEncounter.kind(at: $0)) }
    private struct Projectile {
        let node: SKSpriteNode
        let motion: KitchenProjectileMotion
        let born: TimeInterval
        let heavy: Bool
        let radius: CGFloat
    }
    private var projectiles: [Projectile] = []
    var onDefeated: ((Int) -> Void)?
    private var warning: SKLabelNode { enemies[0].warning }
    private var damage = TooDamage()
    private var enemyAttack: GoblinAttack { get { enemies[0].attack } set { enemies[0].attack = newValue } }
    var left = false
    var right = false
    private let assets = SpriteAssets()
    private let world = SKNode()
    private let too = SKSpriteNode()
    private var goblin: SKSpriteNode { enemies[0].sprite }
    private let tooShadow = SKShapeNode(ellipseOf: CGSize(width: 78, height: 15))
    private var goblinShadow: SKShapeNode { enemies[0].shadow }
    private let labels = SKNode()
    private var lastTime: TimeInterval = 0
    private var time: TimeInterval = 0
    private var jumpStartedAt: TimeInterval = -.infinity
    private var landedUntil: TimeInterval = 0
    private var jumpMotion = JumpMotion()
    private var lift: CGFloat { jumpMotion.height }
    private var facing: CGFloat = 1
    private var weaponCombo = SpatulaCombo()
    var onWeaponReady: ((Bool) -> Void)?
    private var lastWeaponReady = true
    private var combat = ArcadeCombo()
    private var renderedAttack = 0
    private var hitUntil: TimeInterval { get { enemies[0].hitUntil } set { enemies[0].hitUntil = newValue } }
    private var scoredAttack = false
    private var score = 0
    private var lineup = false
    private var animationKey = ""
    private var enemyKey: String { get { enemies[0].animationKey } set { enemies[0].animationKey = newValue } }
    private var ready = false
    private var smokeStart: TimeInterval?
    private var smokeStages = Set<Int>()
    private var smokeResults: [String: Bool] = [:]
    private var startX: CGFloat = 0
    private let floorY: CGFloat = 112
    private var logicalWidth: CGFloat { max(720, size.width / max(size.height, 1) * 540) }
    private let backgroundHeight: CGFloat = 1400 * 941 / 1672
    private var blockWidth: CGFloat { backgroundHeight * 2172 / 724 }
    private var worldWidth: CGFloat { logicalWidth }

    override func didMove(to view: SKView) {
        guard !ready else { return }
        ready = true
        view.isMultipleTouchEnabled = true
        view.contentScaleFactor = view.window?.screen.scale ?? UIScreen.main.scale
        backgroundColor = .black
        addChild(world)
        background.texture?.filteringMode = .linear
        background.anchorPoint = .zero
        background.name = "arena-background"
        background.zPosition = -20
        world.addChild(background)
        for shadow in [tooShadow] + enemies.map(\.shadow) {
            shadow.fillColor = .black.withAlphaComponent(0.28)
            shadow.strokeColor = .clear
            shadow.zPosition = 1
            world.addChild(shadow)
        }
        for sprite in [too] + enemies.map(\.sprite) {
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            sprite.zPosition = 2
            world.addChild(sprite)
        }
        for enemy in enemies {
            enemy.warning.zPosition = 10; enemy.warning.fontSize = 28
            world.addChild(enemy.warning)
            enemy.meter.zPosition = 9; enemy.meter.fontSize = 12
            enemy.meter.fontColor = .init(red: 0.65, green: 1, blue: 0.35, alpha: 1)
            world.addChild(enemy.meter)
        }
        spatula.texture?.filteringMode = .linear
        let itemSize = spatula.texture!.size()
        spatula.size = CGSize(width: 76, height: 76 * itemSize.height / itemSize.width)
        spatula.anchorPoint = CGPoint(x: 0.5, y: 0)
        spatula.zPosition = 1.5
        world.addChild(spatula)
        spatulaShadow.fillColor = .black.withAlphaComponent(0.25)
        spatulaShadow.strokeColor = .clear
        spatulaShadow.zPosition = 1
        world.addChild(spatulaShadow)
        nadoWind.texture?.filteringMode = .linear
        nadoWind.size = CGSize(width: 310, height: 220)
        nadoWind.zPosition = 3
        nadoWind.isHidden = true
        world.addChild(nadoWind)
        labels.zPosition = 5
        world.addChild(labels)
        boxOverlay.zPosition = 30; world.addChild(boxOverlay)
        layoutWorld()
        reset()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--leg-combo-preview") {
            run(.sequence([.wait(forDuration: 0.2),.run { [weak self] in self?.verifyLegCombo() }]))
        }
        if ProcessInfo.processInfo.arguments.contains("--kitchen-hit-preview") {
            run(.sequence([.wait(forDuration: 0.2),.run { [weak self] in self?.verifyKitchenHits() }]))
        }
        if ProcessInfo.processInfo.arguments.contains("--arena-clear-preview") {
            for enemy in enemies { enemy.spawned = true; for _ in 0..<9 { enemy.health.receive() } }
            updateEncounter(); updateCharacters()
        }
        if ProcessInfo.processInfo.arguments.contains("--nado-preview") {
            heavyAttack(); time = nado.started + 0.43
            updateCharacters(); isPaused = true
        }
        if ProcessInfo.processInfo.arguments.contains("--combo-size-preview") {
            pickUpSpatula()
            weaponCombo.press(at: 0)
            weaponCombo.markHit(0)
            weaponCombo.press(at: 0.51 * SpatulaCombo.timingScale)
            weaponCombo.markHit(1)
            weaponCombo.press(at: 1.02 * SpatulaCombo.timingScale)
            time = 1.46 * SpatulaCombo.timingScale
            updateCharacters()
            isPaused = true
        }
        if ProcessInfo.processInfo.arguments.contains("--armed-idle-preview") {
            pickUpSpatula()
        }
        if ProcessInfo.processInfo.arguments.contains("--armed-walk-preview") {
            pickUpSpatula()
            right = true
            updateCharacters()
            isPaused = true
        }
        if ProcessInfo.processInfo.arguments.contains("--kitchen-preview") {
            enemies[0].sprite.position.x = worldWidth - 80
            enemies[1].sprite.position.x = 660
            enemies[2].sprite.position.x = 890
            for enemy in [enemies[1], enemies[2]] {
                enemy.sprite.xScale = 1
                _ = enemy.ranged.update(at: time, inRange: true, enabled: true)
            }
            launchProjectile(from: enemies[1]); launchProjectile(from: enemies[2])
            for shot in projectiles {
                shot.node.position = shot.motion.position(at: 0.45)
                shot.node.zRotation = shot.motion.rotation(at: 0.45)
            }
            updateCharacters()
            isPaused = true
        }
        #endif
    }

    override func didChangeSize(_ oldSize: CGSize) { if ready { layoutWorld() } }

    private func layoutWorld() {
        world.setScale(size.height / 540)
        background.size = CGSize(width: max(blockWidth, logicalWidth), height: backgroundHeight)
        let offset = min(CGFloat(stageNumber - 1) * logicalWidth * 0.65, max(0, background.size.width - logicalWidth))
        background.position = CGPoint(x: -offset, y: -40)
        too.position.x = max(65, min(worldWidth - 65, too.position.x))
        for enemy in enemies where enemy.spawned && !enemy.entering {
            enemy.sprite.position.x = max(80, min(worldWidth - 80, enemy.sprite.position.x))
        }
        if lineup { positionLineup() }
        updateCamera()
    }

    func stopInput() {
        left = false; right = false
        jumpMotion.release()
        combat.cancelChain(); weaponCombo.cancelChain()
    }

    func reset() {
        guard ready else { return }
        stopInput()
        encounter = ArenaEncounter()
        lineup = false; labels.removeAllChildren(); clearProjectiles()
        legCombo.cancel(); nado.cancel(); nadoWind.isHidden = true
        weaponCombo = SpatulaCombo()
        damage = TooDamage(); enemyAttack = GoblinAttack(); too.alpha = 1
        onHealth?(damage.health)
        jumpMotion = JumpMotion(); facing = 1
        jumpStartedAt = -.infinity; landedUntil = 0
        combat = ArcadeCombo(); renderedAttack = 0; hitUntil = 0; score = 0
        animationKey = ""; enemyKey = ""
        carryingSpatula = false
        too.position = CGPoint(x: worldWidth / 2, y: floorY)
        spatula.position = CGPoint(x: too.position.x + 60, y: floorY + 3)
        for (index, enemy) in enemies.enumerated() {
            enemy.hitStarted = -.infinity; enemy.health = GoblinHealth(); enemy.attack = GoblinAttack(); enemy.ranged = KitchenRangedAttack(); enemy.moving = false
            enemy.hitUntil = 0; enemy.animationKey = ""
            enemy.sprite.removeAllActions(); enemy.sprite.alpha = 1
            enemy.spawned = false; enemy.entering = false
            enemy.sprite.position = CGPoint(x: ArenaEncounter.entersLeft(index) ? -120 : worldWidth + 120, y: floorY)
            enemy.sprite.xScale = -1
        }
        onDefeated?(0)
        too.xScale = 1; goblin.xScale = -1
        onScore?(0)
        layoutWorld()
        updateEncounter()
        updateCharacters()
        updateCamera()
    }

    var maximumStage: Int?

    func nextStage() {
        if let maximumStage, stageNumber >= maximumStage { return }
        guard stageCleared, !damage.defeated, !isPaused, !lineup else { return }
        stageNumber += 1
        reset()
    }

    private func updateEncounter() {
        if !damage.defeated {
            let living = enemies.filter { $0.spawned && !$0.health.defeated }.count
            let defeated = enemies.filter { $0.health.defeated }.count
            for id in encounter.arrivals(at: time, living: living, defeated: defeated) {
                let enemy = enemies[id]
                enemy.spawned = true; enemy.entering = true
                enemy.sprite.position.x = ArenaEncounter.entersLeft(id) ? -100 : worldWidth + 100
            }
        }
        let state = "\(stageNumber)-\(encounter.wave)-\(stageCleared)"
        if state != lastEncounterState {
            lastEncounterState = state
            onEncounter?(stageNumber, encounter.wave, stageCleared)
        }
    }

    func setLineup(_ enabled: Bool) {
        onLineup?(enabled)
        if !enabled { reset(); return }
        legCombo.cancel(); nado.cancel(); nadoWind.isHidden = true
        lineup = enabled; stopInput(); jumpMotion = JumpMotion()
        clearProjectiles()
        for enemy in enemies { enemy.ranged.interrupt(at: time); enemy.moving = false }
        weaponCombo.cancel(at: time)
        landedUntil = 0
        combat = ArcadeCombo(); renderedAttack = 0; hitUntil = 0
        damage = TooDamage(); enemyAttack = GoblinAttack(); onHealth?(damage.health)
        labels.removeAllChildren()
        if enabled { positionLineup() }
        updateCharacters()
        updateCamera()
    }

    private func positionLineup() {
        too.position = CGPoint(x: logicalWidth / 2 - 125, y: floorY + 28)
        goblin.position = CGPoint(x: logicalWidth / 2 + 125, y: floorY + 28)
        too.xScale = 1; goblin.xScale = 1
        labels.removeAllChildren()
        for (text, x) in [("TOO  ·  150", too.position.x), ("GOBLIN  ·  108", goblin.position.x)] {
            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.text = text; label.fontSize = 15; label.position = CGPoint(x: x, y: floorY - 10)
            labels.addChild(label)
        }
    }

    func jumpPressed(_ pressed: Bool) {
        if !pressed { jumpMotion.release(); return }
        guard !legCombo.locked(at: time), !nado.active(at: time), !lineup, !isPaused, !damage.locked(at: time), !weaponCombo.locked(at: time), !combat.locked(at: time) else { return }
        if lift == 0 && !jumpMotion.held {
            combat = ArcadeCombo(); renderedAttack = 0
            weaponCombo.cancelChain()
            jumpStartedAt = time; landedUntil = 0
        }
        jumpMotion.press()
    }

    func pickUpSpatula() {
        guard canPickUp else { return }
        carryingSpatula = true
        animationKey = ""
        updateCharacters()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func dropSpatula() {
        guard canUseItem, carryingSpatula else { return }
        placeSpatulaOnFloor()
        updateCharacters()
    }

    private func placeSpatulaOnFloor() {
        carryingSpatula = false
        spatula.position = CGPoint(x: max(50, min(worldWidth - 50, too.position.x + facing * 58)), y: floorY + 3)
        spatula.xScale = facing
        animationKey = ""
    }

    private func updateSpatula() {
        spatula.isHidden = carryingSpatula || lineup
        spatulaShadow.isHidden = spatula.isHidden
        spatulaShadow.position = CGPoint(x: spatula.position.x, y: floorY + 2)
        let state = "\(carryingSpatula)-\(canPickUp)-\(canUseItem)"
        if state != lastSpatulaState {
            lastSpatulaState = state
            onSpatula?(carryingSpatula, canPickUp, canUseItem && carryingSpatula)
        }
    }

    func attack() {
        guard !legCombo.locked(at: time), !nado.active(at: time), !lineup, !isPaused, !damage.locked(at: time), lift == 0 else { return }
        if carryingSpatula {
            weaponCombo.press(at: time)
            landedUntil = 0
        } else { combat.press(at: time) }
    }

    func kick() {
        guard canKick else { return }
        combat = ArcadeCombo(); renderedAttack = 0
        weaponCombo = SpatulaCombo()
        legCombo.press(at: time); landedUntil = 0
        animationKey = ""; updateCharacters()
    }
    private func resolveKickHits() {
        guard !damage.locked(at: time), let strike = legCombo.hit(at: time) else { return }
        let box = TooLegCombo.box(at: too.position,facing: facing,strike: strike)
        let target = enemies.filter { $0.spawned && !$0.health.defeated && box.intersects(enemyBody($0)) }
            .min { abs($0.sprite.position.x-too.position.x) < abs($1.sprite.position.x-too.position.x) }
        if let target { legCombo.markHit(strike); hitEnemy(target,uppercut: strike == 2) }
    }
    func heavyAttack() {
        guard canHeavy else { return }
        combat = ArcadeCombo(); renderedAttack = 0
        weaponCombo.cancel(at: time)
        landedUntil = 0
        nado.press(at: time)
        animationKey = ""
        updateCharacters()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func updateHeavyHits() {
        guard nado.striking(at: time), !damage.locked(at: time) else { return }
        for (id, enemy) in enemies.enumerated() where enemy.spawned && !enemy.health.defeated {
            if TooNado.box(at: too.position).intersects(enemyBody(enemy)), nado.claimHit(id, at: time) {
                let direction: CGFloat = enemy.sprite.position.x < too.position.x ? -1 : 1
                hitEnemy(enemy, uppercut: true, strength: 3, direction: direction)
            }
        }
    }

    private func apply(_ key: String, to node: SKSpriteNode, height: CGFloat, sequence: [Int], fps: Double) {
        let clip = assets.clips[key]!
        node.removeAction(forKey: "frames")
        node.texture = clip.textures[sequence[0]]
        node.size = CGSize(width: height * clip.pixels.width / clip.pixels.height, height: height)
        if sequence.count > 1 {
            node.run(.repeatForever(.animate(with: sequence.map { clip.textures[$0] }, timePerFrame: 1 / fps)), withKey: "frames")
        }
    }

    private func updateCharacters() {
        let reacting = !lineup && damage.locked(at: time)
        let reactionClip = damage.reaction == .hit ? "too-hit" : "knockdown"
        let punchPose = !carryingSpatula && combat.holdingPose(at: time)
        let weaponPose = lift == 0 && time >= landedUntil && weaponCombo.holdingPose(at: time)
        let baseKey = reacting ? "\(reactionClip)-\(damage.frame(at: time))" : lineup ? "idle" : (lift > 0 ? "jump" : (punchPose ? "punch" : (left != right ? "walk" : "idle")))
        let armedJumpFrame: Int? = lift > 0 ? (time - jumpStartedAt < 0.08 ? 0 : 1) : (time < landedUntil ? 2 : nil)
        let motionKey = armedJumpFrame.map { "armed-jump-\($0)" } ?? (baseKey == "walk" ? "armed-walk" : "armed-idle")
        let armedKey = weaponPose ? "armed-combo-\(weaponCombo.frame(at: time))" : motionKey
        let spinning = nado.active(at: time) && !reacting && !lineup
        let kicking = legCombo.locked(at: time) && !reacting && !lineup
        let key = kicking ? "leg-\(legCombo.frame(at: time))" : spinning ? "nado-\(nado.frame(at: time))" : (carryingSpatula && !reacting && !lineup ? armedKey : baseKey)
        if key != animationKey {
            animationKey = key
            too.anchorPoint = CGPoint(x: 0.5,y: 0)
            if kicking {
                apply("leg-combo",to: too,height: 150 * 1152 / 780,sequence: [legCombo.frame(at: time)],fps: 1)
                too.anchorPoint = CGPoint(x: 0.5,y: 102.0/1152)
            } else if spinning {
                let clip = assets.clips["nado"]!
                apply("nado", to: too, height: 150 * clip.pixels.height / 835,
                      sequence: [nado.frame(at: time)], fps: 1)
            } else if reacting {
                // One common crop per clip preserves the rising motion. The final
                // standing pose sets knockdown scale, never each individual frame.
                let clip = assets.clips[reactionClip]!
                let referenceHeight = reactionClip == "knockdown" ? clip.visibleBounds[4].height : clip.visibleBounds[0].height
                apply(reactionClip, to: too, height: 150 * clip.pixels.height / referenceHeight,
                      sequence: [damage.frame(at: time)], fps: 1)
            } else if carryingSpatula, !lineup, weaponPose {
                let clip = assets.clips["armed-combo"]!
                let frame = weaponCombo.frame(at: time)
                // Atlas poses are normalized to muted idle's 835-pixel body height.
                // Keep the same pixel-to-world scale; weapon extent does not set size.
                apply("armed-combo", to: too, height: 150 * clip.pixels.height / 849,
                      sequence: [frame], fps: 1)
            } else if carryingSpatula, !lineup, let frame = armedJumpFrame {
                let clip = assets.clips["armed-jump"]!
                // The landing body sets one scale for all poses; preserve tucked feet.
                apply("armed-jump", to: too, height: 150 * clip.pixels.height / clip.visibleBounds[2].height,
                      sequence: [frame], fps: 1)
            } else { switch key {
            case "armed-walk": apply(key, to: too, height: 150, sequence: [0, 1, 2, 3], fps: 10)
            case "armed-idle":
                apply(key, to: too, height: 150, sequence: [0], fps: 1)
                let frames = assets.clips[key]!.textures
                let holds = [1.10, 0.65, 0.10, 0.10]
                too.run(.repeatForever(.sequence((0..<4).flatMap { i in
                    [SKAction.setTexture(frames[i]), SKAction.wait(forDuration: holds[i])]
                })), withKey: "frames")
            case "walk": apply(key, to: too, height: 150, sequence: Array(0...5), fps: 12)
            case "jump": apply(key, to: too, height: 143, sequence: [3], fps: 1)
            case "punch": apply(key, to: too, height: 128, sequence: [combat.frame], fps: 1)
            default: apply(key, to: too, height: 150, sequence: [0, 1, 0, 4], fps: 3)
            } }
        }
        let ground = lineup ? floorY + 28 : floorY
        too.position.y = ground + lift
        tooShadow.position = CGPoint(x: too.position.x, y: ground + 2)
        tooShadow.setScale(1 - min(lift / 500, 0.35))
        too.alpha = !reacting && time < damage.invulnerableUntil && !lineup ? (sin(time * 35) > 0 ? 0.55 : 1) : 1
        for (index, enemy) in enemies.enumerated() {
            let hidden = (!lineup && (!enemy.spawned || enemy.health.defeated)) || (lineup && index != 0)
            enemy.sprite.isHidden = hidden
            enemy.shadow.isHidden = hidden
            enemy.meter.isHidden = hidden || lineup
            enemy.warning.isHidden = hidden || lineup || (enemy.kind == .goblin ? enemy.attack.phase != .warning : enemy.ranged.phase != .warning)
            guard !hidden else { continue }
            if enemy.kind != .goblin {
                let hitFrame = KitchenHitReaction.frame(age: time - enemy.hitStarted)
                if let hitFrame, !lineup {
                    enemy.sprite.removeAction(forKey: "frames")
                    let hit = assets.clips["\(enemy.kind.clip)-hit"]!
                    let normal = assets.clips[enemy.kind.clip]!
                    // One scale per species across both full 1024px canvases.
                    // Register visible feet to the existing gameplay root; bodies stay untouched.
                    let referenceHeight: CGFloat = enemy.kind == .devPresso ? 803 : 855
                    let visibleHeight = enemy.kind.height * normal.visibleBounds[0].height / normal.pixels.height
                    let canvasSide = visibleHeight * 1024 / referenceHeight
                    let baseline: CGFloat = enemy.kind == .devPresso ? [899,895][hitFrame] : [917,881][hitFrame]
                    enemy.sprite.texture = hit.textures[hitFrame]
                    enemy.sprite.size = CGSize(width: canvasSide,height: canvasSide)
                    enemy.sprite.anchorPoint = CGPoint(x: 0.5,y: (1024-baseline)/1024)
                    enemy.sprite.color = .white
                    enemy.sprite.colorBlendFactor = time-enemy.hitStarted < 0.05 ? 0.55 : 0
                    enemy.animationKey = "hit-\(hitFrame)"
                } else {
                    let throwing = enemy.ranged.phase == .warning || enemy.ranged.phase == .release
                    let key = "\(enemy.kind.clip)-\(throwing)-\(enemy.moving)"
                    if key != enemy.animationKey {
                        enemy.animationKey = key
                        enemy.sprite.anchorPoint = CGPoint(x: 0.5,y: 0)
                        let poseScale: CGFloat = enemy.kind == .proteinToaster && throwing ? 0.88 : 1
                        apply(enemy.kind.clip, to: enemy.sprite, height: enemy.kind.height * poseScale,
                              sequence: throwing ? [2] : (enemy.moving ? [0, 1] : [0]), fps: 5.5)
                        if enemy.kind == .proteinToaster {
                            let clip = assets.clips[enemy.kind.clip]!
                            let cropBottom = min(330, clip.visibleBounds.map(\.maxY).max()! + 2)
                            let feet = throwing ? clip.visibleBounds[2].maxY
                                : max(clip.visibleBounds[0].maxY, clip.visibleBounds[1].maxY)
                            enemy.sprite.anchorPoint.y = (cropBottom - feet) / clip.pixels.height
                        }
                    }
                    enemy.sprite.colorBlendFactor = 0
                }
                enemy.sprite.alpha = 1
                enemy.sprite.position.y = ground
                enemy.shadow.position = CGPoint(x: enemy.sprite.position.x, y: ground + 2)
                enemy.meter.text = "\(enemy.health.hitsRemaining)/9"
                enemy.meter.position = CGPoint(x: enemy.sprite.position.x, y: ground + enemy.kind.height + 8)
                enemy.warning.text = enemy.kind == .devPresso ? "CUP!" : "TOAST!"
                enemy.warning.fontSize = 16; enemy.warning.fontColor = .systemYellow
                enemy.warning.position = CGPoint(x: enemy.sprite.position.x, y: ground + enemy.kind.height + 26)
                continue
            }
            let key = !lineup && enemy.attack.phase == .active ? "kick" : (time < enemy.hitUntil && !lineup ? "hit" : "goblin")
            if key != enemy.animationKey {
                enemy.animationKey = key
                apply(key == "kick" ? "hit" : key, to: enemy.sprite, height: key == "goblin" ? 108 : 100,
                      sequence: key == "kick" ? [1] : (key == "hit" ? [0] : [0, 1, 2, 1]), fps: 5)
            }
            enemy.sprite.position.y = ground
            enemy.shadow.position = CGPoint(x: enemy.sprite.position.x, y: ground + 2)
            enemy.meter.text = "\(enemy.health.hitsRemaining)/9"
            enemy.meter.position = CGPoint(x: enemy.sprite.position.x, y: ground + 118)
            enemy.warning.text = enemy.attack.heavy ? "!!" : "!"
            enemy.warning.fontColor = enemy.attack.heavy ? .systemRed : .systemYellow
            enemy.warning.position = CGPoint(x: enemy.sprite.position.x, y: ground + 140)
        }
        nadoWind.isHidden = !spinning || !nado.striking(at: time)
        nadoWind.position = CGPoint(x: too.position.x, y: ground + 92)
        nadoWind.xScale = spinning ? facing * (1 + 0.06 * sin((time - nado.started) * 35)) : facing
        if spinning {
            nadoWind.alpha = min(0.8, max(0, (time - nado.started - 0.18) / 0.08))
        }
        if canKick != lastKickReady { lastKickReady = canKick; onKickReady?(canKick) }
        let heavyReady = canHeavy
        if heavyReady != lastHeavyReady { lastHeavyReady = heavyReady; onHeavyReady?(heavyReady) }
        updateSpatula()
        let weaponReady = !legCombo.locked(at: time) && !(carryingSpatula ? weaponCombo.locked(at: time) : combat.locked(at: time)) && !nado.active(at: time) && !damage.locked(at: time) && lift == 0
        if weaponReady != lastWeaponReady { lastWeaponReady = weaponReady; onWeaponReady?(weaponReady) }
        drawBoxes()
    }

    private func updateCamera() {
        world.position.x = 0
    }

    private func updateWalking(dt: TimeInterval) {
        let direction: CGFloat = damage.locked(at: time) || nado.active(at: time) || weaponCombo.locked(at: time) || combat.locked(at: time) || left == right ? 0 : (left ? -1 : 1)
        if direction != 0 { facing = direction; too.xScale = facing }
        too.position.x = max(65, min(worldWidth - 65, too.position.x + direction * 220 * dt))
    }

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        NavigationProbe.too = self
        NavigationProbe.tooTicks += 1
        #endif
        let dt = min(max(currentTime - lastTime, 0), 1 / 30.0)
        lastTime = currentTime
        guard ready else { return }
        time += dt
        if !lineup {
            updateEncounter()
            updateWalking(dt: dt)
            let wasAirborne = lift > 0
            jumpMotion.update(dt)
            if wasAirborne && lift == 0 { landedUntil = time + 0.12 }
            resolveComboHits()
            resolveKickHits()
            updateHeavyHits()
            for enemy in enemies where enemy.spawned && !enemy.health.defeated {
                if enemy.entering {
                    let direction: CGFloat = enemy.sprite.position.x < worldWidth / 2 ? 1 : -1
                    enemy.sprite.xScale = enemy.kind == .goblin ? direction : -direction
                    enemy.moving = !damage.defeated && time >= enemy.hitUntil
                    if enemy.moving { enemy.sprite.position.x += direction * 115 * dt }
                    if enemy.sprite.position.x >= 80 && enemy.sprite.position.x <= worldWidth - 80 { enemy.entering = false }
                    continue
                }
                if enemy.kind != .goblin {
                    updateRangedEnemy(enemy, dt: dt)
                    continue
                }
                enemy.attack.update(at: time, distance: too.position.x - enemy.sprite.position.x,
                                    enabled: time >= enemy.hitUntil && !damage.defeated)
                let kick = CombatBoxes.kick(at: enemy.sprite.position, facing: enemy.attack.facing)
                if enemy.attack.phase == .active && !enemy.attack.landed && kick.intersects(tooBody) {
                    enemy.attack.markLanded()
                    takeHit(heavy: enemy.attack.heavy, from: enemy.attack.facing)
                }
                if enemy.attack.phase != .idle { enemy.sprite.xScale = enemy.attack.facing }
                if time >= enemy.hitUntil && enemy.attack.phase == .idle && !damage.defeated {
                    let distance = too.position.x - enemy.sprite.position.x
                    let direction: CGFloat = distance < 0 ? -1 : 1
                    enemy.sprite.xScale = direction
                    if abs(distance) > 105 {
                        enemy.sprite.position.x = max(80, min(worldWidth - 80, enemy.sprite.position.x + direction * 90 * dt))
                    }
                }
            }
        }
        if !lineup { updateProjectiles() }
        updateCharacters()
        updateCamera()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { smokeTest() }
        #endif
    }

    private func resolveComboHits() {
            if renderedAttack != combat.serial {
                renderedAttack = combat.serial
                scoredAttack = false
                animationKey = ""
            }
            // Select one living target per strike, nearest first. A finisher is one hit.
            let targets = enemies.filter { $0.spawned && !$0.health.defeated }.sorted {
                abs($0.sprite.position.x - too.position.x) < abs($1.sprite.position.x - too.position.x)
            }
            if combat.canHit(at: time), !damage.locked(at: time), !scoredAttack,
               let target = targets.first(where: { tooPunch.intersects(enemyBody($0)) }) {
                scoredAttack = true
                combat.markHit(at: time)
                hitEnemy(target, uppercut: combat.frame == 2)
            }
            if carryingSpatula, !damage.locked(at: time), let hit = weaponCombo.hit(at: time),
               let target = targets.first(where: { !$0.health.defeated && weaponBox(uppercut: hit == 2).intersects(enemyBody($0)) }) {
                weaponCombo.markHit(hit)
                hitEnemy(target, uppercut: hit == 2)
            }
    }

    private func enemyBody(_ enemy: Enemy) -> CGRect {
        if enemy.kind == .goblin { return CombatBoxes.goblinBody(at: enemy.sprite.position) }
        return CGRect(x: enemy.sprite.position.x - 43, y: floorY + 8, width: 86, height: 100)
    }

    private func updateRangedEnemy(_ enemy: Enemy, dt: TimeInterval) {
        let distance = too.position.x - enemy.sprite.position.x
        let enabled = time >= enemy.hitUntil && !damage.defeated
        // The supplied appliance art faces left; invert it when aiming right.
        let aim: CGFloat = distance < 0 ? -1 : 1
        if enabled { enemy.sprite.xScale = -aim }
        let visible = abs(distance) < min(560, logicalWidth * 0.65)
        if enemy.ranged.update(at: time, inRange: visible && abs(distance) <= 330, enabled: enabled) { launchProjectile(from: enemy) }
        enemy.moving = enabled && enemy.ranged.phase == .ready && abs(distance) > 290
        if enemy.moving {
            enemy.sprite.position.x = max(80, min(worldWidth - 80, enemy.sprite.position.x + aim * 48 * dt))
        }
    }

    private func launchProjectile(from enemy: Enemy) {
        let arcing = enemy.kind == .proteinToaster
        let aim: CGFloat = too.position.x < enemy.sprite.position.x ? -1 : 1
        let origin = CGPoint(x: enemy.sprite.position.x + (arcing ? 0 : aim * 44),
                             y: floorY + (arcing ? 112 : 96))
        let target = CGPoint(x: too.position.x, y: floorY + lift + 62)
        let motion = KitchenProjectileMotion(origin: origin, target: target, arcing: arcing)
        let clip = assets.clips[arcing ? "sandwich" : "espresso-cup"]!
        let node = SKSpriteNode(texture: clip.textures[0])
        node.size = CGSize(width: arcing ? 42 : 32, height: (arcing ? 42 : 32) * clip.pixels.height / clip.pixels.width)
        node.position = origin; node.zPosition = 4
        world.addChild(node)
        projectiles.append(Projectile(node: node, motion: motion, born: time, heavy: arcing, radius: arcing ? 15 : 11))
    }

    private func updateProjectiles() {
        if damage.defeated { clearProjectiles(); return }
        projectiles.removeAll { shot in
            let age = time - shot.born
            let previous = shot.node.position
            let next = shot.motion.position(at: age)
            shot.node.position = next; shot.node.zRotation = shot.motion.rotation(at: age)
            let hit = KitchenProjectileMotion.hits(from: previous, to: next, body: tooBody, radius: shot.radius)
            if hit { takeHit(heavy: shot.heavy, from: shot.motion.velocity.dx < 0 ? -1 : 1) }
            let expired = age > 4 || next.y < floorY || next.x < -80 || next.x > worldWidth + 80
            if hit || expired { shot.node.removeFromParent(); return true }
            return false
        }
    }

    private func clearProjectiles() {
        for shot in projectiles { shot.node.removeFromParent() }
        projectiles.removeAll()
    }

    private func hitEnemy(_ enemy: Enemy, uppercut: Bool, strength: Int = 1, direction: CGFloat? = nil) {
        guard enemy.spawned, enemy.health.receive() else { return }
        var landed = 1
        if strength > 1 { for _ in 1..<strength { if enemy.health.receive() { landed += 1 } } }
        score += landed; onScore?(score)
        enemy.hitStarted = time
        enemy.hitUntil = time + KitchenHitReaction.duration
        enemy.attack.interrupt(at: time)
        enemy.ranged.interrupt(at: time); enemy.moving = false
        enemy.sprite.position.x = max(80, min(worldWidth - 80, enemy.sprite.position.x + (direction ?? facing) * (strength > 1 ? 85 : (uppercut ? 70 : 8))))
        impact(at: CGPoint(x: enemy.sprite.position.x, y: floorY + 75))
        if enemy.health.defeated {
            enemy.sprite.removeAllActions()
            let defeatedCount = enemies.filter { $0.health.defeated }.count
            onDefeated?(defeatedCount)
            if defeatedCount == enemies.count { clearProjectiles(); stopInput(); updateEncounter() }
        }
        UIImpactFeedbackGenerator(style: uppercut ? .medium : .light).impactOccurred()
    }

    private func weaponBox(uppercut: Bool) -> CGRect {
        CombatBoxes.spatula(at: CGPoint(x: too.position.x, y: floorY), facing: facing, uppercut: uppercut)
    }
    private var tooBody: CGRect {
        CombatBoxes.tooBody(at: CGPoint(x: too.position.x, y: floorY + lift))
    }
    private var tooPunch: CGRect {
        CombatBoxes.punch(at: CGPoint(x: too.position.x, y: floorY + lift), facing: facing, uppercut: combat.frame == 2)
    }
    private var enemyKick: CGRect {
        CombatBoxes.kick(at: CGPoint(x: goblin.position.x, y: floorY), facing: enemyAttack.facing)
    }
    private func takeHit(heavy: Bool, from direction: CGFloat = -1) {
        guard damage.receive(at: time, heavy: heavy) else { return }
        legCombo.cancel(); nado.cancel(); nadoWind.isHidden = true
        weaponCombo.cancel(at: time)
        if carryingSpatula { placeSpatulaOnFloor() }
        stopInput(); combat = ArcadeCombo(); renderedAttack = 0
        jumpMotion = JumpMotion(); landedUntil = 0
        too.position.x = max(65, min(worldWidth - 65, too.position.x + direction * (heavy ? 36 : 16)))
        animationKey = ""
        onHealth?(damage.health)
        impact(at: CGPoint(x: too.position.x, y: floorY + 75))
        UIImpactFeedbackGenerator(style: heavy ? .heavy : .medium).impactOccurred()
    }
    private func drawBoxes() {
        boxOverlay.removeAllChildren()
        guard showHitboxes && !lineup else { return }
        func box(_ rect: CGRect, _ color: SKColor) {
            let shape = SKShapeNode(rect: rect)
            shape.strokeColor = color; shape.lineWidth = 1.5
            shape.fillColor = color.withAlphaComponent(0.12)
            boxOverlay.addChild(shape)
        }
        if !damage.locked(at: time) { box(tooBody, time < damage.invulnerableUntil ? .gray : .cyan) }
        for enemy in enemies where enemy.spawned && !enemy.health.defeated {
            box(enemyBody(enemy), .cyan)
            if enemy.kind == .goblin && enemy.attack.phase == .active {
                box(CombatBoxes.kick(at: enemy.sprite.position, facing: enemy.attack.facing), .red)
            }
        }
        for shot in projectiles {
            box(CGRect(x: shot.node.position.x - shot.radius, y: shot.node.position.y - shot.radius,
                       width: shot.radius * 2, height: shot.radius * 2), .red)
        }
        if let strike = legCombo.hit(at: time) { box(TooLegCombo.box(at: too.position,facing: facing,strike: strike),.orange) }
        if nado.striking(at: time) { box(TooNado.box(at: too.position), .orange) }
        if combat.canHit(at: time) { box(tooPunch, .orange) }
        if let hit = weaponCombo.hit(at: time) { box(weaponBox(uppercut: hit == 2), .orange) }
    }

    private func impact(at point: CGPoint) {
        for i in 0..<9 {
            let spark = SKShapeNode(circleOfRadius: i % 2 == 0 ? 3 : 2)
            spark.fillColor = .init(red: 1, green: 0.8, blue: 0.35, alpha: 1)
            spark.strokeColor = .clear; spark.position = point; spark.zPosition = 5
            world.addChild(spark)
            let angle = Double(i) / 9 * .pi * 2
            spark.run(.sequence([.group([.moveBy(x: cos(angle) * 42, y: sin(angle) * 42, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
        }
    }

    #if DEBUG
    /// Opt-in scene checks use the same spawn, damage and advancement paths as play.
    private func verifyLegCombo() {
        var results: [String: Bool] = [:]
        for direction: CGFloat in [-1,1] {
            reset(); facing = direction
            let enemy = enemies[0]
            enemy.spawned = true; enemy.entering = false
            enemy.sprite.position.x = too.position.x + direction * 145
            kick()
            let start = time
            var elapsed: TimeInterval = 0
            var hits = 0
            for frame in 0..<9 {
                time = start + elapsed + TooLegCombo.timings[frame]/2
                updateCharacters()
                results["texture-\(direction)-\(frame+1)"] = too.texture === assets.clips["leg-combo"]!.textures[frame]
                results["pivot-\(direction)-\(frame+1)"] = abs(too.anchorPoint.x - 0.5) < 0.0001 && abs(too.anchorPoint.y - 102.0/1152.0) < 0.0001 && abs(too.position.y - floorY) < 0.0001
                resolveKickHits(); resolveKickHits()
                if TooLegCombo.impactFrames.contains(frame) { hits += 1 }
                results["damage-\(direction)-\(frame+1)"] = enemy.health.hitsRemaining == 9-hits
                elapsed += TooLegCombo.timings[frame]
            }
            time = start + TooLegCombo.duration + TooLegCombo.recovery + 0.01
            updateCharacters()
            results["restores-\(direction)"] = canKick && too.anchorPoint == CGPoint(x: 0.5,y: 0)
        }
        for direction: CGFloat in [-1,1] {
            reset(); facing = direction; left = direction < 0; right = direction > 0
            kick()
            let start = time
            let origin = too.position.x
            updateWalking(dt: 1.0/30)
            results["moving-from-windup-\(direction)"] = abs(too.position.x-origin-direction*220/30) < 0.001
            var elapsed: TimeInterval = 0
            for frame in 0..<9 {
                time = start + elapsed + TooLegCombo.timings[frame]/2
                let before = too.position.x
                updateWalking(dt: 1.0/30); updateCharacters()
                results["moving-pose-\(direction)-\(frame)"] = abs(too.position.x-before-direction*220/30) < 0.001 && too.texture === assets.clips["leg-combo"]!.textures[frame]
                if TooLegCombo.impactFrames.contains(frame) {
                    let enemy = enemies[0]; enemy.spawned = true; enemy.entering = false
                    enemy.sprite.position.x = too.position.x + direction*145
                    let health = enemy.health.hitsRemaining
                    resolveKickHits(); resolveKickHits()
                    results["moving-hit-\(direction)-\(frame)"] = enemy.health.hitsRemaining == health-1
                }
                elapsed += TooLegCombo.timings[frame]
            }
            left = false; right = false
            let stopped = too.position.x
            updateWalking(dt: 1.0/30)
            results["release-stops-\(direction)"] = too.position.x == stopped
            left = direction > 0; right = direction < 0
            updateWalking(dt: 1.0/30)
            results["turn-mid-combo-\(direction)"] = facing == -direction && too.xScale == -direction
            takeHit(heavy: false)
            let hitPosition = too.position.x
            updateWalking(dt: 1.0/30)
            results["damage-stops-walk-\(direction)"] = too.position.x == hitPosition
        }
        reset(); kick(); takeHit(heavy: false)
        results["damage-cancels"] = !legCombo.locked(at: time)
        reset(); kick(); reset()
        results["reset-cancels"] = !legCombo.locked(at: time)
        let url = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("leg-combo-results.json")
        try! JSONSerialization.data(withJSONObject: results,options: [.prettyPrinted,.sortedKeys]).write(to: url)
        reset(); kick(); time += 0.435; updateCharacters(); isPaused = true
    }
    private func verifyKitchenHits() {
        var results: [String: Bool] = [:]
        for id in [6,7] {
            reset()
            let enemy = enemies[id]
            enemy.spawned = true; enemy.entering = false
            enemy.sprite.position.x = worldWidth * 0.65
            enemy.sprite.xScale = 1
            updateCharacters()
            let bodySize = enemyBody(enemy).size
            hitEnemy(enemy,uppercut: false)
            let start = time
            time = start + 0.08; updateCharacters()
            let size = enemy.sprite.size
            results["\(id)-flinch"] = enemy.sprite.texture === assets.clips["\(enemy.kind.clip)-hit"]!.textures[0]
            results["\(id)-interrupt"] = enemy.ranged.phase == .ready && enemy.hitUntil > time
            results["\(id)-body"] = enemyBody(enemy).size == bodySize
            let direction = enemy.sprite.xScale
            too.position.x = enemy.sprite.position.x + 80
            updateRangedEnemy(enemy,dt: 0)
            results["\(id)-facing"] = enemy.sprite.xScale == direction
            time = start + 0.2; updateCharacters()
            results["\(id)-recovery"] = enemy.sprite.texture === assets.clips["\(enemy.kind.clip)-hit"]!.textures[1] && enemy.sprite.size == size
            results["\(id)-root"] = enemy.sprite.position.y == floorY && enemyBody(enemy).size == bodySize
            time = start + 0.46; updateCharacters()
            results["\(id)-return"] = assets.clips[enemy.kind.clip]!.textures.contains { $0 === enemy.sprite.texture } && enemy.sprite.colorBlendFactor == 0
            hitEnemy(enemy,uppercut: false); time += 0.08; updateCharacters()
            results["\(id)-retrigger"] = enemy.sprite.texture === assets.clips["\(enemy.kind.clip)-hit"]!.textures[0]
        }
        let url = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0].appendingPathComponent("kitchen-hit-results.json")
        try! JSONSerialization.data(withJSONObject: results,options: [.prettyPrinted,.sortedKeys]).write(to: url)
        reset()
        for enemy in enemies { enemy.spawned = false }
        // Both supplied poses in both species; right pair mirrors toward the center.
        for (column,id) in [6,7,8,9].enumerated() {
            let enemy = enemies[id]; enemy.spawned = true; enemy.entering = false
            enemy.sprite.position.x = worldWidth * CGFloat(column+1)/5
            enemy.sprite.xScale = column < 2 ? 1 : -1
            enemy.hitStarted = time - (column < 2 ? 0.08 : 0.2)
            enemy.hitUntil = enemy.hitStarted + KitchenHitReaction.duration
        }
        updateCharacters(); isPaused = true
    }
    private func smokeTest() {
        guard !smokeStages.contains(0) else { return }
        smokeStages.insert(0)
        var results: [String: Bool] = [:]
        reset()
        results["singleBackground"] = world.children.filter { $0.name == "arena-background" }.count == 1 && world.children.filter { $0.name?.hasPrefix("street-block") == true }.isEmpty
        results["lockedCamera"] = world.position.x == 0 && worldWidth == logicalWidth
        results["initialGoblinsBothSides"] = enemies.filter { $0.spawned }.count == 2 && enemies[0].kind == .goblin && enemies[1].kind == .goblin && enemies[0].sprite.position.x < 0 && enemies[1].sprite.position.x > worldWidth
        let originalStage = stageNumber
        nextStage()
        results["nextBlockedBeforeClear"] = stageNumber == originalStage
        let dormantHealth = enemies[5].health.hitsRemaining
        hitEnemy(enemies[5], uppercut: false)
        results["dormantEnemiesCannotBeHit"] = enemies[5].health.hitsRemaining == dormantHealth
        for enemy in enemies where enemy.spawned {
            enemy.entering = false
        }
        enemies[0].sprite.position.x = too.position.x - 90
        enemies[1].sprite.position.x = too.position.x + 90
        heavyAttack(); time += 0.3
        updateHeavyHits(); updateHeavyHits(); updateCharacters()
        results["heavyDamagesBothSidesOnce"] = enemies[0].health.hitsRemaining == 6 && enemies[1].health.hitsRemaining == 6 && score == 6
        results["heavyWind"] = !nadoWind.isHidden
        takeHit(heavy: false)
        results["damageCancelsHeavy"] = !nado.active(at: time)
        reset()
        var maxLiving = 0
        var arrived = Set<Int>()
        var kindsFromLeft = Set<String>(), kindsFromRight = Set<String>()
        for _ in 0..<30 {
            time += 3; updateEncounter()
            let living = enemies.filter { $0.spawned && !$0.health.defeated }
            maxLiving = max(maxLiving, living.count)
            for (id, enemy) in enemies.enumerated() where enemy.spawned {
                arrived.insert(id)
                let kind = String(describing: enemy.kind)
                if ArenaEncounter.entersLeft(id) { kindsFromLeft.insert(kind) } else { kindsFromRight.insert(kind) }
            }
            for enemy in living { hitEnemy(enemy, uppercut: false, strength: 9) }
        }
        results["finiteEighteenEnemies"] = arrived.count == 18 && enemies.count <= 20
        results["bothSidesEveryKind"] = kindsFromLeft.count == 3 && kindsFromRight.count == 3
        results["livingCap"] = maxLiving <= 4
        results["allThreeWaves"] = encounter.wave == 3
        results["clearUnlocksNext"] = stageCleared && projectiles.isEmpty
        isPaused = true; nextStage()
        results["pauseBlocksNext"] = stageNumber == originalStage
        isPaused = false; nextStage()
        results["nextStartsNewStage"] = stageNumber == originalStage + 1 && !stageCleared && score == 0 && damage.health == 5
        results["nextKeepsSingleBackground"] = world.children.filter { $0.name == "arena-background" }.count == 1 && world.position.x == 0 && background.position.x < 0
        results["nextRestartsGoblins"] = encounter.wave == 1 && enemies.filter { $0.spawned }.count == 2
        setLineup(true); setLineup(false)
        results["lineupReturnsToFreshArena"] = !lineup && !stageCleared && encounter.wave == 1
        reset(); pickUpSpatula(); heavyAttack(); time += 1.1; updateCharacters()
        results["heavyRestoresWeapon"] = carryingSpatula && animationKey == "armed-idle"
        reset()
        // Exercise the actual collider-to-combo hit-confirmation path.
        reset()
        enemies[0].entering = false
        enemies[0].sprite.position.x = too.position.x - 100
        attack(); time += 0.08 * ArcadeCombo.timingScale; resolveComboHits()
        time += 0.37 * ArcadeCombo.timingScale; attack()
        results["whiffRepeatsFirstPunch"] = combat.frame == 0 && enemies[0].health.hitsRemaining == 9
        reset()
        enemies[0].entering = false
        enemies[0].sprite.position.x = too.position.x + 80
        let targetStart = enemies[0].sprite.position.x
        attack(); time += 0.08 * ArcadeCombo.timingScale; resolveComboHits(); resolveComboHits()
        results["punchConfirmsOnceOnCollision"] = enemies[0].health.hitsRemaining == 8
        time += 0.37 * ArcadeCombo.timingScale; attack()
        results["collisionUnlocksSecondPunch"] = combat.frame == 1
        time += 0.08 * ArcadeCombo.timingScale; resolveComboHits()
        time += 0.37 * ArcadeCombo.timingScale; attack()
        results["secondCollisionUnlocksFinisher"] = combat.frame == 2
        time += 0.12 * ArcadeCombo.timingScale; resolveComboHits()
        results["finisherPushesEnemyAway"] = enemies[0].sprite.position.x >= targetStart + 86 && enemies[0].health.hitsRemaining == 6
        time += 0.4 * ArcadeCombo.timingScale
        let serial = combat.serial
        jumpPressed(true); heavyAttack(); pickUpSpatula(); attack()
        results["recoveryCannotBeCancelled"] = combat.serial == serial && lift == 0 && !nado.active(at: time) && !carryingSpatula && combat.locked(at: time)
        time += 0.7 * ArcadeCombo.timingScale; attack()
        results["freshPunchAfterRecovery"] = combat.frame == 0 && combat.serial == serial + 1
        reset()
        reset()
        let plantedPosition = too.position
        attack(); time += 0.03; combat.markHit(at: time); updateCharacters()
        let punchSize = too.size
        time += 0.10; updateCharacters()
        results["confirmedPunchDoesNotFlashIdle"] = animationKey == "punch" && too.size == punchSize && too.position == plantedPosition
        attack(); resolveComboHits(); updateCharacters()
        results["secondPunchKeepsPosition"] = combat.frame == 1 && animationKey == "punch" && too.position == plantedPosition && too.size == punchSize
        reset(); pickUpSpatula(); attack(); weaponCombo.markHit(0); updateCharacters()
        let armedPosition = too.position, armedSize = too.size
        time += 0.14; updateCharacters()
        results["confirmedWeaponDoesNotFlashIdle"] = animationKey == "armed-combo-0" && too.position == armedPosition && too.size == armedSize
        attack(); updateCharacters()
        results["weaponLinksDirectlyToNextPose"] = animationKey == "armed-combo-1" && too.position == armedPosition && too.size == armedSize
        time += 1; updateCharacters()
        results["missedLinkReturnsToIdle"] = animationKey == "armed-idle"
        reset()
        // Reproduce spaced targets while the movement control remains held.
        for armed in [false, true] {
            reset()
            if armed { pickUpSpatula() }
            right = true
            for enemy in enemies { enemy.sprite.position.x = worldWidth + 300 }
            attack(); time += 0.03; resolveComboHits(); updateCharacters()
            let firstKey = animationKey, firstSize = too.size
            time += 0.14; updateCharacters()
            results["movingWhiffKeepsPose-\(armed)"] = animationKey == firstKey && too.size == firstSize
            attack(); resolveComboHits(); updateCharacters()
            results["movingWhiffRepeatsOnlyFirst-\(armed)"] = armed ? weaponCombo.strike == 0 : combat.frame == 0
            enemies[0].spawned = true; enemies[0].entering = false
            enemies[0].sprite.position.x = too.position.x + 100
            time += 0.03; resolveComboHits()
            time += 0.14; updateCharacters()
            results["movingConfirmedHitKeepsPose-\(armed)"] = animationKey == firstKey
            attack(); resolveComboHits(); updateCharacters()
            results["movingConfirmedHitLinks-\(armed)"] = armed ? weaponCombo.strike == 1 : combat.frame == 1
            time += 1; updateCharacters()
            results["movementResumesAfterWindow-\(armed)"] = animationKey == (armed ? "armed-walk" : "walk")
        }
        reset()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("arena-smoke-results.json")
        try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        print("ARENA_SMOKE \(results)")
    }
    #endif
}
