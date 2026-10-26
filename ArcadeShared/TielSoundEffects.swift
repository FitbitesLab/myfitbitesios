import AVFoundation

/// The frame loop only latches events and submits work. AVFoundation never runs here.
@MainActor
final class TielSoundEffects {
    private var events = TielSoundEvents()
    private let owner = UUID()
    private let output = TielSoundOutput.shared
    private static let interface = TielSoundEffects()
    static func preload() { _ = interface }
    static func select(_ action: () -> Void) {
        action()
        interface.output.play([.select], owner: interface.owner)
    }
    /// Reserved for advancing story text when the dialogue screen is introduced.
    static func storyTextDidAdvance() { interface.output.play([.select], owner: interface.owner) }
    static func stopAll() { TielSoundOutput.shared.stopAll() }
    #if DEBUG
    private let performance = ProcessInfo.processInfo.arguments.contains("--tiel-sound-performance") ? TielSoundPerformance() : nil
    #endif

    func update(jumps: Int, stomps: Int = 0, coins: Int, hits: Int = 0, cookies: Int = 0, projectiles: Int = 0, checkpoints: Int = 0, crates: Int = 0, muted: Bool = false) {
        #if DEBUG
        performance?.tick { output.play([$0], owner: owner) }
        #endif
        #if DEBUG
        let auditMuted = TielCoinPerformance.enabled && TielCoinPerformance.silent
        #else
        let auditMuted = false
        #endif
        let cues = events.consume(jumps: jumps, stomps: stomps, coins: coins, hits: hits, cookies: cookies, projectiles: projectiles, checkpoints: checkpoints, crates: crates)
        guard !muted, !auditMuted, !cues.isEmpty else { return }
        output.play(cues, owner: owner)
    }

    func rewardCash() { output.play([.rewardCash],owner:owner) }
    func rewardStamp() { output.play([.rewardStamp],owner:owner) }
    func rewardRico() { output.play([.rewardRico],owner:owner) }
    func dialogueTick() { output.play([.dialogue], owner: owner) }

    func thunder() { output.play([.thunder], owner: owner) }
    func splash() { output.play([.splash], owner: owner) }

    func reset(jumps: Int = 0, stomps: Int = 0, coins: Int = 0, hits: Int = 0, cookies: Int = 0, projectiles: Int = 0, checkpoints: Int = 0, crates: Int = 0) {
        stop()
        events.reset(jumps: jumps, stomps: stomps, coins: coins, hits: hits, cookies: cookies, projectiles: projectiles, checkpoints: checkpoints, crates: crates)
    }

    func stop() { output.stop(owner: owner) }
    deinit { output.stop(owner: owner) }

    #if DEBUG
    func verifyPlayback() { output.verifyPlayback() }
    #endif
}

