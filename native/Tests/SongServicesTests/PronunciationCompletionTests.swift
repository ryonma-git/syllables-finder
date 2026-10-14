import Foundation
import Testing
import SongCore
@testable import SongServices

struct PronunciationCompletionTests {
    @Test func structuralMergeRejectsConcurrentAlignmentButPreservesUnrelatedEdits() throws {
        var original = SongDocument()
        original.appendPhrase(text: "expression", language: "en", syllabify: true)
        let wordID = original.words[0].id
        original.syllables = ["ex", "pres", "si", "on"].map { Syllable(parentWordID: wordID, text: $0) }
        original.words[0].syllableIDs = original.syllables.map(\.id)
        var result = original
        EnglishPronunciation.repairAutomaticSegmentation(in: &result)
        EnglishPronunciation.apply(to: &result)
        var current = original
        current.metadata.title = "編集中の曲名"
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current.syllables.count == 3 && current.metadata.title == "編集中の曲名")
        try current.validate()
        current = original
        current.alignments = [.init(languageTargets: [.init(.syllable, current.syllables[0].id)],
            musicTargets: [.timeRange(.init(start: .zero, end: try Beat(1)))], relation: .manual)]
        let protected = current
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current == protected)
    }

    @Test func choosesInstalledQwenWithoutSilentlySwitchingFamilies() {
        #expect(PronunciationCompletion.model(from: ["llama3.1:8b"]) == nil)
        #expect(PronunciationCompletion.model(from: ["qwen3.5:35b", "qwen3.5:9b"]) == "qwen3.5:9b")
        #expect(PronunciationCompletion.model(from: ["qwen3:8b"]) == "qwen3:8b")
    }

    @Test func mergeProtectsConcurrentEditsAndPreservesIDsAndMusic() throws {
        var original = SongDocument()
        original.appendPhrase(text: "The wind moves.", language: "en", syllabify: true)
        let word = try #require(original.words.first { $0.surface == "wind" })
        let index = try #require(original.syllables.firstIndex { $0.parentWordID == word.id })
        var result = original
        result.syllables[index].ipa = .init("wɪnd", source: .init(.ai))
        result.syllables[index].reading = .init("ウィンド", source: .init(.ai))
        var current = original
        current.metadata.title = "手修正した曲名"
        current.phrases[0].translation.edit("風が動く")
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current.syllables[index].reading.value == "ウィンド")
        #expect(current.metadata.title == "手修正した曲名")
        #expect(current.phrases[0].translation.value == "風が動く")
        #expect(current.music == original.music && current.alignments == original.alignments)
        #expect(current.syllables.map(\.id) == original.syllables.map(\.id))
        current = original
        current.syllables[index].reading.edit("手修正")
        let edited = current
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current == edited)
        current = original
        current.phrases[0].originalText = "Changed context"
        let changed = current
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current == changed)
        current = SongDocument()
        let other = current
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current == other)
    }

    @Test func accentChangedWhileModelWasRunningRejectsStaleResult() {
        var original = SongDocument()
        original.appendPhrase(text: "wind", language: "en", syllabify: true)
        var result = original
        result.syllables[0].ipa = .init("wɪnd", source: .init(.ai))
        result.syllables[0].reading = .init("ウィンド", source: .init(.ai))
        var current = original
        current.metadata.englishPronunciation = .british
        let before = current
        PronunciationCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &current)
        #expect(current == before)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SINGING_TEST_LOCAL_QWEN"] == "1"))
    @MainActor func liveBritishCompletionUsesChosenAccent() async throws {
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "The stone glows.", language: "en", syllabify: true)
        let original = song
        let ids = song.phrases.map(\.id)
        let clients = await ModelDiscovery.clients(preferences: ModelPreferences(), apiKey: "")
        try await PronunciationCompletion().run(phraseIDs: ids, clients: clients, verifyCandidates: false, current: { song }, apply: { result, snapshot, id in
            PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { print($0) })
        #expect(PronunciationCompletion.missingWords(in: song, phraseIDs: Set(ids)).isEmpty)
        #expect(EnglishPronunciation.phoneticKey(song.syllables[1].ipa.value) == "stəʊn")
        #expect(EnglishPronunciation.phoneticKey(song.syllables[2].ipa.value) == "ɡləʊz")
        #expect(song.syllables.map(\.id) == original.syllables.map(\.id))
        try song.validate()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SINGING_TEST_LOCAL_QWEN"] == "1"))
    @MainActor func liveNativeFirstRoutingCompletesSyntheticInput() async throws {
        var song = SongDocument()
        song.metadata.title = "自動発音テスト"
        song.appendPhrase(text: "The wind moves quietly near Zorava.", language: "en", syllabify: true)
        let original = song
        let ids = song.phrases.map(\.id)
        #expect(!PronunciationCompletion.missingWords(in: song, phraseIDs: Set(ids)).isEmpty)
        let clients = await ModelDiscovery.clients(preferences: ModelPreferences(), apiKey: "")
        try await PronunciationCompletion().run(phraseIDs: ids, clients: clients, verifyCandidates: false, current: { song }, apply: { result, snapshot, id in
            PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { print($0) })
        let missing = PronunciationCompletion.missingWords(in: song, phraseIDs: Set(ids))
        #expect(missing.isEmpty, "Remaining: \(missing.map(\.surface))")
        let wind = try #require(song.words.first { $0.surface == "wind" })
        #expect(EnglishPronunciation.comparableIPA(song.syllables(in: wind).map(\.ipa.value).joined()) == "wɪnd")
        #expect(song.syllables(in: wind).map(\.reading.value).joined() == "ウィンド")
        #expect(song.syllables.map(\.id) == original.syllables.map(\.id))
        #expect(song.phrases == original.phrases && song.alignments == original.alignments)
        try song.validate()
        if let path = ProcessInfo.processInfo.environment["SINGING_TEST_OUTPUT"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: path) else { throw SongError.invalid("QA output already exists") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try song.encoded().write(to: directory.appendingPathComponent("document.json"))
        }
    }
}
