import Foundation

/// Proposes how a part's lyrics sit on its notes (ADR014). One syllable per sung note is the base
/// hypothesis; melismas and elisions are chosen only where the counts or the music call for them.
/// Alignments a person made (`userEdited`) are anchors and are never moved.
public struct LyricAlignmentProposal: Sendable, Equatable {
    public struct Issue: Sendable, Equatable {
        public enum Kind: String, Sendable { case melisma, elision, unsungSyllable, noteWithoutLyric, countMismatch }
        public let kind: Kind
        public let syllableIDs: [UUID]
        public let eventIDs: [UUID]
        public let message: String
    }
    public let partID: UUID
    /// New alignments for the part (the anchors are not repeated here).
    public let alignments: [Alignment]
    public let issues: [Issue]
    public let syllableCount: Int
    public let sungNoteCount: Int
    public let anchorCount: Int

    public var oneToOneCount: Int { alignments.filter { $0.relation == .syllabic || $0.relation == .oneToOne || $0.relation == .tie }.count }
    public var melismaCount: Int { alignments.filter { $0.relation == .melisma }.count }
    public var elisionCount: Int { alignments.filter { $0.relation == .elision }.count }
}

public enum LyricAligner {
    struct Unit {
        let syllableID: UUID
        let text: String
        let wordStart: Bool
        let wordEnd: Bool
        let phraseStart: Bool
        let phraseEnd: Bool
        let punctuationAfter: Bool
        let stressed: Bool
        let startsWithVowel: Bool
        let endsWithVowel: Bool
        let language: String
    }

    struct SungNote {
        let eventIDs: [UUID]
        let onset: Double
        let duration: Double
        let pitch: Int
        let restBefore: Bool
        let strength: Int
    }

    /// The part's lyric order: `Part.phraseIDs`, or every phrase in section order.
    static func units(song: SongDocument, part: Part) -> [Unit] {
        let sectionOrder = song.sections.flatMap(\.phraseIDs)
        let phraseOrder = part.phraseIDs ?? (sectionOrder.isEmpty ? song.phrases.map(\.id) : sectionOrder)
        let vowels = Set("aeiouyáéíóúàèìòùâêîôûäëïöüæœаеёиоуыэюяあいうえおアイウエオ")
        var result: [Unit] = []
        for phraseID in phraseOrder {
            guard let phrase = song.phrase(phraseID) else { continue }
            let language = song.language(of: phrase)
            let words = song.words(in: phrase)
            for (wordIndex, word) in words.enumerated() {
                let syllables = song.syllables(in: word)
                let trailing = word.surface.reversed().prefix { !$0.isLetter }
                for (index, syllable) in syllables.enumerated() {
                    let text = syllable.text.value
                    let lower = text.lowercased().decomposedStringWithCanonicalMapping.filter { $0.isLetter }
                    result.append(.init(syllableID: syllable.id, text: text,
                                        wordStart: index == 0, wordEnd: index == syllables.count - 1,
                                        phraseStart: wordIndex == 0 && index == 0,
                                        phraseEnd: wordIndex == words.count - 1 && index == syllables.count - 1,
                                        punctuationAfter: index == syllables.count - 1 && trailing.contains { ",.;:!?、。！？".contains($0) },
                                        stressed: !syllable.stress.value.isEmpty,
                                        startsWithVowel: lower.first.map { vowels.contains($0) || $0 == "h" } ?? false,
                                        endsWithVowel: endsWithVowelSound(lower, language: language, wordEnd: index == syllables.count - 1, vowels: vowels),
                                        language: language))
                }
            }
        }
        return result
    }

    /// English spelling ends many words with a silent e ("Like"), which is not a vowel sound.
    private static func endsWithVowelSound(_ letters: String, language: String, wordEnd: Bool, vowels: Set<Character>) -> Bool {
        guard let last = letters.last, vowels.contains(last) else { return false }
        if language == "en" && wordEnd && last == "e" && letters.count >= 2 {
            let before = letters[letters.index(letters.endIndex, offsetBy: -2)]
            return vowels.contains(before)
        }
        return true
    }

