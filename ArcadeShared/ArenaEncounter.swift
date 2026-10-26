import Foundation

/// Three finite waves, with arrivals capped at four living enemies at a time.
struct ArenaEncounter {
    static let count = 18
    static let waveSize = 6
    static func kind(at index: Int) -> KitchenEnemyKind {
        index < waveSize ? .goblin : (index % 2 == 0 ? .devPresso : .proteinToaster)
    }
    // Alternate pairs so each appliance type arrives from both sides.
    static func entersLeft(_ index: Int) -> Bool { (index % 4 == 0 || index % 4 == 3) }
    private(set) var spawned = 0
    private(set) var wave = 1
    private var nextArrival: TimeInterval = 0
    var cleared: Bool { spawned == Self.count }

    mutating func arrivals(at time: TimeInterval, living: Int, defeated: Int) -> [Int] {
        guard defeated < Self.count else { return [] }
        if spawned == wave * Self.waveSize && living == 0 && wave < 3 {
            wave += 1
            nextArrival = time + 1.2
        }
        guard time >= nextArrival, living <= 2, spawned < wave * Self.waveSize else { return [] }
        let ids = Array(spawned..<min(spawned + 2, wave * Self.waveSize))
        spawned += ids.count
        nextArrival = time + 2.6
        return ids
    }
}
