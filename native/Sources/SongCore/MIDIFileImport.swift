import Foundation

/// Reads a Standard MIDI File (format 0/1, PPQ) into candidate parts (MUSIC_IO.md, ADR016).
/// Times stay exact rationals (tick / PPQ); quantizing is an explicit, optional step at import.
public struct MIDIFileImport: Sendable {
    public struct RawNote: Sendable, Equatable {
        public let onTick: Int
        public let offTick: Int
        public let pitch: Int
        public let velocity: Int
    }

    /// One track (format 1) or one channel of a track (format 0) that contains notes.
    public struct Candidate: Sendable, Identifiable, Equatable {
        public let id: Int
        public let track: Int
        public let channel: Int
        public let name: String
        public let notes: [RawNote]
        public var pitchRange: ClosedRange<Int> { (notes.map(\.pitch).min() ?? 60)...(notes.map(\.pitch).max() ?? 60) }
        /// Notes overlapping in time: the staff will fall back to the piano roll for this part.
        public var isPolyphonic: Bool {
            let sorted = notes.sorted { $0.onTick < $1.onTick }
            return zip(sorted, sorted.dropFirst()).contains { $1.onTick < $0.offTick }
        }
    }

    public let format: Int
    public let ticksPerQuarter: Int
    public let tempos: [(tick: Int, bpm: Double)]
    public let meters: [(tick: Int, numerator: Int, denominator: Int)]
    public let candidates: [Candidate]
    public let diagnostics: [String]

    public static func parse(_ data: Data) throws -> MIDIFileImport {
        guard data.count <= 20_000_000 else { throw SongError.invalid("MIDIファイルが大きすぎます（上限20MB）。") }
        var reader = ByteReader(bytes: [UInt8](data))
        guard try reader.ascii(4) == "MThd" else { throw SongError.invalid("MIDIファイル（SMF）ではありません。") }
        let headerLength = try reader.uint(4)
        guard headerLength >= 6 else { throw SongError.invalid("MIDIのヘッダーが壊れています。") }
        let format = try reader.uint(2), trackCount = try reader.uint(2), division = try reader.uint(2)
        try reader.skip(headerLength - 6)
        guard format != 2 else { throw SongError.invalid("format 2（独立した複数パターン）のMIDIにはまだ対応していません。") }
        guard format <= 1 else { throw SongError.invalid("対応しないMIDI形式です（format \(format)）。") }
        guard division & 0x8000 == 0 else { throw SongError.invalid("SMPTE時間のMIDIにはまだ対応していません。拍（PPQ）形式で書き出してください。") }
        guard division > 0 else { throw SongError.invalid("MIDIの分解能が0です。") }
        var tempos: [(Int, Double)] = []
        var meters: [(Int, Int, Int)] = []
        var candidates: [Candidate] = []
        var diagnostics: [String] = []
        for track in 0..<trackCount {
            guard reader.remaining >= 8 else {
                diagnostics.append("ヘッダーでは\(trackCount)トラックですが、\(track)トラックで終わっています。")
                break
            }
            let chunk = try reader.ascii(4), length = try reader.uint(4)
            guard chunk == "MTrk" else { try reader.skip(length); continue }
            guard length <= reader.remaining else { throw SongError.invalid("MIDIファイルが途中で切れています（トラック\(track + 1)）。") }
            var body = ByteReader(bytes: Array(reader.bytes[reader.offset..<(reader.offset + length)]))
            try reader.skip(length)
            var tick = 0
            var runningStatus: UInt8?
            var name = ""
            var open: [Int: [(tick: Int, velocity: Int)]] = [:] // key: channel * 128 + pitch, FIFO
            var notes: [Int: [RawNote]] = [:]                   // key: channel
            var unmatchedOffs = 0
            while body.remaining > 0 {
                tick += try body.variableLength()
                var status = try body.byte()
                if status < 0x80 {
                    guard let running = runningStatus else { throw SongError.invalid("MIDIデータの順序が壊れています（running status）。") }
                    body.offset -= 1; status = running
                }
                switch status {
                case 0xFF:
                    let type = try body.byte(), length = try body.variableLength()
                    let payload = try body.take(length)
                    switch type {
                    case 0x03 where name.isEmpty: name = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    case 0x51 where payload.count == 3:
                        let micros = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                        if micros > 0 { tempos.append((tick, 60_000_000 / Double(micros))) }
                    case 0x58 where payload.count >= 2:
                        let denominator = 1 << Int(payload[1])
                        if payload[0] > 0 && denominator <= 128 { meters.append((tick, Int(payload[0]), denominator)) }
                    case 0x2F: body.offset = body.bytes.count
                    default: break // lyrics, markers, key signature: the original file is kept in source/
                    }
                    runningStatus = nil
                case 0xF0, 0xF7:
                    try body.skip(try body.variableLength()); runningStatus = nil
                default:
                    runningStatus = status
                    let kind = status & 0xF0, channel = Int(status & 0x0F)
                    let first = Int(try body.byte())
                    let second = (kind == 0xC0 || kind == 0xD0) ? 0 : Int(try body.byte())
                    let key = channel * 128 + first
                    if kind == 0x90 && second > 0 {
                        open[key, default: []].append((tick, second))
                    } else if kind == 0x80 || (kind == 0x90 && second == 0) {
                        if var queue = open[key], !queue.isEmpty {
                            let start = queue.removeFirst()
                            open[key] = queue
                            if tick > start.tick { notes[channel, default: []].append(.init(onTick: start.tick, offTick: tick, pitch: first, velocity: start.velocity)) }
                        } else { unmatchedOffs += 1 }
                    }
                }
            }
            let dangling = open.values.reduce(0) { $0 + $1.count }
            if dangling > 0 { diagnostics.append("トラック\(track + 1): 終わりのない音が\(dangling)個あり、読み込みませんでした。") }
            if unmatchedOffs > 0 { diagnostics.append("トラック\(track + 1): 対応する開始のない終了が\(unmatchedOffs)個ありました。") }
            let channels = notes.keys.sorted()
            for channel in channels {
                let list = notes[channel]!.sorted { ($0.onTick, $0.pitch) < ($1.onTick, $1.pitch) }
                let label = name.isEmpty ? "トラック\(track + 1)" : name
                candidates.append(.init(id: candidates.count, track: track, channel: channel,
                                        name: channels.count > 1 ? "\(label)（ch\(channel + 1)）" : label, notes: list))
            }
        }
        if candidates.isEmpty { diagnostics.append("音符が見つかりませんでした。") }
        return .init(format: format, ticksPerQuarter: division, tempos: tempos.sorted { $0.0 < $1.0 },
                     meters: meters.sorted { $0.0 < $1.0 }, candidates: candidates, diagnostics: diagnostics)
    }

