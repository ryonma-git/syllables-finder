import Foundation

/// A display interval. Missing measure data remains visible as an unnumbered interval.
public struct MeasureSlice: Sendable, Equatable, Identifiable {
    public let id: String
    public let number: String
    public let range: BeatRange
    public let inferred: Bool
    public let missing: Bool
    public init(id: String? = nil, number: String, range: BeatRange, inferred: Bool = false, missing: Bool = false) {
        self.id = id ?? "\(number):\(range.start.numerator)/\(range.start.denominator)-\(range.end.numerator)/\(range.end.denominator):\(inferred):\(missing)"
        self.number = number; self.range = range; self.inferred = inferred; self.missing = missing
    }
}

public struct MeasureProjection: Sendable {
    public let slices: [MeasureSlice]
    public let warning: String?

    public init(song: SongDocument) {
        let end = Self.songEnd(song)
        guard end > .zero else { slices = []; warning = nil; return }
        let saved = song.music.measures.sorted { $0.range.start < $1.range.start }
        if !saved.isEmpty {
            var current = Beat.zero
            var result: [MeasureSlice] = []
            var overlap = false
            for measure in saved {
                if measure.range.start < current { overlap = true; break }
                if current < measure.range.start {
                    result.append(.init(number: "小節未設定", range: .init(start: current, end: measure.range.start), missing: true))
                }
                result.append(.init(id: measure.id.uuidString, number: measure.number, range: measure.range))
                current = measure.range.end
            }
            if overlap {
                // The document is still valid. Show time without inventing a measure order.
                slices = [.init(number: "拍時間軸", range: .init(start: .zero, end: end), missing: true)]
                warning = "小節が重なっています。拍時間軸で表示します。"
            } else {
                if current < end { result.append(.init(number: "小節未設定", range: .init(start: current, end: end), missing: true)) }
                slices = result; warning = nil
            }
            return
        }
        let meters = song.music.meters
        var result: [MeasureSlice] = []
        var position = Beat.zero
        var count = 1
        while position < end, count <= 100_000 {
            let meterIndex = meters.lastIndex { $0.onset <= position } ?? 0
            let meter = meters[meterIndex]
            let length = Double(meter.numerator) * 4 / Double(meter.denominator)
            let nominal = (try? position.adding(Beat.grid(length))) ?? end
            let nextChange = meters.dropFirst(meterIndex + 1).first?.onset ?? end
            let next = min(end, nominal, nextChange)
            guard position < next else { break }
            result.append(.init(number: "\(count)", range: .init(start: position, end: next), inferred: true))
            position = next; count += 1
        }
        slices = result
        warning = position < end ? "表示できる小節数の上限を超えました。" : nil
    }

    public static func songEnd(_ song: SongDocument) -> Beat {
        let eventEnds = song.music.events.compactMap { try? $0.range.end }
        let ends = song.music.measures.map(\.range.end) + eventEnds + song.phrases.compactMap(\.timeRange?.end)
        return ends.max() ?? .zero
    }

    public var detailWindows: [[MeasureSlice]] { stride(from: 0, to: slices.count, by: 2).map { Array(slices[$0..<min($0 + 2, slices.count)]) } }

    public func containing(_ beat: Double) -> Int {
        let index = slices.firstIndex { $0.range.start.doubleValue <= beat && beat < $0.range.end.doubleValue }
        return index ?? max(0, slices.count - 1)
    }
}

/// Converts exact beat positions through the document's tempo changes.
public struct TempoMap: Sendable {
    public let tempos: [Tempo]
    public let multiplier: Double

    public init(tempos: [Tempo], multiplier: Double = 1) throws {
        guard !tempos.isEmpty, tempos[0].onset == .zero, multiplier.isFinite, multiplier > 0,
              tempos.allSatisfy({ $0.bpm.isFinite && $0.bpm > 0 }) else {
            throw SongError.invalid("再生テンポを設定できません。")
        }
        self.tempos = tempos; self.multiplier = multiplier
    }

    public func seconds(at beat: Double) -> Double {
        guard beat > 0 else { return 0 }
        var result = 0.0
        for index in tempos.indices {
            let start = tempos[index].onset.doubleValue
            if start >= beat { break }
            let end = index + 1 < tempos.count ? min(beat, tempos[index + 1].onset.doubleValue) : beat
            result += max(0, end - start) * 60 / (tempos[index].bpm * multiplier)
        }
        return result
    }

    public func beat(at seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        var remaining = seconds
        for index in tempos.indices {
            let start = tempos[index].onset.doubleValue
            let rate = tempos[index].bpm * multiplier / 60
            let next = index + 1 < tempos.count ? tempos[index + 1].onset.doubleValue : .infinity
            let segmentSeconds = (next - start) / rate
            if remaining < segmentSeconds { return start + remaining * rate }
            remaining -= segmentSeconds
        }
        return tempos.last!.onset.doubleValue + remaining * tempos.last!.bpm * multiplier / 60
    }
}

public struct PlannedNote: Sendable, Equatable {
    public let pitch: Int
    public let velocity: Int
    public let start: Double
    public let end: Double
}

public struct PlaybackPlan: Sendable {
    public let range: BeatRange
    public let tempo: TempoMap
    public let notes: [PlannedNote]
    public let duration: Double
    public let diagnostics: [String]

    public init(song: SongDocument, range: BeatRange, practiceBPM: Double) throws {
        try range.validate()
        guard let originalBPM = song.music.tempos.first?.bpm, practiceBPM.isFinite, practiceBPM > 0 else {
            throw SongError.invalid("練習テンポを設定できません。")
        }
        let tempo = try TempoMap(tempos: song.music.tempos, multiplier: practiceBPM / originalBPM)
        let rangeStartSeconds = tempo.seconds(at: range.start.doubleValue)
        let total = tempo.seconds(at: range.end.doubleValue) - rangeStartSeconds
        guard total > 0, total <= 300 else { throw SongError.invalid("再生は5分までです。短い小節範囲を選んでください。") }

        var grouped: [MusicalEvent] = []
        var diagnostics: [String] = []
        let events = song.music.events.filter { $0.note != nil }.sorted {
            $0.onset == $1.onset ? $0.id.uuidString < $1.id.uuidString : $0.onset < $1.onset
        }
        for event in events {
            guard let note = event.note else { continue }
            if let tie = note.notation?.tieGroupID,
               let index = grouped.lastIndex(where: { prior in
                   guard let old = prior.note else { return false }
                   return old.notation?.tieGroupID == tie && old.pitch == note.pitch && old.channel == note.channel && old.track == note.track
               }) {
                let prior = grouped[index]
                if (try? prior.range.end) == event.onset {
                    grouped[index].duration = try prior.duration.adding(event.duration)
                    continue
                }
                diagnostics.append("連続しないタイは別の音として再生します。")
            }
            grouped.append(event)
        }
        self.notes = grouped.compactMap { event in
            guard let note = event.note, let end = try? event.range.end,
                  event.onset < range.end, range.start < end else { return nil }
            let startSeconds = max(0, tempo.seconds(at: event.onset.doubleValue) - rangeStartSeconds)
            let endSeconds = min(total, tempo.seconds(at: end.doubleValue) - rangeStartSeconds)
            return PlannedNote(pitch: note.pitch, velocity: note.velocity, start: startSeconds, end: endSeconds)
        }
        self.range = range; self.tempo = tempo; self.duration = total; self.diagnostics = diagnostics
    }

    public func beat(at elapsed: Double) -> Double {
        tempo.beat(at: tempo.seconds(at: range.start.doubleValue) + min(max(elapsed, 0), duration))
    }
}
