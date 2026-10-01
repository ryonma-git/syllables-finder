import Foundation
import PDFKit
import SongCore
import SongNotation
import Testing

struct ScoreSheetTests {
    @Test func scorePDFHasSearchableTitleLyricsAndReadings() throws {
        let song = SampleCatalog.entries.first { $0.id == "frere" }!.make()
        let data = try ScoreSheet(song: song).pdfData()
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).width == 595.28)
        let text = try #require(pdf.string)
        #expect(text.contains("Frère Jacques"))
        #expect(text.contains("Son") && text.contains("matines") == false) // syllables, not whole words
        #expect(text.contains("ジャ"))
        #expect(text.contains("1 / 1"))
    }

    @Test func longSongsContinueOnMorePagesAndKeepEveryMeasure() throws {
        var song = TwinkleSample.make()
        // Repeat the melody eight times (96 bars) without lyrics.
        let original = song.music.events
        for round in 1..<8 {
            for event in original {
                var copy = event
                copy.id = UUID()
                copy.onset = try event.onset.adding(Beat(Int64(48 * round)))
                song.music.events.append(copy)
            }
        }
        song.music.measures = []
        try song.extendMeasures(through: MeasureProjection.songEnd(song))
        let sheet = ScoreSheet(song: song)
        #expect(sheet.pageCount >= 2)
        let pdf = try #require(PDFDocument(data: try sheet.pdfData()))
        #expect(pdf.pageCount == sheet.pageCount)
        #expect(pdf.string?.contains("\(sheet.pageCount) / \(sheet.pageCount)") == true)
    }

    @Test func everyPartGetsAStaffInEverySystem() throws {
        var song = TwinkleSample.make()
        let alto = song.addPart(name: "Alto", abbreviation: "A")
        var cursor = Beat.zero
        for pitch in [55, 55, 60, 60, 60, 60, 60] {
            try song.enterStep(partID: alto, onset: cursor, duration: Beat(1), pitch: pitch)
            cursor = try cursor.adding(Beat(1))
        }
        let proposal = try LyricAligner.propose(song: song, partID: alto)
        LyricAligner.apply(proposal, to: &song)
        let text = try #require(PDFDocument(data: try ScoreSheet(song: song).pdfData())?.string)
        #expect(text.contains("A"))
        #expect(text.components(separatedBy: "Twin").count - 1 >= 3) // soprano twice + alto once
    }
}
