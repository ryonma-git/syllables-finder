import Foundation
import PDFKit
import SongCore
import SongPrint
import Testing

@MainActor
struct PrintTests {
    @Test func readingSelectionChangesAnnotationsButKeepsTheOriginal() throws {
        var song = SongDocument()
        song.appendPhrase(text: "Let it", language: "en", syllabify: true)
        song.syllables[0].ipa = .init("lɛt")
        song.syllables[0].reading = .init("レット")
        song.syllables[0].connectedIPA = .init("lɛɾ")
        song.syllables[0].connectedReading = .init("レ")
        for (mode, ipa, reading) in [(EnglishReadingMode.word, "/lɛt/", "レット"),
                                     (.connected, "/lɛɾ/", "レ")] {
            song.metadata.englishReadingMode = mode
            let sheet = PrintSheet(song: song)
            #expect(sheet.pronunciationLabel == mode.label)
            #expect(sheet.phrases.first?.original == "Let it")
            #expect(sheet.phrases.first?.words.first?.ipa == ipa)
            #expect(sheet.phrases.first?.words.first?.reading == reading)
            let pdf = try #require(PDFDocument(data: PDFSheet.render(sheet)))
            #expect(pdf.findString(ipa, withOptions: []).count == 1)
            #expect(pdf.findString("Let it", withOptions: []).count == 1)
        }
    }

    @Test func oversizedOriginalTranslationAndWordColumnsKeepEveryLineInsidePages() throws {
        var song = SongDocument()
        song.appendPhrase(text: "Blue sky", language: "en", syllabify: true)
        func lines(_ prefix: String, count: Int) -> String {
            (1...count).map { String(format: "%@%03d 日本語の内容", prefix, $0) }.joined(separator: "\n")
        }
        song.phrases[0].originalText = lines("ORIGINAL", count: 100)
        song.phrases[0].translation.edit(lines("TRANSLATION", count: 100))
        song.words[0].contextualMeaning.edit(lines("GLOSS", count: 100))
        song.words[1].contextualMeaning.edit(lines("SECOND", count: 35))
        let splitOrder = try #require(ReadingOrder([.reading, .translation, .original, .meaning, .ipa]))
        for (design, order) in [(PrintDesign.standard, ReadingOrder.baseline),
                                (.compact, .previous), (.largePrint, splitOrder)] {
            var appearance = PrintAppearance()
            appearance.design = design
            let pdf = try #require(PDFDocument(data: PDFSheet.render(PrintSheet(song: song, order: order, appearance: appearance))))
            #expect(pdf.pageCount > 3)
            for (prefix, count) in [("ORIGINAL", 100), ("TRANSLATION", 100), ("GLOSS", 100), ("SECOND", 35)] {
                for index in 1...count {
                    let marker = String(format: "%@%03d", prefix, index)
                    let matches = pdf.findString(marker, withOptions: [])
                    #expect(matches.count == 1, "Missing or repeated \(marker), design \(design)")
                    let match = try #require(matches.first)
                    let page = try #require(match.pages.first)
                    let bounds = match.bounds(for: page)
                    let paper = page.bounds(for: .mediaBox)
                    // Body text must remain clear of the footer and repeated page header.
                    #expect(bounds.minY >= 50, "Below printable area: \(marker)")
                    #expect(bounds.maxY <= paper.maxY - 85, "Overlaps header: \(marker)")
                    #expect(bounds.minX >= 27 && bounds.maxX <= paper.maxX - 27)
                }
            }
        }
    }

    @Test func wrappedAndMultipageTitlesDoNotOverlapLyricsOrLoseText() throws {
        for count in [12, 50, 500] {
            var song = SongDocument()
            song.appendPhrase(text: "BodyStart", language: "en", syllabify: false)
            song.metadata.title = (1...count).map { String(format: "TITLE%03d", $0) }.joined(separator: " ")
            let pdf = try #require(PDFDocument(data: PDFSheet.render(PrintSheet(song: song))))
            var lastTitlePage = 0
            var lastTitleBottom = CGFloat.greatestFiniteMagnitude
            for index in 1...count {
                let marker = String(format: "TITLE%03d", index)
                let matches = pdf.findString(marker, withOptions: [])
                #expect(!matches.isEmpty, "Missing title text: \(marker)")
                let match = try #require(matches.first)
                let page = try #require(match.pages.first)
                let bounds = match.bounds(for: page)
                #expect(bounds.minY >= 50)
                #expect(bounds.maxY <= page.bounds(for: .mediaBox).maxY - 25)
                if index == count {
                    lastTitlePage = pdf.index(for: page)
                    lastTitleBottom = bounds.minY
                }
            }
            let body = try #require(pdf.findString("BodyStart", withOptions: []).first)
            let bodyPage = try #require(body.pages.first)
            let bodyPageIndex = pdf.index(for: bodyPage)
            #expect(bodyPageIndex >= lastTitlePage)
            if bodyPageIndex == lastTitlePage {
                #expect(body.bounds(for: bodyPage).maxY < lastTitleBottom)
            }
        }
    }

