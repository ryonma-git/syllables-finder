import Testing
import SongCore
import Foundation

struct MusicTimelineTests {
    private func beat(_ n: Int64) throws -> Beat { try Beat(n) }

    @Test func twinklePlanCoversSongOnce() throws {
        let song = TwinkleSample.make()
        let projection = MeasureProjection(song: song)
        #expect(projection.slices.count == 12)
        #expect(projection.detailWindows.count == 6)
        let plan = try PlaybackPlan(song: song, range: .init(start: .zero, end: try beat(48)), practiceBPM: 96)
        #expect(plan.notes.count == 42)
        #expect(abs(plan.duration - 30) < 0.000_001)
        #expect(abs(plan.beat(at: 30) - 48) < 0.000_001)
        let selected = try PlaybackPlan(song: song, range: .init(start: beat(8), end: beat(16)), practiceBPM: 96)
        #expect(abs(selected.duration - 5) < 0.000_001)
        #expect(selected.notes.count == 7)
    }

    @Test func tempoAndInversePreserveChanges() throws {
        let map = try TempoMap(tempos: [.init(bpm: 120), .init(onset: beat(4), bpm: 60)])
        #expect(abs(map.seconds(at: 8) - 6) < 0.000_001)
        #expect(abs(map.beat(at: 3) - 5) < 0.000_001)
        let slow = try TempoMap(tempos: [.init(bpm: 120), .init(onset: beat(4), bpm: 60)], multiplier: 0.5)
        #expect(abs(slow.seconds(at: 8) - 12) < 0.000_001)
    }

    @Test func pickupAndOverlapAreRepresented() throws {
        var song = SongDocument()
        song.music.measures = [
            .init(number: "0", range: .init(start: .zero, end: try beat(1))),
            .init(number: "1", range: .init(start: try beat(1), end: try beat(5)))
        ]
        let projection = MeasureProjection(song: song)
        #expect(projection.slices.map(\.range.length) == [1, 4])
        #expect(projection.warning == nil)
        song.music.measures[1].range.start = .zero
        #expect(MeasureProjection(song: song).warning != nil)
    }

    @Test func eventCrossingRangeIsClippedOnce() throws {
        var song = SongDocument()
        song.music.events = [.init(onset: try beat(4), duration: try beat(2), content: .note(.init(pitch: 60)))]
        let first = try PlaybackPlan(song: song, range: .init(start: .zero, end: beat(5)), practiceBPM: 60)
        let second = try PlaybackPlan(song: song, range: .init(start: beat(5), end: beat(7)), practiceBPM: 60)
        #expect(first.notes.count == 1 && abs(first.notes[0].end - 5) < 0.000_001)
        #expect(second.notes.count == 1 && abs(second.notes[0].start) < 0.000_001 && abs(second.notes[0].end - 1) < 0.000_001)
    }

    @Test func guidePCMHasExpectedLengthAndSoundAcrossPhraseBoundary() throws {
        let song = TwinkleSample.make()
        let plan = try PlaybackPlan(song: song, range: .init(start: .zero, end: beat(48)), practiceBPM: 96)
        let samples = try GuidePCMRenderer.render(plan)
        #expect(samples.count == 1_323_000)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
        let boundary = Int(5 * GuidePCMRenderer.sampleRate)
        #expect(samples[(boundary - 2_000)..<boundary].contains { abs($0) > 0.01 })
        #expect(samples[boundary..<(boundary + 2_000)].contains { abs($0) > 0.01 })
    }

    @Test func sampleReadingsAndNotationSurviveRoundTrip() throws {
        let song = TwinkleSample.make()
        #expect(song.syllables.count == 42)
        #expect(song.syllables.allSatisfy { !$0.reading.value.isEmpty && !$0.ipa.value.isEmpty && $0.reading.source.kind == .sample })
        let decoded = try SongDocument.decode(song.encoded())
        #expect(decoded.syllables.map(\.reading) == song.syllables.map(\.reading))
        let score = NotationProjection(song: song, measures: Array(MeasureProjection(song: song).slices.prefix(2)))
        #expect(score.issue == nil)
        #expect(score.pieces.filter { $0.pitch != nil }.count == 7)
        #expect(score.pieces.first?.step == -2) // C4, below the treble staff.
        #expect(score.pieces.last?.duration == 2)
    }

    @Test func tiedEventsBecomeOneSustainedGuideNote() throws {
        var song = SongDocument()
        let tie = UUID()
        var first = Note(pitch: 60)
        var second = Note(pitch: 60)
        first.notation = .init(tieGroupID: tie)
        second.notation = .init(tieGroupID: tie)
        song.music.events = [
            .init(onset: .zero, duration: try beat(1), content: .note(first)),
            .init(onset: try beat(1), duration: try beat(1), content: .note(second))
        ]
        let plan = try PlaybackPlan(song: song, range: .init(start: .zero, end: beat(2)), practiceBPM: 60)
        #expect(plan.notes.count == 1)
        #expect(abs(plan.notes[0].end - 2) < 0.000_001)
        song.music.events[1].onset = try beat(3)
        let separate = try PlaybackPlan(song: song, range: .init(start: .zero, end: beat(4)), practiceBPM: 60)
        #expect(separate.notes.count == 2 && !separate.diagnostics.isEmpty)
    }

    @Test func scoreShowsNaturalAndRejectsUnrepresentableDuration() throws {
        var song = SongDocument()
        song.music.measures = [.init(number: "1", range: .init(start: .zero, end: try beat(4)))]
        var sharp = Note(pitch: 61)
        sharp.notation = .init(spelling: "C#4")
        var natural = Note(pitch: 60)
        natural.notation = .init(spelling: "C4")
        song.music.events = [
            .init(onset: .zero, duration: try beat(1), content: .note(sharp)),
            .init(onset: try beat(1), duration: try beat(1), content: .note(natural))
        ]
        let measures = MeasureProjection(song: song).slices
        let score = NotationProjection(song: song, measures: measures)
        #expect(score.issue == nil)
        #expect(score.pieces.filter { $0.pitch != nil }.map(\.accidental) == ["♯", "♮"])
        song.music.events[1].duration = try Beat(1, 3)
        #expect(NotationProjection(song: song, measures: measures).issue != nil)
    }

    @Test func inferredMeasuresSplitAtMeterChange() throws {
        var song = SongDocument()
        song.music.meters = [.init(numerator: 3, denominator: 4), .init(onset: try beat(3), numerator: 6, denominator: 8)]
        song.music.events = [.init(onset: try beat(3), duration: try beat(3), content: .note(.init(pitch: 60)))]
        let projection = MeasureProjection(song: song)
        #expect(projection.slices.count == 2)
        #expect(projection.slices.map(\.range.length) == [3, 3])
        let inferred = projection.slices.allSatisfy { $0.inferred }
        #expect(inferred)
        #expect(projection.slices.map(\.id) == MeasureProjection(song: song).slices.map(\.id))
    }
}
