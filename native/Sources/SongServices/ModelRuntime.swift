import Foundation
import SongCore
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct APIModelConfiguration: Codable, Sendable, Equatable {
    public var baseURL = "https://api.openai.com/v1"
    public var model = ""
    public var enabled = false
    public init() {}

    public func endpoint() throws -> URL {
        guard let url = URL(string: baseURL), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw ProviderError.unavailable("APIのURLはHTTPS、またはこのMacのlocalhostを指定してください。")
        }
        return url.appendingPathComponent("chat/completions")
    }
}

public struct ModelPreferences: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case automatic, local, api, dictionary
        public var label: String {
            switch self {
            case .automatic: "自動（AppleFM・Qwen）"
            case .local: "ローカルLLM優先"
            case .api: "API優先"
            case .dictionary: "辞書のみ"
            }
        }
    }
    public var mode: Mode = .automatic
    public var localModel = ""
    public var api = APIModelConfiguration()
    public init() {}
}

public struct ModelClient: Sendable {
    public enum Backend: Sendable { case apple, ollama(String), api(APIModelConfiguration, key: String) }
    public let backend: Backend
    private let session: URLSession
    public init(_ backend: Backend, session: URLSession = .shared) { self.backend = backend; self.session = session }
    public var label: String {
        switch backend {
        case .apple: "AppleFM（このMac）"
        case .ollama(let model): "Ollama · " + model
        case .api(let config, _): "API · " + config.model
        }
    }
    public var source: FieldSource {
        switch backend {
        case .apple: .init(.ai, provider: "Apple Foundation Models", model: "system-default")
        case .ollama(let model): .init(.ai, provider: "Ollama", model: model)
        case .api(let config, _): .init(.ai, provider: "OpenAI-compatible", model: config.model)
        }
    }

