import Foundation

public enum EnglishReadingMode: String, Codable, CaseIterable, Sendable {
    case word, connected

    public var label: String { self == .word ? "単語読み" : "つながり読み" }
}

extension Syllable {
    var hasConnectedEnglishReading: Bool { connectedIPA != nil || connectedReading != nil }

    func applyingConnectedEnglishReading() -> Self {
        var result = self
        result.ipa = connectedIPA ?? ipa
        result.reading = connectedReading ?? reading
        return result
    }
}

extension SongDocument {
    public var hasEnglishLyrics: Bool {
        phrases.contains { EnglishPronunciation.supports(language(of: $0)) }
    }

    public var hasConnectedEnglishReading: Bool {
        syllables.contains { unit in
            unit.hasConnectedEnglishReading && word(unit.parentWordID).map(hasEnglishPronunciation(for:)) == true
        }
    }

    public func hasEnglishPronunciation(for word: Word) -> Bool {
        guard let phrase = phrase(word.parentPhraseID) else { return false }
        return EnglishPronunciation.supports(language(of: phrase))
    }

    public func usesConnectedEnglishReading(for word: Word) -> Bool {
        metadata.selectedEnglishReading == .connected && hasEnglishPronunciation(for: word)
    }

    /// A presentation value. The stored pronunciation and alignment remain available to the editor and analysis.
    public func syllableForReading(_ syllable: Syllable) -> Syllable {
        guard metadata.selectedEnglishReading == .connected, syllable.hasConnectedEnglishReading,
              let word = word(syllable.parentWordID), hasEnglishPronunciation(for: word) else { return syllable }
        return syllable.applyingConnectedEnglishReading()
    }

    public mutating func importConnectedEnglishReading(from url: URL) throws {
        let file = url.appendingPathComponent("document.json")
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else {
            throw SongError.invalid("曲ファイルのdocument.jsonを読み込めません。")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumEncodedBytes + 1) ?? Data()
        try importConnectedEnglishReading(from: Self.decode(data))
    }

    /// Copies readings from the corresponding English syllables, with no changes to lyrics or music.
    /// A previously stored connected form must agree with the incoming value; a conflict aborts the import.
    public mutating func importConnectedEnglishReading(from source: SongDocument) throws {
        guard hasEnglishLyrics else { throw SongError.invalid("英語の歌詞がある曲で使えます。") }
        guard metadata.englishPronunciationStyle == source.metadata.englishPronunciationStyle else {
            throw SongError.invalid("取り込む曲と英語の発音基準（米国式・英国式）をそろえてください。")
        }
        let ownPhrases = sections.flatMap(\.phraseIDs).compactMap { phrase($0) }
        let otherPhrases = source.sections.flatMap(\.phraseIDs).compactMap { source.phrase($0) }
        let mismatch = SongError.invalid("取り込む曲は、歌詞の順番・単語・音節の区切りをそろえてください。")
        guard ownPhrases.count == otherPhrases.count else { throw mismatch }
        let indices = Dictionary(uniqueKeysWithValues: syllables.enumerated().map { ($0.element.id, $0.offset) })
        var updated = syllables
        var hasConnectedReading = false
        for (own, other) in zip(ownPhrases, otherPhrases) {
            guard own.originalText == other.originalText, language(of: own) == source.language(of: other) else {
                throw mismatch
            }
            let ownWords = words(in: own), otherWords = source.words(in: other)
            guard ownWords.map(\.surface) == otherWords.map(\.surface) else { throw mismatch }
            guard EnglishPronunciation.supports(language(of: own)) else { continue }
            for (ownWord, otherWord) in zip(ownWords, otherWords) {
                let ownUnits = syllables(in: ownWord), otherUnits = source.syllables(in: otherWord)
                guard ownUnits.map(\.text.value) == otherUnits.map(\.text.value) else { throw mismatch }
                for (ownUnit, otherUnit) in zip(ownUnits, otherUnits) {
                    let incoming = otherUnit.applyingConnectedEnglishReading()
                    guard let index = indices[ownUnit.id] else { throw mismatch }
                    updated[index].connectedIPA = try Self.importedReading(incoming.ipa, saved: ownUnit.connectedIPA, base: ownUnit.ipa)
                    updated[index].connectedReading = try Self.importedReading(incoming.reading, saved: ownUnit.connectedReading, base: ownUnit.reading)
                    hasConnectedReading = hasConnectedReading || updated[index].hasConnectedEnglishReading
                }
            }
        }
        guard hasConnectedReading else {
            throw SongError.invalid("単語読みと異なるIPA・カタカナが見つかりません。")
        }
        syllables = updated
        metadata.englishReadingMode = .connected
    }

    private static func importedReading(_ incoming: TextFieldValue, saved: TextFieldValue?, base: TextFieldValue) throws -> TextFieldValue? {
        guard !incoming.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return saved }
        if let saved {
            guard saved.value == incoming.value else {
                throw SongError.invalid("取り込む読みが、保存済みのつながり読みと一致しません。")
            }
            return saved
        }
        return incoming.value == base.value ? nil : incoming
    }
}
