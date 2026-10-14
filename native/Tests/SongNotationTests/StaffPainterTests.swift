import CoreGraphics
import Foundation
import SongCore
import SongNotation
import Testing

struct StaffPainterTests {
    @Test func clefsAndDigitsFitTheirStaffFrames() throws {
        let song = TwinkleSample.make()
        let slices = Array(MeasureProjection(song: song).slices.prefix(2))
        for clef in Clef.allCases {
            let projection = NotationProjection(song: song, measures: slices)
            let engraving = StaffEngraving(pieces: projection.pieces, measures: slices, meters: song.music.meters, clef: clef,
                                           space: 10, staffTop: 100, lineStart: 0, lineEnd: 600, headerX: 0,
                                           headerMeter: song.music.meters.first, songEnd: 48, x: { 80 + $0 * 60 })
            let shapes = StaffPainter.shapes(for: engraving)
            #expect(shapes.count > engraving.marks.count / 2)
            let clefShape = try #require(shapes.first { $0.path.boundingBoxOfPath.minX >= 4 && $0.path.boundingBoxOfPath.maxX < 40 && $0.path.boundingBoxOfPath.height > 25 })
            let box = clefShape.path.boundingBoxOfPath
            switch clef {
            case .treble: #expect(abs(box.minY - 85.5) < 0.5 && abs(box.maxY - 156.5) < 0.5)
            case .treble8vb: #expect(box.maxY > 165)
            case .bass: #expect(abs(box.minY - 99.5) < 0.5 && abs(box.maxY - 132) < 0.5)
            }
        }
    }

    @Test func textOutlinesAdvanceForJapaneseAndLatin() throws {
        let latin = try #require(StaffPainter.textPath("Freu", font: "HiraginoSans-W3", size: 12, x: 10, baseline: 50))
        let kana = try #require(StaffPainter.textPath("ひかり", font: "HiraginoSans-W3", size: 12, x: 10, baseline: 50))
        #expect(latin.width > 10 && kana.width > 30)
        #expect(latin.path.boundingBoxOfPath.maxY <= 50.5)
    }
}
