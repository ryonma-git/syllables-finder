import Foundation

public enum EnglishPronunciationStyle: String, Codable, CaseIterable, Sendable {
    case british, american

    public var label: String { self == .british ? "英国式" : "米国式" }
    public var modelInstruction: String {
        self == .british
            ? "Use standard British English (non-rhotic dictionary citation forms). Use /ɒ/ for LOT, /ɔː/ for THOUGHT and /əʊ/ for GOAT. Do not substitute American /ɑ/, /oʊ/, /ɚ/ or /ɝ/. Use strong forms for isolated singing aids unless context requires a weak form."
            : "Use General American English dictionary pronunciations."
    }

    /// Switching accents invalidates automatic pronunciations, never the song's structure.
    /// Keep a manually corrected word intact, including the matching other fields.
    @discardableResult
    public static func apply(_ style: Self, to song: inout SongDocument) -> EnglishPronunciation.Report {
        guard song.metadata.englishPronunciationStyle != style else {
            song.metadata.englishPronunciation = style
            return EnglishPronunciation.apply(to: &song)
        }
        let englishIDs = Set(song.phrases.filter { EnglishPronunciation.supports(song.language(of: $0)) }.map(\.id))
        var protected = Set<UUID>()
        for word in song.words where englishIDs.contains(word.parentPhraseID) {
            let units = song.syllables(in: word)
            guard !word.structureUserEdited, units.allSatisfy({
                !$0.structureUserEdited && !$0.text.userEdited && !$0.ipa.userEdited && !$0.reading.userEdited && !$0.stress.userEdited
                    && $0.moraIDs.isEmpty && $0.phonemeIDs.isEmpty
            }) else { protected.insert(word.id); continue }
            for id in word.syllableIDs {
                guard let index = song.syllables.firstIndex(where: { $0.id == id }) else { continue }
                let source = FieldSource(.rule, provider: "English accent changed")
                song.syllables[index].ipa.accept("", source: source)
                song.syllables[index].reading.accept("", source: source)
                song.syllables[index].stress.accept("", source: source)
            }
        }
        song.metadata.englishPronunciation = style
        var report = EnglishPronunciation.apply(to: &song, excludingWordIDs: protected)
        report.protectedWords += protected.count
        return report
    }
}

/// A deliberately bounded set of British citation forms, not a US-to-UK spelling transform.
/// Unknown words go to the configured model or remain unset. IPA facts checked against Collins:
/// https://www.collinsdictionary.com/dictionary/english/mountain
/// https://www.collinsdictionary.com/dictionary/english/from
/// https://www.collinsdictionary.com/dictionary/english/fall
/// https://www.collinsdictionary.com/dictionary/english/gone
enum BritishPronunciationLexicon {
    // Separate phonetic syllables; reuse only when they fit the existing singing groups.
    static let entries: [String: [[String]]] = [
        "mountain": [["ˈmaʊn", "tɪn"]], "mountains": [["ˈmaʊn", "tɪnz"]],
        "fall": [["fɔːl"]], "falls": [["fɔːlz"]], "falling": [["ˈfɔː", "lɪŋ"]],
        "from": [["frɒm"], ["frəm"]], "gone": [["ɡɒn"]], "soft": [["sɒft"]],
        "a": [["ə"]], "an": [["ən"]], "the": [["ðə"], ["ðiː"]],
        "are": [["ɑː"], ["ə"]], "for": [["fɔː"], ["fə"]], "or": [["ɔː"]],
        "of": [["ɒv"], ["əv"]], "to": [["tuː"], ["tə"]], "and": [["ænd"], ["ənd"]],
        "go": [["ɡəʊ"]], "snow": [["snəʊ"]], "no": [["nəʊ"]],
        "all": [["ɔːl"]], "call": [["kɔːl"]], "calling": [["ˈkɔː", "lɪŋ"]],
        "here": [["hɪə"]], "there": [["ðeə"]], "where": [["weə"]],
        "i": [["aɪ"]], "you": [["juː"]], "we": [["wiː"]], "he": [["hiː"]],
        "she": [["ʃiː"]], "it": [["ɪt"]], "in": [["ɪn"]], "on": [["ɒn"]],
        "is": [["ɪz"]], "was": [["wɒz"]], "not": [["nɒt"]], "with": [["wɪð"]],
        "be": [["biː"]], "me": [["miː"]], "my": [["maɪ"]], "by": [["baɪ"]],
        "wind": [["wɪnd"], ["waɪnd"]], "read": [["riːd"], ["red"]]
    ]
    static func forms(for surface: String) -> [[String]] {
        let key = surface.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        return entries[key] ?? []
    }
}