    @Test func continuousOriginalPrecedesAnnotationsInEveryOrder() throws {
        var song = SongDocument()
        song.appendPhrase(text: "Bonjour, amie !", language: "fr", syllabify: true)
        try song.setSyllables(wordID: song.words[0].id, texts: ["Bon", "jour"])
        song.phrases[0].translation.edit("こんにちは、友だち！")
        let splitOrder = try #require(ReadingOrder([.reading, .translation, .original, .meaning, .ipa]))
        for order in [ReadingOrder.baseline, .previous, splitOrder] {
            let sheet = PrintSheet(song: song, order: order)
            let pdf = try #require(PDFDocument(data: PDFSheet.render(sheet)))
            let page = try #require(pdf.page(at: 0))
            let originals = pdf.findString("Bonjour, amie !", withOptions: [])
            #expect(originals.count == 1)
            let original = try #require(originals.first).bounds(for: page)
            let segmented = try #require(pdf.findString("Bon·jour,", withOptions: []).first).bounds(for: page)
            #expect(original.minY > segmented.maxY)
            #expect(pdf.string?.contains("こんにちは、友だち！") == true)

            let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
            defer { try? FileManager.default.removeItem(at: path) }
            try WordSheet.render(sheet).write(to: path)
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", path.path, "word/document.xml"]
            process.standardOutput = output
            try process.run()
            let xml = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            let originalPosition = try #require(xml.range(of: "Bonjour, amie !"))
            let annotationPosition = try #require(xml.range(of: "<w:tbl>"))
            #expect(originalPosition.lowerBound < annotationPosition.lowerBound)
        }
    }

    @Test func originalWithoutWordAnnotationsIsPrintedOnce() throws {
        var song = SongDocument()
        song.appendPhrase(text: "原文だけの行。", language: "ja", syllabify: false)
        song.phrases[0].wordIDs = []
        let pdf = try #require(PDFDocument(data: PDFSheet.render(PrintSheet(song: song))))
        #expect(pdf.findString("原文だけの行。", withOptions: []).count == 1)
    }

    @Test func wholeWordFallbackAppearsWithWarningInPDFAndWord() throws {
        var song = SongDocument()
        song.appendPhrase(text: "expression", language: "en", syllabify: true)
        try song.setSyllables(wordID: song.words[0].id, texts: ["ex", "pres", "si", "on"])
        EnglishPronunciation.apply(to: &song)
        let sheet = PrintSheet(song: song)
        #expect(sheet.phrases[0].words[0].reading.contains("音節対応は要確認"))
        #expect(!sheet.phrases[0].words[0].ipa.isEmpty)
        let pdf = try #require(PDFDocument(data: PDFSheet.render(sheet)))
        #expect(pdf.string?.contains("音節対応は要確認") == true)
        #expect(try !WordSheet.render(sheet).isEmpty)
    }

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

    @Test func printedNucleiFollowEachAlphabeticLanguage() throws {
        func colored(_ text: String, _ language: String) -> String {
            PrintSyllable(text: text, language: language).fragments
                .filter(\.isVowelNucleus).map(\.text).joined()
        }
        #expect(colored("make", "en") == "a")
        #expect(colored("schön", "de") == "ö")
        #expect(colored("Frè", "fr") == "è")
        #expect(colored("Jacques", "fr") == "a")
        #expect(colored("quié", "es") == "ié")
        #expect(colored("cia", "it") == "a")
        #expect(colored("quae", "la") == "ae")
        #expect(colored("Пе", "ru") == "е")
        for language in ["en", "de", "fr", "es", "it", "la", "ru"] {
            let entry = try #require(SampleCatalog.entries.first { $0.languageCode == language })
            let words = PrintSheet(song: entry.make()).phrases.flatMap(\.words)
            #expect(words.contains { $0.displayFragments.contains(where: \.isVowelNucleus) })
        }
    }

    @Test func unsegmentedWordsAreNotAssignedInventedVowels() {
        let word = PrintSyllable(text: "sch", language: "en")
        #expect(word.fragments == [PrintFragment(text: "sch", isVowelNucleus: false)])
        let german = PrintSyllable(text: "schö", language: "de")
        #expect(german.fragments == [PrintFragment(text: "sch", isVowelNucleus: false),
                                      PrintFragment(text: "ö", isVowelNucleus: true)])
    }

    @Test func syllabicScriptsUseWholeCharacterCuesWithoutClaimingVowelLetters() throws {
        for (text, language) in [("さ", "ja"), ("아", "ko"), ("好", "zh")] {
            let fragment = try #require(PrintSyllable(text: text, language: language).fragments.first)
            #expect(fragment.text == text)
            #expect(fragment.isSyllableCue && !fragment.isVowelNucleus && fragment.isColored)
            let entry = try #require(SampleCatalog.entries.first { $0.languageCode == language })
            let sheet = PrintSheet(song: entry.make())
            #expect(sheet.phrases.flatMap(\.words).contains {
                $0.displayFragments.contains(where: \.isSyllableCue)
            })
            #expect(sheet.colorLegend.contains("音節字全体"))
        }
        for text in ["ん", "っ", "ー", "!"] {
            let colored = PrintSyllable(text: text, language: "ja").fragments.contains { $0.isColored }
            #expect(!colored)
        }
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
