import Foundation
import Testing
import SongCore
@testable import SongServices

private actor MeaningCalls {
    var value = 0
    func record() { value += 1 }
}

private struct MeaningStub: AIProvider {
    var id = "test"
    var displayName: String { id }
    var capabilities: AIProviderCapabilities { [.translation] }
    var source: FieldSource { .init(.ai, provider: id) }
    var calls = MeaningCalls()
    var failure: ProviderError?
    var cancel = false
    var empty = false
    func analyze(request: LinguisticAnalysisRequest) async throws -> LinguisticAnalysis {
        await calls.record()
        if cancel { throw CancellationError() }
        if let failure { throw failure }
        return .init(translation: "小鳥が川辺で休む。", words: request.words.map {
            .init(id: $0.id, lemma: $0.surface, partOfSpeech: "名詞", contextualMeaning: empty ? "" : "文脈の意味", dictionaryMeaning: "辞書の意味")
        })
    }
}

struct MeaningCompletionTests {
    private func song() -> SongDocument {
        var song = SongDocument()
        song.appendPhrase(text: "The bird rests.", language: "en", syllabify: true)
        return song
    }

    @Test @MainActor func fillsAllLinesAndKeepsExistingMeaningsPronunciationAndMusic() async throws {
        var song = song()
        song.appendPhrase(text: "We rest.", language: "en", syllabify: false)
        song.words[0].contextualMeaning = .init("既存の意味")
        song.phrases[0].translation.edit("手修正した訳")
        song.words[1].contextualMeaning.edit("一度入力")
        song.words[1].contextualMeaning.edit("") // Deliberate deletion is protected too.
        let original = song
        try await MeaningCompletion.run(phraseIDs: song.phrases.map(\.id), providers: [MeaningStub()], current: { song }, apply: { result, snapshot, id in
            MeaningCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { _ in })
        #expect(song.words[0].contextualMeaning == original.words[0].contextualMeaning)
        #expect(song.words[1].contextualMeaning == original.words[1].contextualMeaning)
        #expect(song.phrases[0].translation == original.phrases[0].translation)
        #expect(song.phrases[1].translation.value == "小鳥が川辺で休む。")
        #expect(song.syllables == original.syllables && song.alignments == original.alignments && song.music == original.music)
        #expect(song.words.map(\.id) == original.words.map(\.id))
        let missing = MeaningCompletion.missing(in: song, phraseIDs: Set(song.phrases.map(\.id)))
        #expect(missing.words == 0 && missing.lines == 0)
        try song.validate()
    }

    @Test @MainActor func concurrentEditsRemainWhileUnchangedEmptyFieldsFill() async throws {
        var song = song()
        let original = song
        try await MeaningCompletion.run(phraseIDs: song.phrases.map(\.id), providers: [MeaningStub()], current: { song }, apply: { result, snapshot, id in
            song.metadata.title = "解析中の編集"
            song.words[0].contextualMeaning.edit("後から入力")
            song.phrases[0].translation.edit("後から訳を入力")
            song.syllables[0].reading.edit("カナ")
            MeaningCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { _ in })
        #expect(song.metadata.title == "解析中の編集")
        #expect(song.words[0].contextualMeaning.value == "後から入力")
        #expect(song.words[1].contextualMeaning.value == "文脈の意味")
        #expect(song.phrases[0].translation.value == "後から訳を入力")
        #expect(song.syllables[0].reading.value == "カナ")
        #expect(song.syllables.map(\.id) == original.syllables.map(\.id))
    }

    @Test func changedContextOrDocumentRejectsMerge() async throws {
        let original = song()
        let request = LinguisticAnalysisRequest(document: original, phrase: original.phrases[0])
        let provider = MeaningStub()
        let result = try LinguisticAnalysisService().apply(await provider.analyze(request: request), request: request, source: provider.source, to: original)
        var changed = original
        changed.phrases[0].originalText = "Changed sentence."
        let before = changed
        MeaningCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &changed)
        #expect(changed == before)
        changed = SongDocument()
        let other = changed
        MeaningCompletion.merge(result, from: original, phraseID: original.phrases[0].id, into: &changed)
        #expect(changed == other)
    }

    @Test @MainActor func failedOrEmptyModelFallsBackAndCompletedSongSkipsAI() async throws {
        var song = song()
        song.appendPhrase(text: "We rest.", language: "en", syllabify: false)
        let offline = MeaningStub(id: "offline", failure: .unavailable("offline"))
        let invalid = MeaningStub(id: "empty", empty: true)
        let good = MeaningStub(id: "good")
        let ids = song.phrases.map(\.id)
        let run = { @MainActor in
            try await MeaningCompletion.run(phraseIDs: ids, providers: [offline, invalid, good], current: { song }, apply: { result, snapshot, id in
                MeaningCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
            }, progress: { _ in })
        }
        try await run()
        #expect(await offline.calls.value == 1)
        #expect(await invalid.calls.value == 2)
        #expect(await good.calls.value == 2)
        let completed = song
        try await run()
        #expect(await good.calls.value == 2)
        #expect(song == completed)
    }

    @Test @MainActor func cancellationAndMissingAIKeepInput() async throws {
        let song = song()
        for providers in [[MeaningStub(cancel: true)], []] {
            do {
                try await MeaningCompletion.run(phraseIDs: song.phrases.map(\.id), providers: providers, current: { song }, apply: { _, _, _ in
                    Issue.record("Must not apply")
                }, progress: { _ in })
                Issue.record("Expected failure")
            } catch { #expect(error is CancellationError || error is ProviderError) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SINGING_TEST_MEANINGS"] == "1"))
    @MainActor func liveMeaningsFillJapaneseTranslationsAndContextualGlosses() async throws {
        var song = SongDocument()
        song.metadata.title = "意味と発音の確認"
        song.appendPhrase(text: "A young fox waits beside a quiet lake.", language: "en", syllabify: true)
        song.appendPhrase(text: "We carry warm bread to our friends.", language: "en", syllabify: true)
        let original = song
        var preferences = ModelPreferences()
        if ProcessInfo.processInfo.environment["SINGING_TEST_MEANINGS_LOCAL"] == "1" { preferences.mode = .local }
        let clients = ModelDiscovery.forMeanings(await ModelDiscovery.clients(preferences: preferences, apiKey: ""), mode: preferences.mode)
        try await MeaningCompletion.run(phraseIDs: song.phrases.map(\.id), providers: clients.map { ModelAnalysisProvider(client: $0) }, current: { song }, apply: { result, snapshot, id in
            MeaningCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { print($0) })
        let remaining = MeaningCompletion.missing(in: song, phraseIDs: Set(song.phrases.map(\.id)))
        #expect(remaining.words == 0 && remaining.lines == 0)
        let article = try #require(song.words.first { $0.surface == "A" })
        #expect(article.contextualMeaning.value != "その")
        let we = try #require(song.words.first { $0.surface == "We" })
        #expect(we.contextualMeaning.value.contains("私") || we.contextualMeaning.value.contains("わたし"))
        #expect(song.syllables == original.syllables && song.alignments == original.alignments)
        for phrase in song.phrases {
            print("Translation: \(phrase.translation.value)")
            print(song.words(in: phrase).map { "\($0.surface)=\($0.contextualMeaning.value)" }.joined(separator: ", "))
        }
        try song.validate()
        if let path = ProcessInfo.processInfo.environment["SINGING_TEST_MEANING_OUTPUT"] {
            guard !FileManager.default.fileExists(atPath: path) else { throw SongError.invalid("QA output already exists") }
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try song.encoded().write(to: directory.appendingPathComponent("document.json"))
        }
    }
}
