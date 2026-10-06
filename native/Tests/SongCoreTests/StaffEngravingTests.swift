import Foundation
import SongCore
import Testing

struct StaffEngravingTests {
    private func engrave(_ song: SongDocument, measures range: Range<Int>, clef: Clef = .treble,
                         space: Double = 10, header: Bool = true) -> (StaffEngraving, [MeasureSlice]) {
        let slices = Array(MeasureProjection(song: song).slices[range])
        let start = slices.first!.range.start.doubleValue
        let projection = NotationProjection(song: song, measures: slices)
        let engraving = StaffEngraving(pieces: projection.pieces, measures: slices, meters: song.music.meters, clef: clef,
                                       space: space, staffTop: 100, lineStart: 0, lineEnd: 1000,
                                       headerX: header ? 0 : nil, headerMeter: header ? song.music.meters.first : nil,
                                       songEnd: MeasureProjection.songEnd(song).doubleValue,
                                       x: { 80 + ($0 - start) * 60 })
        return (engraving, slices)
    }

    private func heads(_ engraving: StaffEngraving) -> [StaffPoint] {
        engraving.marks.compactMap { if case .notehead(let point, _) = $0 { point } else { nil } }
    }

    @Test func thirdBeatNoteStillEngravesAtItsExactPosition() throws {
        var song = TwinkleSample.make()
        song.music.events[0].duration = try Beat(1, 3)
        let slices = Array(MeasureProjection(song: song).slices.prefix(1))
        let projection = NotationProjection(song: song, measures: slices)
        #expect(projection.issue == nil)
        #expect(projection.notice != nil)
        let (engraving, _) = engrave(song, measures: 0..<1)
        #expect(engraving.hits.contains { $0.eventID == song.music.events[0].id && abs($0.duration - 1.0 / 3) < 0.000_001 })
        #expect(heads(engraving).count == song.music.events.filter { $0.onset.doubleValue < 4 }.count)
        #expect(engraving.marks.contains { if case .line(let a, let b, _) = $0 {
            return a.y == 100 && b.y == 100 && b.x > a.x
        } else { return false } })
    }

    @Test func noteheadsSitExactlyOnLinesAndSpaces() {
        // Twinkle opens C4 C4 G4 G4 | A4 A4 G4(half).
        let (engraving, _) = engrave(TwinkleSample.make(), measures: 0..<2)
        let ys = heads(engraving).map(\.y)
        #expect(ys.count == 7)
        #expect(ys[0] == 150) // C4: first ledger line below the staff (top 100 + 5 spaces)
        #expect(ys[2] == 130) // G4: second line from the bottom
        #expect(ys[4] == 125) // A4: the space above it
        let staffLines = (0..<5).map { 100 + Double($0) * 10 }
        #expect(staffLines.contains(ys[2]))
        let ledgers = engraving.marks.filter {
            if case .line(let a, let b, _) = $0 { return a.y == 150 && b.y == 150 && b.x - a.x < 30 }
            return false
        }
        #expect(ledgers.count == 2)
    }

    @Test func noteheadsAreOneStaffSpaceTallAndStemsFollowTheMiddleLine() throws {
        var song = TwinkleSample.make()
        // Put B4 (middle line) and C5 into the first measure: both stems go down.
        song.music.events[2].content = .note(.init(pitch: 71))
        song.music.events[3].content = .note(.init(pitch: 72))
        let (engraving, _) = engrave(song, measures: 0..<1)
        let stems = engraving.marks.compactMap { mark -> (StaffPoint, StaffPoint)? in
            if case .line(let a, let b, let width) = mark, a.x == b.x, abs(width - 1.2) < 1e-9 { return (a, b) }
            return nil
        }
        #expect(stems.count == 4)
        #expect(stems[0].1.y < stems[0].0.y) // C4 up
        #expect(stems[2].1.y > stems[2].0.y) // B4 down
        #expect(stems[3].1.y > stems[3].0.y) // C5 down
        // A stem up from the ledger C4 reaches at least the middle line.
        #expect(stems[0].1.y <= 120)
    }

    @Test func barlinesSpanTheStaffAndTheSongEndsWithAFinalBar() {
        let song = TwinkleSample.make()
        let (middle, _) = engrave(song, measures: 0..<4)
        let bars = middle.marks.filter {
            if case .line(let a, let b, _) = $0 { return a.x == b.x && a.y == 100 && b.y == 140 }
            return false
        }
        #expect(bars.count == 4)
        let (last, _) = engrave(song, measures: 8..<12, header: false)
        let thick = last.marks.filter { if case .line(_, _, let width) = $0 { return width == 5 } else { return false } }
        #expect(thick.count == 1)
    }

    @Test func eighthNotesAreBeamedByBeatInsteadOfFlagged() {
        // Frère Jacques measures 5–6: "Son-nez les ma-ti-nes" in eighths.
        let (engraving, _) = engrave(SampleCatalog.entries[2].make(), measures: 4..<6)
        let beams = engraving.marks.filter { if case .beam = $0 { true } else { false } }
        let flags = engraving.marks.filter { if case .flag = $0 { true } else { false } }
        #expect(beams.count >= 2)
        #expect(flags.isEmpty)
    }

    @Test func clefHeaderAndBassClefPositions() throws {
        #expect(StaffEngraving.headerWidth(space: 10, meter: .init()) > StaffEngraving.headerWidth(space: 10, meter: nil))
        var song = TwinkleSample.make()
        song.music.events[0].content = .note(.init(pitch: 43)) // G2: bottom line of the bass staff
        let (engraving, _) = engrave(song, measures: 0..<1, clef: .bass)
        #expect(heads(engraving)[0].y == 140)
        #expect(engraving.marks.contains(.clef(.bass, x: 5)))
        #expect(engraving.marks.contains { if case .timeSignature(4, 4, _, false) = $0 { true } else { false } })
    }

    @Test func emptyMeasureShowsOneCenteredWholeRest() throws {
        var song = TwinkleSample.make()
        let firstMeasure = song.music.events.filter { $0.onset < (try! Beat(4)) }.map(\.id)
        firstMeasure.forEach { song.removeNote(id: $0) }
        let (engraving, _) = engrave(song, measures: 0..<1)
        let rests = engraving.marks.compactMap { if case .rest(let point, let kind) = $0 { (point, kind) } else { nil } }
        #expect(rests.count == 1)
        #expect(rests[0].1 == .whole)
        #expect(rests[0].0.x == 80 + 2 * 60)
        #expect(rests[0].0.y == 112.5) // hangs from the fourth line
    }

    @Test func lyricsStartAtNoteheadsWithHyphensInsideWords() {
        let song = TwinkleSample.make()
        let (engraving, slices) = engrave(song, measures: 0..<2)
        let range = BeatRange(start: slices.first!.range.start, end: slices.last!.range.end)
        let items = LyricLayout.items(song: song, range: range, include: { _ in true }, headLeft: engraving.headLeft,
                                      x: { 80 + $0 * 60 }, noteEnd: { engraving.headRight[$0] }, measure: { Double($0.count) * 7 })
        #expect(items.map(\.text) == ["Twin", "kle", "twin", "kle", "lit", "tle", "star"])
        #expect(items[0].hyphen != nil && items[1].hyphen == nil && items[6].hyphen == nil)
        #expect(items[0].x == heads(engraving)[0].x - 6) // notehead left edge (width 1.2 sp)
    }
}
