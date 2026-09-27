import Foundation

/// Deterministic guide audio. A complete range is rendered off the UI actor.
public enum GuidePCMRenderer {
    public static let sampleRate = 44_100.0

    public static func render(_ plan: PlaybackPlan) throws -> [Float] {
        let count = Int(ceil(plan.duration * sampleRate))
        guard count > 0, count <= Int(300 * sampleRate) else {
            throw SongError.invalid("再生は5分までです。短い小節範囲を選んでください。")
        }
        var samples = [Float](repeating: 0, count: count)
        for note in plan.notes {
            try Task<Never, Never>.checkCancellation()
            let first = max(0, Int(floor(note.start * sampleRate)))
            let last = min(count, Int(ceil(note.end * sampleRate)))
            guard first < last else { continue }
            let frequency = 440.0 * pow(2, Double(note.pitch - 69) / 12)
            let amplitude = 0.20 * Double(note.velocity) / 127
            for frame in first..<last {
                if frame.isMultiple(of: 16_384) { try Task<Never, Never>.checkCancellation() }
                let instant = Double(frame) / sampleRate
                let elapsed = max(0, instant - note.start)
                let remaining = max(0, note.end - instant)
                let envelope = min(1, elapsed / 0.008, remaining / 0.018)
                samples[frame] += Float(amplitude * envelope * sin(2 * .pi * frequency * elapsed))
            }
        }
        for index in samples.indices {
            if index.isMultiple(of: 16_384) { try Task<Never, Never>.checkCancellation() }
            samples[index] = tanh(samples[index])
        }
        return samples
    }
}
