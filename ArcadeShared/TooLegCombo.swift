import Foundation
import CoreGraphics

/// One press plays the complete nine-pose combo. Each impact can score once.
struct TooLegCombo {
    static let timings: [TimeInterval] = [0.12,0.14,0.10,0.15,0.10,0.13,0.17,0.13,0.18]
    static let impactFrames = [1,3,6] // Supplied frames 02, 04, 07.
    static var duration: TimeInterval { timings.reduce(0,+) }
    static let recovery: TimeInterval = 0.16
    private(set) var started: TimeInterval = -.infinity
    private var claimed = Set<Int>()
    func active(at time: TimeInterval) -> Bool { time >= started && time-started < Self.duration }
    func locked(at time: TimeInterval) -> Bool { time >= started && time-started < Self.duration+Self.recovery }
    @discardableResult mutating func press(at time: TimeInterval) -> Bool {
        guard !locked(at: time) else { return false }
        started = time; claimed.removeAll(); return true
    }
    func frame(at time: TimeInterval) -> Int {
        let age = time-started
        var end: TimeInterval = 0
        for (index,duration) in Self.timings.enumerated() {
            end += duration
            if age < end { return index }
        }
        return 8 // Guard during recovery.
    }
    func hit(at time: TimeInterval) -> Int? {
        guard active(at: time), let strike = Self.impactFrames.firstIndex(of: frame(at: time)), !claimed.contains(strike) else { return nil }
        return strike
    }
    mutating func markHit(_ strike: Int) { claimed.insert(strike) }
    mutating func cancel() { started = -.infinity; claimed.removeAll() }
    static func box(at p: CGPoint, facing: CGFloat, strike: Int) -> CGRect {
        let width: CGFloat = strike == 2 ? 155 : 140
        let bottom: CGFloat = strike == 1 ? 28 : 12
        let height: CGFloat = strike == 1 ? 125 : 90
        return CGRect(x: facing < 0 ? p.x-22-width : p.x+22,y: p.y+bottom,width: width,height: height)
    }
}
