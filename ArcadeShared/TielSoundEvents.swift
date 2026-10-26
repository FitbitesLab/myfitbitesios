/// Presentation events are latched from confirmed simulation counters, never raw button presses.
nonisolated struct TielSoundEvents {
    enum Cue: String, CaseIterable {
        case jump, coin, stomp, select, projectile, cookie, thunder, checkpoint, crate, dialogue, rewardCash, rewardStamp, rewardRico, splash
        var volume: Float {
            switch self {
            case .splash: return 0.45
            case .rewardCash: return 0.20
            case .rewardStamp: return 0.32
            case .rewardRico: return 0.27
            case .dialogue: return 0.80 // Stronger dialogue presence on phone speakers; other cues retain their mix.
            case .crate: return 0.48 // Audible wood impact over the stage music.
            case .cookie: return 0.16 // Soft munch and bonus cue.
            case .checkpoint: return 0.45 // Raised 25% from 0.36.
            case .thunder: return 0.23
            case .select: return 0.18
            case .coin: return 0.135 // Reduced 10% from 0.15.
            case .projectile: return 0.22
            case .stomp: return 0.27
            default: return 0.30
            }
        }
    }
    private var previous = Snapshot()
    struct Snapshot {
        var jumps = 0
        var stomps = 0
        var coins = 0
        var hits = 0
        var cookies = 0
        var projectiles = 0
        var checkpoints = 0
        var crates = 0
    }
    mutating func reset(jumps: Int = 0, stomps: Int = 0, coins: Int = 0, hits: Int = 0, cookies: Int = 0, projectiles: Int = 0, checkpoints: Int = 0, crates: Int = 0) {
        previous = Snapshot(jumps:jumps,stomps:stomps,coins:coins,hits:hits,cookies:cookies,projectiles:projectiles,checkpoints:checkpoints,crates:crates)
    }
    mutating func consume(jumps: Int, stomps: Int, coins: Int, hits: Int = 0, cookies: Int = 0, projectiles: Int = 0, checkpoints: Int = 0, crates: Int = 0) -> [Cue] {
        let old = previous
        previous = Snapshot(jumps:jumps,stomps:stomps,coins:coins,hits:hits,cookies:cookies,projectiles:projectiles,checkpoints:checkpoints,crates:crates)
        // A restart/debug reposition must not replay pickups or old impacts.
        guard jumps >= old.jumps, stomps >= old.stomps, coins >= old.coins,
              hits >= old.hits, cookies >= old.cookies, projectiles >= old.projectiles, checkpoints >= old.checkpoints, crates >= old.crates else { return [] }
        var result: [Cue] = []
        if stomps > old.stomps || hits > old.hits { result.append(.stomp) }
        else if jumps > old.jumps { result.append(.jump) }
        // Multiple coins collected in the same physics frame make one gentle chime.
        // Give a B Cookie its own reward sound if it overlaps an ordinary coin.
        if cookies > old.cookies { result.append(.cookie) }
        else if coins > old.coins { result.append(.coin) }
        if projectiles > old.projectiles { result.append(.projectile) }
        if crates > old.crates { result.append(.crate) }
        if checkpoints > old.checkpoints { result.append(.checkpoint) }
        return result
    }
}
