import Foundation

/// Loopback is a transport address, not proof that Ollama will run a model on this Mac.
/// Ollama's /api/show and /api/tags expose remote_host/remote_model for remote aliases:
/// https://github.com/ollama/ollama/blob/main/api/types.go
public enum OllamaLocalModels {
    public struct Inventory: Sendable {
        public let local: [String]
        public let excluded: [String]
    }

    private struct Metadata: Decodable {
        struct Details: Decodable { let format: String? }
        struct ModelInfo: Decodable {
            let architecture: String?
            let parameterCount: Double?
            enum CodingKeys: String, CodingKey {
                case architecture = "general.architecture", parameterCount = "general.parameter_count"
            }
        }
        let remote_host: String?
        let remote_model: String?
        let details: Details?
        let model_info: ModelInfo?

        var hasLocalWeights: Bool {
            guard (remote_host ?? "").isEmpty, (remote_model ?? "").isEmpty,
                  let format = details?.format?.lowercased(), ["gguf", "safetensors"].contains(format),
                  let architecture = model_info?.architecture, !architecture.isEmpty,
                  let count = model_info?.parameterCount, count.isFinite, count > 0 else { return false }
            return true
        }
    }

    private static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request, delegate: NoOllamaRedirect())
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else {
            throw ProviderError.unavailable("Ollamaのモデル情報を確認できませんでした。接続状態を確認してください。")
        }
        return data
    }

    /// Run immediately before inference as well as discovery, so a saved model name is not a bypass.
    /// This request contains only the model name; no lyrics, pronunciation or translation are sent.
    public static func requireLocal(_ model: String, session: URLSession = .shared) async throws {
        try Task.checkCancellation()
        guard !model.isEmpty else { throw ProviderError.unavailable("ローカルモデルを選択してください。") }
        // Explicit cloud routing can make /show itself proxy to the upstream model.
        // Name checks are only an early rejection; ordinary aliases still require metadata below.
        let name = model.lowercased()
        guard !name.hasSuffix("@cloud"), !name.hasSuffix(":cloud"), !name.hasSuffix("-cloud") else {
            throw ProviderError.unavailable("Ollamaのクラウドモデルは使用しません。外部AIには送信を許可したAPI接続を使ってください。")
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/show")!)
        request.httpMethod = "POST"; request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        let response = try await data(for: request, session: session)
        let metadata = try JSONDecoder().decode(Metadata.self, from: response)
        guard metadata.hasLocalWeights else {
            throw ProviderError.unavailable("このMacで実行するモデルと確認できないため、\(model)へ歌詞を送信しません。Ollamaのクラウドモデルは対象外です。外部AIには送信を許可したAPI接続を使ってください。")
        }
    }

    public static func inventory(session: URLSession = .shared) async throws -> Inventory {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 5
        struct List: Decodable {
            struct Model: Decodable { let name: String; let remote_host: String?; let remote_model: String? }
            let models: [Model]
        }
        let response = try await data(for: request, session: session)
        let list = try JSONDecoder().decode(List.self, from: response)
        var local: [String] = [], excluded: [String] = []
        for model in list.models.sorted(by: { $0.name < $1.name }) {
            try Task.checkCancellation()
            guard (model.remote_host ?? "").isEmpty, (model.remote_model ?? "").isEmpty else {
                excluded.append(model.name); continue
            }
            do {
                try await requireLocal(model.name, session: session)
                local.append(model.name)
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation(); excluded.append(model.name) }
        }
        return Inventory(local: Array(Set(local)).sorted(), excluded: Array(Set(excluded)).sorted())
    }
}

final class NoOllamaRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