/// One persistent graph and two reusable voices per cue for every world. All mutable state and
/// AVFoundation calls are confined to this serial queue, including setup and interruption recovery.
private nonisolated final class TielSoundOutput: @unchecked Sendable {
    static let shared = TielSoundOutput()
    private let queue = DispatchQueue(label: "tiel.sound-output", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var buffers: [TielSoundEvents.Cue: AVAudioPCMBuffer] = [:]
    private var voices: [TielSoundEvents.Cue: [AVAudioPlayerNode]] = [:]
    private var cursor: [TielSoundEvents.Cue: Int] = [:]
    private var voiceOwners: [ObjectIdentifier: UUID] = [:]
    private var interrupted = false
    private var lastPreparationAttempt: TimeInterval = -10
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var playbackCounts: [String: Int] = [:]
    #endif

    private init() {
        queue.async { self.prepare() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.interrupted = began
                self.pauseVoices()
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] note in
            guard let changed = note.object as? AVAudioEngine else { return }
            self?.queue.async { [weak self] in
                guard let self, self.engine === changed else { return }
                // Route changes invalidate scheduled player state. Resume on the next cue.
                self.pauseVoices()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.engine = nil; self.buffers.removeAll(); self.voices.removeAll(); self.cursor.removeAll(); self.voiceOwners.removeAll()
                self.prepare()
            }
        })
    }

    private func prepare() {
        dispatchPrecondition(condition: .onQueue(queue))
        precondition(!Thread.isMainThread)
        lastPreparationAttempt = ProcessInfo.processInfo.systemUptime
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let graph = AVAudioEngine()
            var loadedBuffers: [TielSoundEvents.Cue: AVAudioPCMBuffer] = [:]
            var loadedVoices: [TielSoundEvents.Cue: [AVAudioPlayerNode]] = [:]
            for cue in TielSoundEvents.Cue.allCases {
                guard let url = Bundle.main.url(forResource: "tiel-\(cue.rawValue)", withExtension: "wav") else {
                    NSLog("Tiel audio: missing cue %@", cue.rawValue); continue
                }
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return }
                try file.read(into: buffer)
                loadedBuffers[cue] = buffer
                loadedVoices[cue] = (0..<2).map { _ in
                    let voice = AVAudioPlayerNode()
                    graph.attach(voice)
                    graph.connect(voice, to: graph.mainMixerNode, format: buffer.format)
                    voice.volume = cue.volume
                    return voice
                }
            }
            graph.prepare()
            buffers = loadedBuffers; voices = loadedVoices; engine = graph
        } catch {
            // Sound availability must never interrupt gameplay.
            NSLog("Tiel audio preparation failed: %@", String(describing: error))
            engine = nil
        }
    }

    func play(_ cues: [TielSoundEvents.Cue], owner: UUID) {
        let submitted = ProcessInfo.processInfo.systemUptime
        queue.async {
            // Drop late effects after setup or an interruption instead of replaying a backlog.
            guard ProcessInfo.processInfo.systemUptime - submitted < 0.15, !self.interrupted else { return }
            for cue in cues { self.playNow(cue, owner: owner) }
        }
    }

    private func playNow(_ cue: TielSoundEvents.Cue, owner: UUID) {
        dispatchPrecondition(condition: .onQueue(queue))
        precondition(!Thread.isMainThread)
        if engine == nil && !interrupted && ProcessInfo.processInfo.systemUptime-lastPreparationAttempt >= 1 {prepare()}
        guard !interrupted, let engine, let buffer = buffers[cue], let pool = voices[cue] else { return }
        do {
            if !engine.isRunning {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
            }
            let index = cursor[cue, default: 0] % pool.count
            let player = pool[index]
            voiceOwners[ObjectIdentifier(player)] = owner
            // Interrupt only this voice's old buffer; retain the graph and decoded samples.
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
            cursor[cue] = index + 1
            #if DEBUG
            playbackCounts[cue.rawValue, default: 0] += 1
            #endif
        } catch { /* Retry output startup on a later event, off the frame thread. */ }
    }

    func stop(owner: UUID) {
        queue.async { self.stopNow(owner: owner) }
    }

    private func stopNow(owner: UUID) {
        dispatchPrecondition(condition: .onQueue(queue))
        // Stop the departing scene without cutting a menu click or the next world.
        for pool in voices.values { for voice in pool where voiceOwners[ObjectIdentifier(voice)] == owner {
            voice.stop()
            voiceOwners.removeValue(forKey: ObjectIdentifier(voice))
        } }
        if voiceOwners.isEmpty { engine?.pause() }
    }

    func stopAll() {
        queue.async {
            self.pauseVoices()
        }
    }

    private func pauseVoices() {
        dispatchPrecondition(condition: .onQueue(queue))
        for pool in voices.values { for voice in pool { voice.stop() } }
        voiceOwners.removeAll()
        engine?.pause()
    }

    #if DEBUG
    func verifyPlayback() {
        queue.async {
            self.pauseVoices(); self.playbackCounts.removeAll()
            let owner = UUID()
            var latch = TielSoundEvents()
            func update(_ jumps: Int, _ stomps: Int, _ coins: Int, hits: Int = 0, cookies: Int = 0, projectiles: Int = 0, muted: Bool = false) {
                let cues = latch.consume(jumps: jumps, stomps: stomps, coins: coins, hits: hits, cookies: cookies, projectiles: projectiles)
                if !muted { for cue in cues { self.playNow(cue, owner: owner) } }
            }
            var result = ["allSoundsPreloaded": self.buffers.count == TielSoundEvents.Cue.allCases.count && self.voices.values.reduce(0) { $0 + $1.count } == TielSoundEvents.Cue.allCases.count * 2,
                          "audioRunsOffMainThread": !Thread.isMainThread]
            update(1, 0, 0)
            result["jumpStartsPlayback"] = self.playbackCounts["jump"] == 1 && self.engine?.isRunning == true
            update(1, 0, 0)
            result["unchangedStateDoesNotRepeat"] = self.playbackCounts["jump"] == 1
            update(1, 0, 3)
            result["coinClusterIsOneChime"] = self.playbackCounts["coin"] == 1
            update(1, 1, 3)
            result["stompStartsPlayback"] = self.playbackCounts["stomp"] == 1
            update(1, 1, 4, hits: 1, cookies: 1, projectiles: 2)
            result["damageUsesHitStompPreset"] = self.playbackCounts["stomp"] == 2
            result["cookieOverridesOverlappingCoin"] = self.playbackCounts["cookie"] == 1 && self.playbackCounts["coin"] == 1
            result["projectileVolleyIsOneCue"] = self.playbackCounts["projectile"] == 1
            update(1, 1, 4, hits: 1, cookies: 1, projectiles: 2)
            result["newEventsDoNotRepeat"] = self.playbackCounts["cookie"] == 1 && self.playbackCounts["projectile"] == 1 && self.playbackCounts["stomp"] == 2
            self.playNow(.dialogue, owner: owner)
            result["dialogueStartsPlayback"] = self.playbackCounts["dialogue"] == 1 && self.voices[.dialogue]?.contains { $0.isPlaying } == true
            result["dialogueUsesRequestedGain"] = self.voices[.dialogue]?.allSatisfy { abs($0.volume - TielSoundEvents.Cue.dialogue.volume) < 0.00001 } == true
            NSLog("Tiel dialogue gain: requested=%f actual=%@", TielSoundEvents.Cue.dialogue.volume, String(describing:self.voices[.dialogue]?.map { $0.volume }))
            let graph = self.engine
            for _ in 0..<120 { self.playNow(.coin, owner: owner) }
            result["rapidPlaybackReusesGraphAndVoices"] = self.engine === graph && self.voices.values.reduce(0) { $0 + $1.count } == TielSoundEvents.Cue.allCases.count * 2 && self.playbackCounts["coin"] == 121
            self.pauseVoices()
            result["pauseStopsEveryVoice"] = self.voices.values.flatMap { $0 }.allSatisfy { !$0.isPlaying } && self.engine?.isRunning == false
            latch.reset(); update(1, 0, 1, muted: true)
            result["captureModeIsSilent"] = self.engine?.isRunning == false && self.playbackCounts["coin"] == 121
            self.interrupted = true; self.playNow(.jump, owner: owner)
            result["interruptionStaysSilent"] = self.playbackCounts["jump"] == 1
            self.interrupted = false; self.playNow(.jump, owner: owner)
            result["playbackResumes"] = self.playbackCounts["jump"] == 2 && self.engine?.isRunning == true
            let menuOwner = UUID()
            self.playNow(.select, owner: menuOwner)
            result["selectionStartsPlayback"] = self.playbackCounts["select"] == 1
            self.stopNow(owner: owner)
            result["sceneStopPreservesSelection"] = self.voices[.select]?.contains { $0.isPlaying } == true && self.voices[.jump]?.allSatisfy { !$0.isPlaying } == true
            self.stopNow(owner: menuOwner)
            result["lastOwnerStopPausesEngine"] = self.engine?.isRunning == false
            // Story and a subsequent level use independent owners on the same graph.
            let tutorialOwner = UUID(), nextLevelOwner = UUID()
            self.playNow(.jump, owner: tutorialOwner)
            self.playNow(.coin, owner: tutorialOwner)
            self.stopNow(owner: tutorialOwner)
            self.playNow(.jump, owner: nextLevelOwner)
            self.playNow(.coin, owner: nextLevelOwner)
            self.stopNow(owner: tutorialOwner)
            result["tutorialExitPreservesNextLevelSounds"] = self.engine?.isRunning == true
                && self.voices[.jump]?.contains { $0.isPlaying } == true
                && self.voices[.coin]?.contains { $0.isPlaying } == true
            self.stopNow(owner: nextLevelOwner)
            self.pauseVoices(); self.playbackCounts.removeAll()
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tiel-sound-results.json")
            try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
    }
    #endif
}
