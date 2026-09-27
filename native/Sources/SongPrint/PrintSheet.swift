import Foundation
import SongCore

public struct PrintWord: Sendable {
    public let original: String
    public let meaning: String
    public let ipa: String
    public let reading: String
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
                                     ipa: syllables.map(\.ipa.value).filter { !$0.isEmpty }
                                        .map { "/\($0)/" }.joined(separator: " · "),
                                     reading: syllables.map(\.reading.value).filter { !$0.isEmpty }
                                        .joined(separator: "・"))
                })
            }
        }
    }
}
