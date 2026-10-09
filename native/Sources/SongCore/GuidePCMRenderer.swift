import Foundation

/// Deterministic guide audio. Playback renders small chunks off the UI actor.
public enum GuidePCMRenderer {
    public static let sampleRate = 44_100.0

    public static func render(_ plan: PlaybackPlan) throws -> [Float] {
        let frames = ceil(plan.duration * sampleRate)
        guard frames.isFinite, frames > 0, frames < Double(Int.max) else {
            throw SongError.invalid("再生範囲の長さが正しくありません。")
        }
        return try render(plan, startingAt: 0, frameCount: Int(frames))
    }

    /// Render absolute sample frames so notes crossing a chunk boundary keep their phase and envelope.
    public static func render(_ plan: PlaybackPlan, startingAt start: Int, frameCount: Int) throws -> [Float] {
        let end = ceil(plan.duration * sampleRate)
        guard end.isFinite, end > 0, end < Double(Int.max), start >= 0, frameCount > 0,
              start < Int(end), frameCount <= Int(end) - start else {
            throw SongError.invalid("音声の準備範囲が正しくありません。")
        }
        let count = frameCount
        var samples = [Float](repeating: 0, count: count)
        for note in plan.notes {
            try Task<Never, Never>.checkCancellation()
            let first = max(start, Int(floor(note.start * sampleRate)))
            let last = min(start + count, Int(ceil(note.end * sampleRate)))
            guard first < last else { continue }
            let frequency = 440.0 * pow(2, Double(note.pitch - 69) / 12)
            let amplitude = 0.20 * Double(note.velocity) / 127
            for frame in first..<last {
                if frame.isMultiple(of: 16_384) { try Task<Never, Never>.checkCancellation() }
                let instant = Double(frame) / sampleRate
                let elapsed = max(0, instant - note.start)
                let remaining = max(0, note.end - instant)
                let envelope = min(1, elapsed / 0.008, remaining / 0.018)
                samples[frame - start] += Float(amplitude * envelope * sin(2 * .pi * frequency * elapsed))
            }
        }
        for index in samples.indices {
            if index.isMultiple(of: 16_384) { try Task<Never, Never>.checkCancellation() }
            samples[index] = tanh(samples[index])
        }
        return samples
    }
}
