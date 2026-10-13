import Foundation
import Testing
import SongCore
@testable import SongServices

private final class ReviewStub: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var answer: (@Sendable (URLRequest) throws -> Data)?
        var models: [String] = []
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let answer = Self.state.lock.withLock { Self.state.answer }
            let data = try answer?(request) ?? Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct PronunciationReviewTests {
    private func song(source: FieldSource = .init(.ai, provider: "Ollama", model: "generator")) -> SongDocument {
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "from", language: "en", syllabify: true)
        song.syllables[0].ipa = .init("fraɪm", source: source)
        song.syllables[0].reading = .init("フライム", source: source)
        return song
    }
    private func session(_ answer: @escaping @Sendable (URLRequest) throws -> Data) -> URLSession {
        ReviewStub.state.lock.withLock { ReviewStub.state.answer = answer; ReviewStub.state.models = [] }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReviewStub.self]
        return URLSession(configuration: config)
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private static func response(_ request: URLRequest, verdict: String = "review", expected: String = "frɒm", invalidIDs: Bool = false) throws -> Data {
        let body = try body(request)
        let model = body["model"] as! String
        ReviewStub.state.lock.withLock { ReviewStub.state.models.append(model) }
        let messages = body["messages"] as! [[String: String]]
        #expect(messages[0]["content"]!.contains("No recording is supplied"))
        let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
        #expect(input["accent"] as? String == "british")
        let words = (input["words"] as! [[String: Any]]).map {
            ["id": invalidIDs ? 999 : $0["id"]!, "verdict": verdict, "explanation": "母音が辞書候補と異なります。", "expectedIPA": expected] as [String: Any]
        }
        let output = try JSONSerialization.data(withJSONObject: ["words": words])
        return try JSONSerialization.data(withJSONObject: ["message": ["content": String(decoding: output, as: UTF8.self)]])
    }

    @Test @MainActor func skipsGeneratorAndChecksWithAnotherModelWithoutMutation() async throws {
        let original = song(), baseline = original
        let session = session { try Self.response($0) }; defer { session.invalidateAndCancel() }
        var results: [UUID: PronunciationReview.Result] = [:]
        try await PronunciationReview.run(document: original,
            clients: [.init(.ollama("generator"), session: session), .init(.ollama("reviewer"), session: session)],
            update: { results[$0] = $1 }, progress: { _ in })
        #expect(ReviewStub.state.lock.withLock { ReviewStub.state.models } == ["reviewer"])
        #expect(results.values.first?.verdict == .review)
        #expect(results.values.first?.expectedIPA == "frɒm")
        #expect(original == baseline)
    }
    @Test @MainActor func oneModelAndUnknownProvenanceCannotPretendIndependentReview() async throws {
        let session = session { _ in Issue.record("No model should be called"); throw URLError(.badURL) }
        defer { session.invalidateAndCancel() }
        for original in [song(), song(source: .init(.ai))] {
            var results: [UUID: PronunciationReview.Result] = [:]
            try await PronunciationReview.run(document: original, clients: [.init(.ollama("generator"), session: session)],
                update: { results[$0] = $1 }, progress: { _ in })
            #expect(results.values.first?.verdict == .uncertain)
            #expect(results.values.first?.reviewer == "AI未検証")
        }
        let entry = PronunciationAudit.entries(in: song())[0]
        var config = APIModelConfiguration(); config.model = "generator:latest"
        #expect(!PronunciationReview.canIndependentlyReview(entry, with: .init(.api(config, key: "fake"))))
    }
    @Test @MainActor func modelOKCannotEraseDictionaryOrKanaMismatch() async throws {
        let original = song()
        let session = session { try Self.response($0, verdict: "ok", expected: "fraɪm") }
        defer { session.invalidateAndCancel() }
        let entries = PronunciationAudit.entries(in: original)
        let result = try await PronunciationReview.check(entries, language: "en", style: .british, client: .init(.ollama("reviewer"), session: session))
        #expect(result.values.first?.verdict == .review)
        #expect(!entries[0].issues.isEmpty)
    }
    @Test @MainActor func invalidOutputFallsBackButNeverToGenerator() async throws {
        let session = session { request in
            let body = try Self.body(request)
            return try Self.response(request, invalidIDs: body["model"] as? String == "bad")
        }; defer { session.invalidateAndCancel() }
        var results: [UUID: PronunciationReview.Result] = [:]
        try await PronunciationReview.run(document: song(), clients: ["bad", "generator", "good"].map { .init(.ollama($0), session: session) },
            update: { results[$0] = $1 }, progress: { _ in })
        #expect(ReviewStub.state.lock.withLock { ReviewStub.state.models } == ["bad", "good"])
        #expect(results.values.first?.reviewer == "Ollama · good")
    }
    @Test @MainActor func offlineIsUnverifiedAndCancellationDoesNotPublishResults() async throws {
        let session = session { _ in throw URLError(.cannotConnectToHost) }; defer { session.invalidateAndCancel() }
        var results: [UUID: PronunciationReview.Result] = [:]
        try await PronunciationReview.run(document: song(), clients: [.init(.ollama("offline"), session: session)],
            update: { results[$0] = $1 }, progress: { _ in })
        #expect(results.values.first?.verdict == .uncertain)
        let original = song()
        let task = Task { @MainActor in
            try await PronunciationReview.run(document: original, clients: [], update: { _, _ in Issue.record("Cancelled result") }, progress: { _ in })
        }
        task.cancel()
        do { try await task.value; Issue.record("Cancellation ignored") } catch { #expect(error is CancellationError) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SINGING_TEST_PRONUNCIATION_REVIEW"] == "1"))
    @MainActor func liveQwenChecksAppleGeneratedIncorrectIPA() async throws {
        let original = song(source: .init(.ai, provider: "Apple Foundation Models", model: "system-default"))
        let entries = PronunciationAudit.entries(in: original)
        let result = try await PronunciationReview.check(entries, language: "en", style: .british, client: .init(.ollama("qwen3.5:9b")))
        #expect(result.values.first?.verdict == .review)
        #expect(result.values.first?.expectedIPA.contains("ɒ") == true || result.values.first?.expectedIPA.contains("ə") == true)
        #expect(result.values.first?.reviewer == "Ollama · qwen3.5:9b")
    }
}
