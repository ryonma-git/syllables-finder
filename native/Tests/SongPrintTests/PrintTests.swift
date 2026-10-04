import Foundation
import PDFKit
import SongCore
import SongPrint
import Testing

@MainActor
struct PrintTests {
    @Test func meaningCanMoveBelowWithoutChangingLineSpacing() throws {
        var song = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        NinthPronunciation.apply(.stage, to: &song)
        song.words[0].contextualMeaning.edit("語釈確認")
        var translations: [CGFloat] = []
        for order in [ReadingOrder.previous, .meaningBelow] {
            let sheet = PrintSheet(song: song, order: order)
            let pdf = try #require(PDFDocument(data: PDFSheet.render(sheet)))
            let page = try #require(pdf.page(at: 0))
            #expect(pdf.pageCount == 1)
            #expect(pdf.string?.contains("劇ドイツ語") == true)
            #expect(pdf.string?.contains("ブリュー・デル") == true)
            #expect(pdf.string?.contains("文の意味") == false)
            let lyric = try #require(pdf.findString("Freu·de", withOptions: []).first).bounds(for: page)
            let gloss = try #require(pdf.findString("語釈確認", withOptions: []).first).bounds(for: page)
            #expect(order == .previous ? gloss.minY > lyric.minY : gloss.minY < lyric.minY)
            translations.append(try #require(pdf.findString("歓喜よ", withOptions: []).first).bounds(for: page).minY)
        }
        #expect(translations[0] == translations[1])
        #expect(PrintSheet(song: song).order == .baseline)
        #expect(ReadingOrder.baseline.elements == [.original, .reading, .ipa, .meaning, .translation])
    }

    @Test func readingFirstKeepsTranslationBelowAnnotatedWords() throws {
        var song = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        song.words[0].contextualMeaning.edit("語釈確認")
        song.phrases[0].translation.edit("翻訳確認")
        let sheet = PrintSheet(song: song, order: .requested)
        let pdf = try #require(PDFDocument(data: PDFSheet.render(sheet)))
        let page = try #require(pdf.page(at: 0))
        #expect(pdf.pageCount == 1)
        func position(_ text: String) throws -> CGFloat {
            try #require(pdf.findString(text, withOptions: []).first).bounds(for: page).minY
        }
        let positions = try [position("Freu·de"), position("フロイ・デ"),
                             position("/ˈfʁɔʏ·də/"), position("語釈確認"), position("翻訳確認")]
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 > $1 })
        #expect(pdf.string?.contains(ReadingOrder.requested.legend) == true)
    }

    @Test func arbitraryOrderCanPutTranslationBetweenWordLayers() throws {
        let order = try #require(ReadingOrder([.reading, .translation, .original, .meaning, .ipa]))
        #expect(order.beforeTranslation == [.reading])
        #expect(order.afterTranslation == [.original, .meaning, .ipa])
        #expect(order.moving(.translation, by: -1).elements == [.translation, .reading, .original, .meaning, .ipa])
        #expect(order.moving(.reading, to: 3).elements == [.translation, .original, .meaning, .reading, .ipa])
        #expect(ReadingOrder([.original, .original, .ipa, .meaning, .translation]) == nil)
        let song = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        let pdf = try #require(PDFDocument(data: PDFSheet.render(PrintSheet(song: song, order: order))))
        let page = try #require(pdf.page(at: 0))
        func position(_ text: String) throws -> CGFloat {
            try #require(pdf.findString(text, withOptions: []).first).bounds(for: page).minY
        }
        let positions = try [position("フロイ・デ"), position("歓喜よ"), position("Freu·de"),
                             position("/ˈfʁɔʏ·də/")]
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func pdfAndWordContainSameEditedContent() throws {
        var song = SampleCatalog.entries[1].make()
        song.metadata.title = "授業用 & <Mary>"
        song.phrases[0].translation.edit("日本語訳 & 補足")
        let sheet = PrintSheet(song: song)
        #expect(sheet.phrases.count == 4)
        #expect(sheet.phrases[0].words.count == 5)
        #expect(sheet.phrases[0].words[0].reading == "メ・リー")
        #expect(sheet.phrases[0].words[0].segmented == "Ma·ry")
        #expect(sheet.phrases[0].words[4].segmented == "lamb,")
        #expect(sheet.phrases[0].words[0].syllables[0].fragments == [
            PrintFragment(text: "M", isVowelNucleus: false),
            PrintFragment(text: "a", isVowelNucleus: true)
        ])
        let pdf = try PDFSheet.render(sheet)
        let document = try #require(PDFDocument(data: pdf))
        #expect(document.pageCount == 1)
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
        let german = PrintSyllable(text: "schö", language: "de")
        #expect(german.fragments == [PrintFragment(text: "sch", isVowelNucleus: false),
                                      PrintFragment(text: "ö", isVowelNucleus: true)])
    }

    @Test func partialKatakanaRemainsVisible() throws {
        var song = SampleCatalog.entries[1].make()
        let first = try #require(song.words.first?.syllableIDs.first)
        let index = try #require(song.syllables.firstIndex { $0.id == first })
        song.syllables[index].reading.edit("")
        let word = try #require(PrintSheet(song: song).phrases.first?.words.first)
        #expect(word.reading == "□・リー")
    }

    @Test func ninthLyricsSheetShowsGermanAndJapaneseOnOnePage() throws {
        let song = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        let sheet = PrintSheet(song: song)
        let pdf = try PDFSheet.render(sheet)
        let document = try #require(PDFDocument(data: pdf))
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("Göt·ter·fun·ken") == true)
        #expect(document.string?.contains("フロイ・デ") == true)
        #expect(document.string?.contains("歓喜よ") == true)
    }
}