    /// Sung notes of a part in time order; notes joined by a tie count once.
    static func sungNotes(song: SongDocument, partID: UUID) -> [SungNote] {
        let events = song.music.events.filter { $0.partID == partID }.sorted { $0.onset < $1.onset }
        var result: [SungNote] = []
        var chain: [MusicalEvent] = []
        var chainRestBefore = true
        var sawRest = true
        var lastEnd: Beat?
        func flush() {
            guard let first = chain.first, let pitch = first.note?.pitch else { chain = []; return }
            let end = (chain.last.flatMap { try? $0.range.end.doubleValue }) ?? first.onset.doubleValue
            result.append(.init(eventIDs: chain.map(\.id), onset: first.onset.doubleValue, duration: end - first.onset.doubleValue,
                                pitch: pitch, restBefore: chainRestBefore, strength: strength(song: song, onset: first.onset)))
            chain = []
        }
        for event in events {
            let end = try? event.range.end
            guard let note = event.note else {
                flush(); sawRest = true; lastEnd = end; continue
            }
            let gap = lastEnd.map { event.onset > $0 } ?? true
            if let last = chain.last, let lastNote = last.note, let group = lastNote.notation?.tieGroupID,
               group == note.notation?.tieGroupID, lastNote.pitch == note.pitch, !gap {
                chain.append(event)
            } else {
                flush()
                chain = [event]
                chainRestBefore = sawRest || gap
            }
            sawRest = false
            lastEnd = end
        }
        flush()
        return result
    }

    /// 3 downbeat, 2 middle of the bar, 1 on a beat, 0 off the beat.
    static func strength(song: SongDocument, onset: Beat) -> Int {
        let measure = song.music.measures.first { $0.range.start <= onset && onset < $0.range.end }
        let meter = song.music.meters.last { $0.onset <= onset } ?? .init()
        let start = measure?.range.start.doubleValue ?? {
            let length = Double(meter.numerator) * 4 / Double(meter.denominator)
            let from = meter.onset.doubleValue
            return from + floor((onset.doubleValue - from) / length) * length
        }()
        let position = onset.doubleValue - start
        let beat = meter.denominator == 8 && meter.numerator % 3 == 0 ? 1.5 : 4 / Double(meter.denominator)
        let length = measure?.range.length ?? Double(meter.numerator) * 4 / Double(meter.denominator)
        if abs(position) < 1e-9 { return 3 }
        if abs(position - length / 2) < 1e-9 && meter.numerator % 2 == 0 { return 2 }
        let ratio = position / beat
        return abs(ratio - ratio.rounded()) < 1e-9 ? 1 : 0
    }

