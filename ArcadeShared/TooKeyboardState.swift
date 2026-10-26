import Foundation

/// Tracks physical keys independently, so releasing A does not release a held left arrow.
struct TooKeyboardState {
    enum Action: Equatable { case attack, heavy, pickUp, drop, kick }
    private(set) var held = Set<Int>()
    // USB keyboard usages, as reported by UIKey.keyCode.
    static let leftKeys: Set<Int> = [4, 80]   // A, left
    static let rightKeys: Set<Int> = [7, 79]  // D, right
    static let jumpKeys: Set<Int> = [26, 44, 82] // W, space, up
    static let actions: [Int: Action] = [13: .attack, 14: .heavy, 8: .pickUp, 20: .drop, 15: .kick]
    static let supported = leftKeys.union(rightKeys).union(jumpKeys).union(actions.keys)
    var left: Bool { !held.isDisjoint(with: Self.leftKeys) }
    var right: Bool { !held.isDisjoint(with: Self.rightKeys) }
    var jump: Bool { !held.isDisjoint(with: Self.jumpKeys) }
    mutating func press(_ code: Int) -> Action? {
        guard Self.supported.contains(code), held.insert(code).inserted else { return nil }
        return Self.actions[code]
    }
    mutating func release(_ code: Int) { held.remove(code) }
    mutating func clear() { held.removeAll() }
}
