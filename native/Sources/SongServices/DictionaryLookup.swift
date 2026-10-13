import Foundation
import CoreServices
import SongCore

/// Uses only the dictionaries installed/enabled on this Mac. It does not claim to translate sentences.
public enum DictionaryLookup {
    public static func definition(for surface: String) -> String? {
        let word = surface.trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'-’")).inverted)
        guard !word.isEmpty else { return nil }
        let text = word as CFString
        guard let value = DCSCopyTextDefinition(nil, text, CFRange(location: 0, length: CFStringGetLength(text)))?.takeRetainedValue() as String? else { return nil }
        return String(value.prefix(2000))
    }
    @discardableResult
    public static func apply(to song: inout SongDocument, phraseIDs: Set<UUID>) -> Int {
        var found = 0
        for index in song.words.indices where phraseIDs.contains(song.words[index].parentPhraseID) {
            guard song.words[index].dictionaryMeaning.value.isEmpty, !song.words[index].dictionaryMeaning.userEdited,
                  let definition = definition(for: song.words[index].surface) else { continue }
            song.words[index].dictionaryMeaning.accept(definition, source: .init(.dictionary, provider: "macOS Dictionary"))
            found += 1
        }
        return found
    }
}
