import Foundation
import Testing
@testable import SongCore

struct AlignmentSafetyTests {
    private func songWithTwoParts() throws -> SongDocument {
        var song = SongDocument()
        song.appendPhrase(text: "one two")
        for word in song.words { try song.setSyllables(wordID: word.id, texts: [word.surface]) }
        let first = song.addPart(name: "First"), second = song.addPart(name: "Second")
        try song.enterStep(partID: first, onset: .zero, duration: Beat(1), pitch: 60)
        try song.enterStep(partID: second, onset: .zero, duration: Beat(1), pitch: 48)
        return song
    }

    @Test func clearingOnePartKeepsOtherPartsAndOtherLanguageTargets() throws {
        var song = try songWithTwoParts()
        let firstPart = song.music.parts[0].id, secondPart = song.music.parts[1].id
        let syllable = LanguageTarget(.syllable, song.syllables[0].id)
        let otherSyllable = LanguageTarget(.syllable, song.syllables[1].id)
        song.alignments = [.init(languageTargets: [syllable, otherSyllable],
                                musicTargets: song.music.events.map { .event($0.id) }, relation: .manual, userEdited: true)]
        try song.align(syllableID: syllable.id, to: [], inPart: firstPart)
        try song.validate()
        #expect(song.ranges(for: syllable, inPart: firstPart).isEmpty)
        #expect(song.ranges(for: syllable, inPart: secondPart).count == 1)
        #expect(song.ranges(for: otherSyllable, inPart: firstPart).count == 1)
        #expect(song.ranges(for: otherSyllable, inPart: secondPart).count == 1)
        #expect(song.alignments.allSatisfy { $0.userEdited })
    }

    @Test func ambiguousOrMixedPartEditsAreRejectedWithoutChangingAlignments() throws {
        var song = try songWithTwoParts()
        let syllable = song.syllables[0].id
        for event in song.music.events { try song.align(syllableID: syllable, to: [event.id]) }
        let before = song
        #expect(throws: SongError.self) { try song.align(syllableID: syllable, to: []) }
        #expect(song == before)
        #expect(throws: SongError.self) { try song.align(syllableID: syllable, to: song.music.events.map(\.id)) }
        #expect(song == before)
        let firstPart = song.music.parts[0].id
        let firstEvent = try #require(song.music.events.first { $0.partID == firstPart })
        try song.align(syllableID: syllable, to: [firstEvent.id], inPart: firstPart)
        #expect(song.ranges(for: .init(.syllable, syllable)).count == 2)
        try song.validate()
    }

    @Test func changingSyllableCountRemovesItsPhonemeReferencesOnly() throws {
        var song = try songWithTwoParts()
        let oldSyllable = song.syllables[0].id
        let phoneme = Phoneme(parentSyllableID: oldSyllable, symbol: "w")
        song.phonemes = [phoneme]
        song.syllables[0].phonemeIDs = [phoneme.id]
        let preserved = LanguageTarget(.syllable, song.syllables[1].id)
        song.alignments = [.init(languageTargets: [.init(.phoneme, phoneme.id), preserved],
                                musicTargets: [.event(song.music.events[0].id)], relation: .manual)]
        try song.validate()
        try song.setSyllables(wordID: song.words[0].id, texts: ["o", "ne"])
        try song.validate()
        #expect(song.phonemes.isEmpty)
        #expect(song.alignments.count == 1)
        #expect(song.alignments[0].languageTargets == [preserved])
    }
}

@Suite(.serialized)
struct PackageSafetyTests {
    @Test func cumulativeAttachmentLimitRejectsTheChangeAndRemainingPackageReopens() throws {
        var package = DocumentPackage()
        let chunk = Data(repeating: 1, count: 20_000_000)
        for index in 0..<4 { try package.attach(chunk, at: ["source", "\(index).mid"]) }
        let paths = package.attachmentPaths
        // The JSON and source directory also belong to the package budget.
        #expect(throws: SongError.self) { try package.attach(chunk, at: ["source", "overflow.mid"]) }
        #expect(package.attachmentPaths == paths)
        let saved = try package.fileWrapper()
        let reopened = try DocumentPackage(reading: saved)
        #expect(reopened.attachmentPaths == paths)
        #expect(reopened.song == package.song)
    }

    @Test func savingRechecksThePackageBudgetAfterDocumentGrowth() throws {
        var package = DocumentPackage()
        try package.attach(Data(repeating: 1, count: 99_000_000), at: ["source", "reference.dat"])
        package.song.metadata.notes = String(repeating: "a", count: 2_000_000)
        #expect(try package.song.encoded().count < SongDocument.maximumEncodedBytes)
        #expect(throws: SongError.self) { try package.fileWrapper() }
        package.song.metadata.notes = "短い補足"
        let reopened = try DocumentPackage(reading: package.fileWrapper())
        #expect(reopened.song == package.song)
        #expect(reopened.attachmentPaths == ["source/reference.dat"])
    }

    @Test func attachmentDepthHasTheSameBoundaryWhenWritingAndReading() throws {
        var package = DocumentPackage()
        let acceptedPath = (0..<17).map { "level\($0)" }
        try package.attach(Data([1]), at: acceptedPath)
        #expect(try DocumentPackage(reading: package.fileWrapper()).attachmentPaths == package.attachmentPaths)
        let paths = package.attachmentPaths
        #expect(throws: SongError.self) { try package.attach(Data([2]), at: acceptedPath + ["too-deep"]) }
        #expect(package.attachmentPaths == paths)
    }

    @Test func entryLimitAppliesToAttachmentChangesToo() throws {
        var entries = Dictionary(uniqueKeysWithValues: (0..<10_000).map {
            ("file\($0)", FileWrapper(regularFileWithContents: Data()))
        })
        entries["document.json"] = FileWrapper(regularFileWithContents: try SongDocument().encoded())
        var package = try DocumentPackage(reading: FileWrapper(directoryWithFileWrappers: entries))
        #expect(throws: SongError.self) { try package.attach(Data(), at: ["overflow"]) }
        #expect(package.attachmentPaths.count == 10_000)
        #expect(try DocumentPackage(reading: package.fileWrapper()).attachmentPaths.count == 10_000)
    }

    @Test func oversizedJSONCannotBeWrittenAsAnUnreadableDocument() throws {
        var package = DocumentPackage()
        package.song.metadata.notes = String(repeating: "a", count: SongDocument.maximumEncodedBytes)
        #expect(throws: SongError.self) { try package.song.encoded() }
        #expect(throws: SongError.self) { try package.fileWrapper() }
        package.song.metadata.notes = "編集を短くして保存し直せます。"
        #expect(try DocumentPackage(reading: package.fileWrapper()).song == package.song)
    }
}
