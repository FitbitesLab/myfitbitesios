import SwiftUI
import SpriteKit
import Combine
import UIKit


@MainActor
final class GameSession: ObservableObject {
    let scene = StreetScene(size: CGSize(width: 1100, height: 540))
    @Published var stage = 1
    @Published var wave = 1
    @Published var cleared = false
    @Published var paused = false
    @Published var lineup = false
    @Published var hits = 0
    @Published var defeated = 0
    @Published var health = 5
    @Published var boxes = false
    @Published var heavyReady = false
    @Published var kickReady = false
    @Published var weaponReady = true
    @Published var armed = false
    @Published var canPickUp = false
    @Published var canDrop = false
    init() {
        scene.onEncounter = { [weak self] stage, wave, cleared in
            self?.stage = stage; self?.wave = wave; self?.cleared = cleared
        }
        scene.onKickReady = { [weak self] in self?.kickReady = $0 }
        scene.onHeavyReady = { [weak self] in self?.heavyReady = $0 }
        scene.onWeaponReady = { [weak self] in self?.weaponReady = $0 }
        scene.onSpatula = { [weak self] armed, pickup, drop in
            self?.armed = armed; self?.canPickUp = pickup; self?.canDrop = drop
        }
        scene.scaleMode = .resizeFill
        scene.onHealth = { [weak self] in self?.health = $0 }
        scene.onDefeated = { [weak self] in self?.defeated = $0 }
        scene.onScore = { [weak self] in self?.hits = $0 }
        scene.onLineup = { [weak self] in self?.lineup = $0 }
    }
    func reset() { paused = false; lineup = false; scene.isPaused = false; scene.reset() }
}

