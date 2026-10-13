import Foundation
import Testing
@testable import SongServices

struct ModelRuntimeTests {
    @Test func apiEndpointsRequireTLSExceptLoopbackAndRejectEmbeddedSecrets() throws {
        var config = APIModelConfiguration()
        #expect(try config.endpoint().absoluteString == "https://api.openai.com/v1/chat/completions")
        for value in ["http://example.com/v1", "https://user:secret@example.com/v1", "https://example.com/v1?key=secret"] {
            config.baseURL = value
            #expect(throws: ProviderError.self) { try config.endpoint() }
        }
        config.baseURL = "http://127.0.0.1:1234/v1"
        #expect(try config.endpoint().host == "127.0.0.1")
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
