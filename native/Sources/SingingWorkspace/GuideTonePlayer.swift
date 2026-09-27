import AVFoundation
import SongCore

/// Plays the document's guide notes as a plain sine tone. It does not synthesize a voice.
@MainActor
final class GuideTonePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private var startingBeat = 0.0
    private var playbackBPM = 88.0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!)
    }

    func stop() { player.stop() }

    var position: Double? {
        guard player.isPlaying, let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime) else { return nil }
        return startingBeat + Double(playerTime.sampleTime) / playerTime.sampleRate * playbackBPM / 60
    }

    func play(song: SongDocument, phrase: Phrase, fromBeat: Double, bpm: Double) throws {
        guard let range = phrase.timeRange, bpm > 0 else { return }
        let endBeat = range.end.doubleValue
        guard fromBeat < endBeat else { return }
        let secondsPerBeat = 60.0 / bpm
        let frames = Int(ceil((endBeat - fromBeat) * secondsPerBeat * sampleRate))
        guard frames > 0, frames <= Int(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0),
                                            frameCapacity: UInt32(frames)),
              let output = buffer.floatChannelData?[0] else { return }
        let notes = phrase.musicalEventIDs.compactMap { song.event($0) }
            .compactMap { event -> (start: Double, end: Double, pitch: Int)? in
                guard let note = event.note else { return nil }
                return (event.onset.doubleValue,
                        event.onset.doubleValue + event.duration.doubleValue, note.pitch)
            }.sorted { $0.start < $1.start }
        var index = 0
        for frame in 0..<frames {
            let beat = fromBeat + Double(frame) / sampleRate / secondsPerBeat
            while index < notes.count && beat >= notes[index].end { index += 1 }
            guard index < notes.count, beat >= notes[index].start else {
                output[frame] = 0
                continue
            }
            let note = notes[index]
            let elapsed = (beat - note.start) * secondsPerBeat
            let remaining = (note.end - beat) * secondsPerBeat
            let envelope = min(1, elapsed / 0.012, remaining / 0.035)
            let frequency = 440.0 * pow(2.0, Double(note.pitch - 69) / 12.0)
            output[frame] = Float(0.22 * max(0, envelope) * sin(2 * .pi * frequency * elapsed))
        }
        buffer.frameLength = UInt32(frames)
        player.stop()
        if !engine.isRunning { try engine.start() }
        startingBeat = fromBeat
        playbackBPM = bpm
        player.scheduleBuffer(buffer)
        player.play()
    }
}
