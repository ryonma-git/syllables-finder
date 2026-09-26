import Foundation

public struct SongDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion = currentSchemaVersion
    public var id = UUID()
    public var revision: UInt64 = 0
    public var metadata = SongMetadata()
    public var sections: [Section] = []
    public var phrases: [Phrase] = []
    public var words: [Word] = []
    public var syllables: [Syllable] = []
    public var moras: [Mora] = []
    public var phonemes: [Phoneme] = []
    public var music = Music()
    public var alignments: [Alignment] = []
    public init() {}

    public func word(_ id: UUID) -> Word? { words.first { $0.id == id } }
    public func syllable(_ id: UUID) -> Syllable? { syllables.first { $0.id == id } }
    public func phrase(_ id: UUID) -> Phrase? { phrases.first { $0.id == id } }
    public func event(_ id: UUID) -> MusicalEvent? { music.events.first { $0.id == id } }
    public func words(in phrase: Phrase) -> [Word] { phrase.wordIDs.compactMap { word($0) } }
    public func syllables(in word: Word) -> [Syllable] { word.syllableIDs.compactMap { syllable($0) } }

    public func ranges(for target: LanguageTarget) -> [BeatRange] {
        alignments.filter { $0.languageTargets.contains(target) }.flatMap { alignment in
            alignment.musicTargets.compactMap { destination in
                switch destination {
                case .timeRange(let range): return range
                case .event(let id, let relative):
                    guard let event = event(id) else { return nil }
                    if let relative {
                        guard let start = try? event.onset.adding(relative.start),
                              let end = try? event.onset.adding(relative.end) else { return nil }
                        return BeatRange(start: start, end: end)
                    }
                    return try? event.range
                }
            }
        }
    }

    /// A failed mutation never escapes; revision changes only after a valid transaction.
    public func editing(_ mutation: (inout SongDocument) throws -> Void) throws -> SongDocument {
        var candidate = self
        try mutation(&candidate)
        guard revision < UInt64.max else { throw SongError.invalid("文書の編集回数が上限に達しました。") }
        candidate.revision = revision + 1
        try candidate.validate()
        return candidate
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SongDocument {
        guard data.count <= 20_000_000 else { throw SongError.invalid("文書が大きすぎます（上限20MB）。") }
        struct Header: Decodable { var schemaVersion: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion == currentSchemaVersion else { throw SongError.unsupportedVersion(header.schemaVersion) }
        let document = try decoder.decode(Self.self, from: data)
        try document.validate()
        return document
    }

    public func validate() throws {
        func require(_ value: Bool, _ message: String) throws {
            guard value else { throw SongError.invalid(message) }
        }
        func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
        try require(schemaVersion == Self.currentSchemaVersion, "対応しない文書形式です。")
        let allIDs = [id] + sections.map(\.id) + phrases.map(\.id) + words.map(\.id)
            + syllables.map(\.id) + moras.map(\.id) + phonemes.map(\.id)
            + music.events.map(\.id) + music.measures.map(\.id) + music.spans.map(\.id) + alignments.map(\.id)
        try require(unique(allIDs), "文書内のIDが重複しています。")
        let phraseIDs = Set(phrases.map(\.id)), wordIDs = Set(words.map(\.id))
        let syllableIDs = Set(syllables.map(\.id)), moraIDs = Set(moras.map(\.id))
        let phonemeIDs = Set(phonemes.map(\.id)), eventIDs = Set(music.events.map(\.id))
        let sectionChildren = sections.flatMap(\.phraseIDs)
        try require(unique(sectionChildren) && Set(sectionChildren) == phraseIDs, "節とフレーズの所属が一致しません。")
        let phraseChildren = phrases.flatMap(\.wordIDs)
        try require(unique(phraseChildren) && Set(phraseChildren) == wordIDs, "フレーズと単語の所属が一致しません。")
        let wordChildren = words.flatMap(\.syllableIDs)
        try require(unique(wordChildren) && Set(wordChildren) == syllableIDs, "単語と音節の所属が一致しません。")
        let moraChildren = syllables.flatMap(\.moraIDs), phonemeChildren = syllables.flatMap(\.phonemeIDs)
        try require(unique(moraChildren) && Set(moraChildren) == moraIDs, "音節とモーラの所属が一致しません。")
        try require(unique(phonemeChildren) && Set(phonemeChildren) == phonemeIDs, "音節と音素の所属が一致しません。")
        for phrase in phrases {
            try phrase.timeRange?.validate()
            try require(unique(phrase.musicalEventIDs) && Set(phrase.musicalEventIDs).isSubset(of: eventIDs), "フレーズの音符参照が不正です。")
            for id in phrase.wordIDs { try require(word(id)?.parentPhraseID == phrase.id, "単語の親が一致しません。") }
            if let range = phrase.timeRange {
                for id in phrase.musicalEventIDs {
                    if let event = event(id) { try require(range.contains(try event.range), "音符がフレーズの練習範囲を超えています。") }
                }
            }
        }
        for word in words {
            for id in word.syllableIDs { try require(syllable(id)?.parentWordID == word.id, "音節の親が一致しません。") }
        }
        let moraIndex = Dictionary(uniqueKeysWithValues: moras.map { ($0.id, $0) })
        let phonemeIndex = Dictionary(uniqueKeysWithValues: phonemes.map { ($0.id, $0) })
        for syllable in syllables {
            for id in syllable.moraIDs { try require(moraIndex[id]?.parentSyllableID == syllable.id, "モーラの親が一致しません。") }
            for id in syllable.phonemeIDs { try require(phonemeIndex[id]?.parentSyllableID == syllable.id, "音素の親が一致しません。") }
        }
        for mora in moras {
            try require(unique(mora.phonemeIDs), "モーラの音素が重複しています。")
            for id in mora.phonemeIDs {
                try require(phonemeIndex[id]?.parentMoraID == mora.id && phonemeIndex[id]?.parentSyllableID == mora.parentSyllableID,
                            "音素とモーラの親が一致しません。")
            }
        }
        for phoneme in phonemes {
            if let id = phoneme.parentMoraID {
                try require(moraIndex[id]?.parentSyllableID == phoneme.parentSyllableID && moraIndex[id]?.phonemeIDs.contains(phoneme.id) == true,
                            "音素のモーラ参照が不正です。")
            }
        }
        for measure in music.measures { try measure.range.validate() }
        for event in music.events {
            try require(event.duration > .zero, "音符・休符の長さは0より大きくしてください。")
            _ = try event.range
            if let id = event.measureID {
                try require(music.measures.contains { $0.id == id && $0.range.start <= event.onset && event.onset < $0.range.end },
                            "音符の小節参照が不正です。")
            }
            if let note = event.note {
                try require((0...127).contains(note.pitch) && (1...127).contains(note.velocity), "音高または強さが範囲外です。")
                try require(note.channel.map { (0...15).contains($0) } ?? true, "MIDIチャンネルが範囲外です。")
                try require(note.track.map { $0 >= 0 } ?? true, "MIDIトラックが範囲外です。")
            }
        }
        try require(!music.tempos.isEmpty && music.tempos.first?.onset == .zero, "曲頭のテンポが必要です。")
        try require(unique(music.tempos.map(\.onset)) && music.tempos.map(\.onset) == music.tempos.map(\.onset).sorted(), "テンポ位置が重複または逆順です。")
        for tempo in music.tempos { try require(tempo.bpm.isFinite && tempo.bpm > 0 && tempo.bpm <= 1000, "テンポが範囲外です。") }
        try require(!music.meters.isEmpty && music.meters.first?.onset == .zero, "曲頭の拍子が必要です。")
        try require(unique(music.meters.map(\.onset)) && music.meters.map(\.onset) == music.meters.map(\.onset).sorted(), "拍子位置が重複または逆順です。")
        for meter in music.meters {
            try require(meter.numerator > 0 && meter.numerator <= 128 && meter.denominator > 0 && meter.denominator <= 128,
                        "拍子が範囲外です。")
            try require(meter.denominator & (meter.denominator - 1) == 0, "拍子の分母が不正です。")
        }
        for span in music.spans {
            try span.range.validate()
            try require(unique(span.eventIDs) && Set(span.eventIDs).isSubset(of: eventIDs), "音楽構造の参照が不正です。")
            for id in span.eventIDs {
                if let event = event(id) { try require(span.range.contains(try event.range), "音符が音楽フレーズの範囲を超えています。") }
            }
        }
        for alignment in alignments {
            try require(!alignment.languageTargets.isEmpty && !alignment.musicTargets.isEmpty, "対応付けの対象が空です。")
            try require(unique(alignment.languageTargets) && unique(alignment.musicTargets), "対応付けが重複しています。")
            if alignment.relation == .oneToOne {
                try require(alignment.languageTargets.count == 1 && alignment.musicTargets.count == 1, "1対1の対応には対象を1つずつ指定してください。")
            }
            for target in alignment.languageTargets {
                let exists: Bool
                switch target.kind {
                case .word: exists = wordIDs.contains(target.id)
                case .syllable: exists = syllableIDs.contains(target.id)
                case .mora: exists = moraIDs.contains(target.id)
                case .phoneme: exists = phonemeIDs.contains(target.id)
                }
                try require(exists, "対応付けの言語参照が見つかりません。")
            }
            for target in alignment.musicTargets {
                switch target {
                case .timeRange(let range): try range.validate()
                case .event(let id, let relative):
                    guard let event = event(id) else { throw SongError.invalid("対応付けの音符が見つかりません。") }
                    if let relative {
                        try relative.validate()
                        try require(relative.end <= event.duration, "音素の対応範囲が音符の長さを超えています。")
                    }
                }
            }
        }
    }
}
