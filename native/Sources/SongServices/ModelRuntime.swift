import Foundation
import SongCore
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct APIModelConfiguration: Codable, Sendable, Equatable {
    public static let openAIBaseURL = "https://api.openai.com/v1"
    public static let openAIModel = "gpt-6.2-sol"
    public enum OpenAITransport: String, Codable, Sendable { case responses, chatCompletions }
    public var baseURL = Self.openAIBaseURL
    public var model = Self.openAIModel
    public var enabled = false
    /// Previously saved settings used Chat Completions and have no transport field.
    public var openAITransport: OpenAITransport? = .responses
    public init() {}

    public var isOfficialOpenAI: Bool {
        baseURL == Self.openAIBaseURL || baseURL == Self.openAIBaseURL + "/"
    }
    public var usesResponsesAPI: Bool { isOfficialOpenAI && openAITransport == .responses }

    /// An environment key belongs exclusively to the official endpoint.
    public func resolvedKey(saved: String, openAIEnvironmentKey: String?) -> String {
        let key = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { return key }
        guard isOfficialOpenAI else { return "" }
        return openAIEnvironmentKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public func endpoint() throws -> URL {
        guard let url = URL(string: baseURL), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw ProviderError.unavailable("APIのURLはHTTPS、またはこのMacのlocalhostを指定してください。")
        }
        return url.appendingPathComponent(usesResponsesAPI ? "responses" : "chat/completions")
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
    public var usesOpenAIPronunciation: Bool { mode == .api && api.enabled && api.isOfficialOpenAI }
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
        case .api(let config, _): (config.isOfficialOpenAI ? "OpenAI · " : "API · ") + config.model
        }
    }
    public var source: FieldSource {
        switch backend {
        case .apple: .init(.ai, provider: "Apple Foundation Models", model: "system-default")
        case .ollama(let model): .init(.ai, provider: "Ollama", model: model)
        case .api(let config, _): .init(.ai, provider: config.isOfficialOpenAI ? "OpenAI" : "OpenAI-compatible", model: config.model)
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
            try await OllamaLocalModels.requireLocal(model, session: session)
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
            if config.usesResponsesAPI {
                return try await openAIResponse(config, key: key, instructions: instructions, input: input, schema: schema)
            }
            // json_object is supported by more compatible servers than strict JSON Schema.
            var body: [String: Any] = ["model": config.model, "stream": false,
                "messages": [["role": "system", "content": instructions + "\nReturn JSON matching this schema:\n" + String(decoding: schema, as: UTF8.self)],
                             ["role": "user", "content": input]],
                "response_format": ["type": "json_object"]]
            if config.isOfficialOpenAI {
                body["max_completion_tokens"] = 4096
                body["store"] = false
            }
            let data = try await request(url: config.endpoint(), body: body, key: key)
            struct Envelope: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }; let choices: [Choice] }
            guard let content = try JSONDecoder().decode(Envelope.self, from: data).choices.first?.message.content else { throw ProviderError.malformedResponse }
            return Data(content.utf8)
        }
    }

    private func openAIResponse(_ config: APIModelConfiguration, key: String, instructions: String, input: String, schema: Data) async throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: schema) as? [String: Any] else { throw ProviderError.malformedResponse }
        let body: [String: Any] = [
            "model": config.model, "store": false, "max_output_tokens": 4096,
            "instructions": instructions, "input": input,
            "text": ["format": ["type": "json_schema", "name": "song_analysis", "strict": true,
                                "schema": Self.closedSchema(object)]]
        ]
        let data = try await request(url: config.endpoint(), body: body, key: key)
        struct Response: Decodable {
            struct Item: Decodable {
                struct Part: Decodable { let type: String; let text: String? }
                let type: String; let role: String?; let content: [Part]?
            }
            let status: String; let output: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == "completed" else {
            throw ProviderError.unavailable("OpenAIの応答が途中で終了しました。長い歌詞の行は分けてお試しください。")
        }
        let parts = response.output.filter { $0.type == "message" && $0.role == "assistant" }.flatMap { $0.content ?? [] }
        let result = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !parts.contains(where: { $0.type == "refusal" }), !result.isEmpty else { throw ProviderError.malformedResponse }
        return Data(result.utf8)
    }

    /// Responses strict mode requires closed objects with every property declared required.
    /// A field the provider schema allowed to be absent remains optional by accepting null.
    private static func closedSchema(_ node: [String: Any]) -> [String: Any] {
        var result = node
        if let properties = node["properties"] as? [String: [String: Any]] {
            let required = Set(node["required"] as? [String] ?? [])
            var fields = properties.mapValues(closedSchema)
            for (name, field) in fields where !required.contains(name) {
                fields[name] = ["anyOf": [field, ["type": "null"]]]
            }
            result["properties"] = fields
            result["required"] = properties.keys.sorted()
            result["additionalProperties"] = false
        }
        if let items = node["items"] as? [String: Any] { result["items"] = closedSchema(items) }
        return result
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
            if case .api(let config, _) = backend, config.isOfficialOpenAI {
                switch status {
                case 401: throw ProviderError.unavailable("OpenAIがAPIキーを認証できません（401）。「AI接続」でキーを確認してください。")
                case 403: throw ProviderError.unavailable("OpenAIのアクセス権がありません（403）。プロジェクトのキーでこのAPIとモデルを利用できるか確認してください。")
                case 404: throw ProviderError.unavailable("OpenAIのモデルが見つかりません（404）。モデル名とプロジェクトの利用権限を確認してください。")
                case 429:
                    let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
                    let exhausted = ["insufficient_quota", "billing_hard_limit_reached"].contains(error?["code"] as? String ?? "")
                    throw ProviderError.unavailable(exhausted
                        ? "OpenAIの利用枠に達しました（429）。API組織のクレジット残高と請求設定を確認してください。"
                        : "OpenAIの利用上限に達しました（429）。少し待ってから再試行してください。")
                default: break
                }
            }
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
