import Foundation
import Testing
@testable import SongServices

struct ModelRuntimeTests {
    @Test func meaningPriorityUsesOptionalQwenAndHonorsExplicitPreference() {
        let apple = ModelClient(.apple)
        let qwen = ModelClient(.ollama("qwen3.5:9b"))
        let api = ModelClient(.api(.init(), key: ""))
        let clients = [apple, qwen, api]
        #expect(ModelDiscovery.forMeanings(clients, mode: .automatic).map(\.label) == [qwen, apple, api].map(\.label))
        #expect(ModelDiscovery.forMeanings([apple, api], mode: .automatic).map(\.label) == [apple, api].map(\.label))
        #expect(ModelDiscovery.forMeanings([api, apple, qwen], mode: .api).map(\.label) == [api, apple, qwen].map(\.label))
    }

    @Test func apiEndpointsRequireTLSExceptLoopbackAndRejectEmbeddedSecrets() throws {
        var config = APIModelConfiguration()
        #expect(try config.endpoint().absoluteString == "https://api.openai.com/v1/responses")
        for value in ["http://example.com/v1", "https://user:secret@example.com/v1", "https://example.com/v1?key=secret"] {
            config.baseURL = value
            #expect(throws: ProviderError.self) { try config.endpoint() }
        }
        config.baseURL = "http://127.0.0.1:1234/v1"
        #expect(try config.endpoint().host == "127.0.0.1")
    }

    @Test func existingTransportSurvivesAndOfficialKeysStayOnTheirEndpoint() throws {
        let old = Data(#"{"mode":"api","localModel":"","api":{"baseURL":"https://api.openai.com/v1","model":"existing","enabled":true}}"#.utf8)
        let legacy = try JSONDecoder().decode(ModelPreferences.self, from: old)
        #expect(legacy.usesOpenAIPronunciation)
        #expect(legacy.api.model == "existing")
        #expect(try legacy.api.endpoint().lastPathComponent == "completions")
        var preferences = ModelPreferences()
        #expect(!preferences.usesOpenAIPronunciation)
        preferences.api.enabled = true
        #expect(!preferences.usesOpenAIPronunciation)
        preferences.mode = .api
        #expect(preferences.usesOpenAIPronunciation)
        for value in [APIModelConfiguration.openAIBaseURL, APIModelConfiguration.openAIBaseURL + "/"] {
            preferences.api.baseURL = value
            #expect(preferences.api.resolvedKey(saved: "", openAIEnvironmentKey: " env-key ") == "env-key")
            #expect(preferences.api.resolvedKey(saved: "existing-key", openAIEnvironmentKey: "env-key") == "existing-key")
        }
        for value in ["https://api.openai.com.example/v1", "https://api.openai.com:444/v1", "https://api.openai.com/v1/other", "http://localhost/v1"] {
            preferences.api.baseURL = value
            #expect(!preferences.usesOpenAIPronunciation)
            #expect(try preferences.api.endpoint().lastPathComponent == "completions")
            #expect(preferences.api.resolvedKey(saved: "", openAIEnvironmentKey: "secret") == "")
        }
    }

    @Test func dictionaryModeNeverDiscoversOrUsesAI() async {
        var preferences = ModelPreferences(); preferences.mode = .dictionary
        preferences.api.enabled = true; preferences.api.model = "unused"
        let clients = await ModelDiscovery.clients(preferences: preferences, apiKey: "dummy")
        #expect(clients.isEmpty)
    }

    @Test func disabledAPIRefusesBeforeAnyNetworkRequest() async throws {
        var config = APIModelConfiguration(); config.model = "test"
        do {
            try await ModelClient(.api(config, key: "dummy")).probe()
            Issue.record("Disabled API must not be contacted")
        } catch { #expect(error is ProviderError) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SINGING_TEST_APPLE_FM"] == "1"))
    func liveAppleFMRespondsToStructuredConnectionTest() async throws {
        print("AppleFM availability: \(ModelClient.appleAvailability.message)")
        try await ModelClient(.apple).probe()
    }
}
