import Foundation
import Testing
@testable import SongCore

struct SongCoreTests {
    @Test func sampleCatalogSongsHaveCompleteSyllableNoteAlignment() throws {
        #expect(SampleCatalog.entries.map(\.id) == ["twinkle", "mary", "frere", "ninth", "morning",
                                                   "entchen", "pollitos", "martino", "adeste", "birch",
                                                   "sakura", "arirang", "jasmine"])
        #expect(Set(SampleCatalog.entries.map(\.languageCode)) == Set(Syllabifier.languages.map(\.id)))
        for entry in SampleCatalog.entries {
            let song = entry.make()
            try song.validate()
            #expect(song == entry.make())
            #expect(!song.phrases.isEmpty)
            #expect(song.metadata.sourceLanguage == entry.languageCode)
            if entry.id != "morning" {
                #expect(song.syllables.allSatisfy { !$0.reading.value.isEmpty && !$0.ipa.value.isEmpty })
            }
            if !song.music.events.isEmpty && entry.id != "morning" {
                #expect(song.syllables.count == song.music.events.compactMap(\.note).count)
                #expect(song.syllables.allSatisfy { syllable in
                    song.alignments.contains { $0.languageTargets.contains(.init(.syllable, syllable.id)) }
                })
            }
        }
    }

    @Test func traditionalSamplesAreAnnotatedWithoutInventedMusic() throws {
        for entry in TraditionalSamples.entries {
            let song = entry.make()
            #expect(song.music.events.isEmpty && song.alignments.isEmpty)
            #expect(song.words.allSatisfy { !$0.contextualMeaning.value.isEmpty })
            #expect(song.phrases.allSatisfy { !$0.translation.value.isEmpty })
            #expect(song.phrases.allSatisfy { !$0.originalText.isEmpty })
            #expect(try SongDocument.decode(song.encoded()) == song)
        }
    }

    @Test func ninthSampleHasFourAnnotatedLinesWithoutInventedNotes() throws {
        let song = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        try song.validate()
        #expect(song.phrases.count == 4)
        #expect(song.music.events.isEmpty)
        #expect(song.alignments.isEmpty)
        #expect(song.phrases[0].originalText == "Freude, schöner Götterfunken, Tochter aus Elysium!")
        #expect(song.words.count == 30)
        #expect(song.words.allSatisfy { !$0.contextualMeaning.value.isEmpty })
        #expect(song.syllables.allSatisfy { !$0.ipa.value.isEmpty && !$0.reading.value.isEmpty })
        #expect(try SongDocument.decode(song.encoded()) == song)
    }

    @Test func maryEndsWithTheExpectedPickupAndFourBeatTonic() throws {
        let song = try #require(SampleCatalog.entries.first { $0.id == "mary" }).make()
        let notes = song.music.events
        #expect(notes.count == 26)
        #expect(notes.map { $0.note?.pitch } == [
            64, 62, 60, 62, 64, 64, 64,
            62, 62, 62, 64, 67, 67,
            64, 62, 60, 62, 64, 64, 64,
            64, 62, 62, 64, 62, 60
        ])
        let b1 = try Beat(1), b4 = try Beat(4), b22 = try Beat(22)
        let b23 = try Beat(23), b28 = try Beat(28), b32 = try Beat(32)
        #expect(song.phrases[2].timeRange?.end == b23)
        #expect(song.phrases[3].timeRange?.start == b23)
        #expect(notes[19].onset == b22 && notes[19].duration == b1) // lamb
        #expect(notes[20].onset == b23 && notes[20].duration == b1) // Its
        #expect(notes[25].onset == b28 && notes[25].duration == b4) // snow
        #expect(MeasureProjection.songEnd(song) == b32)
    }
    @Test func testSampleRoundTripAndDeterministicIDs() throws {
        let doc = SampleSongDocument.make()
        try doc.validate()
        #expect(try SongDocument.decode(doc.encoded()) == doc)
        #expect(doc == SampleSongDocument.make())
        #expect(doc.syllables.first?.text.value == "Morn")
    }

    @Test func testTwinkleSampleHasOneNoteForEverySungSyllable() throws {
        let doc = TwinkleSample.make()
        try doc.validate()
        #expect(doc == TwinkleSample.make())
        #expect(try SongDocument.decode(doc.encoded()) == doc)
        #expect(doc.phrases.count == 6)
        #expect(doc.syllables.count == 42)
        #expect(doc.music.events.count == 42)
        #expect(doc.music.measures.count == 12)
        #expect(doc.music.events.prefix(4).allSatisfy { $0.measureID == doc.music.measures[0].id })
        #expect(doc.music.events.dropFirst(4).prefix(3).allSatisfy { $0.measureID == doc.music.measures[1].id })
        #expect(doc.alignments.count == 42)
        #expect(doc.phrases[0].originalText == "Twinkle, twinkle, little star,")
        #expect(doc.music.events.prefix(7).compactMap { $0.note?.pitch } == [60, 60, 67, 67, 69, 69, 67])
        for alignment in doc.alignments {
            #expect(alignment.languageTargets.count == 1)
            #expect(alignment.musicTargets.count == 1)
            #expect(doc.ranges(for: alignment.languageTargets[0]).count == 1)
        }
        let midi = try SampleMIDI.encode(doc)
        #expect(Array(midi.prefix(4)) == Array("MThd".utf8))
        #expect(Array(midi.dropFirst(14).prefix(4)) == Array("MTrk".utf8))
        #expect(midi.count > 300)
    }

    @Test func testFutureSchemaRejectedBeforeBodyDecode() {
        #expect(throws: SongError.unsupportedVersion(999)) { try SongDocument.decode(Data("{\"schemaVersion\":999}".utf8)) }
    }

    @Test func testDirectAndMoraAndMixedPhonemes() throws {
        try SampleSongDocument.make().validate()
        var doc = SampleSongDocument.japanese()
        try doc.validate()
        let phoneme = Phoneme(parentSyllableID: doc.syllables[0].id, symbol: "ʔ")
        doc.syllables[0].phonemeIDs.insert(phoneme.id, at: 0); doc.phonemes.append(phoneme)
        try doc.validate()
        #expect(try SongDocument.decode(doc.encoded()) == doc)
        doc.phonemes[0].parentMoraID = doc.moras[1].id
        #expect(throws: (any Error).self) { try doc.validate() }
    }

    @Test func testBrokenHierarchyAndDuplicateIDsRejected() {
        var doc = SampleSongDocument.make()
        doc.words[0].syllableIDs.append(UUID())
        #expect(throws: (any Error).self) { try doc.validate() }
        doc = SampleSongDocument.make()
        doc.words[1].id = doc.words[0].id
        #expect(throws: (any Error).self) { try doc.validate() }
        doc = SampleSongDocument.make()
        doc.syllables[0].parentWordID = doc.words[1].id
        #expect(throws: (any Error).self) { try doc.validate() }
    }

    @Test func testManyToManyAndMelismaAndPhonemeSubrange() throws {
        var doc = SampleSongDocument.make()
        #expect(doc.alignments[0].relation == .melisma)
        #expect(doc.ranges(for: .init(.syllable, doc.syllables[0].id)).count == 2)
        doc.alignments[0].languageTargets.append(.init(.syllable, doc.syllables[1].id))
        doc.alignments.append(.init(languageTargets: [.init(.phoneme, doc.phonemes[0].id)],
                                   musicTargets: [.event(doc.music.events[0].id, relativeRange: .init(start: .zero, end: try Beat(1, 4)))], relation: .manual))
        try doc.validate()
        #expect(try SongDocument.decode(doc.encoded()) == doc)
        doc.alignments[0].relation = .oneToOne
        #expect(throws: (any Error).self) { try doc.validate() }
    }

    @Test func testInvalidEventAndSubrangeRejected() throws {
        var doc = SampleSongDocument.make()
        doc.music.events[0].content = .note(.init(pitch: 128))
        #expect(throws: (any Error).self) { try doc.validate() }
        doc = SampleSongDocument.make()
        doc.alignments[0].musicTargets = [.event(doc.music.events[0].id, relativeRange: .init(start: .zero, end: try Beat(2)))]
        #expect(throws: (any Error).self) { try doc.validate() }
        doc.music.tempos[0].bpm = .nan
        #expect(throws: (any Error).self) { try doc.validate() }
    }

    @Test func testRationalTripletsAndDecodeValidation() throws {
        let a = try Beat(160, 480)
        let oneThird = try Beat(1, 3)
        let oneHalf = try Beat(1, 2)
        let one = try Beat(1)
        #expect(a == oneThird)
        #expect(try a.adding(a).adding(a) == one)
        #expect(oneThird < oneHalf)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Beat.self, from: Data("{\"numerator\":1,\"denominator\":0}".utf8)) }
        #expect(throws: (any Error).self) { try Beat.grid(.nan) }
        #expect(throws: (any Error).self) { try Beat(1_000_000_000).adding(Beat(1)) }
    }

    @Test func testInvalidTransactionLeavesOriginalUntouched() throws {
        let doc = SampleSongDocument.make()
        #expect(throws: (any Error).self) { try doc.editing {
            try $0.updateNote(id: doc.music.events[0].id, pitch: 999, onset: .zero, duration: Beat(1), velocity: 80)
        } }
        #expect(doc.music.events[0].note?.pitch == 60)
        let changed = try doc.editing {
            try $0.updateNote(id: doc.music.events[0].id, pitch: 61, onset: .zero, duration: Beat(1), velocity: 90)
        }
        #expect(changed.revision == 1)
        #expect(changed.music.events[0].note?.pitch == 61)
    }

    @Test func testDeleteRepairsReferencesAndManualAlignmentPreservesOtherTargets() throws {
        var doc = SampleSongDocument.make()
        doc.alignments[0].languageTargets.append(.init(.syllable, doc.syllables[1].id))
        let changed = try doc.editing {
            try $0.align(syllableID: doc.syllables[0].id, to: [doc.music.events[3].id])
        }
        #expect(changed.alignments[0].languageTargets == [.init(.syllable, doc.syllables[1].id)])
        #expect(changed.alignments.last!.userEdited)
        let deleted = try changed.editing { $0.removeNote(id: doc.music.events[3].id) }
        try deleted.validate()
        #expect(deleted.music.events.count == 7)
    }

    @Test func testDocumentPackagePreservesUnknownSourceBytes() throws {
        let source = Data("<score><unknown attr='keep'/></score>".utf8)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "document.json": FileWrapper(regularFileWithContents: try SampleSongDocument.make().encoded()),
            "preserved": FileWrapper(directoryWithFileWrappers: ["source.musicxml": FileWrapper(regularFileWithContents: source)])
        ])
        var package = try DocumentPackage(reading: wrapper)
        package.song.metadata.title = "日本語を保持"
        let output = try package.fileWrapper()
        #expect(output.fileWrappers?["preserved"]?.fileWrappers?["source.musicxml"]?.regularFileContents == source)
        #expect(try DocumentPackage(reading: output).song.metadata.title == "日本語を保持")
    }

    @Test func testPackageRejectsSymlinkAndMissingDocument() throws {
        #expect(throws: (any Error).self) { try DocumentPackage(reading: FileWrapper(directoryWithFileWrappers: [:])) }
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "document.json": FileWrapper(regularFileWithContents: try SongDocument().encoded()),
            "external": FileWrapper(symbolicLinkWithDestinationURL: URL(fileURLWithPath: "/tmp"))
        ])
        #expect(throws: (any Error).self) { try DocumentPackage(reading: wrapper) }
    }

    @Test func testManualTextKeepsPunctuationWithoutGuessingPhonemes() throws {
        let doc = try SongDocument().editing { $0.appendPhrase(text: "Hello,  光！") }
        #expect(doc.phrases[0].originalText == "Hello,  光！")
        #expect(doc.syllables.isEmpty)
        #expect(doc.words.map(\.surface) == ["Hello,", "光！"])
    }
}