    public static func propose(song: SongDocument, partID: UUID) throws -> LyricAlignmentProposal {
        guard let part = song.music.part(partID) else { throw SongError.invalid("声部が見つかりません。") }
        let units = units(song: song, part: part)
        let notes = sungNotes(song: song, partID: partID)
        let eventToNote = Dictionary(uniqueKeysWithValues: notes.enumerated().flatMap { index, note in note.eventIDs.map { ($0, index) } })

        // Anchors: person-made alignments on this part's notes, matched to syllable occurrences in order.
        struct Anchor { let unit: Int; let notes: ClosedRange<Int>; let syllables: Int }
        let manual = song.alignments.filter { alignment in
            alignment.userEdited && alignment.musicTargets.contains { target in
                if case .event(let id, _) = target { return eventToNote[id] != nil }
                return false
            }
        }.compactMap { alignment -> (Alignment, ClosedRange<Int>)? in
            let indices = alignment.musicTargets.compactMap { target -> Int? in
                if case .event(let id, _) = target { return eventToNote[id] }
                return nil
            }
            guard let low = indices.min(), let high = indices.max() else { return nil }
            return (alignment, low...high)
        }.sorted { $0.1.lowerBound < $1.1.lowerBound }
        var anchors: [Anchor] = []
        var searchFrom = 0
        for (alignment, range) in manual {
            let ids = alignment.languageTargets.filter { $0.kind == .syllable }.map(\.id)
            guard let first = ids.first,
                  let unit = units[searchFrom...].firstIndex(where: { $0.syllableID == first }),
                  anchors.last.map({ range.lowerBound > $0.notes.upperBound }) ?? true else { continue }
            anchors.append(.init(unit: unit, notes: range, syllables: max(1, ids.count)))
            searchFrom = unit + max(1, ids.count)
        }

        var alignments: [Alignment] = []
        var issues: [LyricAlignmentProposal.Issue] = []
        var unitCursor = 0, noteCursor = 0
        func solve(units unitRange: Range<Int>, notes noteRange: Range<Int>) {
            let segmentUnits = Array(units[unitRange]), segmentNotes = Array(notes[noteRange])
            let steps = align(segmentUnits, segmentNotes)
            if segmentUnits.count != segmentNotes.count && !segmentUnits.isEmpty && !segmentNotes.isEmpty {
                issues.append(.init(kind: .countMismatch, syllableIDs: segmentUnits.map(\.syllableID),
                                    eventIDs: segmentNotes.flatMap(\.eventIDs),
                                    message: "音節\(segmentUnits.count)・音\(segmentNotes.count)の区間です。メリスマ・エリジオンの位置を確認してください。"))
            }
            for step in steps {
                switch step {
                case .sing(let u, let range):
                    let unit = segmentUnits[u]
                    let events = range.flatMap { segmentNotes[$0].eventIDs }
                    let relation: Alignment.Relation = range.count > 1 ? .melisma : (events.count > 1 ? .tie : .syllabic)
                    alignments.append(.init(languageTargets: [.init(.syllable, unit.syllableID)], musicTargets: events.map { .event($0) }, relation: relation))
                    if range.count > 1 {
                        issues.append(.init(kind: .melisma, syllableIDs: [unit.syllableID], eventIDs: events,
                                            message: "「\(unit.text)」を\(range.count)音にのばします（メリスマ）。"))
                    }
                case .elide(let u, let note):
                    let pair = [segmentUnits[u], segmentUnits[u + 1]]
                    let events = segmentNotes[note].eventIDs
                    alignments.append(.init(languageTargets: pair.map { .init(.syllable, $0.syllableID) }, musicTargets: events.map { .event($0) },
                                            relation: .elision))
                    issues.append(.init(kind: .elision, syllableIDs: pair.map(\.syllableID), eventIDs: events,
                                        message: "「\(pair[0].text)」「\(pair[1].text)」を1音で歌います（エリジオン）。"))
                case .skipUnit(let u):
                    issues.append(.init(kind: .unsungSyllable, syllableIDs: [segmentUnits[u].syllableID], eventIDs: [],
                                        message: "「\(segmentUnits[u].text)」をのせる音がありません。"))
                case .skipNote(let note):
                    issues.append(.init(kind: .noteWithoutLyric, syllableIDs: [], eventIDs: segmentNotes[note].eventIDs,
                                        message: "歌詞のない音があります。"))
                }
            }
        }
        for anchor in anchors {
            solve(units: unitCursor..<anchor.unit, notes: noteCursor..<anchor.notes.lowerBound)
            unitCursor = anchor.unit + anchor.syllables
            noteCursor = anchor.notes.upperBound + 1
        }
        solve(units: unitCursor..<units.count, notes: noteCursor..<notes.count)
        return .init(partID: partID, alignments: alignments, issues: issues, syllableCount: units.count,
                     sungNoteCount: notes.count, anchorCount: anchors.count)
    }

    enum Step: Equatable {
        case sing(Int, Range<Int>)
        case elide(Int, Int)
        case skipUnit(Int)
        case skipNote(Int)
    }

    /// Minimum-cost monotonic alignment of units to sung notes.
    static func align(_ units: [Unit], _ notes: [SungNote]) -> [Step] {
        let s = units.count, n = notes.count
        guard s > 0 || n > 0 else { return [] }
        let maxMelisma = 16
        var cost = Array(repeating: Array(repeating: Double.infinity, count: n + 1), count: s + 1)
        var back = Array(repeating: Array(repeating: Step?.none, count: n + 1), count: s + 1)
        cost[0][0] = 0
        for i in 0...s {
            for j in 0...n where cost[i][j] < .infinity {
                let base = cost[i][j]
                func relax(_ ni: Int, _ nj: Int, _ extra: Double, _ step: Step) {
                    if base + extra < cost[ni][nj] - 1e-12 { cost[ni][nj] = base + extra; back[ni][nj] = step }
                }
                if i < s && j < n {
                    var melisma = 0.0
                    for k in 1...min(maxMelisma, n - j) {
                        if k > 1 { melisma += extraNoteCost(units[i], notes[j + k - 1], previous: notes[j + k - 2]) }
                        relax(i + 1, j + k, placement(units, i, notes, j) + melisma, .sing(i, j..<(j + k)))
                    }
                    if i + 1 < s { relax(i + 2, j + 1, placement(units, i, notes, j) + elisionCost(units[i], units[i + 1]), .elide(i, j)) }
                }
                if i < s { relax(i + 1, j, 6, .skipUnit(i)) }
                if j < n { relax(i, j + 1, i == 0 || i == s ? 2.5 : 4, .skipNote(j)) }
            }
        }
        var steps: [Step] = []
        var i = s, j = n
        while i > 0 || j > 0, let step = back[i][j] {
            steps.append(step)
            switch step {
            case .sing(_, let range): i -= 1; j -= range.count
            case .elide: i -= 2; j -= 1
            case .skipUnit: i -= 1
            case .skipNote: j -= 1
            }
        }
        return steps.reversed()
    }

