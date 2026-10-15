import Foundation
import SongCore
import Testing

struct SwingTests {
    @Test func eighthAndSixteenthTimingRoundTripWithoutRounding() throws {
        for unit in SwingSettings.Subdivision.allCases {
            let map = SwingTiming(.init(subdivision: unit))
            for numerator in 0...96 {
                let written = try Beat(Int64(numerator), 24)
                #expect(try map.writtenBeat(map.performedBeat(written)) == written)
                #expect(abs(map.writtenBeat(map.performedBeat(written.doubleValue)) - written.doubleValue) < 1e-12)
            }
        }
        let eighth = SwingTiming(.init(subdivision: .eighth))
        #expect(try eighth.performedBeat(Beat(1, 2)) == Beat(2, 3))
        let sixteenth = SwingTiming(.init())
        #expect(try sixteenth.performedBeat(Beat(1, 4)) == Beat(1, 3))
        #expect(try sixteenth.performedBeat(Beat(1, 2)) == Beat(1, 2))
        #expect(try sixteenth.performedBeat(Beat(3, 4)) == Beat(5, 6))
    }

    @Test func straightPassagesAndDisabledSwingAreIdentity() throws {
        var settings = try SwingSettings(ranges: [.init(start: Beat(4), end: Beat(8))])
        try settings.validate()
        let map = SwingTiming(settings)
        #expect(try map.performedBeat(Beat(1, 4)) == Beat(1, 4))
        #expect(try map.performedBeat(Beat(17, 4)) == Beat(13, 3))
        #expect(try map.performedBeat(Beat(33, 4)) == Beat(33, 4))
        for boundary in [4.0, 8.0] { #expect(map.performedBeat(boundary) == boundary) }
        settings.enabled = false
        #expect(try SwingTiming(settings).performedBeat(Beat(17, 4)) == Beat(17, 4))
        settings.enabled = true; settings.longFraction = try Beat(1, 2)
        #expect(try SwingTiming(settings).performedBeat(Beat(17, 4)) == Beat(17, 4))
    }

    private func performedSong() throws -> SongDocument {
        var song = SongDocument()
        _ = song.appendPhrase(text: "la la", language: "en", syllabify: true)
        let part = Part(name: "旋律")
        song.music.parts = [part]
        let measure = Measure(number: "1", range: try .init(start: .zero, end: Beat(1)))
        song.music.measures = [measure]
        song.music.tempos = [.init(bpm: 60)]
        song.music.events = [
            .init(onset: .zero, duration: try Beat(1, 3), measureID: measure.id, content: .note(.init(pitch: 60)), partID: part.id),
            .init(onset: try Beat(1, 3), duration: try Beat(1, 6), measureID: measure.id, content: .note(.init(pitch: 62)), partID: part.id),
            .init(onset: try Beat(1, 2), duration: try Beat(1, 2), measureID: measure.id, content: .rest, partID: part.id)
        ]
        song.phrases[0].timeRange = try .init(start: .zero, end: Beat(1, 2))
        song.phrases[0].musicalEventIDs = Array(song.music.events.prefix(2).map(\.id))
        song.music.spans = [.init(kind: .phrase, title: "練習", range: song.phrases[0].timeRange!, eventIDs: song.phrases[0].musicalEventIDs)]
        song.syllables[0].reading.edit("ラー")
        song.alignments = [
            .init(languageTargets: [.init(.syllable, song.syllables[0].id)],
                  musicTargets: [.event(song.music.events[0].id, relativeRange: try .init(start: .zero, end: Beat(1, 6)))],
                  relation: .manual, userEdited: true),
            .init(languageTargets: [.init(.syllable, song.syllables[1].id)], musicTargets: [.event(song.music.events[1].id)], relation: .syllabic),
            .init(languageTargets: [.init(.word, song.words[0].id)], musicTargets: [.timeRange(try .init(start: .zero, end: Beat(1, 3)))], relation: .manual)
        ]
        try song.validate()
        return song
    }

    @Test func conversionPreservesSoundLinksAndManualLyricsAndCreatesSimpleScore() throws {
        let original = try performedSong()
        let converted = try SwingConversion.normalizingPerformedTiming(in: original, settings: .init())
        #expect(try converted.music.events[0].duration == Beat(1, 4))
        #expect(try converted.music.events[1].onset == Beat(1, 4))
        #expect(try converted.music.events[1].duration == Beat(1, 4))
        #expect(converted.music.events.map(\.id) == original.music.events.map(\.id))
        #expect(converted.music.events.map(\.content) == original.music.events.map(\.content))
        #expect(converted.words == original.words && converted.syllables == original.syllables)
        #expect(converted.alignments.map(\.id) == original.alignments.map(\.id))
        #expect(converted.alignments[0].userEdited)
        #expect(try converted.alignments[0].musicTargets == [.event(original.music.events[0].id, relativeRange: .init(start: .zero, end: Beat(1, 8)))])
        #expect(try converted.alignments[2].musicTargets == [.timeRange(.init(start: .zero, end: Beat(1, 4)))])
        let measures = MeasureProjection(song: converted)
        let score = NotationProjection(song: converted, measures: measures.slices)
        #expect(score.issue == nil && score.notice == nil)
        #expect(score.pieces.allSatisfy { !$0.approximateRhythm })
        let range = try BeatRange(start: .zero, end: Beat(1))
        let oldPlan = try PlaybackPlan(song: original, range: range, practiceBPM: 60)
        let swung = try PlaybackPlan(song: converted, range: range, practiceBPM: 60)
        for (old, new) in zip(oldPlan.notes, swung.notes) {
            #expect(old.pitch == new.pitch && abs(old.start - new.start) < 1e-12 && abs(old.end - new.end) < 1e-12)
        }
        var disabled = converted
        disabled.music.swing?.enabled = false
        let straight = try PlaybackPlan(song: disabled, range: range, practiceBPM: 60)
        #expect(straight.notes[0].end == 0.25 && straight.notes[1].start == 0.25)
        #expect(disabled.music.events == converted.music.events)
        #expect(throws: SongError.self) { try SwingConversion.normalizingPerformedTiming(in: converted, settings: .init()) }
        #expect(try SongDocument.decode(converted.encoded()) == converted)
    }

    @Test func seekingLoopRangeTempoAndPlayheadUseTheSameTimingMap() throws {
        var song = try SwingConversion.normalizingPerformedTiming(in: performedSong(), settings: .init())
        song.music.tempos = [.init(bpm: 120), .init(onset: try Beat(1, 4), bpm: 60)]
        let range = try BeatRange(start: Beat(1, 8), end: Beat(1, 2))
        let plan = try PlaybackPlan(song: song, range: range, practiceBPM: 120)
        #expect(abs(plan.duration - 0.25) < 1e-12)
        #expect(plan.notes[0].start == 0)
        #expect(abs(plan.notes[1].start - 1.0 / 12) < 1e-12)
        for written in [0.125, 0.25, 0.375, 0.5] {
            #expect(abs(plan.beat(at: plan.elapsed(atWrittenBeat: written)) - written) < 1e-12)
        }
        let slow = try PlaybackPlan(song: song, range: range, practiceBPM: 60)
        #expect(abs(slow.duration - plan.duration * 2) < 1e-12)
    }

    @Test func midiExportReflectsSwingWithoutChangingTheSourceNotes() throws {
        var song = try SwingConversion.normalizingPerformedTiming(in: performedSong(), settings: .init())
        let originalEvents = song.music.events
        for enabled in [true, false] {
            song.music.swing?.enabled = enabled
            let parsed = try MIDIFileImport.parse(SampleMIDI.encode(song))
            var imported = SongDocument()
            _ = try parsed.apply(to: &imported, candidateIDs: parsed.candidates.map(\.id), replace: true, grid: nil)
            #expect(try imported.music.events[1].onset == (enabled ? Beat(1, 3) : Beat(1, 4)))
            #expect(imported.music.events.compactMap { $0.note?.pitch } == [60, 62])
            #expect(song.music.events == originalEvents)
        }
    }

    @Test func invalidRatiosAndDiscontinuousOrOverlappingRangesAreRejected() throws {
        #expect(throws: SongError.self) { try SwingSettings(longFraction: Beat(1, 3)).validate() }
        #expect(throws: SongError.self) { try SwingSettings(longFraction: Beat(4, 5)).validate() }
        #expect(throws: SongError.self) { try SwingSettings(ranges: [.init(start: Beat(1, 4), end: Beat(1))]).validate() }
        #expect(throws: SongError.self) {
            try SwingSettings(ranges: [.init(start: Beat(0), end: Beat(2)), .init(start: Beat(1), end: Beat(3))]).validate()
        }
    }

    @Test func versionTwoKeepsPerformedTimingAndOriginalBytesUntilExplicitConversion() throws {
        let song = try performedSong()
        var object = try #require(JSONSerialization.jsonObject(with: song.encoded()) as? [String: Any])
        object["schemaVersion"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)
        let package = try DocumentPackage(reading: FileWrapper(directoryWithFileWrappers: ["document.json": FileWrapper(regularFileWithContents: data)]))
        #expect(package.song.schemaVersion == 3 && package.song.music.swing == nil)
        #expect(package.song.music.events == song.music.events)
        #expect(package.attachmentPaths == ["preserved/document-v2.json"])
        let backup = try package.fileWrapper().fileWrappers?["preserved"]?.fileWrappers?["document-v2.json"]?.regularFileContents
        #expect(backup == data)
    }
}
