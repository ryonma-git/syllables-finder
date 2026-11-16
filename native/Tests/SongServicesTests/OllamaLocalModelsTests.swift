import Foundation
import Testing
import SongCore
@testable import SongServices

/// Existing semantic tests use a local-weight fixture; boundary cases are covered below.
enum LocalOllamaFixture {
    static let metadata = Data(#"{"details":{"format":"gguf"},"model_info":{"general.architecture":"llama","general.parameter_count":8000000000}}"#.utf8)
    static func respondToMetadata(_ handler: URLProtocol) -> Bool {
        guard handler.request.url?.path == "/api/show" else { return false }
        handler.client?.urlProtocol(handler, didReceive: HTTPURLResponse(url: handler.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        handler.client?.urlProtocol(handler, didLoad: metadata)
        handler.client?.urlProtocolDidFinishLoading(handler)
        return true
    }
}

private final class LocalityStub: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var calls: [String] = []
        var answer: (@Sendable (URLRequest) throws -> Data)?
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let answer = Self.state.lock.withLock {
                Self.state.calls.append(request.url!.path)
                return Self.state.answer
            }
            let data = try answer?(request) ?? Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct OllamaLocalModelsTests {
    private func session(_ answer: @escaping @Sendable (URLRequest) throws -> Data) -> URLSession {
        LocalityStub.state.lock.withLock { LocalityStub.state.answer = answer; LocalityStub.state.calls = [] }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LocalityStub.self]
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

    @Test func explicitCloudRoutesAreRejectedBeforeMetadataCanBeProxied() async {
        let session = session { _ in
            Issue.record("Explicit cloud routes must not be contacted, even for metadata")
            return LocalOllamaFixture.metadata
        }
        defer { session.invalidateAndCancel() }
        for name in ["model@cloud", "model:cloud", "model:120b-cloud"] {
            await #expect(throws: ProviderError.self) { try await OllamaLocalModels.requireLocal(name, session: session) }
        }
        #expect(LocalityStub.state.lock.withLock { LocalityStub.state.calls }.isEmpty)
    }

    @Test func discoveryExcludesRemoteAliasesAndUnknownModelsWithoutSendingLyrics() async throws {
        let session = session { request in
            if request.url?.path == "/api/tags" {
                return Data(#"{"models":[{"name":"installed-local"},{"name":"ordinary-alias"},{"name":"unknown"},{"name":"advertised-cloud","remote_host":"https://ollama.com"}]}"#.utf8)
            }
            #expect(request.url?.path == "/api/show")
            let body = try Self.body(request)
            #expect(Set(body.keys) == ["model"])
            switch body["model"] as? String {
            case "installed-local": return LocalOllamaFixture.metadata
            case "ordinary-alias":
                return Data(#"{"remote_host":"https://ollama.com","remote_model":"cloud-model","details":{"format":"gguf"},"model_info":{"general.architecture":"llama","general.parameter_count":8000000000}}"#.utf8)
            default: return Data(#"{}"#.utf8)
            }
        }
        defer { session.invalidateAndCancel() }
        var preferences = ModelPreferences(); preferences.mode = .local
        preferences.localModel = "ordinary-alias"
        let clients = await ModelDiscovery.clients(preferences: preferences, apiKey: "", session: session)
        let ollama = clients.compactMap { if case .ollama(let name) = $0.backend { name } else { nil as String? } }
        #expect(ollama == ["installed-local"])
        #expect(!LocalityStub.state.lock.withLock { LocalityStub.state.calls }.contains("/api/chat"))
    }

    @Test func directAndLegacyClientsRefuseRemoteOrUnverifiedModelsBeforeInference() async throws {
        for metadata in [#"{}"#, #"{"remote_model":"upstream","remote_host":"https://ollama.com"}"#] {
            let session = session { request in
                #expect(request.url?.path == "/api/show")
                let body = try Self.body(request)
                #expect(Set(body.keys) == ["model"])
                return Data(metadata.utf8)
            }
            defer { session.invalidateAndCancel() }
            var song = SongDocument(); song.appendPhrase(text: "Private classroom line", language: "en", syllabify: false)
            let request = LinguisticAnalysisRequest(document: song, phrase: song.phrases[0])
            await #expect(throws: (any Error).self) { try await ModelClient(.ollama("ordinary-alias"), session: session).probe() }
            await #expect(throws: (any Error).self) { try await OllamaProvider(model: "ordinary-alias", session: session).analyze(request: request) }
            #expect(LocalityStub.state.lock.withLock { LocalityStub.state.calls } == ["/api/show", "/api/show"])
        }
    }

    @Test func verifiedLocalModelRemainsUsableAndIsRecheckedBeforeEachGeneration() async throws {
        let session = session { request in
            if request.url?.path == "/api/show" { return LocalOllamaFixture.metadata }
            #expect(request.url?.path == "/api/chat")
            return Data(#"{"message":{"content":"{\"ok\":true}"}}"#.utf8)
        }
        defer { session.invalidateAndCancel() }
        let client = ModelClient(.ollama("installed-local"), session: session)
        try await client.probe(); try await client.probe()
        #expect(LocalityStub.state.lock.withLock { LocalityStub.state.calls } == ["/api/show", "/api/chat", "/api/show", "/api/chat"])
    }
}
