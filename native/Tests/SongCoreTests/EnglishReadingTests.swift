import SongCore
import Testing

struct EnglishReadingTests {
    @Test func importsBothReadingsAndPersistsTheSelectionWithoutChangingTheBase() throws {
        var song = example()
        var alternate = example()
        alternate.syllables[0].ipa.edit("lɛɾ")
        alternate.syllables[0].reading.edit("レ")
        alternate.syllables[1].reading.edit("リット")
        let original = try SongDocument.decode(song.encoded())
        #expect(original.metadata.selectedEnglishReading == .word)
        try song.importConnectedEnglishReading(from: alternate)
        let imported = song
        try song.importConnectedEnglishReading(from: alternate)
        #expect(song == imported)

        song = try SongDocument.decode(song.encoded())
        let first = song.words[0], second = song.words[1]
        #expect(song.metadata.selectedEnglishReading == .connected)
        #expect(song.selectedPronunciation(for: first).reading == "レ")
        #expect(song.selectedPronunciation(for: first).ipa == "lɛɾ")
        #expect(song.selectedPronunciation(for: second).ipa == "ɪt")
        #expect(song.syllableForReading(song.syllables[1]).reading.value == "リット")
        #expect(song.pronunciationDisplay(for: first).reading == "レット")
        #expect(song.syllables[0].ipa == original.syllables[0].ipa)
        #expect(song.phrases == original.phrases)
        #expect(song.music == original.music)
        song.metadata.englishReadingMode = .word
        #expect(song.selectedPronunciation(for: first).reading == "レット")
        #expect(song.selectedPronunciation(for: second).reading == "イット")
        #expect(song.syllables[1].connectedReading?.value == "リット")
    }

    @Test func rejectsIncompatibleOrConflictingImportsWithoutPartiallyEditingTheSong() throws {
        var song = example()
        var alternate = example()
        alternate.syllables[0].reading.edit("レ")
        alternate.syllables[1].text.edit("itt")
        let original = song
        #expect(throws: SongError.self) { try song.importConnectedEnglishReading(from: alternate) }
        #expect(song == original)

        alternate.syllables[1].text.edit("it")
        alternate.syllables[1].reading.edit("リット")
        try song.importConnectedEnglishReading(from: alternate)
        let imported = song
        alternate.syllables[1].reading.edit("リッ")
        #expect(throws: SongError.self) { try song.importConnectedEnglishReading(from: alternate) }
        #expect(song == imported)
    }

    @Test func englishModeDoesNotChangeFrenchPronunciation() {
        var song = example()
        song.appendPhrase(text: "Un ami", language: "fr", syllabify: true)
        song.metadata.englishReadingMode = .connected
        song.syllables[2].reading.edit("アン")
        song.syllables[2].connectedReading = .init("別の読み")
        #expect(song.selectedPronunciation(for: song.words[2]).reading == "アン")
        #expect(song.syllableForReading(song.syllables[2]).reading.value == "アン")
    }

    @Test func kanaOnlyOverrideKeepsAvailableWholeWordIPA() {
        var song = example()
        song.syllables[0].ipa = .init("")
        song.words[0].wholePronunciation = .init(surface: "Let", style: .american, ipa: "lɛt",
                                                 reading: "レット", source: .init(.dictionary))
        song.syllables[0].connectedReading = .init("レ")
        song.metadata.englishReadingMode = .connected
        let display = song.selectedPronunciation(for: song.words[0])
        #expect(display.ipa == "lɛt")
        #expect(display.reading == "レ")
        #expect(display.notice != nil)
    }

    private func example() -> SongDocument {
        var song = SongDocument()
        song.appendPhrase(text: "Let it", language: "en", syllabify: true)
        song.syllables[0].ipa = .init("lɛt")
        song.syllables[0].reading = .init("レット")
        song.syllables[1].ipa = .init("ɪt")
        song.syllables[1].reading = .init("イット")
        return song
    }
}
