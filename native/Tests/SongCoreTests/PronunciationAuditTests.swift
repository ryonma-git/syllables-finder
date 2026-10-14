import Foundation
import Testing
import SongCore

struct PronunciationAuditTests {
    @Test func findsDictionaryMismatchAndKanaMismatchWithoutChangingAnything() throws {
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "mountain falling from", language: "en", syllabify: true)
        song.syllables[1].ipa.edit("taɪn")
        song.syllables[2].reading.edit("ファ")
        let part = song.addPart(name: "旋律")
        let note = try song.enterStep(partID: part, onset: Beat(0), duration: Beat(1), pitch: 60)
        try song.align(syllableID: song.syllables[0].id, to: [note])
        let original = song
        let entries = PronunciationAudit.entries(in: song)
        #expect(entries[0].status == .review && entries[0].issues.contains { $0.contains("単語全体") })
        #expect(entries[1].status == .review && entries[1].issues.contains { $0.contains("フォー") })
        #expect(entries[2].status == .matched)
        #expect(entries[0].manuallyEdited && entries[1].manuallyEdited)
        #expect(song == original)
    }
    @Test func dictionaryAbsenceAndMissingIPAAndUnsupportedLanguageAreNotPasses() {
        var song = SongDocument()
        song.appendPhrase(text: "Zog the", language: "en", syllabify: true)
        song.syllables[0].ipa = .init("zɒɡ")
        song.syllables[0].reading = .init("ゾッグ")
        song.syllables[1].ipa = .init("")
        song.appendPhrase(text: "bonjour", language: "fr", syllabify: false)
        let entries = PronunciationAudit.entries(in: song)
        #expect(entries[0].status == .absent)
        #expect(entries[1].status == .missing)
        #expect(entries[2].status == .missing || entries[2].status == .unsupported)
    }
    @Test func acceptsDictionaryVariantsAndDocumentsConventionsButFlagsWrongSyllableAllocation() {
        var song = SongDocument()
        song.appendPhrase(text: "are the of creation", language: "en", syllabify: true)
        #expect(PronunciationAudit.entries(in: song).allSatisfy { $0.status == .matched })
        song.syllables[3].ipa = .init("kriˈeɪ")
        song.syllables[4].ipa = .init("ʃ")
        song.syllables[5].ipa = .init("ən")
        #expect(PronunciationAudit.entries(in: song).last!.issues.contains { $0.contains("配分") })
        var british = SongDocument()
        british.metadata.englishPronunciation = .british
        british.appendPhrase(text: "from", language: "en", syllabify: true)
        british.syllables[0].ipa = .init("frəm")
        british.syllables[0].reading = .init("フラム")
        #expect(PronunciationAudit.entries(in: british)[0].status == .matched)
    }
}
