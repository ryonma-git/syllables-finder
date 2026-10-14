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

    @Test func modelSeesWholeWordContextWithoutOrderedHomographBias() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "the wind", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            #expect(input["context"] as? String == "the wind")
            let words = input["words"] as! [[String: Any]]
            #expect(words.count == 1 && words[0]["surface"] as? String == "wind")
            #expect(words[0]["dictionaryIPA"] == nil)
            return try Self.response(input: words, wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: "ウィンド")
        }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotate(phrase: song.phrases[0], in: song)
        #expect(EnglishPronunciation.comparableIPA(result.syllables.last!.ipa.value) == "wɪnd")
        #expect(result.syllables.first?.reading.value == "ザ")
    }

    @Test func hallucinatedOrInconsistentPronunciationsAreHeldWithoutThrowing() async throws {
        for (full, unit, reading) in [("waʊnd", "waʊnd", "ワウンド"), ("wɪnd", "wind", "ウィンド"),
                                      ("wɪnd", ">wɪnd", "ウィンド"),
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
            let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
            #expect(result.issues.count == 1)
            #expect(!result.issues[0].reason.isEmpty)
            #expect(result.document.syllables[0].ipa.value.isEmpty)
            #expect(song.syllables[0].ipa.value.isEmpty)
        }
    }

    @Test @MainActor func automaticCompletionIsolatesMalformedWordsAndKeepsSuccessfulResults() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "wind Zorava", language: "en", syllabify: true)
        let session = session { request in
            if request.url?.path == "/api/tags" {
                return Data(#"{"models":[{"name":"qwen3.5:9b"}]}"#.utf8)
            }
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            let words = input["words"] as! [[String: Any]]
            if let wind = words.first(where: { $0["surface"] as? String == "wind" }) {
                return try Self.response(input: [wind], wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: "ウィンド")
            }
            return Data(#"{"message":{"content":"{\"words\":[]}"}}"#.utf8)
        }
        defer { session.invalidateAndCancel() }
        let ids = song.phrases.map(\.id)
        try await PronunciationCompletion(session: session).run(phraseIDs: ids, current: { song }, apply: { result, snapshot, id in
            PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { _ in })
        #expect(song.syllables(in: song.words[0]).map(\.reading.value).joined() == "ウィンド")
        #expect(PronunciationCompletion.missingWords(in: song, phraseIDs: Set(ids)).map(\.surface) == ["Zorava"])
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 2)
    }

    @Test @MainActor func alreadyCompleteDocumentDoesNotContactOllama() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "The sun", language: "en", syllabify: true)
        let session = session { _ in throw ProviderError.unavailable("Must not connect") }
        defer { session.invalidateAndCancel() }
        try await PronunciationCompletion(session: session).run(phraseIDs: song.phrases.map(\.id), current: { song },
            apply: { _, _, _ in Issue.record("Should not apply anything") }, progress: { _ in })
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 0)
    }

    @Test func manualIPAAndDetailedPhonemesAreNotSentToModel() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "wind", language: "en", syllabify: true)
        song.syllables[0].ipa.edit("waɪnd")
        let session = session { _ in throw ProviderError.unavailable("Must not connect") }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotate(phrase: song.phrases[0], in: song)
        #expect(result.syllables[0].ipa == song.syllables[0].ipa)
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 0)
    }

    @Test @MainActor func connectionFailureKeepsTheInputAndDoesNotApplyResults() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "wind", language: "en", syllabify: true)
        let original = song
        let session = session { _ in throw URLError(.cannotConnectToHost) }
        defer { session.invalidateAndCancel() }
        do {
            try await PronunciationCompletion(session: session).run(phraseIDs: song.phrases.map(\.id), current: { song },
                apply: { _, _, _ in Issue.record("Failure must not apply a result") }, progress: { _ in })
            Issue.record("Expected a connection error")
        } catch { #expect(error is URLError) }
        #expect(song == original)
    }

    @Test func invalidRequestLocalIDsAreRejectedBeforeMappingToSavedIDs() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "wind", language: "en", syllabify: true)
        for invalid in [-1, 999] {
            let session = session { request in
                let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
                let messages = body["messages"] as! [[String: String]]
                let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
                var words = input["words"] as! [[String: Any]]
                words[0]["id"] = invalid
                return try Self.response(input: words, wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: "ウィンド")
            }
            defer { session.invalidateAndCancel() }
            let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
            #expect(result.issues.count == 1)
            #expect(result.document.syllables[0].ipa.value.isEmpty)
        }
    }

    @Test @MainActor func unavailableModelFallsBackAndIsNotRetriedOnEveryLine() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "the wind", language: "en", syllabify: true)
        song.appendPhrase(text: "the wind", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            if body["model"] as? String == "offline" { throw URLError(.cannotConnectToHost) }
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: "ウィンド")
        }
        defer { session.invalidateAndCancel() }
        let clients = [ModelClient(.ollama("offline"), session: session), ModelClient(.ollama("good"), session: session)]
        let ids = song.phrases.map(\.id)
        try await PronunciationCompletion(session: session).run(phraseIDs: ids, clients: clients, current: { song }, apply: { result, snapshot, id in
            PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
        }, progress: { _ in })
        #expect(PronunciationCompletion.missingWords(in: song, phraseIDs: Set(ids)).isEmpty)
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 3)
    }

    @Test func compatibleAPIUsesChosenEndpointAndHeaderWithoutLeakingKeyIntoPayload() async throws {
        let session = session { request in
            #expect(request.url?.absoluteString == "https://example.invalid/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-key")
            let body = try Self.body(request)
            #expect(!String(decoding: body, as: UTF8.self).contains("fake-test-key"))
            return Data(#"{"choices":[{"message":{"content":"{\"ok\":true}"}}]}"#.utf8)
        }
        defer { session.invalidateAndCancel() }
        var config = APIModelConfiguration(); config.baseURL = "https://example.invalid/v1"; config.model = "test-model"; config.enabled = true
        try await ModelClient(.api(config, key: "fake-test-key"), session: session).probe()
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 1)
    }

    @Test func britishRequestNamesAccentAndRejectsRhoticGOATAndUnsupportedPhones() async throws {
        for badIPA in ["ɡoʊ", "kɑr", "ɝ", "ɡɐ"] {
            var song = SongDocument()
            song.metadata.englishPronunciation = .british
            song.appendPhrase(text: "Zog", language: "en", syllabify: true)
            let session = session { request in
                let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
                let messages = body["messages"] as! [[String: String]]
                #expect(messages[0]["content"]!.contains("British English"))
                let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
                #expect(input["englishAccent"] as? String == "british")
                return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: badIPA, syllableIPA: badIPA, reading: "ゴウ")
            }
            defer { session.invalidateAndCancel() }
            let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
            #expect(result.issues.count == 1)
            #expect(result.document.syllables[0].ipa.value.isEmpty)
        }
    }

    @Test func modelKanaCannotContradictBritishIPA() async throws {
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "Zog", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: "zɒɡ", syllableIPA: "zɒɡ", reading: "ザグ")
        }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotate(phrase: song.phrases[0], in: song)
        #expect(result.syllables[0].ipa.value == "zɒɡ")
        #expect(result.syllables[0].reading.value == "ゾッグ")
    }

    @Test func wholeWordLengthMismatchIsRejected() async throws {
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "Zog", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: "zɔːɡ", syllableIPA: "zɔɡ", reading: "ゾーグ")
        }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].reason.contains("一致しません"))
        #expect(result.document.syllables[0].ipa.value.isEmpty)
    }

    @Test func emptyOrNonKanaModelReadingUsesValidatedIPA() async throws {
        for reading in ["", "wind"] {
            var song = SongDocument()
            song.appendPhrase(text: "wind", language: "en", syllabify: true)
            let session = session { request in
                let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
                let messages = body["messages"] as! [[String: String]]
                let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
                return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: reading)
            }
            defer { session.invalidateAndCancel() }
            let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
            #expect(result.issues.isEmpty)
            #expect(result.document.syllables[0].reading.value == "ウィンド")
        }
    }

    @Test @MainActor func aBadWordDoesNotDiscardItsNeighbourOrStopTheNextLine() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "on wind", language: "en", syllabify: true)
        song.appendPhrase(text: "wind", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            let words = input["words"] as! [[String: Any]]
            let answers = words.reversed().map { word -> [String: Any] in
                let ipa = word["surface"] as? String == "on" ? "ɒn" : "wɪnd"
                return ["id": word["id"]!, "ipa": ipa, "syllables": [["id": 0, "ipa": ipa, "reading": ""]]]
            }
            let response = try JSONSerialization.data(withJSONObject: ["words": answers])
            return try JSONSerialization.data(withJSONObject: ["message": ["content": String(decoding: response, as: UTF8.self)]])
        }
        defer { session.invalidateAndCancel() }
        let issues = try await PronunciationCompletion(session: session).run(phraseIDs: song.phrases.map(\.id),
            clients: [ModelClient(.ollama("test"), session: session)], current: { song }, apply: { result, snapshot, id in
                PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
            }, progress: { _ in })
        #expect(issues.map(\.surface) == ["on"])
        #expect(issues[0].reason.contains("辞書候補"))
        #expect(song.words.filter { $0.surface == "wind" }.allSatisfy { song.syllables(in: $0)[0].reading.value == "ウィンド" })
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 2)
        _ = try song.encoded()
    }

    @Test @MainActor func undecodableLineIsReportedAndLaterLineStillCompletes() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "on", language: "en", syllabify: true)
        song.appendPhrase(text: "wind", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            if input["context"] as? String == "on" { return Data(#"{"message":{"content":"invalid json"}}"#.utf8) }
            return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: "wɪnd", syllableIPA: "wɪnd", reading: "")
        }
        defer { session.invalidateAndCancel() }
        let issues = try await PronunciationCompletion(session: session).run(phraseIDs: song.phrases.map(\.id),
            clients: [ModelClient(.ollama("test"), session: session)], current: { song }, apply: { result, snapshot, id in
                PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
            }, progress: { _ in })
        #expect(issues.map(\.surface) == ["on"])
        #expect(song.syllables.last!.reading.value == "ウィンド")
    }

    @Test @MainActor func nextModelResolvesHeldWordsAndClearsTheirIssues() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "wind", language: "en", syllabify: true)
        let session = session { request in
            let body = try JSONSerialization.jsonObject(with: try Self.body(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let input = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
            let ipa = body["model"] as? String == "first" ? "waʊnd" : "wɪnd"
            return try Self.response(input: input["words"] as! [[String: Any]], wordIPA: ipa, syllableIPA: ipa, reading: "")
        }
        defer { session.invalidateAndCancel() }
        let issues = try await PronunciationCompletion(session: session).run(phraseIDs: song.phrases.map(\.id),
            clients: ["first", "second"].map { ModelClient(.ollama($0), session: session) }, current: { song }, apply: { result, snapshot, id in
                PronunciationCompletion.merge(result, from: snapshot, phraseID: id, into: &song)
            }, progress: { _ in })
        #expect(issues.isEmpty)
        #expect(song.syllables[0].reading.value == "ウィンド")
        #expect(PronunciationStub.state.lock.withLock { PronunciationStub.state.calls } == 2)
    }

    @Test func duplicateIDsAreHeldWhileUnrelatedValidWordsSurvive() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "on wind", language: "en", syllabify: true)
        let session = session { _ in
            let words: [[String: Any]] = [
                ["id": 0, "ipa": "ɑn", "syllables": [["id": 0, "ipa": "ɑn", "reading": ""]]],
                ["id": 0, "ipa": "ɔn", "syllables": [["id": 0, "ipa": "ɔn", "reading": ""]]],
                ["id": 1, "ipa": "wɪnd", "syllables": [["id": 0, "ipa": "wɪnd", "reading": ""]]],
                ["id": 999, "ipa": "ɑn", "syllables": [["id": -1, "ipa": "ɑn", "reading": ""]]]
            ]
            let response = try JSONSerialization.data(withJSONObject: ["words": words])
            return try JSONSerialization.data(withJSONObject: ["message": ["content": String(decoding: response, as: UTF8.self)]])
        }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
        #expect(result.issues.map(\.surface) == ["on"])
        #expect(result.issues[0].reason.contains("重複"))
        #expect(result.document.syllables.last!.reading.value == "ウィンド")
        #expect(result.document.words.map(\.id) == song.words.map(\.id))
        #expect(result.document.syllables.map(\.id) == song.syllables.map(\.id))
    }

    @Test func malformedWordFieldsDoNotDiscardDecodableNeighbours() async throws {
        var song = SongDocument()
        song.appendPhrase(text: "on wind", language: "en", syllabify: true)
        let session = session { _ in
            let output = #"{"words":[{"id":0,"ipa":null,"syllables":"bad type"},{"id":1,"ipa":"wɪnd","syllables":[{"id":0,"ipa":"wɪnd"}]},{"id":"invalid","ipa":null}]}"#
            return try JSONSerialization.data(withJSONObject: ["message": ["content": output]])
        }
        defer { session.invalidateAndCancel() }
        let result = try await OllamaPronunciationProvider(model: "test", session: session).annotateWithReport(phrase: song.phrases[0], in: song)
        #expect(result.issues.map(\.surface) == ["on"])
        #expect(result.document.syllables[0].ipa.value.isEmpty)
        #expect(result.document.syllables.last!.reading.value == "ウィンド")
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
