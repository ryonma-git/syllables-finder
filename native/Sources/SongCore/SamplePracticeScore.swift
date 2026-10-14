import Foundation

/// A transcribed melody and its explicit lyric underlay. No proportional or nearest-note
/// allocation is used: each group names how many consecutive syllables and notes it joins.
struct SamplePracticeScore: Sendable {
    struct Line: Sendable {
        let syllables: String
        let notes: String
        let groups: String

        /// Notes are `G4:1/2`, `F#4:1`, or `R:1`. A group `2` is a two-note melisma;
        /// `2:1` joins two lyric units on one note (for example a consonantal preposition).
        /// An empty groups string means one syllable per note, with an exact count check.
        init(_ syllables: String, _ notes: String, groups: String = "") {
            self.syllables = syllables; self.notes = notes; self.groups = groups
        }
    }

    let sourceURL: String
    let meterNumerator: Int
    let meterDenominator: Int
    let bpm: Double
    let pickup: String
    let lines: [Line]

    init(_ sourceURL: String, meter: Int = 4, denominator: Int = 4, bpm: Double = 88,
         pickup: String = "0", lines: [Line]) {
        self.sourceURL = sourceURL; meterNumerator = meter; meterDenominator = denominator
        self.bpm = bpm; self.pickup = pickup; self.lines = lines
    }

    func attaching(to original: SongDocument, serial: Int) throws -> SongDocument {
        guard original.phrases.count == lines.count else { throw SongError.invalid("譜面と歌詞の行数が一致しません。") }
        var song = original
        func id(_ number: Int) -> UUID {
            UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", serial * 10_000 + number))!
        }
        let partID = id(1)
        song.music = Music()
        song.music.parts = [.init(id: partID, name: "歌の旋律", clef: .treble)]
        song.music.tempos = [.init(bpm: bpm)]
        song.music.meters = [.init(numerator: meterNumerator, denominator: meterDenominator)]
        song.alignments = []
        var cursor = Beat.zero
        var eventSerial = 1_000, alignmentSerial = 5_000
        for (index, line) in lines.enumerated() {
            let syllables = song.words(in: song.phrases[index]).flatMap { song.syllables(in: $0) }
            guard syllables.map(\.text.value).joined(separator: "|") == line.syllables else {
                throw SongError.invalid("歌詞の区切りが譜面と異なります（\(index + 1)行目）。")
            }
            let start = cursor
            var eventIDs: [UUID] = [], noteIDs: [UUID] = []
            for token in line.notes.split(whereSeparator: \.isWhitespace) {
                let fields = token.split(separator: ":")
                guard fields.count == 2 else { throw SongError.invalid("音符データが不正です。") }
                let duration = try Self.beat(String(fields[1]))
                guard duration > .zero else { throw SongError.invalid("音符の長さが不正です。") }
                let content: EventContent
                if fields[0] == "R" { content = .rest }
                else { content = .note(.init(pitch: try Self.pitch(String(fields[0])))) }
                let eventID = id(eventSerial); eventSerial += 1
                let event = MusicalEvent(id: eventID, onset: cursor, duration: duration, content: content, partID: partID)
                song.music.events.append(event); eventIDs.append(eventID)
                if event.note != nil { noteIDs.append(eventID) }
                cursor = try cursor.adding(duration)
            }
            let groups = line.groups.isEmpty
                ? Array(repeating: "1", count: syllables.count)
                : line.groups.split(whereSeparator: \.isWhitespace).map(String.init)
            var lyricIndex = 0, noteIndex = 0
            for group in groups {
                let fields = group.split(separator: ":", omittingEmptySubsequences: false)
                let counts = fields.compactMap { Int($0) }
                guard fields.count == counts.count, (1...2).contains(counts.count), counts.allSatisfy({ $0 > 0 }) else {
                    throw SongError.invalid("歌詞の対応データが不正です。")
                }
                let lyricCount = counts.count == 1 ? 1 : counts[0]
                let noteCount = counts.last!
                guard lyricIndex + lyricCount <= syllables.count, noteIndex + noteCount <= noteIDs.count else {
                    throw SongError.invalid("歌詞と音符の対応が範囲外です。")
                }
                song.alignments.append(.init(id: id(alignmentSerial),
                    languageTargets: syllables[lyricIndex..<(lyricIndex + lyricCount)].map { .init(.syllable, $0.id) },
                    musicTargets: noteIDs[noteIndex..<(noteIndex + noteCount)].map { .event($0) },
                    relation: lyricCount > 1 ? .elision : noteCount > 1 ? .melisma : .syllabic))
                alignmentSerial += 1; lyricIndex += lyricCount; noteIndex += noteCount
            }
            guard lyricIndex == syllables.count, noteIndex == noteIDs.count else {
                throw SongError.invalid("対応していない歌詞または音符があります。")
            }
            let range = BeatRange(start: start, end: cursor)
            song.phrases[index].timeRange = range
            song.phrases[index].musicalEventIDs = eventIDs
            song.music.spans.append(.init(id: id(8_000 + index), kind: .phrase,
                title: song.phrases[index].originalText, range: range, eventIDs: eventIDs))
        }
        let regular = try Beat(Int64(meterNumerator * 4), Int64(meterDenominator))
        let pickupLength = try Self.beat(pickup)
        guard pickupLength >= .zero, pickupLength < regular else { throw SongError.invalid("弱起の長さが不正です。") }
        var start = Beat.zero, measureIndex = 0
        while start < cursor {
            let length = measureIndex == 0 && pickupLength > .zero ? pickupLength : regular
            let end = min(try start.adding(length), cursor)
            let measure = Measure(id: id(100 + measureIndex),
                number: String(measureIndex + (pickupLength > .zero ? 0 : 1)), range: .init(start: start, end: end))
            song.music.measures.append(measure)
            start = end; measureIndex += 1
        }
        for index in song.music.events.indices {
            song.music.events[index].measureID = song.music.measures.first {
                $0.range.start <= song.music.events[index].onset && song.music.events[index].onset < $0.range.end
            }?.id
        }
        song.metadata.notes = song.metadata.notes.replacingOccurrences(of: "音符は未入力。", with: "")
            + " 旋律資料: \(sourceURL)。収録した原語歌詞の範囲を採譜し、音節・メリスマ・休符・弱起を対応づけています。全曲ではなく、表示する歌詞の範囲の練習用単旋律です。"
        try song.validate()
        return song
    }

    private static func beat(_ text: String) throws -> Beat {
        let fields = text.split(separator: "/", omittingEmptySubsequences: false)
        let values = fields.compactMap { Int64($0) }
        guard fields.count == values.count, (1...2).contains(values.count) else { throw SongError.invalid("拍数が不正です。") }
        return try Beat(values[0], values.count == 2 ? values[1] : 1)
    }

    private static func pitch(_ text: String) throws -> Int {
        let letters = Array(text)
        guard let first = letters.first, let base = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][String(first)] else {
            throw SongError.invalid("音名が不正です。")
        }
        let accidental = letters.count > 1 && (letters[1] == "#" || letters[1] == "b")
        guard let octave = Int(String(letters.dropFirst(accidental ? 2 : 1))) else { throw SongError.invalid("オクターブが不正です。") }
        let value = (octave + 1) * 12 + base + (accidental ? letters[1] == "#" ? 1 : -1 : 0)
        guard (0...127).contains(value) else { throw SongError.invalid("音域が不正です。") }
        return value
    }
}
