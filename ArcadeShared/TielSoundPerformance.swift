#if DEBUG
import QuartzCore
import Foundation

/// Opt-in audit: exercise sound playback while the actual SpriteKit scene renders.
@MainActor
final class TielSoundPerformance {
    private let silent = ProcessInfo.processInfo.arguments.contains("--tiel-sound-performance-silent")
    private var start = 0.0
    private var last = 0.0
    private var nextCue = 0.0
    private var frames: [Double] = []
    private var calls: [Double] = []
    private var triggers = 0
    private var finished = false

    func tick(play: (TielSoundEvents.Cue) -> Void) {
        guard !finished else { return }
        let now = CACurrentMediaTime()
        if start == 0 { start = now; nextCue = now + 2 }
        defer { last = now }
        guard now - start >= 2 else { return }
        if last > 0 { frames.append(now - last) }
        if now >= nextCue {
            nextCue = now + 0.12
            let cue = TielSoundEvents.Cue.allCases[triggers % TielSoundEvents.Cue.allCases.count]
            let before = CACurrentMediaTime()
            if !silent { play(cue) }
            calls.append(CACurrentMediaTime() - before)
            triggers += 1
        }
        guard now - start >= 12 else { return }
        finished = true
        func stats(_ samples: [Double]) -> [String: Double] {
            let sorted = samples.sorted()
            return ["p95ms": sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000,
                    "p99ms": sorted[Int(Double(sorted.count - 1) * 0.99)] * 1000,
                    "maxMs": (sorted.last ?? 0) * 1000]
        }
        let report: [String: Any] = ["silent": silent, "frames": frames.count,
            "fps": Double(frames.count) / frames.reduce(0, +), "frame": stats(frames),
            "soundCall": stats(calls), "triggers": triggers]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tiel-sound-performance.json")
        DispatchQueue.global(qos: .utility).async {
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
    }
}
#endif

#if DEBUG
/// Same real pickup path in each mode; only audio/effects/HUD are isolated.
@MainActor
final class TielCoinPerformance {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--tiel-coin-profile")
    static let silent = ProcessInfo.processInfo.arguments.contains("--coin-profile-silent")
    static let noEffects = ProcessInfo.processInfo.arguments.contains("--coin-profile-no-effects")
    static let noHUD = ProcessInfo.processInfo.arguments.contains("--coin-profile-no-hud")
    private var start = 0.0, last = 0.0, next = 0.0
    private var frames: [Double] = [], costs: [Double] = []
    private var done = false
    private(set) var triggers = 0
    func begin(_ now: Double) -> Bool {
        guard !done else { return false }
        if start == 0 { start = now; next = now + 2 }
        defer { last = now }
        guard now-start >= 2 else { return false }
        if last > 0 { frames.append(now-last) }
        if now-start >= 12 {
            done = true
            func stats(_ a: [Double]) -> [String:Double] {
                let a=a.sorted();guard !a.isEmpty else { return [:] }
                return ["p95ms":a[Int(Double(a.count-1)*0.95)]*1000,"p99ms":a[Int(Double(a.count-1)*0.99)]*1000,"maxMs":a.last!*1000]
            }
            let result:[String:Any] = ["silent":Self.silent,"noEffects":Self.noEffects,"noHUD":Self.noHUD,"triggers":triggers,"frames":frames.count,"fps":Double(frames.count)/frames.reduce(0,+),"frame":stats(frames),"update":stats(costs),"over25ms":frames.filter{$0>0.025}.count]
            let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("coin-profile.json")
            DispatchQueue.global(qos:.utility).async { try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:url) }
            return false
        }
        guard now >= next else { return false }
        next=now+0.12;triggers+=1;return true
    }
    func record(_ cost: Double) { if !done && triggers>0 { costs.append(cost) } }
}
#endif
