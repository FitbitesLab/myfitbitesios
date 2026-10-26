import SpriteKit
import UIKit

/// Real key-down/key-up events allow movement, jumping and attacks at the same time.
@MainActor
final class TooKeyboardView: SKView {
    private var keyboard = TooKeyboardState()
    private var sentLeft = false, sentRight = false, sentJump = false
    override var canBecomeFirstResponder: Bool { scene is StreetScene }

    override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(clearKeyboardInput),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { clearKeyboardInput() }
        else if canBecomeFirstResponder { becomeFirstResponder() }
    }
    override func resignFirstResponder() -> Bool {
        clearKeyboardInput()
        return super.resignFirstResponder()
    }
    func synchronizeKeyboardFocus() {
        if scene?.isPaused == true { clearKeyboardInput() }
        if window != nil, canBecomeFirstResponder, !isFirstResponder { becomeFirstResponder() }
    }
    @objc func clearKeyboardInput() {
        keyboard.clear()
        sendHeldInput()
    }
    private func sendHeldInput() {
        guard let scene = scene as? StreetScene else {
            sentLeft = false; sentRight = false; sentJump = false
            return
        }
        // Update only changed controls so a keyboard attack does not cancel a touch-held direction.
        if keyboard.left != sentLeft { scene.left = keyboard.left; sentLeft = keyboard.left }
        if keyboard.right != sentRight { scene.right = keyboard.right; sentRight = keyboard.right }
        if keyboard.jump != sentJump { scene.jumpPressed(keyboard.jump); sentJump = keyboard.jump }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {


        guard let scene = scene as? StreetScene, !scene.isPaused else {
            clearKeyboardInput(); super.pressesBegan(presses, with: event); return
        }
        var other = Set<UIPress>()
        var actions: [TooKeyboardState.Action] = []
        for press in presses {
            guard let code = press.key?.keyCode.rawValue, TooKeyboardState.supported.contains(code) else {
                other.insert(press); continue
            }
            if let action = keyboard.press(code) { actions.append(action) }
        }
        sendHeldInput()
        for action in actions {
            switch action {
            case .attack: scene.attack()
            case .heavy: scene.heavyAttack()
            case .pickUp: scene.pickUpSpatula()
            case .drop: scene.dropSpatula()
            case .kick: scene.kick()
            }
        }
        if !other.isEmpty { super.pressesBegan(other, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {


        var other = Set<UIPress>()
        for press in presses {
            guard let code = press.key?.keyCode.rawValue, TooKeyboardState.supported.contains(code) else {
                other.insert(press); continue
            }
            keyboard.release(code)
        }
        sendHeldInput()
        if !other.isEmpty { super.pressesEnded(other, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        clearKeyboardInput()
        super.pressesCancelled(presses, with: event)
    }
}
