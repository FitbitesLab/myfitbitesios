import Foundation
import CoreGraphics

enum KitchenEnemyKind {
    case goblin, devPresso, proteinToaster
    var clip: String { self == .devPresso ? "dev-presso" : "protein-toaster" }
    var height: CGFloat { self == .devPresso ? 135 : 125 }
}

/// Aim is captured at release; shots never home after Too dodges.
struct KitchenProjectileMotion {
    let origin: CGPoint
    let velocity: CGVector
    let gravity: CGFloat
    let duration: TimeInterval
    let spinning: Bool
    init(origin: CGPoint, target: CGPoint, arcing: Bool) {
        self.origin = origin
        spinning = !arcing
        let dx = target.x - origin.x, dy = target.y - origin.y
        if arcing {
            duration = max(1.0, min(1.5, Double(abs(dx) / 300)))
            gravity = 700
            velocity = CGVector(dx: dx / duration, dy: (dy + 0.5 * gravity * duration * duration) / duration)
        } else {
            duration = max(0.1, Double(hypot(dx, dy) / 290))
            gravity = 0
            velocity = CGVector(dx: dx / duration, dy: dy / duration)
        }
    }
    func position(at age: TimeInterval) -> CGPoint {
        CGPoint(x: origin.x + velocity.dx * age,
                y: origin.y + velocity.dy * age - 0.5 * gravity * age * age)
    }
    func rotation(at age: TimeInterval) -> CGFloat {
        spinning ? CGFloat(age) * 11 * (velocity.dx < 0 ? 1 : -1)
            : atan2(velocity.dy - gravity * age, velocity.dx) - .pi / 4
    }
    /// Segment/expanded-body intersection prevents tunneling during fast frames.
    static func hits(from a: CGPoint, to b: CGPoint, body: CGRect, radius: CGFloat) -> Bool {
        let box = body.insetBy(dx: -radius, dy: -radius)
        var low: CGFloat = 0, high: CGFloat = 1
        for (start, delta, minimum, maximum) in [(a.x, b.x-a.x, box.minX, box.maxX), (a.y, b.y-a.y, box.minY, box.maxY)] {
            if abs(delta) < 0.00001 { if start < minimum || start > maximum { return false } }
            else {
                let t1 = (minimum-start)/delta, t2 = (maximum-start)/delta
                low = max(low, min(t1,t2)); high = min(high, max(t1,t2))
                if low > high { return false }
            }
        }
        return true
    }
}

struct KitchenRangedAttack {
    enum Phase { case ready, warning, release, recovery }
    private(set) var phase: Phase = .ready
    private var until: TimeInterval = 0
    /// Returns true exactly once per throw, at the release frame.
    mutating func update(at time: TimeInterval, inRange: Bool, enabled: Bool) -> Bool {
        guard enabled else { interrupt(at: time); return false }
        switch phase {
        case .ready:
            if inRange && time >= until { phase = .warning; until = time + 0.7 }
        case .warning:
            if !inRange { interrupt(at: time) }
            else if time >= until { phase = .release; until = time + 0.25; return true }
        case .release:
            if time >= until { phase = .recovery; until = time + 1.7 }
        case .recovery:
            if time >= until { phase = .ready }
        }
        return false
    }
    mutating func interrupt(at time: TimeInterval) { phase = .ready; until = time + 0.65 }
}

/// Three impact ticks and six recovery ticks at 20 animation ticks per second.
/// Matches the existing 0.45-second combat stun; never relies on display refresh rate.
enum KitchenHitReaction {
    static let impactDuration: TimeInterval = 0.15
    static let duration: TimeInterval = 0.45
    static func frame(age: TimeInterval) -> Int? {
        guard age >= 0, age < duration else { return nil }
        return age < impactDuration ? 0 : 1
    }
}
