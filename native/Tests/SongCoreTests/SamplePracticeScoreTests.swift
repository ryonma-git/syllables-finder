import Foundation
import Testing
@testable import SongCore

struct SamplePracticeScoreTests {
    @Test func everySampleCoversItsLyricsAndEverySungNoteExactlyOnce() throws {
        for entry in SampleCatalog.entries {
            let song = entry.make()
            #expect(!song.hasUnplacedLyrics, "Unplaced lyrics: \(entry.id)")
            for syllable in song.syllables {
                let matches = song.alignments.filter { $0.languageTargets.contains(.init(.syllable, syllable.id)) }
                #expect(matches.count == 1, "Missing or duplicate underlay: \(entry.id)")
            }
            for event in song.music.events {
                let matches = song.alignments.filter { alignment in
                    alignment.musicTargets.contains { if case .event(let id, _) = $0 { return id == event.id }; return false }
                }
                #expect(matches.count == (event.note == nil ? 0 : 1), "Uncovered note or sung rest: \(entry.id)")
            }
            for phrase in song.phrases {
                let range = try #require(phrase.timeRange)
                #expect(!phrase.musicalEventIDs.isEmpty)
                let syllables = song.words(in: phrase).flatMap { song.syllables(in: $0) }
                for syllable in syllables {
                    #expect(song.ranges(for: .init(.syllable, syllable.id)).allSatisfy { range.contains($0) })
                }
            }
        }
    }

    @Test func sourceAnchorsPreserveMelismasElisionPickupsAndRestBars() throws {
        func sample(_ id: String) -> SongDocument { SampleCatalog.entries.first { $0.id == id }!.make() }
        let cuckoo = sample("cuckoo")
        #expect(cuckoo.music.meters[0].numerator == 3)
        #expect(cuckoo.music.events.filter { $0.note == nil }.count == 2)
        #expect(cuckoo.music.events.last?.duration == (try Beat(3)))
        let mountain = sample("mountain")
        #expect(mountain.music.measures[0].number == "0")
        #expect(mountain.music.measures[0].range.end == (try Beat(1, 2)))
        let ninth = sample("ninth")
        #expect(ninth.music.events.count == 62)
        #expect(ninth.phrases.map { $0.timeRange?.length } == [16,16,16,16])
        #expect(ninth.alignments.filter { $0.relation == .melisma }.count == 2)
        let danny = sample("danny")
        let call = try #require(danny.syllables.first { $0.text.value == "cal" })
        let melisma = try #require(danny.alignments.first { $0.languageTargets.contains(.init(.syllable, call.id)) })
        #expect(melisma.relation == .melisma && melisma.musicTargets.count == 2)
        let week = sample("week")
        #expect(week.alignments.first?.relation == .elision)
        #expect(week.alignments.first?.languageTargets.count == 2)
        #expect(week.syllables.first?.ipa.value == "v")
        #expect(sample("clarinet").syllables.suffix(2).map(\.text.value) == ["net", "te"])
        #expect(sample("gloria").syllables.count == 16)
        let jasmine = sample("jasmine")
        #expect(jasmine.syllables.count == 22 && jasmine.alignments.count == 22)
        #expect(jasmine.music.events.count == 39)
    }

    @Test func exportedMidiKeepsPitchTimingAndMeterForAllSamples() throws {
        for entry in SampleCatalog.entries {
            let song = entry.make(), notes = song.music.events.filter { $0.note != nil }
            let parsed = try MIDIFileImport.parse(SampleMIDI.encode(song))
            let melody = try #require(parsed.candidates.first)
            #expect(melody.notes.map(\.pitch) == notes.compactMap { $0.note?.pitch })
            #expect(melody.notes.map(\.onTick) == notes.map { Int(($0.onset.doubleValue * 480).rounded()) })
            #expect(melody.notes.map(\.offTick) == notes.map { Int((($0.onset.doubleValue + $0.duration.doubleValue) * 480).rounded()) })
            #expect(parsed.meters.count == song.music.meters.count)
            #expect(parsed.meters.first?.numerator == song.music.meters.first?.numerator)
            #expect(parsed.meters.first?.denominator == song.music.meters.first?.denominator)
        }
    }

    @Test func transcriptionErrorsCannotSilentlyDropNotesOrSyllables() throws {
        let song = SampleSongDocument.make()
        #expect(throws: SongError.self) { try SamplePracticeScore("test", lines: []).attaching(to: song, serial: 1) }
        let lyrics = song.syllables.map(\.text.value).joined(separator: "|")
        for notes in ["C4:1/invalid", "C4:1/0", "C4:0", "C10:1", "C4:1"] {
            #expect(throws: SongError.self) {
                try SamplePracticeScore("test", lines: [.init(lyrics, notes)]).attaching(to: song, serial: 1)
            }
        }
        #expect(throws: SongError.self) {
            try SamplePracticeScore("test", lines: [.init(lyrics, "C4:1", groups: "bad:1")]).attaching(to: song, serial: 1)
        }
    }
}
