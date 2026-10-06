import Foundation

public struct StaffPiece: Sendable, Equatable {
    public let eventID: UUID?
    public let start: Double
    public let duration: Double
    public let pitch: Int?
    /// Diatonic steps above E4, the bottom line of the treble staff.
    public let step: Int?
    public let accidental: String?
    public let tiedFrom: Bool
    public let tiedTo: Bool
    /// The beat span is exact, but its note/rest symbol has a simplified rhythm.
    public let approximateRhythm: Bool
    /// Absolute diatonic index (octave × 7 + letter, C = 0), independent of the clef.
    public var diatonic: Int? { step.map { $0 + 4 * 7 + 2 } }
}

/// A readable treble clef projection for simple monophonic melodies.
public struct NotationProjection: Sendable {
    public let pieces: [StaffPiece]
    public let issue: String?
    public let notice: String?

    private static let values: [Double] = [4, 3, 2, 1.5, 1, 0.75, 0.5, 0.375, 0.25]
    private static let pitchClasses = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private static let naturals: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    private static let steps: [Character: Int] = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6]

    public init(song: SongDocument, measures: [MeasureSlice], including include: (MusicalEvent) -> Bool = { _ in true }) {
        var output: [StaffPiece] = []
        var problem: String?
        var noteNotice = false
        var approximateRhythm = false
        for measure in measures {
            var activeAccidentals: [Int: Int] = [:]
            let from = measure.range.start.doubleValue
            let to = measure.range.end.doubleValue
            let events = song.music.events.filter {
                guard include($0), let end = try? $0.range.end.doubleValue else { return false }
                return $0.onset.doubleValue < to && from < end
            }.sorted { $0.onset < $1.onset }
            var cursor = from
            for event in events {
                let eventFrom = max(from, event.onset.doubleValue)
                let eventTo = min(to, (try? event.range.end.doubleValue) ?? to)
                if eventFrom < cursor - 0.000_001 { problem = "複数声部・重複音符はピアノロールで表示します。"; break }
                if eventFrom > cursor + 0.000_001 {
                    if !Self.appendPieces(to: &output, id: nil, start: cursor, end: eventFrom,
                                      pitch: nil, step: nil, accidental: nil,
                                      continuationBefore: false, continuationAfter: false) {
                        approximateRhythm = true
                    }
                }
                if let note = event.note {
                    let name = Self.spelling(note: note)
                    var parsed = Self.parse(name)
                    if parsed?.pitch != note.pitch, note.notation?.spelling != nil {
                        parsed = Self.parse(Self.pitchClasses[note.pitch % 12] + String(note.pitch / 12 - 1))
                        noteNotice = true
                    }
                    guard let parsed, parsed.pitch == note.pitch else {
                        problem = "音名を五線へ変換できません。ピアノロールで表示します。"; break
                    }
                    let key = parsed.octave * 7 + Self.steps[parsed.letter]!
                    let continued = event.onset.doubleValue < from
                    let accidental: String?
                    if continued {
                        // A note tied over the barline keeps its pitch without a new accidental, and
                        // does not set this measure's state: a later same-line note still needs its sign.
                        accidental = nil
                    } else {
                        let last = activeAccidentals[key] ?? 0
                        accidental = parsed.alteration == last ? nil
                            : parsed.alteration == 0 ? "♮" : parsed.alteration == 1 ? "♯" : "♭"
                        activeAccidentals[key] = parsed.alteration
                    }
                    if !Self.appendPieces(to: &output, id: event.id, start: eventFrom, end: eventTo,
                                      pitch: note.pitch, step: key - (4 * 7 + 2), accidental: accidental,
                                      continuationBefore: continued,
                                      continuationAfter: ((try? event.range.end.doubleValue) ?? eventTo) > to) {
                        approximateRhythm = true
                    }
                } else {
                    if !Self.appendPieces(to: &output, id: event.id, start: eventFrom, end: eventTo,
                                      pitch: nil, step: nil, accidental: nil,
                                      continuationBefore: false, continuationAfter: false) {
                        approximateRhythm = true
                    }
                }
                cursor = eventTo
            }
            if problem != nil { break }
            if cursor < to - 0.000_001 {
                if !Self.appendPieces(to: &output, id: nil, start: cursor, end: to,
                                  pitch: nil, step: nil, accidental: nil,
                                  continuationBefore: false, continuationAfter: false) {
                    approximateRhythm = true
                }
            }
        }
        pieces = problem == nil ? output : []
        issue = problem
        let notices = [
            approximateRhythm ? "変則音価は略譜です（音高・拍位置は正確、符尾・休符は簡略表示）。" : nil,
            noteNotice ? "解釈できない音名は標準の音名で表示しています。" : nil
        ].compactMap { $0 }
        self.notice = notices.isEmpty ? nil : notices.joined(separator: " ")
    }

    private static func spelling(note: Note) -> String {
        if let spelling = note.notation?.spelling { return spelling }
        return pitchClasses[note.pitch % 12] + String(note.pitch / 12 - 1)
    }

    private static func parse(_ spelling: String) -> (letter: Character, alteration: Int, octave: Int, pitch: Int)? {
        let text = spelling.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        guard let letter = text.first, let natural = naturals[letter] else { return nil }
        var suffix = String(text.dropFirst())
        var alteration = 0
        if suffix.hasPrefix("#") { alteration = 1; suffix.removeFirst() }
        else if suffix.hasPrefix("b") { alteration = -1; suffix.removeFirst() }
        guard let octave = Int(suffix), (-1...9).contains(octave) else { return nil }
        return (letter, alteration, octave, (octave + 1) * 12 + natural + alteration)
    }

    private static func appendPieces(to result: inout [StaffPiece], id: UUID?, start: Double, end: Double,
                                     pitch: Int?, step: Int?, accidental: String?,
                                     continuationBefore: Bool, continuationAfter: Bool) -> Bool {
        var exactPieces: [StaffPiece] = []
        var cursor = start
        var count = 0
        while cursor < end - 0.000_001 && count < 10_000 {
            let remaining = end - cursor
            guard let value = values.first(where: { $0 <= remaining + 0.000_001 }) else { break }
            let next = cursor + value
            exactPieces.append(.init(eventID: id, start: cursor, duration: value, pitch: pitch, step: step,
                                accidental: count == 0 ? accidental : nil,
                                tiedFrom: pitch != nil && (count > 0 || continuationBefore),
                                tiedTo: pitch != nil && (next < end - 0.000_001 || continuationAfter),
                                approximateRhythm: false))
            cursor = next; count += 1
        }
        if cursor >= end - 0.000_001 {
            result.append(contentsOf: exactPieces)
            return true
        }
        // Preserve the note and its exact horizontal beat position when the duration needs
        // tuplets or finer subdivisions than this engraver can express.
        result.append(.init(eventID: id, start: start, duration: end - start, pitch: pitch, step: step,
                            accidental: accidental, tiedFrom: pitch != nil && continuationBefore,
                            tiedTo: pitch != nil && continuationAfter, approximateRhythm: true))
        return false
    }
}
