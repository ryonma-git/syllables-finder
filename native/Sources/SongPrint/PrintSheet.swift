import Foundation
import SongCore

public struct PrintFragment: Sendable, Equatable {
    public let text: String
    public let isVowelNucleus: Bool

    public init(text: String, isVowelNucleus: Bool) {
        self.text = text
        self.isVowelNucleus = isVowelNucleus
    }
}

public struct PrintSyllable: Sendable, Equatable {
    public let text: String
    public let fragments: [PrintFragment]

    public init(text: String, language: String) {
        self.text = text
        // This is an orthographic cue for English and German syllables already stored in the document.
        // It does not infer an IPA transcription or change the saved pronunciation.
        let english = language.hasPrefix("en")
        let german = language.hasPrefix("de")
        guard english || german else {
            fragments = [.init(text: text, isVowelNucleus: false)]
            return
        }
        let letters = Array(text)
        let vowels = german ? "aeiouyäöü" : "aeiouy"
        guard let start = letters.indices.first(where: { vowels.contains(letters[$0].lowercased()) }) else {
            fragments = [.init(text: text, isVowelNucleus: false)]
            return
        }
        var end = start + 1
        while end < letters.count && vowels.contains(letters[end].lowercased()) { end += 1 }
        if english && end < letters.count && letters[end].lowercased() == "w" { end += 1 }
        var parts: [PrintFragment] = []
        if start > 0 { parts.append(.init(text: String(letters[..<start]), isVowelNucleus: false)) }
        parts.append(.init(text: String(letters[start..<end]), isVowelNucleus: true))
        if end < letters.count { parts.append(.init(text: String(letters[end...]), isVowelNucleus: false)) }
        fragments = parts
    }
}

public struct PrintWord: Sendable {
    public let original: String
    public let meaning: String
    public let syllables: [PrintSyllable]
    public let ipa: String
    public let reading: String

    public init(original: String, meaning: String, syllables: [PrintSyllable], ipa: String, reading: String) {
        self.original = original; self.meaning = meaning; self.syllables = syllables
        self.ipa = ipa; self.reading = reading
    }

    /// Keeps punctuation attached to its word when the stored syllables omit it.
    public var displayFragments: [PrintFragment] {
        guard !syllables.isEmpty else { return [.init(text: original, isVowelNucleus: false)] }
        var parts = syllables.enumerated().flatMap { index, syllable in
            (index == 0 ? [] : [PrintFragment(text: "·", isVowelNucleus: false)]) + syllable.fragments
        }
        let joined = syllables.map(\.text).joined()
        if let range = original.range(of: joined, options: [.caseInsensitive, .anchored]) {
            let suffix = String(original[range.upperBound...])
            if !suffix.isEmpty { parts.append(.init(text: suffix, isVowelNucleus: false)) }
        } else if let range = original.range(of: joined, options: .caseInsensitive) {
            let prefix = String(original[..<range.lowerBound])
            let suffix = String(original[range.upperBound...])
            if !prefix.isEmpty { parts.insert(.init(text: prefix, isVowelNucleus: false), at: 0) }
            if !suffix.isEmpty { parts.append(.init(text: suffix, isVowelNucleus: false)) }
        }
        return parts
    }

    public var segmented: String {
        displayFragments.map(\.text).joined()
    }
}

public struct PrintPhrase: Sendable {
    public let section: String
    public let original: String
    public let translation: String
    public let words: [PrintWord]
}

public struct PrintSheet: Sendable {
    public let title: String
    public let phrases: [PrintPhrase]

    public init(song: SongDocument) {
        title = song.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "歌唱練習シート" : song.metadata.title
        phrases = song.sections.flatMap { section in
            section.phraseIDs.compactMap { song.phrase($0) }.map { phrase in
                PrintPhrase(section: section.title, original: phrase.originalText,
                            translation: phrase.translation.value,
                            words: song.words(in: phrase).map { word in
                    let syllables = song.syllables(in: word)
                    return PrintWord(original: word.surface, meaning: word.contextualMeaning.value,
                                     syllables: syllables.map {
                                         PrintSyllable(text: $0.text.value, language: phrase.language ?? song.metadata.sourceLanguage)
                                     },
                                     ipa: syllables.isEmpty || syllables.contains(where: { $0.ipa.value.isEmpty })
                                        ? "" : syllables.map(\.ipa.value).joined(separator: "·").wrappedInSlashes,
                                     reading: syllables.allSatisfy { $0.reading.value.isEmpty }
                                        ? "" : syllables.map { $0.reading.value.isEmpty ? "□" : $0.reading.value }.joined(separator: "・"))
                })
            }
        }
    }
}

private extension String {
    var wrappedInSlashes: String { isEmpty ? "" : "/\(self)/" }
}
