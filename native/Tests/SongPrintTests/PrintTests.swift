import Foundation
import PDFKit
import SongCore
import SongPrint
import Testing

@MainActor
struct PrintTests {
    @Test func pdfAndWordContainSameEditedContent() throws {
        var song = SampleCatalog.entries[1].make()
        song.metadata.title = "授業用 & <Mary>"
        song.phrases[0].translation.edit("日本語訳 & 補足")
        let sheet = PrintSheet(song: song)
        #expect(sheet.phrases.count == 4)
        #expect(sheet.phrases[0].words.count == 5)
        #expect(sheet.phrases[0].words[0].reading == "メ・リー")
        #expect(sheet.phrases[0].words[0].segmented == "Ma·ry")
        #expect(sheet.phrases[0].words[0].syllables[0].fragments == [
            PrintFragment(text: "M", isVowelNucleus: false),
            PrintFragment(text: "a", isVowelNucleus: true)
        ])
        let pdf = try PDFSheet.render(sheet)
        let document = try #require(PDFDocument(data: pdf))
        #expect(document.pageCount >= 1)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == 595.28)
        #expect(document.string?.contains("日本語訳 & 補足") == true)
        #expect(document.string?.contains("音節") == true)
        #expect(document.string?.contains("メ・リー") == true)
        let word = try WordSheet.render(sheet)
        #expect(word.starts(with: [0x50, 0x4b]))
        #expect(word.count > 3_000)
    }

    @Test func unsegmentedWordsAreNotAssignedInventedVowels() {
        let word = PrintSyllable(text: "sch", language: "en")
        #expect(word.fragments == [PrintFragment(text: "sch", isVowelNucleus: false)])
        let french = PrintSyllable(text: "Frè", language: "fr")
        #expect(french.fragments == [PrintFragment(text: "Frè", isVowelNucleus: false)])
    }
}
