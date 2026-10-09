import Foundation
import SongCore
import Testing

struct StepEntryTests {
    private func beat(_ value: Double) throws -> Beat { try Beat.grid(value, divisions: 4) }

    @Test func stepEntryWritesNotesGrowsMeasuresAndStaysValid() throws {
        var song = SongDocument()
        song.music.meters = [.init(numerator: 3, denominator: 4)]
        let part = song.addPart(name: "Soprano", abbreviation: "S")
        var cursor = Beat.zero
        for (pitch, length) in [(67, 1.0), (69, 0.5), (71, 0.5), (72, 1.0), (nil, 1.0), (74, 3.0)] as [(Int?, Double)] {
            try song.enterStep(partID: part, onset: cursor, duration: try beat(length), pitch: pitch)
            cursor = try cursor.adding(beat(length))
        }
        try song.validate()
        #expect(song.music.events.count == 6)
        #expect(song.music.measures.map(\.number) == ["1", "2", "3"])
        #expect(song.music.measures.last?.range.end == (try beat(9)))
        #expect(song.partEnd(part) == (try beat(7)))
        #expect(song.music.events.allSatisfy { $0.measureID != nil && $0.partID == part })
    }

    @Test func enteringOverAnExistingSpanReplacesAndShortens() throws {
        var song = TwinkleSample.make()
        let part = song.music.parts[0].id
        let before = song.alignments.count
        // Write a half note at beat 0.5: shortens C4(0–1), replaces C4(1–2) … up to 2.5.
        try song.enterStep(partID: part, onset: beat(0.5), duration: beat(2), pitch: 72)
        try song.validate()
        let firstMeasure = song.music.events.filter { $0.onset < (try! Beat(4)) }.sorted { $0.onset < $1.onset }
        #expect(firstMeasure.map { $0.note?.pitch } == [60, 72, 67])
        #expect(firstMeasure[0].duration == (try beat(0.5)))
        #expect(song.alignments.count == before - 2) // the removed notes' syllables lose their alignment
    }

    @Test func partsCanBeAddedAndRemovedWithTheirNotes() throws {
        var song = TwinkleSample.make()
        let alto = song.addPart(name: "Alto", abbreviation: "A", clef: .treble)
        try song.enterStep(partID: alto, onset: .zero, duration: Beat(4), pitch: 55)
        try song.validate()
        #expect(song.music.parts.count == 2)
        try song.removePart(id: alto)
        #expect(song.music.parts.count == 1 && song.music.events.count == 42)
        #expect(throws: SongError.self) { try song.removePart(id: song.music.parts[0].id) }
        try song.validate()
    }
}
