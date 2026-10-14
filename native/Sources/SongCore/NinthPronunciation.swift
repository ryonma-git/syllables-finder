import Foundation

public enum NinthPronunciation: String, Codable, CaseIterable, Sendable {
    case standard, stage

    public var label: String { self == .stage ? "劇ドイツ語" : "標準ドイツ語" }

    private static var reference: SongDocument {
        SampleCatalog.entries.first { $0.id == "ninth" }!.make()
    }

    public static func isAvailable(in song: SongDocument) -> Bool {
        song.id == reference.id && song.metadata.sourceLanguage.hasPrefix("de")
    }

    /// A preset for this sample, not a general German pronunciation converter.
    /// Stage diction retains consonantal r, including -er (Bithell, German
    /// Pronunciation and Phonology, p. 30). Kana is a Japanese singing aid.
    public static func apply(_ style: Self, to song: inout SongDocument) {
        guard isAvailable(in: song) else { return }
        let reference = reference
        for word in reference.words {
            guard let currentWord = song.word(word.id), currentWord.surface == word.surface,
                  !currentWord.structureUserEdited,
                  currentWord.syllableIDs == word.syllableIDs else { continue }
            for standard in reference.syllables(in: word) {
                guard let index = song.syllables.firstIndex(where: { $0.id == standard.id }) else { continue }
                let current = song.syllables[index]
                let stage = stageValues(standard)
                // Preserve manual/analysed pronunciations and changed syllable structures.
                guard current.text == standard.text, !current.structureUserEdited,
                      current.phonemeIDs.isEmpty, current.moraIDs.isEmpty,
                      !current.ipa.userEdited, !current.reading.userEdited,
                      current.ipa.source.kind == .sample, current.reading.source.kind == .sample,
                      (current.ipa.value == standard.ipa.value && current.reading.value == standard.reading.value)
                        || (current.ipa.value == stage.ipa && current.reading.value == stage.reading) else { continue }
                song.syllables[index].ipa.value = style == .stage ? stage.ipa : standard.ipa.value
                song.syllables[index].reading.value = style == .stage ? stage.reading : standard.reading.value
            }
        }
        song.metadata.ninthPronunciation = style == .stage ? .stage : nil
    }

    private static func stageValues(_ syllable: Syllable) -> (ipa: String, reading: String) {
        let endings: [String: (String, String)] = [
            "nɐ": ("nər", "ネル"), "ɐ": ("ər", syllable.text.value == "ter" ? "テル" : "エル"),
            "tɐ": ("tər", "テル"), "bɐ": ("bər", "ベル"), "dɐ": ("dər", "デル"),
            "viːɐ": ("viːr", "ヴィール"), "ˈveːɐ": ("ˈveːr", "ヴェール")
        ]
        if let ending = endings[syllable.ipa.value] { return ending }
        return (syllable.ipa.value.replacingOccurrences(of: "ʁ", with: "r"), syllable.reading.value)
    }
}
