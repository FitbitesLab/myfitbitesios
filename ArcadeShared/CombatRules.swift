import Foundation
import CoreGraphics

/// All boxes are logical world units relative to ground center, independent of PNG padding.
enum CombatBoxes {
    static func tooBody(at p: CGPoint) -> CGRect {
        CGRect(x: p.x - 28, y: p.y + 12, width: 56, height: 110)
    }
    static func goblinBody(at p: CGPoint) -> CGRect {
        CGRect(x: p.x - 32, y: p.y + 8, width: 64, height: 86)
    }
    static func punch(at p: CGPoint, facing: CGFloat, uppercut: Bool) -> CGRect {
        directed(at: p, facing: facing, offset: 24, bottom: uppercut ? 22 : 40,
                 width: uppercut ? 82 : 88, height: uppercut ? 110 : 65)
    }
    static func spatula(at p: CGPoint, facing: CGFloat, uppercut: Bool) -> CGRect {
        directed(at: p, facing: facing, offset: 10, bottom: uppercut ? 30 : 40,
                 width: uppercut ? 115 : 140, height: uppercut ? 135 : 65)
    }
    static func kick(at p: CGPoint, facing: CGFloat) -> CGRect {
        directed(at: p, facing: facing, offset: 22, bottom: 12, width: 78, height: 52)
    }
    private static func directed(at p: CGPoint, facing: CGFloat, offset: CGFloat,
                                 bottom: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: facing < 0 ? p.x - offset - width : p.x + offset,
               y: p.y + bottom, width: width, height: height)
    }
}

struct TooDamage {
    enum Reaction { case hit, knockdown }
    private(set) var health = 5
    private(set) var reaction: Reaction = .hit
    private(set) var started: TimeInterval = -.infinity
    private(set) var lockedUntil: TimeInterval = 0
    private(set) var invulnerableUntil: TimeInterval = 0
    var defeated: Bool { health == 0 }
    func locked(at time: TimeInterval) -> Bool { defeated || time < lockedUntil }
    mutating func receive(at time: TimeInterval, heavy: Bool) -> Bool {
        guard !defeated, time >= invulnerableUntil else { return false }
        health -= 1
        reaction = heavy || defeated ? .knockdown : .hit
        started = time
        lockedUntil = time + (reaction == .hit ? 0.28 : 1.10)
        invulnerableUntil = lockedUntil + 0.65
        return true
    }
    func frame(at time: TimeInterval) -> Int {
        if defeated { return 0 }
        let elapsed = time - started
        if reaction == .hit { return elapsed < 0.07 ? 0 : (elapsed < 0.19 ? 1 : 2) }
        switch elapsed {
        case ..<0.35: return 0
        case ..<0.52: return 1
        case ..<0.70: return 2
        case ..<0.90: return 3
        default: return 4
        }
    }
}

struct GoblinAttack {
    enum Phase { case idle, warning, active, recovery }
    private(set) var phase: Phase = .idle
    private(set) var facing: CGFloat = -1
    private(set) var count = 0
    private var until: TimeInterval = 0
    private(set) var landed = false
    var heavy: Bool { count % 3 == 0 }
    mutating func update(at time: TimeInterval, distance: CGFloat, enabled: Bool) {
        guard enabled else { interrupt(at: time); return }
        switch phase {
        case .idle:
            if time >= until && abs(distance) < 135 {
                count += 1; facing = distance < 0 ? -1 : 1
                phase = .warning; until = time + 0.6; landed = false
            }
        case .warning:
            if time >= until { phase = .active; until = time + 0.16 }
        case .active:
            if time >= until { phase = .recovery; until = time + 0.65 }
        case .recovery:
            if time >= until { phase = .idle; until = time + 0.35 }
        }
    }
    mutating func markLanded() { landed = true }
    mutating func interrupt(at time: TimeInterval) {
        phase = .idle; until = time + 0.55; landed = false
    }
}

/// Every landed strike removes one point, including the four-pose finisher.
struct GoblinHealth {
    private(set) var hitsRemaining = 9
    var defeated: Bool { hitsRemaining == 0 }
    @discardableResult mutating func receive() -> Bool {
        guard !defeated else { return false }
        hitsRemaining -= 1
        return true
    }
}
