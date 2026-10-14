import AVFoundation
import SongCore

enum GuideState: Equatable { case stopped, preparing, playing, paused, failed }

/// The player sample clock is the only transport clock. UI timers only read it.
@MainActor
final class GuideTonePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let auditionNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: GuidePCMRenderer.sampleRate, channels: 1)!
    private let chunkFrames = Int(8 * GuidePCMRenderer.sampleRate)
    private var generation: UInt64 = 0
    private var renderTask: Task<[Float], Error>?
    private var plan: PlaybackPlan?
    private var nextFrame = 0
    private var totalFrames = 0
    private var startingElapsed = 0.0
    private var pausedPosition: Double?
    private var loop = false
    private(set) var state = GuideState.stopped
    nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?  // written once in init
    var onFinished: (@MainActor () -> Void)?
    /// Called when the output device configuration changed and playback was cancelled.
    var onInterrupted: (@MainActor () -> Void)?
    var onError: (@MainActor (Error) -> Void)?

    init() {
        engine.attach(player)
        engine.attach(auditionNode)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(auditionNode, to: engine.mainMixerNode, format: format)
        // The engine stops itself when the output device changes; scheduled buffers are gone.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    private func handleConfigurationChange() {
        let wasActive = state != .stopped && state != .failed
        stop()
        if wasActive { onInterrupted?() }
    }

    func stop() {
        generation &+= 1
        renderTask?.cancel(); renderTask = nil
        player.stop(); auditionNode.stop()
        plan = nil; nextFrame = 0; totalFrames = 0; pausedPosition = nil; state = .stopped
    }

    func pause() {
        guard state == .playing else { return }
        pausedPosition = position
        player.pause(); state = .paused
    }

    /// Returns false when the engine can no longer continue (for example after a device change).
    @discardableResult
    func resume() -> Bool {
        guard state == .paused else { return false }
        guard engine.isRunning else { stop(); return false }
        player.play(); pausedPosition = nil; state = .playing
        return true
    }

    var position: Double? {
        if state == .paused { return pausedPosition }
        guard state == .playing, let plan,
              let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime) else { return nil }
        let elapsed = startingElapsed + Double(playerTime.sampleTime) / playerTime.sampleRate
        let inRange = loop ? elapsed.truncatingRemainder(dividingBy: plan.duration) : min(elapsed, plan.duration)
        return plan.beat(at: inRange)
    }

    func play(song: SongDocument, range: BeatRange, fromBeat: Double, bpm: Double, loop: Bool) async throws {
        stop()
        let token = generation
        state = .preparing
        do {
            let plan = try PlaybackPlan(song: song, range: range, practiceBPM: bpm)
            let frames = ceil(plan.duration * GuidePCMRenderer.sampleRate)
            guard frames.isFinite, frames > 0, frames < Double(Int.max) else {
                throw SongError.invalid("再生範囲の長さが正しくありません。")
            }
            let rangeStartSeconds = plan.tempo.seconds(at: range.start.doubleValue)
            let offset = min(plan.duration, max(0, plan.tempo.seconds(at: fromBeat) - rangeStartSeconds))
            let firstFrame = min(Int(frames) - 1, Int(floor(offset * GuidePCMRenderer.sampleRate)))
            if !engine.isRunning { try engine.start() }
            self.plan = plan; self.loop = loop
            self.totalFrames = Int(frames); self.nextFrame = firstFrame
            self.startingElapsed = Double(firstFrame) / GuidePCMRenderer.sampleRate
            // Keep two short buffers queued. The completion of each consumed buffer
            // prepares the next one, so a long song never occupies one giant buffer.
            try await scheduleNextChunk(token: token)
            try await scheduleNextChunk(token: token)
            guard generation == token else { throw CancellationError() }
            player.play()
            state = .playing
        } catch {
            if generation == token {
                renderTask = nil; player.stop(); state = .failed
            }
            throw error
        }
    }

    private func scheduleNextChunk(token: UInt64) async throws {
        guard generation == token, let plan else { throw CancellationError() }
        if nextFrame >= totalFrames {
            guard loop else { return }
            nextFrame = 0
        }
        let start = nextFrame
        let count = min(chunkFrames, totalFrames - start)
        nextFrame += count
        let task = Task.detached(priority: .userInitiated) {
            try GuidePCMRenderer.render(plan, startingAt: start, frameCount: count)
        }
        renderTask = task
        let samples = try await task.value
        guard generation == token else { throw CancellationError() }
        renderTask = nil
        let buffer = try makeBuffer(samples)
        if !loop && start + count == totalFrames {
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.state = .stopped
                    self.onFinished?()
                }
            }
        } else {
            player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    do { try await self.scheduleNextChunk(token: token) }
                    catch {
                        guard self.generation == token else { return }
                        self.stop()
                        self.state = .failed
                        self.onError?(error)
                    }
                }
            }
        }
    }

    private func makeBuffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        guard samples.count <= Int(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(samples.count)),
              let output = buffer.floatChannelData?[0] else {
            throw SongError.invalid("音声の準備に失敗しました。")
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { output.update(from: base, count: samples.count) }
        }
        buffer.frameLength = UInt32(samples.count)
        return buffer
    }

    func audition(pitch: Int) {
        guard (0...127).contains(pitch) else { return }
        auditionNode.stop()
        let frames = Int(0.32 * GuidePCMRenderer.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames)),
              let output = buffer.floatChannelData?[0] else { return }
        let frequency = 440.0 * pow(2, Double(pitch - 69) / 12)
        for frame in 0..<frames {
            let time = Double(frame) / GuidePCMRenderer.sampleRate
            let envelope = min(1, time / 0.008, (0.32 - time) / 0.025)
            output[frame] = Float(0.13 * max(0, envelope) * sin(2 * .pi * frequency * time))
        }
        buffer.frameLength = UInt32(frames)
        do {
            if !engine.isRunning { try engine.start() }
            auditionNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            auditionNode.play()
        } catch { auditionNode.stop() }
    }

    func stopAudition() { auditionNode.stop() }
}
