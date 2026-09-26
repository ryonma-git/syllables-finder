import SwiftUI
import SongCore
import SongServices

struct AnalysisSheet: View {
    let song: SongDocument
    let phrase: Phrase
    let apply: (SongDocument) -> Void
    let currentSong: () -> SongDocument
    @Environment(\.dismiss) private var dismiss
    @State private var providers: [any AIProvider] = [MockAIProvider()]
    @State private var selected = "mock"
    @State private var status = "手修正した意味・全文訳は保持します。音節の分割は変更しません。"
    @State private var working = false
    @State private var task: Task<Void, Never>?
    private func key(_ provider: any AIProvider) -> String { provider.id + (provider.source.model ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("意味を解析", systemImage: "sparkles").font(.title2.bold())
            Text(phrase.originalText).font(.title3)
            Picker("解析方法", selection: $selected) {
                ForEach(providers.indices, id: \.self) { index in
                    let provider = providers[index]
                    Text(provider.displayName + (provider.source.model.map { " · " + $0 } ?? "")).tag(key(provider))
                }
            }.disabled(working)
            Button("このMacのOllamaモデルを確認") {
                working = true
                task = Task { @MainActor in
                    defer { working = false }
                    do {
                        let models = try await OllamaProvider.models()
                        try Task.checkCancellation()
                        providers = [MockAIProvider()] + models.map { OllamaProvider(model: $0) as any AIProvider }
                        selected = "mock"
                        status = models.isEmpty ? "Ollamaにモデルがありません。モデルの追加はOllamaで行ってください。" : "モデルを選んで解析できます。歌詞はこのMacのOllamaに渡されます。"
                    } catch is CancellationError { status = "キャンセルしました。" }
                    catch { status = "Ollamaに接続できません。起動状態を確認してください。" }
                }
            }.disabled(working)
            Text("対象は選択中のフレーズだけです。クラウドへの送信は行いません。").font(.caption).foregroundStyle(.secondary)
            if working { ProgressView().controlSize(.small) }
            Text(status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(working ? "キャンセル" : "閉じる", role: .cancel) { task?.cancel(); dismiss() }
                Spacer()
                Button("解析して適用") { analyze() }.buttonStyle(.borderedProminent).disabled(working)
            }
        }.padding(28).frame(width: 490).onDisappear { task?.cancel() }
    }
    private func analyze() {
        guard let provider = providers.first(where: { key($0) == selected }) else { return }
        let request = LinguisticAnalysisRequest(document: song, phrase: phrase)
        working = true
        task = Task { @MainActor in
            defer { working = false }
            do {
                let analysis = try await provider.analyze(request: request)
                try Task.checkCancellation()
                let next = try LinguisticAnalysisService().apply(analysis, request: request, source: provider.source, to: currentSong())
                apply(next); dismiss()
            } catch is CancellationError { status = "キャンセルしました。" }
            catch { status = error.localizedDescription }
        }
    }
}
