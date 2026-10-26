import SwiftUI
import SpriteKit

/// Own the renderer explicitly so switching modes cannot reuse a detached/paused scene.
struct AdventureSceneView: UIViewRepresentable {
    let scene: SKScene
    func makeUIView(context: Context) -> SKView {
        let view = TooKeyboardView()
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = false
        view.isMultipleTouchEnabled = true
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {
        (view as? TooKeyboardView)?.synchronizeKeyboardFocus()
        guard view.scene !== scene else { return }
        (view as? TooKeyboardView)?.clearKeyboardInput()
        view.presentScene(nil)
        view.isPaused = false
        scene.isPaused = false
        view.presentScene(scene)
        (view as? TooKeyboardView)?.synchronizeKeyboardFocus()
    }
    static func dismantleUIView(_ view: SKView, coordinator: ()) {
        (view as? TooKeyboardView)?.clearKeyboardInput()
        if let scene = view.scene as? StreetScene { scene.stopInput() }
        view.scene?.isPaused = true
        view.isPaused = true
        view.presentScene(nil)
    }
}
