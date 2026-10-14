import Foundation
import SongCore
import Testing

struct LyricAlignerTests {
    /// syllable ID → ordered event IDs, for comparing alignments independent of alignment IDs.
    private func map(_ alignments: [Alignment]) -> [UUID: [UUID]] {
        var result: [UUID: [UUID]] = [:]
        for alignment in alignments {
            let events = alignment.musicTargets.compactMap { target -> UUID? in if case .event(let id, _) = target { id } else { nil } }
            for target in alignment.languageTargets where target.kind == .syllable { result[target.id, default: []] += events }
        }
        return result
    }

    private func realign(_ song: SongDocument) throws -> (SongDocument, LyricAlignmentProposal) {
        var copy = song
        copy.alignments = []
        let proposal = try LyricAligner.propose(song: copy, partID: copy.music.parts[0].id)
        LyricAligner.apply(proposal, to: &copy)
        try copy.validate()
        return (copy, proposal)
    }

    private func song(_ words: [[String]], notes: [(Int, Double)], tie: Set<Int> = []) throws -> SongDocument {
        var song = SongDocument()
        song.appendPhrase(text: words.map { $0.joined() }.joined(separator: " "))
        for (index, word) in song.words.enumerated() { try song.setSyllables(wordID: word.id, texts: words[index]) }
        var cursor = 0.0
        let group = UUID()
        for (index, (pitch, duration)) in notes.enumerated() {
            var note = Note(pitch: pitch)
            if tie.contains(index) { note.notation = .init(tieGroupID: group) }
            song.music.events.append(.init(onset: try Beat.grid(cursor), duration: try Beat.grid(duration), content: .note(note)))
            cursor += duration
        }
        song.ensureParts()
        return song
    }

    @Test func oneNoteOneSyllableSamplesAreReproducedExactly() throws {
        for id in ["twinkle", "mary", "frere"] {
            let original = SampleCatalog.entries.first { $0.id == id }!.make()
            let (aligned, proposal) = try realign(original)
            #expect(map(aligned.alignments) == map(original.alignments), "\(id)")
            #expect(proposal.melismaCount == 0 && proposal.elisionCount == 0)
            #expect(proposal.issues.isEmpty)
        }
    }

    @Test func extraNotesBecomeMelismasAndAnAnchorSettlesTheAmbiguity() throws {
        let original = SampleSongDocument.make() // Morning light: 6 syllables on 8 notes
        let (_, proposal) = try realign(original)
        #expect(proposal.melismaCount == 2)
        #expect(proposal.issues.contains { $0.kind == .countMismatch })
        // A person fixes "Morn" on the first two notes; the rest follows the sample.
        var anchored = original
        let morn = original.syllables[0].id
        anchored.alignments = []
        try anchored.align(syllableID: morn, to: [original.music.events[0].id, original.music.events[1].id])
        let second = try LyricAligner.propose(song: anchored, partID: anchored.music.parts[0].id)
        LyricAligner.apply(second, to: &anchored)
        #expect(second.anchorCount == 1)
        #expect(map(anchored.alignments) == map(original.alignments))
        #expect(anchored.alignments.contains { $0.userEdited && $0.languageTargets == [.init(.syllable, morn)] })
    }

    @Test func threeRuleSyllablesOnTwoNotesElideInsideTheWord() throws {
        var twinkle = TwinkleSample.make()
        let diamond = twinkle.words.first { $0.surface == "diamond" }!
        try twinkle.setSyllables(wordID: diamond.id, texts: ["di", "a", "mond"])
        let (aligned, proposal) = try realign(twinkle)
        #expect(proposal.elisionCount == 1)
        let elision = try #require(aligned.alignments.first { $0.relation == .elision })
        let texts = elision.languageTargets.compactMap { aligned.syllable($0.id)?.text.value }
        #expect(texts == ["di", "a"])
        #expect(proposal.melismaCount == 0)
    }

    @Test func tiedNotesCountAsOneSungNote() throws {
        let song = try song([["Ah"], ["men"]], notes: [(60, 2), (60, 2), (62, 4)], tie: [0, 1])
        let (aligned, proposal) = try realign(song)
        #expect(proposal.sungNoteCount == 2 && proposal.melismaCount == 0)
        let ah = aligned.alignments.first { $0.languageTargets.first?.id == aligned.syllables[0].id }!
        #expect(ah.relation == .tie && ah.musicTargets.count == 2)
    }

    @Test func runningEighthsCarryTheMelismaNotTheNextWord() throws {
        // "Glo-ri-a Deo": Glo sings a run of four eighths.
        let song = try song([["Glo", "ri", "a"], ["De", "o"]],
                            notes: [(67, 0.5), (69, 0.5), (71, 0.5), (72, 0.5), (74, 1), (72, 1), (71, 2), (67, 2)])
        let (aligned, _) = try realign(song)
        let glo = map(aligned.alignments)[aligned.syllables[0].id]!
        #expect(glo == Array(aligned.music.events.prefix(4).map(\.id)))
    }

    @Test func restsSeparateLinesAndBreathsDoNotSplitWords() throws {
        var song = try song([["Freu", "de"], ["schö", "ner"]], notes: [(64, 1), (64, 1), (65, 1), (67, 1)])
        // Insert a rest between the two words.
        let second = song.music.events[2].onset
        for index in 2..<4 { song.music.events[index].onset = try song.music.events[index].onset.adding(Beat(1)) }
        song.music.events.append(.init(onset: second, duration: try Beat(1), content: .rest, partID: song.music.parts[0].id))
        let (aligned, proposal) = try realign(song)
        #expect(proposal.issues.isEmpty)
        #expect(map(aligned.alignments)[aligned.syllables[2].id] == [song.music.events[2].id])
    }

    @Test func aligningOnePartLeavesTheOtherPartAlone() throws {
        var song = TwinkleSample.make()
        let soprano = song.music.parts[0].id
        let alto = Part(name: "Alto", abbreviation: "A")
        song.music.parts.append(alto)
        let altoEvents = song.music.events.map { event -> MusicalEvent in
            var copy = event; copy.id = UUID(); copy.partID = alto.id
            if case .note(var note) = copy.content { note.pitch -= 5; copy.content = .note(note) }
            return copy
        }
        song.music.events += altoEvents
        let before = song.alignments
        let proposal = try LyricAligner.propose(song: song, partID: alto.id)
        LyricAligner.apply(proposal, to: &song)
        try song.validate()
        #expect(song.alignments.filter { before.contains($0) }.count == before.count)
        #expect(proposal.alignments.count == 42)
        #expect(song.music.events(in: soprano).count == 42)
        // Manual alignment in the alto does not remove the soprano's alignment of the same syllable.
        let first = song.syllables[0].id
        try song.align(syllableID: first, to: [altoEvents[1].id])
        #expect(song.alignments.contains { $0.languageTargets.contains(.init(.syllable, first)) && !$0.userEdited })
    }

    @Test func partLyricOrderAllowsRepeats() throws {
        var song = SampleCatalog.entries[2].make() // Frère Jacques, 4 lines
        let lines = song.phrases.map(\.id)
        song.music.parts[0].phraseIDs = [lines[0], lines[0], lines[1], lines[2]]
        let proposal = try LyricAligner.propose(song: song, partID: song.music.parts[0].id)
        #expect(proposal.syllableCount == 8 + 8 + 6 + 12)
        LyricAligner.apply(proposal, to: &song)
        try song.validate()
    }
}
