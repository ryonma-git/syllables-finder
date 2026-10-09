import Foundation
import Testing
import SongCore
@testable import SongServices

// Each test supplies an isolated response. No requests leave URLSession's protocol stub.
private final class PronunciationStub: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0
        var answer: (@Sendable (URLRequest) throws -> Data)?
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let answer = Self.state.lock.withLock {
                Self.state.calls += 1
                return Self.state.answer
            }
            let data = try answer?(request) ?? Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct PronunciationTests {
    private func session(_ answer: @escaping @Sendable (URLRequest) throws -> Data) -> URLSession {
        PronunciationStub.state.lock.withLock {
            PronunciationStub.state.calls = 0
            PronunciationStub.state.answer = answer
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PronunciationStub.self]
        return URLSession(configuration: configuration)
    }

    @Test func dictionaryWordsDoNotNeedModelOrNetworkAndKeepUserReadings() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "coming creation are the I've", language: "en", syllabify: true)
        song.syllables[0].ipa = .init("koʊ", source: .init(.ai))
        song.syllables[0].reading.edit("手修正")
        let session = session { _ in throw ProviderError.unavailable("Network must not run") }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "", session: session).annotate(phrase: song.phrases[0], in: song)
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 0)
        #expect(result.syllables[0].ipa.value == "ˈkʌ")
        #expect(result.syllables[0].reading == song.syllables[0].reading)
        #expect(result.syllables.map(\.id) == song.syllables.map(\.id))
        #expect(result.alignments == song.alignments)
    }

    @Test func modelSeesWholeWordContextAndDictionaryAlternatives() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "the wind", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            #expect(input["context"] as? String == "the wind")
            let words = input["words"] as! [[String: Any]]
            #expect(words.count == 1 && words[0]["surface"] as? String == "wind")
            #expect((words[0]["dictionaryIPA"] as! [String]).count == 2)
            return try Self.response(input: words, wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: "ウィンド")
        }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotate(phrase: song.phrases[0], in: song)
        #expect(EnglishPronunciation.comparableIPA(result.syllables.last!.ipa.value) == "wɪnd")
        #expect(result.syllables.first?.reading.value == "ザ")
    }

    @Test func hallucinatedOrInconsistentPronunciationsAndNonKanaAreRejected() async throws {
        for (full, unit, reading) in [("waʊnd", "waʊnd", "ワウンド"), ("wɪnd", "wind", "ウィンド"),
                                      ("wɪnd", "wɪnd", "wind"), ("wɪnd", ">wɪnd", "ウィンド"),
                                      (" ", " ", "ウィンド")] {
            var song = SongDocument()
            song.appendPhrase(text: "wind", language: "en", syllabify: true)
            let session = session { request in
                let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
                let messages = body["messages"] as! [[String: String]]
                let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
                return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: full, syllableIPA: unit, reading: reading)
            }
            defer { session.invalidateAndCancel() }
            do {
                _ = try await OllamaPronunciationProvider(model: "test", session: session).annotate(phrase: song.phrases[0], in: song)
                Issue.record("Invalid pronunciation was accepted: \(full) / \(unit) / \(reading)")
            } catch { #expect(error is ProviderError) }
            #expect(song.syllables[0].ipa.value.isEmpty)
        }
    }

    private static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private static func response(input: [[String: Any]], wordIPA: String, syllableIPA: String, reading: String) throws -> Data {
        let words = input.map { word in
            ["id": word["id"]!, "ipa": wordIPA, "syllables": (word["syllables"] as! [[String: Any]]).map {
                ["id": $0["id"]!, "ipa": syllableIPA, "reading": reading]
            }] as [String: Any]
        }
        let output = try JSONSerialization.data(withJSONObject: ["words": words])
        return try JSONSerialization.data(withJSONObject: ["message": ["content": String(decoding: output, as: UTF8.self)]])
    }
}
