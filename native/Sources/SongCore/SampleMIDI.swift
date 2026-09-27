import Foundation

/// Writes a simple single-track MIDI guide from the notes already in a sample document.
/// This is intentionally limited to a constant tempo and one melody track.
public enum SampleMIDI {
    public static func encode(_ song: SongDocument) throws -> Data {
        try song.validate()
        guard song.music.tempos.count == 1 else {
            throw SongError.invalid("サンプルMIDIは単一テンポの曲だけを書き出せます。")
        }
        let ticksPerBeat = 480
        struct Message {
            let tick: Int
            let priority: Int
            let bytes: [UInt8]
        }
        var messages: [Message] = []
        let bpm = song.music.tempos[0].bpm
        let micros = Int((60_000_000 / bpm).rounded())
        guard micros > 0, micros <= 0xFF_FF_FF else {
            throw SongError.invalid("MIDIに書き出せないテンポです。")
        }
        messages.append(.init(tick: 0, priority: 0, bytes: [0xFF, 0x51, 0x03,
            UInt8((micros >> 16) & 0xFF), UInt8((micros >> 8) & 0xFF), UInt8(micros & 0xFF)]))
        messages.append(.init(tick: 0, priority: 1, bytes: [0xC0, 0]))
        for event in song.music.events {
            guard let note = event.note else { continue }
            let start = Int((event.onset.doubleValue * Double(ticksPerBeat)).rounded())
            let end = Int(((event.onset.doubleValue + event.duration.doubleValue) * Double(ticksPerBeat)).rounded())
            guard start >= 0, end > start, end <= 100_000_000 else {
                throw SongError.invalid("サンプルMIDIの時間範囲が大きすぎます。")
            }
            messages.append(.init(tick: start, priority: 3, bytes: [0x90, UInt8(note.pitch), UInt8(note.velocity)]))
            messages.append(.init(tick: end, priority: 2, bytes: [0x80, UInt8(note.pitch), 0]))
        }
        messages.sort { ($0.tick, $0.priority) < ($1.tick, $1.priority) }
        var track: [UInt8] = []
        var previous = 0
        for message in messages {
            track += variableLength(message.tick - previous)
            track += message.bytes
            previous = message.tick
        }
        track += [0, 0xFF, 0x2F, 0]
        var result: [UInt8] = Array("MThd".utf8)
        result += bigEndian(6, count: 4) + bigEndian(0, count: 2)
        result += bigEndian(1, count: 2) + bigEndian(ticksPerBeat, count: 2)
        result += Array("MTrk".utf8) + bigEndian(track.count, count: 4) + track
        return Data(result)
    }

    private static func bigEndian(_ value: Int, count: Int) -> [UInt8] {
        (0..<count).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        var remaining = value
        var result = [UInt8(remaining & 0x7F)]
        remaining >>= 7
        while remaining > 0 {
            result.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return result
    }
}