    static func extraNoteCost(_ unit: Unit, _ note: SungNote, previous: SungNote) -> Double {
        var cost = 1.0
        if note.restBefore { return 8 }                 // a melisma does not continue over a rest
        if note.duration <= 0.5 + 1e-9 && abs(note.pitch - previous.pitch) <= 2 { cost *= 0.55 } // running notes
        if note.strength >= 3 { cost += 0.35 }          // a new bar usually brings a new syllable
        if unit.wordEnd { cost *= 0.8 }                 // final vowels are commonly drawn out
        if unit.stressed { cost *= 0.85 }
        return cost
    }

    static func placement(_ units: [Unit], _ i: Int, _ notes: [SungNote], _ j: Int) -> Double {
        let unit = units[i], note = notes[j]
        var cost = 0.0
        if note.restBefore && j > 0 {
            if !unit.wordStart { cost += 2.5 }           // a breath rarely splits a word
            else if !unit.phraseStart && !(i > 0 && units[i - 1].punctuationAfter) { cost += 0.35 }
        } else if unit.phraseStart && i > 0 && j > 0 {
            cost += 0.3                                  // lines usually begin after a rest
        }
        if unit.stressed && note.strength == 0 { cost += 0.2 }
        if !unit.stressed && unit.wordStart == false && note.strength == 3 { cost += 0.1 }
        return cost
    }

    static func elisionCost(_ first: Unit, _ second: Unit) -> Double {
        guard first.endsWithVowel && second.startsWithVowel else { return 5 }
        if first.wordEnd && second.wordStart { return first.language == "en" ? 2.5 : 0.9 } // synalepha (it, es, fr, la)
        if !first.wordEnd { return 1.0 }                    // vowels in hiatus inside a word (di-a-mond → dia-mond)
        return 3
    }

    /// Replaces the part's automatic alignments with the proposal; person-made ones stay.
    public static func apply(_ proposal: LyricAlignmentProposal, to song: inout SongDocument) {
        let partEvents = Set(song.music.events(in: proposal.partID).map(\.id))
        song.alignments.removeAll { alignment in
            !alignment.userEdited && alignment.musicTargets.contains { target in
                if case .event(let id, _) = target { return partEvents.contains(id) }
                return false
            }
        }
        song.alignments.append(contentsOf: proposal.alignments)
        guard song.music.parts.first?.id == proposal.partID else { return }
        // The first part defines each phrase's practice range, when the phrase has not got one.
        for index in song.phrases.indices where song.phrases[index].timeRange == nil {
            let syllableIDs = Set(song.words(in: song.phrases[index]).flatMap(\.syllableIDs))
            let events = song.alignments.filter { $0.languageTargets.contains { syllableIDs.contains($0.id) } }
                .flatMap(\.musicTargets).compactMap { target -> MusicalEvent? in
                    if case .event(let id, _) = target, partEvents.contains(id) { return song.event(id) }
                    return nil
                }
            guard let start = events.map(\.onset).min(), let end = events.compactMap({ try? $0.range.end }).max(), start < end else { continue }
            song.phrases[index].timeRange = .init(start: start, end: end)
            song.phrases[index].musicalEventIDs = Array(Set(events.map(\.id))).sorted { song.event($0)!.onset < song.event($1)!.onset }
        }
    }
}
