import Foundation
import Testing
@testable import SongCore

struct SongCoreTests {
    @Test func testSampleRoundTripAndDeterministicIDs() throws {
        let doc = SampleSongDocument.make()
        try doc.validate()
        #expect(try SongDocument.decode(doc.encoded()) == doc)
        #expect(doc == SampleSongDocument.make())
        #expect(doc.syllables.first?.text.value == "Morn")
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
