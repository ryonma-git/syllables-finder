import Foundation

public enum OllamaModelDownload {
    @MainActor
    public static func run(model: String, session: URLSession = .shared, progress: (String) -> Void) async throws {
        guard !model.isEmpty, model.count < 120, model.allSatisfy({ $0.isLetter || $0.isNumber || ":._-/".contains($0) }) else {
            throw ProviderError.unavailable("モデル名を確認してください。")
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/pull")!)
        request.httpMethod = "POST"; request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProviderError.unavailable("Ollamaでモデルを追加できませんでした。") }
        struct Status: Decodable { let status: String?; let completed: Double?; let total: Double?; let error: String? }
        var success = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.utf8.count < 10_000 else { throw ProviderError.malformedResponse }
            let value = try JSONDecoder().decode(Status.self, from: Data(line.utf8))
            if value.error != nil { throw ProviderError.unavailable("モデルをダウンロードできませんでした。モデル名と通信を確認してください。") }
            if let completed = value.completed, let total = value.total, total > 0 {
                progress("ダウンロード中 \(Int(completed / total * 100))%")
            } else { progress(value.status == "success" ? "ダウンロード完了" : "モデルを準備中…") }
            success = success || value.status == "success"
        }
        guard success else { throw ProviderError.unavailable("ダウンロードの完了を確認できませんでした。再確認してください。") }
    }
}
