import Foundation
import Testing
import SongCore
@testable import SongServices

struct AnalysisTests {
    @Test func testMockAndManualEditsPreserved() async throws {
        var doc = SampleSongDocument.make()
        doc.words[0].contextualMeaning.edit("自分の訳")
        doc.phrases[0].translation.edit("自分の全文訳")
        let request = LinguisticAnalysisRequest(document: doc, phrase: doc.phrases[0])
        let provider = MockAIProvider()
        let analysis = try await provider.analyze(request: request)
        let changed = try LinguisticAnalysisService().apply(analysis, request: request, source: provider.source, to: doc)
        #expect(changed.words[0].contextualMeaning.value == "自分の訳")
        #expect(changed.phrases[0].translation.value == "自分の全文訳")
        #expect(changed.syllables == doc.syllables)
        #expect(changed.alignments == doc.alignments)
        #expect(changed.words[1].lemma.value == "light")
    }

    @Test func testStaleResponseAndWrongIDsRejected() async throws {
        let doc = SampleSongDocument.make()
        let request = LinguisticAnalysisRequest(document: doc, phrase: doc.phrases[0])
        var analysis = try await MockAIProvider().analyze(request: request)
        let edited = try doc.editing { $0.words[0].notes.edit("変更") }
        #expect(throws: SongError.staleAnalysis) { try LinguisticAnalysisService().apply(analysis, request: request, source: .init(.ai), to: edited) }
        analysis.words[0].id = UUID()
        #expect(throws: (any Error).self) { try LinguisticAnalysisService().apply(analysis, request: request, source: .init(.ai), to: doc) }
    }

    @Test func testProviderFailureDoesNotMutateDocument() async throws {
        let doc = SampleSongDocument.make()
        let request = LinguisticAnalysisRequest(document: doc, phrase: doc.phrases[0])
        do {
            _ = try await MockAIProvider(fails: true).analyze(request: request)
            Issue.record("Expected failure")
        } catch { #expect(error is ProviderError) }
        #expect(doc == SampleSongDocument.make())
    }

    @Test func testCancellation() async {
        let doc = SampleSongDocument.make()
        let request = LinguisticAnalysisRequest(document: doc, phrase: doc.phrases[0])
        let task = Task {
            // Cancellation is set inside this task before the provider is entered.
            try await Task.sleep(for: .seconds(60))
            return try await MockAIProvider().analyze(request: request)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
}
