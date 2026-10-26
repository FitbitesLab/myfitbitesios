import Foundation
import CoreGraphics

/// One grounded area strike per activation, followed by visible recovery/cooldown.
struct TooNado {
    private(set) var started: TimeInterval = -.infinity
    private var struck = Set<Int>()
    func active(at time: TimeInterval) -> Bool { time - started < 1.05 }
    func locked(at time: TimeInterval) -> Bool { time - started < 1.55 }
    func striking(at time: TimeInterval) -> Bool {
        let age = time - started
        return age >= 0.18 && age < 0.78
    }
    mutating func press(at time: TimeInterval) {
        guard !locked(at: time) else { return }
        started = time; struck.removeAll()
    }
    mutating func cancel() { started = -.infinity; struck.removeAll() }
    mutating func claimHit(_ id: Int, at time: TimeInterval) -> Bool {
        guard striking(at: time) else { return false }
        return struck.insert(id).inserted
    }
    func frame(at time: TimeInterval) -> Int {
        let age = time - started
        if age < 0.18 { return 0 }
        if age >= 0.78 { return 4 }
        return [1, 2, 3, 2, 3, 1][min(5, Int((age - 0.18) / 0.10))]
    }
    static func box(at p: CGPoint) -> CGRect {
        CGRect(x: p.x - 145, y: p.y + 8, width: 290, height: 150)
    }
}
