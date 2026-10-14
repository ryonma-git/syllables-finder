import Foundation

/// Notes remain at their written positions. Swing is a reversible performance setting.
public struct SwingSettings: Codable, Equatable, Sendable {
    public enum Subdivision: String, Codable, CaseIterable, Sendable {
        case eighth, sixteenth
        public var label: String { self == .eighth ? "8分音符" : "16分音符" }
        /// Number of long/short pairs per quarter-note beat.
        var pairsPerBeat: Int64 { self == .eighth ? 1 : 2 }
    }

    public var enabled: Bool
    public var subdivision: Subdivision
    /// Long note's share of a pair: 1/2 is straight, 2/3 is triplet swing.
    public var longFraction: Beat
    /// Empty means the whole song. Other passages retain their straight timing.
    public var ranges: [BeatRange]

    public init(enabled: Bool = true, subdivision: Subdivision = .sixteenth,
                longFraction: Beat = try! Beat(2, 3), ranges: [BeatRange] = []) {
        self.enabled = enabled; self.subdivision = subdivision
        self.longFraction = longFraction; self.ranges = ranges
    }

    public var percent: Double { longFraction.doubleValue * 100 }
    public var label: String {
        enabled ? "\(subdivision.label) · \(percent.formatted(.number.precision(.fractionLength(1))))%" : "オフ（ストレート）"
    }

    public func validate() throws {
        guard longFraction >= (try Beat(1, 2)), longFraction <= (try Beat(3, 4)) else {
            throw SongError.invalid("スウィングの比率は50〜75%で指定してください。")
        }
        var previousEnd = Beat.zero
        for range in ranges {
            try range.validate()
            guard range.start >= previousEnd else {
                throw SongError.invalid("スウィングの範囲が重複または逆順です。")
            }
            for boundary in [range.start, range.end] {
                guard (boundary.numerator * subdivision.pairsPerBeat) % boundary.denominator == 0 else {
                    throw SongError.invalid("スウィングの範囲は音符の組の境界で指定してください。8分は1拍、16分は0.5拍単位です。")
                }
            }
            previousEnd = range.end
        }
    }
}

/// Continuous and monotone in both directions, including rests, ties and off-grid notes.
/// No quantization is implicit in applying or removing the performance setting.
public struct SwingTiming: Sendable {
    public let settings: SwingSettings?
    public init(_ settings: SwingSettings?) { self.settings = settings }

    public func performedBeat(_ beat: Double) -> Double { map(beat, inverse: false) }
    public func writtenBeat(_ beat: Double) -> Double { map(beat, inverse: true) }
    public func performedBeat(_ beat: Beat) throws -> Beat { try map(beat, inverse: false) }
    public func writtenBeat(_ beat: Beat) throws -> Beat { try map(beat, inverse: true) }

    private func map(_ beat: Double, inverse: Bool) -> Double {
        guard let settings, settings.enabled,
              settings.ranges.isEmpty || settings.ranges.contains(where: {
                  $0.start.doubleValue <= beat && beat < $0.end.doubleValue
              }) else { return beat }
        let pair = 1 / Double(settings.subdivision.pairsPerBeat)
        let base = floor(beat / pair) * pair
        let local = beat - base
        let half = pair / 2, long = pair * settings.longFraction.doubleValue
        if inverse {
            return base + (local <= long ? local * half / long : half + (local - long) * half / (pair - long))
        }
        return base + (local <= half ? local * long / half : long + (local - half) * (pair - long) / half)
    }

    private func map(_ beat: Beat, inverse: Bool) throws -> Beat {
        guard let settings, settings.enabled,
              settings.ranges.isEmpty || settings.ranges.contains(where: { $0.start <= beat && beat < $0.end }) else { return beat }
        let count = settings.subdivision.pairsPerBeat
        let base = try Beat((beat.numerator * count) / beat.denominator, count)
        let local = try beat.subtracting(base)
        let pair = try Beat(1, count), half = try Beat(1, count * 2)
        let long = try pair.multiplied(by: settings.longFraction)
        let short = try pair.subtracting(long)
        let mapped: Beat
        if inverse {
            mapped = local <= long ? try local.multiplied(by: half.divided(by: long))
                : try half.adding(local.subtracting(long).multiplied(by: half.divided(by: short)))
        } else {
            mapped = local <= half ? try local.multiplied(by: long.divided(by: half))
                : try long.adding(local.subtracting(half).multiplied(by: short.divided(by: half)))
        }
        return try base.adding(mapped)
    }
}

extension Beat {
    func multiplied(by other: Beat) throws -> Beat {
        // Beat bounds keep each product below Int64.max. Reduce before the public bounds check.
        let n = numerator * other.numerator, d = denominator * other.denominator
        var a = n, b = d
        while b != 0 { (a, b) = (b, a % b) }
        return try Beat(n / max(1, a), d / max(1, a))
    }

    func divided(by other: Beat) throws -> Beat {
        guard other > .zero else { throw SongError.invalid("音価を0で割ることはできません。") }
        return try multiplied(by: Beat(other.denominator, other.numerator))
    }
}

public enum SwingConversion {
    /// For imported/performed MIDI that already contains swing. The caller explicitly chooses
    /// its subdivision, ratio and passages. Never infer swing from arbitrary triplets.
    /// Event/language IDs, pitches, text, manual corrections and link identities survive.
    public static func normalizingPerformedTiming(in song: SongDocument, settings: SwingSettings) throws -> SongDocument {
        guard song.music.swing == nil else {
            throw SongError.invalid("この曲はすでにスウィングを設定として保存しています。二重の変換はできません。")
        }
        try settings.validate()
        var sourceSettings = settings
        sourceSettings.enabled = true
        let timing = SwingTiming(sourceSettings)
        func range(_ range: BeatRange) throws -> BeatRange {
            try .init(start: timing.writtenBeat(range.start), end: timing.writtenBeat(range.end))
        }
        return try song.editing { result in
            for index in result.music.events.indices {
                let old = song.music.events[index]
                let converted = try range(old.range)
                result.music.events[index].onset = converted.start
                result.music.events[index].duration = try converted.end.subtracting(converted.start)
            }
            for index in result.phrases.indices {
                if let old = song.phrases[index].timeRange { result.phrases[index].timeRange = try range(old) }
            }
            for index in result.music.spans.indices { result.music.spans[index].range = try range(song.music.spans[index].range) }
            for index in result.music.measures.indices { result.music.measures[index].range = try range(song.music.measures[index].range) }
            for index in result.music.tempos.indices { result.music.tempos[index].onset = try timing.writtenBeat(song.music.tempos[index].onset) }
            for index in result.music.meters.indices { result.music.meters[index].onset = try timing.writtenBeat(song.music.meters[index].onset) }
            for index in result.alignments.indices {
                result.alignments[index].musicTargets = try song.alignments[index].musicTargets.map { target in
                    switch target {
                    case .timeRange(let old): return .timeRange(try range(old))
                    case .event(let id, let relative):
                        guard let relative, let event = song.event(id) else { return target }
                        let base = try timing.writtenBeat(event.onset)
                        let start = try timing.writtenBeat(event.onset.adding(relative.start)).subtracting(base)
                        let end = try timing.writtenBeat(event.onset.adding(relative.end)).subtracting(base)
                        return .event(id, relativeRange: .init(start: start, end: end))
                    }
                }
            }
            result.music.swing = settings
        }
    }
}
