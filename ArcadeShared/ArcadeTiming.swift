import Foundation

/// Release cuts the ascent; holding preserves it, but never adds a second impulse.
struct JumpMotion {
    private(set) var height: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private(set) var held = false

    mutating func press() {
        guard !held else { return }
        held = true
        guard height == 0 else { return }
        velocity = 540
        height = 0.1
    }

    mutating func release() {
        held = false
        if velocity > 220 { velocity = 220 }
    }

    mutating func update(_ dt: TimeInterval) {
        guard height > 0 else { return }
        velocity -= 1150 * dt
        height = max(0, height + velocity * dt)
        if height == 0 { velocity = 0 }
    }
}

/// Deliberate, hit-confirmed punches. Input during a hold/recovery is discarded.
struct ArcadeCombo {
    static let timingScale: TimeInterval = 0.25
    private(set) var frame = 0
    private(set) var serial = 0
    private(set) var started: TimeInterval = -.infinity
    private(set) var activeUntil: TimeInterval = 0
    private(set) var readyAt: TimeInterval = 0
    private var chainUntil: TimeInterval = -.infinity
    private var landed = false
    func active(at time: TimeInterval) -> Bool { time >= started && time < activeUntil }
    func locked(at time: TimeInterval) -> Bool { time < readyAt }
    /// Rendering outlives damage frames: never flash idle between taps, including misses.
    func holdingPose(at time: TimeInterval) -> Bool {
        active(at: time) || locked(at: time) || (frame < 2 && time <= chainUntil)
    }

    mutating func press(at time: TimeInterval) {
        guard !locked(at: time) else { return }
        frame = landed && time <= chainUntil && frame < 2 ? frame + 1 : 0
        serial += 1; started = time; landed = false
        activeUntil = time + (frame == 2 ? 0.48 : 0.32) * Self.timingScale
        readyAt = activeUntil + (frame == 2 ? 0.65 : 0.12) * Self.timingScale
        chainUntil = frame == 2 ? -.infinity : readyAt + 0.55
    }
    func canHit(at time: TimeInterval) -> Bool {
        guard active(at: time), !landed else { return false }
        return (frame == 2 ? 0.10..<0.32 : 0.04..<0.24).contains((time - started) / Self.timingScale)
    }
    mutating func markHit(at time: TimeInterval) {
        if canHit(at: time) { landed = true }
    }
    mutating func cancelChain() { chainUntil = -.infinity }
}

/// Each accepted press starts one strike; impact holds cannot be skipped.
/// Late follow-ups restart at forehand. Finisher recovery discards all input.
struct SpatulaCombo {
    static let timingScale: TimeInterval = 0.25
    private(set) var started: TimeInterval = -.infinity
    private(set) var readyAt: TimeInterval = 0
    private(set) var strike = 0
    private var activeUntil: TimeInterval = 0
    private var chainUntil: TimeInterval = -.infinity
    private var landed = false
    static let impactHold: TimeInterval = 0.38 * timingScale
    static let followUpWindow: TimeInterval = 0.60
    static let recovery: TimeInterval = 0.65 * timingScale
    func active(at time: TimeInterval) -> Bool { time >= started && time < activeUntil }
    func locked(at time: TimeInterval) -> Bool { time < readyAt }
    func holdingPose(at time: TimeInterval) -> Bool {
        active(at: time) || locked(at: time) || (strike < 2 && time <= chainUntil)
    }

    mutating func press(at time: TimeInterval) {
        guard !locked(at: time) else { return }
        strike = landed && time <= chainUntil && strike < 2 ? strike + 1 : 0
        started = time
        activeUntil = time + (strike == 2 ? 0.70 * Self.timingScale : Self.impactHold)
        readyAt = activeUntil + (strike == 2 ? Self.recovery : 0.12 * Self.timingScale)
        chainUntil = strike == 2 ? -.infinity : readyAt + Self.followUpWindow
        landed = false
    }
    func frame(at time: TimeInterval) -> Int {
        guard strike == 2 else { return strike }
        switch (time - started) / Self.timingScale {
        case ..<0.12: return 2
        case ..<0.24: return 3
        case ..<0.38: return 4
        default: return 5
        }
    }
    func hit(at time: TimeInterval) -> Int? {
        guard active(at: time), !landed else { return nil }
        let elapsed = (time - started) / Self.timingScale
        let window = strike == 2 ? 0.42..<0.60 : 0.04..<0.22
        return window.contains(elapsed) ? strike : nil
    }
    mutating func cancelChain() { chainUntil = -.infinity }
    mutating func markHit(_ hit: Int) { if hit == strike { landed = true } }
    mutating func cancel(at time: TimeInterval) {
        started = -.infinity; activeUntil = 0; chainUntil = -.infinity
        readyAt = max(readyAt, time + Self.recovery)
    }
}
