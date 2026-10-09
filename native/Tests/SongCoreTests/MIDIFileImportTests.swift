import Foundation
import SongCore
import Testing

struct MIDIFileImportTests {
    private func vlq(_ value: Int) -> [UInt8] {
        var remaining = value, result = [UInt8(remaining & 0x7F)]
        remaining >>= 7
        while remaining > 0 { result.insert(UInt8(remaining & 0x7F) | 0x80, at: 0); remaining >>= 7 }
        return result
    }
    private func be(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) } }
    private func file(format: Int = 1, division: Int = 480, tracks: [[UInt8]]) -> Data {
        var bytes = Array("MThd".utf8) + be(6, 4) + be(format, 2) + be(tracks.count, 2) + be(division, 2)
        for track in tracks { bytes += Array("MTrk".utf8) + be(track.count, 4) + track }
        return Data(bytes)
    }

    @Test func runningStatusVelocityZeroTempoAndMeter() throws {
        // Conductor track: 3/4, 120 BPM then 60 BPM at beat 3. Melody: running status note-ons, velocity 0 offs.
        let conductor: [UInt8] = [0, 0xFF, 0x58, 4, 3, 2, 24, 8] + [0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20]
            + vlq(1440) + [0xFF, 0x51, 3, 0x0F, 0x42, 0x40] + [0, 0xFF, 0x2F, 0]
        let melody: [UInt8] = [0, 0xFF, 0x03, 7] + Array("Soprano".utf8)
            + [0, 0x90, 60, 90] + vlq(480) + [60, 0] + [0, 62, 90] + vlq(960) + [62, 0] + [0, 64, 80] + vlq(240) + [0x80, 64, 0]
            + [0, 0xFF, 0x2F, 0]
        let parsed = try MIDIFileImport.parse(file(tracks: [conductor, melody]))
        #expect(parsed.candidates.count == 1)
        #expect(parsed.candidates[0].name == "Soprano")
        #expect(parsed.candidates[0].notes.map(\.pitch) == [60, 62, 64])
        #expect(parsed.tempos.map(\.bpm) == [120, 60])
        #expect(parsed.meters.first?.numerator == 3)
        var song = SongDocument()
        let parts = try parsed.apply(to: &song, candidateIDs: [0], replace: true, grid: nil)
        try song.validate()
        #expect(song.music.parts.map(\.name) == ["Soprano"] && parts.count == 1)
        #expect(song.music.meters == [.init(numerator: 3, denominator: 4)])
        let three = try Beat(3)
        #expect(song.music.tempos.count == 2 && song.music.tempos[1].onset == three)
        let durations = [try Beat(1), try Beat(2), try Beat(1, 2)]
        #expect(song.music.events.map(\.duration) == durations)
        #expect(song.music.measures.count == 2)
    }

    @Test func overlappingSamePitchPairsFirstInFirstOutAndChannelsSplit() throws {
        let track: [UInt8] = [0, 0x90, 60, 100, 0, 0x91, 48, 100] + vlq(240) + [0x90, 60, 100] + vlq(240) + [0x80, 60, 0]
            + vlq(240) + [0x80, 60, 0] + [0, 0x81, 48, 0] + [0, 0xFF, 0x2F, 0]
        let parsed = try MIDIFileImport.parse(file(format: 0, tracks: [track]))
        #expect(parsed.candidates.count == 2)
        let upper = try #require(parsed.candidates.first { $0.channel == 0 })
        #expect(upper.notes.map { [$0.onTick, $0.offTick] } == [[0, 480], [240, 720]])
        #expect(upper.isPolyphonic)
        #expect(parsed.candidates.first { $0.channel == 1 }?.notes.count == 1)
    }

    @Test func unsupportedAndBrokenFilesAreRejectedWithReasons() throws {
        #expect(throws: SongError.self) { try MIDIFileImport.parse(Data("RIFF....".utf8)) }
        #expect(throws: SongError.self) { try MIDIFileImport.parse(file(format: 2, tracks: [[0, 0xFF, 0x2F, 0]])) }
        #expect(throws: SongError.self) { try MIDIFileImport.parse(file(division: 0xE728, tracks: [[0, 0xFF, 0x2F, 0]])) }
        var truncated = [UInt8](file(tracks: [[0, 0x90, 60, 100, 0x83, 0x60, 0x80, 60, 0, 0, 0xFF, 0x2F, 0]]))
        truncated.removeLast(5)
        #expect(throws: SongError.self) { try MIDIFileImport.parse(Data(truncated)) }
        #expect(throws: SongError.self) { try MIDIFileImport.parse(file(tracks: [[0, 60, 100]])) } // data before any status
        let dangling = try MIDIFileImport.parse(file(tracks: [[0, 0x90, 60, 100, 0, 0xFF, 0x2F, 0]]))
        #expect(dangling.candidates.isEmpty && dangling.diagnostics.count == 2)
    }

    @Test func exportedSampleRoundTripsAndQuantizingIsExplicit() throws {
        let twinkle = TwinkleSample.make()
        let parsed = try MIDIFileImport.parse(SampleMIDI.encode(twinkle))
        var song = SongDocument()
        _ = try parsed.apply(to: &song, candidateIDs: parsed.candidates.map(\.id), replace: true, grid: nil)
        try song.validate()
        #expect(song.music.events.map { $0.note?.pitch } == twinkle.music.events.map { $0.note?.pitch })
        #expect(song.music.events.map(\.onset) == twinkle.music.events.map(\.onset))
        #expect(song.music.tempos.first?.bpm == twinkle.music.tempos.first?.bpm)

        // A played (unquantized) note stays exact unless a grid is chosen.
        let played: [UInt8] = [0, 0x90, 60, 90] + vlq(470) + [0x80, 60, 0] + vlq(12) + [0x90, 62, 90] + vlq(475) + [0x80, 62, 0] + [0, 0xFF, 0x2F, 0]
        let loose = try MIDIFileImport.parse(file(tracks: [played]))
        var exact = SongDocument(), snapped = SongDocument()
        _ = try loose.apply(to: &exact, candidateIDs: [0], replace: true, grid: nil)
        _ = try loose.apply(to: &snapped, candidateIDs: [0], replace: true, grid: Beat(1, 4))
        let played482 = try Beat(482, 480)
        #expect(exact.music.events[1].onset == played482)
        let one = try Beat(1)
        #expect(snapped.music.events.map(\.onset) == [.zero, one])
        #expect(snapped.music.events.map(\.duration) == [one, one])
    }

    @Test func addingAsPartsKeepsExistingMusicAndAlignments() throws {
        var song = TwinkleSample.make()
        let alignments = song.alignments
        let melody: [UInt8] = [0, 0xFF, 0x03, 4] + Array("Alto".utf8) + [0, 0x90, 55, 80] + vlq(1920) + [0x80, 55, 0, 0, 0xFF, 0x2F, 0]
        let parsed = try MIDIFileImport.parse(file(tracks: [melody]))
        _ = try parsed.apply(to: &song, candidateIDs: [0], replace: false, grid: nil)
        try song.validate()
        #expect(song.music.parts.map(\.name) == ["旋律", "Alto"])
        #expect(song.alignments == alignments)
        #expect(song.music.events.count == 43)
    }
}
