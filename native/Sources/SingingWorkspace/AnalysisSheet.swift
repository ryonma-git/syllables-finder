import SwiftUI
import SongCore
import SongServices

struct AnalysisSheet: View {
    let song: SongDocument
    let phrase: Phrase
    let apply: (SongDocument) -> Void
    let currentSong: () -> SongDocument
    @EnvironmentObject private var modelSettings: ModelSettings
    @Environment(\.dismiss) private var dismiss
    @State private var clients: [ModelClient] = []
    @State private var selected = "automatic"
    @State private var status = "手修正した意味・全文訳は保持します。音節の分割は変更しません。"
    @State private var working = false
    @State private var task: Task<Void, Never>?
    @State private var showingModels = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("意味を解析", systemImage: "sparkles").font(.title2.bold())
            ScrollView { Text(phrase.originalText).font(.title3).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
            Picker("解析方法", selection: $selected) {
                Text("設定した優先順で自動").tag("automatic")
                Text("Macの辞書で単語を調べる").tag("dictionary")
                ForEach(clients.indices, id: \.self) { index in Text(clients[index].label).tag(clients[index].label) }
            }.disabled(working)
            Button("AI接続と辞書の設定…") { showingModels = true }.disabled(working)
            Text("対象は選択中の1行です。外部APIはAI接続で送信を許可した場合だけ使います。辞書モードでは全文訳は作成しません。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if working { ProgressView().controlSize(.small) }
            Text(status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(working ? "キャンセル" : "閉じる", role: .cancel) { task?.cancel(); dismiss() }
                Spacer()
                Button("解析して適用") { analyze() }.buttonStyle(.borderedProminent).disabled(working)
            }
        }.padding(24).frame(width: 540)
            .task { await refresh() }
            .sheet(isPresented: $showingModels, onDismiss: { task = Task { await refresh() } }) { ModelConnectionSheet(settings: modelSettings) }
            .onDisappear { task?.cancel() }
    }
    @MainActor private func refresh() async {
        working = true
        clients = ModelDiscovery.forMeanings(await modelSettings.clients(), mode: modelSettings.preferences.mode)
        working = false
    }
    private func analyze() {
        let request = LinguisticAnalysisRequest(document: song, phrase: phrase)
        working = true
        task = Task { @MainActor in
            defer { working = false }
            do {
                let current = currentSong()
                guard current.id == request.documentID, current.revision == request.revision else { throw SongError.staleAnalysis }
                let candidates = selected == "automatic" ? clients : clients.filter { $0.label == selected }
                if selected == "dictionary" || candidates.isEmpty {
                    var count = 0
                    let next = try current.editing { count = DictionaryLookup.apply(to: &$0, phraseIDs: [phrase.id]) }
                    if count > 0 { apply(next); status = "\(count)語の辞書定義を追加しました。単語の詳細で確認できます。" }
                    else { status = "追加できる辞書定義がありません。Macの辞書の有効状態を確認してください。" }
                    return
                }
                var failure: Error = ProviderError.unavailable("利用できるAIがありません。")
                for client in candidates {
                    do {
                        status = client.label + "で解析中…"
                        let provider = ModelAnalysisProvider(client: client)
                        let analysis = try await provider.analyze(request: request)
                        try Task.checkCancellation()
                        let next = try LinguisticAnalysisService().apply(analysis, request: request, source: provider.source, to: currentSong())
                        apply(next); dismiss(); return
                    } catch is CancellationError { throw CancellationError() }
                    catch { failure = error }
                }
                let latest = currentSong()
                guard latest.id == request.documentID, latest.revision == request.revision else { throw SongError.staleAnalysis }
                var count = 0
                let next = try latest.editing { count = DictionaryLookup.apply(to: &$0, phraseIDs: [phrase.id]) }
                if count > 0 { apply(next) }
                status = "AIで解析できなかったため、辞書定義を\(count)語追加しました。全文訳は変更していません。" + failure.localizedDescription
            } catch { status = Task.isCancelled ? "キャンセルしました。" : error.localizedDescription }
        }
    }
}