    /// Exact beats unless `grid` (in quarter notes, e.g. 0.25 for sixteenths) asks for quantizing.
    func beat(_ tick: Int, grid: Beat?) throws -> Beat {
        let exact = try Beat(Int64(tick), Int64(ticksPerQuarter))
        guard let grid else { return exact }
        let steps = (Double(tick) / Double(ticksPerQuarter) / grid.doubleValue).rounded()
        return try Beat(Int64(steps) * grid.numerator, grid.denominator)
    }

    /// Adds the chosen candidates as parts. With `replace`, the song's notes, parts, measures, tempo and
    /// meter are replaced by the file's (alignments to removed notes go with them).
    public func apply(to song: inout SongDocument, candidateIDs: [Int], replace: Bool, grid: Beat?) throws -> [UUID] {
        let chosen = candidates.filter { candidateIDs.contains($0.id) }
        guard !chosen.isEmpty else { throw SongError.invalid("読み込む声部を選んでください。") }
        if replace {
            for event in song.music.events { song.removeNote(id: event.id) }
            song.music.parts = []
            song.music.measures = []
            var newTempos: [Tempo] = []
            for tempo in tempos {
                let onset = try beat(tempo.tick, grid: grid)
                if let last = newTempos.last, last.onset == onset { newTempos[newTempos.count - 1].bpm = tempo.bpm }
                else { newTempos.append(.init(onset: onset, bpm: min(1000, max(1, tempo.bpm)))) }
            }
            if newTempos.first?.onset != .zero { newTempos.insert(.init(bpm: newTempos.first?.bpm ?? 120), at: 0) }
            song.music.tempos = newTempos
            var newMeters: [Meter] = []
            for meter in meters {
                let onset = try beat(meter.tick, grid: grid)
                let value = Meter(onset: onset, numerator: meter.numerator, denominator: meter.denominator)
                if let last = newMeters.last, last.onset == onset { newMeters[newMeters.count - 1] = value } else { newMeters.append(value) }
            }
            if newMeters.first?.onset != .zero { newMeters.insert(.init(), at: 0) }
            song.music.meters = newMeters
        }
        var added: [UUID] = []
        for candidate in chosen {
            let pitches = candidate.notes.map(\.pitch)
            let part = song.addPart(name: candidate.name, clef: .suggested(forPitches: pitches))
            added.append(part)
            for note in candidate.notes {
                let onset = try beat(note.onTick, grid: grid)
                var end = try beat(note.offTick, grid: grid)
                if end <= onset { end = try onset.adding(grid ?? Beat(1, Int64(ticksPerQuarter))) }
                song.music.events.append(.init(onset: onset, duration: try end.subtracting(onset),
                                               content: .note(.init(pitch: note.pitch, velocity: max(1, min(127, note.velocity)),
                                                                    channel: candidate.channel, track: candidate.track)),
                                               partID: part))
            }
        }
        song.music.events.sort { $0.onset < $1.onset }
        try song.extendMeasures(through: MeasureProjection.songEnd(song))
        for index in song.music.events.indices where song.music.events[index].measureID == nil {
            let onset = song.music.events[index].onset
            song.music.events[index].measureID = song.music.measures.first { $0.range.start <= onset && onset < $0.range.end }?.id
        }
        return added
    }
}

struct ByteReader {
    let bytes: [UInt8]
    var offset = 0
    init(bytes: [UInt8]) { self.bytes = bytes }
    var remaining: Int { bytes.count - offset }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw SongError.invalid("MIDIファイルが途中で切れています。") }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= remaining else { throw SongError.invalid("MIDIファイルが途中で切れています。") }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }
    mutating func skip(_ count: Int) throws { _ = try take(count) }
    mutating func uint(_ count: Int) throws -> Int { try take(count).reduce(0) { $0 << 8 | Int($1) } }
    mutating func ascii(_ count: Int) throws -> String { String(decoding: try take(count), as: UTF8.self) }
    mutating func variableLength() throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let next = try byte()
            value = value << 7 | Int(next & 0x7F)
            if next & 0x80 == 0 { return value }
        }
        throw SongError.invalid("MIDIの可変長数値が不正です。")
    }
}