struct GameScreen: View {
    var onMenu: (() -> Void)? = nil
    var demoMode = false
    var creditBalance: Int? = nil
    var creditLocked = false
    var onLifeLost: (() -> Void)? = nil
    var onNewRun: (() -> Void)? = nil
    @StateObject private var game = GameSession()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AdventureSceneView(scene: game.scene)
                    .ignoresSafeArea()
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TOO ADVENTURE  ·  STAGE \(game.stage)").font(.system(size: 14, weight: .heavy, design: .rounded)).lineLimit(1)
                            ArcadeHealthBar(health: game.health)
                            if let creditBalance {
                                Text("CREDITS \(creditBalance)")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .accessibilityLabel("\(creditBalance) arcade credits available")
                            }
                            Text(game.lineup ? "Character lineup" : "WAVE \(game.wave)/3  ·  \(game.defeated)/\(StreetScene.enemyCount) DEFEATED")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 1, green: 0.87, blue: 0.4))
                        }
                        Spacer()
                        if let onMenu {
                            Button("Menu") { game.scene.stopInput(); game.scene.isPaused = true; onMenu() }
                        }
                        if !demoMode {
                        Button(game.boxes ? "Hide boxes" : "Hitboxes") {
                            game.boxes.toggle(); game.scene.showHitboxes = game.boxes
                        }
                        Button(game.lineup ? "Play" : "Lineup") {
                            game.lineup.toggle(); game.scene.setLineup(game.lineup)
                        }.accessibilityIdentifier("lineup")
                        }
                        Button { game.paused.toggle(); game.scene.stopInput(); game.scene.isPaused = game.paused } label: {
                            Image(systemName: game.paused ? "play.fill" : "pause.fill")
                        }.accessibilityLabel(game.paused ? "Resume" : "Pause")
                        Button { if let onNewRun { onNewRun() } else { game.reset() } } label: { Image(systemName: "arrow.counterclockwise") }
                            .accessibilityLabel("Restart")
                    }
                    .buttonStyle(HUDButtonStyle())
                    Spacer()
                    if !game.lineup {
                        HStack(alignment: .bottom) {
                            HoldControl(symbol: "chevron.left", label: "Move left") { game.scene.left = $0 }
                            HoldControl(symbol: "chevron.right", label: "Move right") { game.scene.right = $0 }
                            Spacer()
                            HStack(spacing: 8) {
                                TouchControl(symbol: "hand.draw.fill", caption: "PICK UP", label: "Pick up spatula", accent: true) {
                                    if $0 { game.scene.pickUpSpatula() }
                                }.disabled(!game.canPickUp).opacity(game.canPickUp ? 1 : 0.4)
                                TouchControl(symbol: "arrow.down.to.line", caption: "DROP", label: "Drop spatula", accent: false) {
                                    if $0 { game.scene.dropSpatula() }
                                }.disabled(!game.canDrop).opacity(game.canDrop ? 1 : 0.4)
                            }
                            // Right-thumb diamond: heavy above, attack left, jump below.
                            // The three-kick combo occupies the right position.
                            VStack(spacing: 0) {
                                TouchControl(symbol: "tornado", caption: game.heavyReady ? "HEAVY" : "WAIT", label: "Too-nado heavy attack", accent: true) {
                                    if $0 { game.scene.heavyAttack() }
                                }.disabled(!game.heavyReady).opacity(game.heavyReady ? 1 : 0.4)
                                    .frame(maxWidth: .infinity)
                                HStack {
                                TouchControl(symbol: "burst.fill", caption: game.weaponReady ? (game.armed ? "COMBO" : "BOP") : "WAIT", label: game.armed ? "Spatula combo" : "Bop", accent: true) {
                                    if $0 { game.scene.attack() }
                                }.disabled(!game.weaponReady).opacity(game.weaponReady ? 1 : 0.4)
                                    Spacer(minLength: 0)
                                    TouchControl(symbol: "figure.kickboxing", caption: game.kickReady ? "KICK" : "WAIT", label: "Three-kick combo", accent: true) {
                                        if $0 { game.scene.kick() }
                                    }.disabled(!game.kickReady).opacity(game.kickReady ? 1 : 0.4)
                                }
                                TouchControl(symbol: "arrow.up", caption: "JUMP", label: "Jump", accent: false) {
                                    game.scene.jumpPressed($0)
                                }.frame(maxWidth: .infinity)
                            }.frame(width: 198, height: 180)
                        }.disabled(game.paused)
                    } else {
                        Text("Original animation sheets · full-resolution textures · consistent scale")
                            .font(.system(size: 11, weight: .medium)).padding(10)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 15)
                if game.health == 0 && onLifeLost == nil {
                    VStack(spacing: 12) {
                        Text("TAKE A BREATHER").font(.headline)
                        Button(onNewRun == nil ? "Try again" : "Back to Arcade") { if let onNewRun { onNewRun() } else { game.reset() } }.buttonStyle(.borderedProminent)
                    }.foregroundStyle(.white).padding(24)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                }
                if game.cleared && game.health > 0 && !game.lineup {
                    VStack(spacing: 5) {
                        Text("STAGE CLEAR!")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(Color.yellow)
                            .shadow(color: .black, radius: 0, x: 2, y: 3)
                        Text("ALL 18 ENEMIES DOWN")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(2).foregroundStyle(.white)
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.28)
                    if demoMode {
                        VStack(spacing: 12) {
                            Text("DEMO COMPLETE").font(.headline)
                            Button(onNewRun == nil ? "Play again" : "Back to Arcade") { if let onNewRun { onNewRun() } else { game.reset() } }
                            if let onMenu { Button("Back to title", action: onMenu) }
                        }
                        .foregroundStyle(.white)
                        .buttonStyle(.borderedProminent)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.53)
                    } else {
                    ArcadeNextButton { game.scene.nextStage() }
                        .disabled(game.paused)
                        .position(x: geometry.size.width - 145, y: geometry.size.height * 0.47)
                    }
                }
                if game.paused {
                    Text("PAUSED").font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white).padding(25)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .onAppear { game.scene.maximumStage = demoMode ? 1 : nil; game.scene.viewport = geometry.size; game.paused = creditLocked; game.scene.isPaused = creditLocked }
            .onChange(of: game.health) { old, health in
                if old > 0 && health == 0, let onLifeLost {
                    game.paused = true; game.scene.stopInput(); game.scene.isPaused = true
                    onLifeLost()
                }
            }
            .onChange(of: creditLocked) { _, locked in
                if !locked && game.health == 0 { game.reset() }
                game.paused = locked; game.scene.stopInput(); game.scene.isPaused = locked
            }
            .onDisappear { game.scene.stopInput(); game.scene.isPaused = true }
            .onChange(of: geometry.size) { _, size in game.scene.viewport = size }
            .onChange(of: phase) { _, value in
                if value != .active { game.paused = true; game.scene.stopInput(); game.scene.isPaused = true }
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }
}

struct HUDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13).frame(height: 34)
            .background(.black.opacity(configuration.isPressed ? 0.7 : 0.4), in: Capsule())
    }
}
struct ControlFace: View {
    let symbol: String
    let label: String
    let accent: Bool
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold))
            Text(label).font(.system(size: 8, weight: .heavy))
        }
        .frame(width: 62, height: 60)
        .background(accent ? Color(red: 0.80, green: 0.36, blue: 0.13) : .black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.25), lineWidth: 1))
    }
}
struct HoldControl: View {
    var hideArtwork = false
    let symbol: String
    let label: String
    let changed: (Bool) -> Void
    var body: some View {
        TouchControl(hideArtwork: hideArtwork, symbol: symbol, caption: "MOVE", label: label, accent: false, changed: changed)
    }
}

@MainActor private enum TielJumpButtonArtwork {
    static let silhouette:UIImage = {
        guard let sheet=UIImage(named:"tiel-chubby-jump-spritesheet")?.cgImage,
              let frame=sheet.cropping(to:CGRect(x:1024,y:0,width:1024,height:768)) else{return UIImage()}
        return UIImage(cgImage:frame).withRenderingMode(.alwaysTemplate)
    }()
}

