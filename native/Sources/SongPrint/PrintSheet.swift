import Foundation
import SongCore

public struct PrintFragment: Sendable, Equatable {
    public let text: String
    public let isVowelNucleus: Bool
    public let isSyllableCue: Bool
    public var isColored: Bool { isVowelNucleus || isSyllableCue }

    public init(text: String, isVowelNucleus: Bool, isSyllableCue: Bool = false) {
        self.text = text
        self.isVowelNucleus = isVowelNucleus
        self.isSyllableCue = isSyllableCue
    }
}

public struct PrintSyllable: Sendable, Equatable {
    public let text: String
    public let fragments: [PrintFragment]

    public init(text: String, language: String) {
        self.text = text
        // Use the lyric entry rules for written vowel cues; saved syllables and IPA are unchanged.
        let characters = Array(text)
        let code = String(language.prefix(2)).lowercased()
        let syllableCues: [Range<Int>] = ["ja", "ko", "zh"].contains(code)
            ? characters.indices.filter { Self.isSyllableCarrier(characters[$0], language: code) }.map { $0..<($0 + 1) }
            : []
        // A stored sung syllable carries one nucleus. Additional written vowels can be silent
        // (French "Jacques"), so do not color a second candidate in the same stored syllable.
        let ranges = Syllabifier.orthographicVowelNuclei(in: text, language: language).first.map { [$0] } ?? []
        guard !ranges.isEmpty || !syllableCues.isEmpty else {
            fragments = [.init(text: text, isVowelNucleus: false)]
            return
        }
        var highlighted = Array(repeating: false, count: characters.count)
        var syllabic = Array(repeating: false, count: characters.count)
        for range in ranges {
            for index in range { highlighted[index] = true }
        }
        for range in syllableCues {
            for index in range { syllabic[index] = true }
        }
        var parts: [PrintFragment] = []
        for (index, character) in characters.enumerated() {
            let colored = highlighted[index]
            let cue = syllabic[index]
            if let last = parts.indices.last, parts[last].isVowelNucleus == colored,
               parts[last].isSyllableCue == cue {
                parts[last] = .init(text: parts[last].text + String(character), isVowelNucleus: colored, isSyllableCue: cue)
            } else {
                parts.append(.init(text: String(character), isVowelNucleus: colored, isSyllableCue: cue))
            }
        }
        fragments = parts
    }

    private static func isSyllableCarrier(_ character: Character, language: String) -> Bool {
        guard let scalar = character.unicodeScalars.first?.value else { return false }
        switch language {
        case "ja":
            return ((0x3041...0x309F).contains(scalar) || (0x30A0...0x30FF).contains(scalar))
                && !"んンっッー".contains(character)
        case "ko":
            return (0xAC00...0xD7A3).contains(scalar) || (0x1161...0x1175).contains(scalar)
                || (0x314F...0x3163).contains(scalar)
        case "zh":
            return (0x3400...0x4DBF).contains(scalar) || (0x4E00...0x9FFF).contains(scalar)
                || (0x20000...0x2FA1F).contains(scalar)
        default: return false
        }
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

public enum ReadingElement: String, CaseIterable, Hashable, Sendable {
    case original, reading, ipa, meaning, translation

    public var label: String {
        switch self {
        case .original: "本文・音節"
        case .reading: "カタカナ"
        case .ipa: "発音記号（IPA）"
        case .meaning: "単語訳"
        case .translation: "翻訳"
        }
    }
}

public struct ReadingOrder: Equatable, Sendable {
    public let elements: [ReadingElement]

    public init?(_ elements: [ReadingElement]) {
        guard elements.count == ReadingElement.allCases.count,
              Set(elements) == Set(ReadingElement.allCases) else { return nil }
        self.elements = elements
    }

    public static let baseline = Self([.original, .reading, .ipa, .meaning, .translation])!
    public static let previous = Self([.meaning, .original, .ipa, .reading, .translation])!
    public static let meaningBelow = Self([.original, .meaning, .ipa, .reading, .translation])!
    public static let requested = baseline

    public var legend: String { elements.map(\.label).joined(separator: " → ") }

    public var beforeTranslation: [ReadingElement] {
        Array(elements.prefix { $0 != .translation })
    }

    public var afterTranslation: [ReadingElement] {
        Array(elements.drop { $0 != .translation }.dropFirst())
    }

    public func moving(_ element: ReadingElement, by offset: Int) -> Self {
        guard let index = elements.firstIndex(of: element), elements.indices.contains(index + offset) else {
            return self
        }
        var result = elements
        result.swapAt(index, index + offset)
        return Self(result)!
    }

    public func moving(_ element: ReadingElement, to destination: Int) -> Self {
        guard let source = elements.firstIndex(of: element),
              elements.indices.contains(destination), source != destination else { return self }
        var result = elements
        result.remove(at: source)
        result.insert(element, at: destination)
        return Self(result)!
    }
}

public struct PrintSheet: Sendable {
    public let title: String
    public let phrases: [PrintPhrase]
    public let order: ReadingOrder
    public let appearance: PrintAppearance
    public let pronunciationLabel: String?

    public var colorLegend: String {
        let hasSyllableCues = phrases.flatMap(\.words).flatMap(\.syllables)
            .contains { $0.fragments.contains(where: \.isSyllableCue) }
        return hasSyllableCues
            ? "色付き文字は母音核、かな・漢字・ハングルでは音節字全体の目安  ·  は音節の区切り"
            : "色付き文字は綴り上の母音核の目安  ·  は音節の区切り"
    }

    public init(song: SongDocument, order: ReadingOrder = .baseline,
                appearance: PrintAppearance = .init()) {
        self.order = order
        self.appearance = appearance
        pronunciationLabel = NinthPronunciation.isAvailable(in: song)
            ? (song.metadata.ninthPronunciation ?? .standard).label : nil
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
