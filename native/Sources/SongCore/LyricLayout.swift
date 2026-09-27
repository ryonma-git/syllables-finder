import Foundation

/// One sung lyric item under a staff: a syllable (or syllables elided onto one note), with the
/// hyphen to the next syllable of the same word and the extender line of a melisma.
public struct LyricItem: Sendable, Equatable, Identifiable {
    public var id: UUID { syllableIDs[0] }
    public let syllableIDs: [UUID]
    public let text: String
    public let x: Double
    /// Drawn width; smaller than the natural width when the next note leaves too little room.
    public var width: Double
    /// Font scale (≤ 1) that makes the text fit `width`.
    public var fontScale = 1.0
    public let start: Double
    /// Beat of the last sung note of this item, for extender lines.
    public let lastNoteStart: Double
    public var hyphen: (from: Double, to: Double)?
    public var extender: (from: Double, to: Double)?

    public static func == (a: LyricItem, b: LyricItem) -> Bool {
        a.syllableIDs == b.syllableIDs && a.text == b.text && a.x == b.x && a.width == b.width
            && a.hyphen?.from == b.hyphen?.from && a.hyphen?.to == b.hyphen?.to
            && a.extender?.from == b.extender?.from && a.extender?.to == b.extender?.to
    }
}

public enum LyricLayout {
    /// - Parameters:
    ///   - include: events of the staff (one part); syllables aligned to other parts are ignored.
    ///   - headLeft: notehead left edges from the engraving, when drawn as a staff.
    ///   - measure: text width in points.
    public static func items(song: SongDocument, range: BeatRange, include: (MusicalEvent) -> Bool,
                             headLeft: [UUID: Double], x: (Double) -> Double, noteEnd: (UUID) -> Double?,
                             measure: (String) -> Double) -> [LyricItem] {
        let from = range.start.doubleValue, to = range.end.doubleValue
        let events = Dictionary(uniqueKeysWithValues: song.music.events.filter(include).map { ($0.id, $0) })
        struct Placed { let syllable: Syllable; let first: MusicalEvent; let last: MusicalEvent }
        var placed: [Placed] = []
        for alignment in song.alignments {
            let targets = alignment.musicTargets.compactMap { target -> MusicalEvent? in
                if case .event(let id, _) = target { return events[id] }
                return nil
            }.sorted { $0.onset < $1.onset }
            guard let first = targets.first, let last = targets.last else { continue }
            let start = first.onset.doubleValue
            guard start >= from - 1e-9, start < to - 1e-9 else { continue }
            for target in alignment.languageTargets where target.kind == .syllable {
                if let syllable = song.syllable(target.id) { placed.append(.init(syllable: syllable, first: first, last: last)) }
            }
        }
        // Language order inside a note keeps elided syllables readable (e.g. "di‿a").
        let order = Dictionary(uniqueKeysWithValues: song.words.flatMap(\.syllableIDs).enumerated().map { ($1, $0) })
        placed.sort { ($0.first.onset, order[$0.syllable.id] ?? 0) < ($1.first.onset, order[$1.syllable.id] ?? 0) }
        var grouped: [[Placed]] = []
        for item in placed {
            if let last = grouped.last?.last, last.first.id == item.first.id { grouped[grouped.count - 1].append(item) }
            else { grouped.append([item]) }
        }
        var items: [LyricItem] = grouped.map { group in
            let text = group.map(\.syllable.text.value).joined(separator: "‿")
            let first = group[0].first
            let last = group.max { $0.last.onset < $1.last.onset }!.last
            let left = headLeft[first.id] ?? x(first.onset.doubleValue) + 2
            return LyricItem(syllableIDs: group.map(\.syllable.id), text: text, x: left, width: measure(text),
                             start: first.onset.doubleValue, lastNoteStart: last.onset.doubleValue)
        }
        // Beat-proportional spacing can leave less room than a syllable needs (fast notes). Shrink the
        // text down to 60% so a hyphen still separates syllables, instead of running words together.
        for index in items.indices {
            let limit = (index + 1 < items.count ? items[index + 1].x : x(to)) - items[index].x
            let room = limit - (index + 1 < items.count ? 9 : 2)
            if items[index].width > room {
                let fitted = max(items[index].width * 0.6, room)
                items[index].fontScale = fitted / items[index].width
                items[index].width = fitted
            }
        }
        for index in items.indices {
            let item = items[index]
            let end = item.x + item.width
            let lastSyllable = item.syllableIDs.last!
            if let word = song.syllable(lastSyllable).flatMap({ song.word($0.parentWordID) }),
               let position = word.syllableIDs.firstIndex(of: lastSyllable), position + 1 < word.syllableIDs.count {
                let nextID = word.syllableIDs[position + 1]
                let nextX = items.dropFirst(index + 1).first { $0.syllableIDs.contains(nextID) }?.x
                let target = nextX ?? min(end + 16, x(to))
                if target - end > 3 { items[index].hyphen = (end, target) }
            } else if item.lastNoteStart > item.start + 1e-9 {
                // A word-final melisma continues with an extender to the end of its last note.
                let lastID = song.alignments.first { $0.languageTargets.contains(.init(.syllable, lastSyllable)) }?
                    .musicTargets.compactMap { target -> UUID? in if case .event(let id, _) = target { id } else { nil } }
                    .compactMap { events[$0] }.max { $0.onset < $1.onset }?.id
                let stop = lastID.flatMap(noteEnd) ?? x(item.lastNoteStart) + 10
                if stop - end > 6 { items[index].extender = (end + 2, min(stop, x(to))) }
            }
        }
        return items
    }
}