struct TouchControl: View {
    var hideArtwork = false
    let symbol: String
    let caption: String
    let label: String
    let accent: Bool
    let changed: (Bool) -> Void
    @State private var pressed=false
    var body: some View {
        Group {
            if caption == "JUMP" {
                ZStack {
                    Circle().fill(Color(red:0.26,green:0.15,blue:0.04).opacity(0.3)).offset(y:4)
                    Circle().fill(LinearGradient(colors:[Color(red:1,green:0.89,blue:0.52).opacity(0.92),Color(red:0.94,green:0.61,blue:0.16).opacity(0.86)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    Circle().strokeBorder(.white.opacity(0.7),lineWidth:2)
                    Circle().inset(by:6).stroke(.white.opacity(0.25),lineWidth:1)
                    VStack(spacing:3) {
                        Image(uiImage:TielJumpButtonArtwork.silhouette).renderingMode(.template).resizable().scaledToFit().frame(width:49,height:44)
                        Text("JUMP").font(.custom("ChalkboardSE-Bold",size:12)).tracking(1.5)
                    }.foregroundStyle(Color(red:0.30,green:0.20,blue:0.08))
                }.frame(width:86,height:86)
                    .scaleEffect(pressed ? 0.93:1).offset(y:pressed ? 3:0)
                    .animation(.easeOut(duration:0.10),value:pressed)
            } else {ControlFace(symbol:symbol,label:caption,accent:accent)}
        }
        .opacity(hideArtwork ? 0 : 1)
        .accessibilityHidden(true)
        .overlay(PressSurface(label:label){held in pressed=held;changed(held)})
    }
}

/// UIControl begins tracking on touch-down, with explicit release and cancellation.
struct PressSurface: UIViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    let label: String
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> ImmediateControl { ImmediateControl() }
    func updateUIView(_ control: ImmediateControl, context: Context) {
        control.changed = changed
        control.isEnabled = enabled
        control.accessibilityLabel = label
        if !enabled { control.releasePress() }
    }
    static func dismantleUIView(_ control: ImmediateControl, coordinator: ()) { control.releasePress() }
}

final class ImmediateControl: UIControl {
    var changed: (Bool) -> Void = { _ in }
    private var pressing = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        isExclusiveTouch = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        pressing = true
        changed(true)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !bounds.insetBy(dx: -24, dy: -24).contains(touch.location(in: self)) {
            releasePress()
            return false
        }
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { releasePress() }
    override func cancelTracking(with event: UIEvent?) { releasePress() }
    func releasePress() {
        guard pressing else { return }
        pressing = false
        changed(false)
    }
    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        changed(true); changed(false)
        return true
    }
}

struct ArcadeHealthBar: View {
    let health: Int
    private var colors: [Color] {
        health <= 1 ? [.pink, .red] : health <= 2 ? [.orange, .yellow] : [.cyan, .green]
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.pink)
                .shadow(color: .pink.opacity(0.65), radius: 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TOO").tracking(1.5)
                    Spacer()
                    Text("\(health) / 5")
                }.font(.system(size: 9, weight: .black, design: .rounded))
                HStack(spacing: 3) {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index < health ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.1)))
                            .overlay(alignment: .top) {
                                if index < health {
                                    Capsule().fill(.white.opacity(0.45)).frame(height: 3).padding(3)
                                }
                            }
                    }
                }.frame(height: 17)
            }.frame(width: 158)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Color(red: 0.10, green: 0.07, blue: 0.24).opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.cyan.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .purple.opacity(0.3), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.2), value: health)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Too health")
        .accessibilityValue("\(health) of 5")
    }
}


/// Code-drawn arcade signage stays crisp at every device scale.
struct ArcadeArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.18))
        path.addLine(to: CGPoint(x: w * 0.69, y: h * 0.18))
        path.addLine(to: CGPoint(x: w * 0.69, y: 0))
        path.addLine(to: CGPoint(x: w, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.69, y: h))
        path.addLine(to: CGPoint(x: w * 0.69, y: h * 0.82))
        path.addLine(to: CGPoint(x: 0, y: h * 0.82))
        path.closeSubpath()
        return path
    }
}

struct ArcadeNextButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    ArcadeArrow()
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.36), .yellow, Color(red: 1, green: 0.42, blue: 0.04)], startPoint: .top, endPoint: .bottom))
                        .overlay(ArcadeArrow().stroke(Color(red: 0.28, green: 0.10, blue: 0.02), lineWidth: 4))
                        .shadow(color: .black.opacity(0.65), radius: 0, x: 0, y: 6)
                        .shadow(color: .orange.opacity(0.6), radius: 14)
                    Text("NEXT")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .italic().tracking(2)
                        .foregroundStyle(Color(red: 0.32, green: 0.10, blue: 0.015))
                        .shadow(color: .white.opacity(0.7), radius: 0, x: 0, y: 1)
                        .offset(x: -19)
                }
                .frame(width: 202, height: 86)
                Text("TAP TO ADVANCE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(2).foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            }
            .offset(x: pulse && !reduceMotion ? 7 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Next stage")
        .accessibilityHint("Advance to the next arena")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