    public static var appleAvailability: (available: Bool, message: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return (true, "利用可能（応答テストは未実行）")
            case .unavailable(.deviceNotEligible): return (false, "このMacはApple Intelligenceに非対応です。")
            case .unavailable(.appleIntelligenceNotEnabled): return (false, "システム設定でApple Intelligenceを有効にしてください。")
            case .unavailable(.modelNotReady): return (false, "Appleのモデルを準備中です。時間を置いて再確認してください。")
            case .unavailable: return (false, "AppleFMは現在利用できません。")
            }
        }
        #endif
        return (false, "AppleFMにはmacOS 26以降と対応するMacが必要です。")
    }

    public func generate(instructions: String, input: String, schema: Data) async throws -> Data {
        try Task.checkCancellation()
        switch backend {
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                guard Self.appleAvailability.available else { throw ProviderError.unavailable(Self.appleAvailability.message) }
                let object = try JSONSerialization.jsonObject(with: schema) as! [String: Any]
                let dynamic = try Self.appleSchema(object, name: "Response")
                let format = try GenerationSchema(root: dynamic, dependencies: [])
                let modelSession = LanguageModelSession(model: .default, instructions: instructions)
                let response = try await modelSession.respond(to: input, schema: format,
                    options: GenerationOptions(temperature: 0, maximumResponseTokens: 2500))
                try Task.checkCancellation()
                return Data(response.content.jsonString.utf8)
            }
            #endif
            throw ProviderError.unavailable(Self.appleAvailability.message)
        case .ollama(let model):
            guard !model.isEmpty else { throw ProviderError.unavailable("ローカルモデルを選択してください。") }
            let body: [String: Any] = ["model": model, "stream": false, "think": false,
                "format": try JSONSerialization.jsonObject(with: schema),
                "messages": [["role": "system", "content": instructions], ["role": "user", "content": input]],
                "options": ["temperature": 0, "num_predict": 3000]]
            let data = try await request(url: URL(string: "http://127.0.0.1:11434/api/chat")!, body: body)
            struct Envelope: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            return Data(try JSONDecoder().decode(Envelope.self, from: data).message.content.utf8)
        case .api(let config, let key):
            guard config.enabled, !key.isEmpty, !config.model.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ProviderError.unavailable("APIの利用許可・モデル名・APIキーを設定してください。")
            }
            // json_object is supported by more compatible servers than strict JSON Schema.
            let body: [String: Any] = ["model": config.model, "stream": false,
                "messages": [["role": "system", "content": instructions + "\nReturn JSON matching this schema:\n" + String(decoding: schema, as: UTF8.self)],
                             ["role": "user", "content": input]],
                "response_format": ["type": "json_object"]]
            let data = try await request(url: config.endpoint(), body: body, key: key)
            struct Envelope: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }; let choices: [Choice] }
            guard let content = try JSONDecoder().decode(Envelope.self, from: data).choices.first?.message.content else { throw ProviderError.malformedResponse }
            return Data(content.utf8)
        }
    }

    public func probe() async throws {
        let schema = Data(#"{"type":"object","required":["ok"],"properties":{"ok":{"type":"boolean"}}}"#.utf8)
        let data = try await generate(instructions: "Return the JSON object {\"ok\":true}. This is a connection test.", input: "Connection test. Set ok to true.", schema: schema)
        struct Probe: Decodable { let ok: Bool }
        guard try JSONDecoder().decode(Probe.self, from: data).ok else { throw ProviderError.malformedResponse }
    }

    private func request(url: URL, body: [String: Any], key: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request, delegate: NoModelRedirect())
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.unavailable("\(label)から有効な応答がありません（HTTP \(status)）。接続設定を確認してください。")
        }
        return data
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func appleSchema(_ object: [String: Any], name: String) throws -> DynamicGenerationSchema {
        switch object["type"] as? String {
        case "string": return DynamicGenerationSchema(type: String.self)
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        case "array":
            guard let items = object["items"] as? [String: Any] else { throw ProviderError.malformedResponse }
            return DynamicGenerationSchema(arrayOf: try appleSchema(items, name: name + "Item"))
        case "object":
            guard let fields = object["properties"] as? [String: [String: Any]] else { throw ProviderError.malformedResponse }
            return DynamicGenerationSchema(name: name, properties: try fields.keys.sorted().map {
                DynamicGenerationSchema.Property(name: $0, schema: try appleSchema(fields[$0]!, name: name + $0.capitalized))
            })
        default: throw ProviderError.malformedResponse
        }
    }
    #endif
}

private final class NoModelRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ModelDiscovery {
    /// Short Japanese glosses were more reliable with the installed Qwen 3.5 in local checks.
    /// Keep explicit user priorities, and retain AppleFM when that optional model is absent.
    public static func forMeanings(_ clients: [ModelClient], mode: ModelPreferences.Mode) -> [ModelClient] {
        guard mode == .automatic else { return clients }
        func preferred(_ client: ModelClient) -> Bool {
            if case .ollama(let model) = client.backend { return model.lowercased().hasPrefix("qwen3.5:") }
            return false
        }
        return clients.filter(preferred) + clients.filter { !preferred($0) }
    }

    public static func clients(preferences: ModelPreferences, apiKey: String, session: URLSession = .shared) async -> [ModelClient] {
        guard preferences.mode != .dictionary else { return [] }
        let models = (try? await OllamaProvider.models(session: session)) ?? []
        var local = [ModelClient]()
        if ModelClient.appleAvailability.available { local.append(ModelClient(.apple, session: session)) }
        let chosen = models.contains(preferences.localModel) ? preferences.localModel : PronunciationCompletion.model(from: models) ?? models.first
        let localModels = (chosen.map { [$0] } ?? []) + Set(models).sorted().filter { $0 != chosen }
        let localClients = localModels.map { ModelClient(.ollama($0), session: session) }
        if preferences.mode == .local { local.insert(contentsOf: localClients, at: 0) }
        else { local += localClients }
        if preferences.api.enabled, !apiKey.isEmpty, !preferences.api.model.isEmpty {
            let api = ModelClient(.api(preferences.api, key: apiKey), session: session)
            if preferences.mode == .api { local.insert(api, at: 0) } else { local.append(api) }
        }
        return local
    }
}
