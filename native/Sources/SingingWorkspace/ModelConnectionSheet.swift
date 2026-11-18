import SwiftUI
import SongServices

struct ModelConnectionSheet: View {
    @ObservedObject var settings: ModelSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ModelPreferences()
    @State private var key = ""
    @State private var models: [String] = []
    @State private var appleStatus = ModelClient.appleAvailability.message
    @State private var localStatus = "未確認"
    @State private var apiStatus = "未確認"
    @State private var message = ""
    @State private var downloadModel = "qwen3.5:9b"
    @State private var confirmDownload = false
    @State private var task: Task<Void, Never>?
    @State private var working = false
    @State private var ollamaReachable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("AI接続と辞書", systemImage: "cpu").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("優先する方法", selection: $draft.mode) {
                        ForEach(ModelPreferences.Mode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text("自動では発音はAppleFM優先、意味・訳は導入済みQwen 3.5を優先します。使えない場合は他のローカルAI、送信を許可したAPIの順で試します。")
                        .font(.caption).foregroundStyle(.secondary)
                    apiSettings
                    GroupBox("AppleFM · このMacのApple Intelligence") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appleStatus).font(.callout)
                            Button("AppleFMの応答をテスト") { test(ModelClient(.apple), target: .apple) }
                                .disabled(working || !ModelClient.appleAvailability.available)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("このMacのローカルLLM · Ollama") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localStatus).font(.callout)
                            Text("このMacでの実行を確認できたモデルだけを使います。Ollamaのクラウドモデル・実行先が不明なモデルは使いません。外部AIは下のAPIで送信を許可してください。")
                                .font(.caption).foregroundStyle(.secondary)
                            Picker("モデル", selection: $draft.localModel) {
                                Text("自動選択（Qwen優先）").tag("")
                                ForEach(models, id: \.self) { Text($0).tag($0) }
                            }
                            HStack {
                                Button("モデルを探す") { scan() }.disabled(working)
                                Button("選択モデルの応答をテスト") {
                                    if let model = selectedLocal { test(ModelClient(.ollama(model)), target: .local) }
                                }.disabled(working || selectedLocal == nil)
                                Link("Ollamaの入手", destination: URL(string: "https://ollama.com/download/mac")!)
                            }
                            HStack {
                                TextField("追加するモデル名", text: $downloadModel).textFieldStyle(.roundedBorder)
                                Button("モデルを追加…") { confirmDownload = true }.disabled(working || !ollamaReachable)
                            }
                            Text("追加は任意です。ダウンロード容量と実行メモリはモデルによって異なります。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(6)
                    }
                    GroupBox("辞書のみでも使えます") {
                        Text("内蔵の英語発音辞書と、このMacで有効な辞書を使います。辞書にない読みは未設定として残し、単語の定義と全文翻訳を区別します。")
                            .font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }.padding(.trailing, 8)
            }
            if working { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(working ? "中止" : "閉じる") { task?.cancel(); if !working { dismiss() } }
                Spacer()
                Button("設定を保存") {
                    do { try settings.save(draft, newKey: key); key = ""; dismiss() }
                    catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(working)
            }
        }.padding(22).frame(width: 650, height: min(720, (NSScreen.main?.visibleFrame.height ?? 850) - 120))
            .onAppear { draft = settings.preferences; scan() }
            .onDisappear { task?.cancel(); key = "" }
            .confirmationDialog("\(downloadModel)をこのMacに追加しますか？", isPresented: $confirmDownload) {
                Button("ダウンロードして追加") { download() }
            } message: { Text("Ollamaがモデルをダウンロードします。数GB以上の空き容量が必要な場合があります。既存モデルは削除しません。") }
    }
    private var apiSettings: some View {
        GroupBox("OpenAI・互換API") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("OpenAIを優先する") {
                        let sameProvider = draft.api.isOfficialOpenAI
                        if !sameProvider { key = "" }
                        let wasEnabled = sameProvider && draft.api.enabled
                        draft.api = APIModelConfiguration()
                        draft.api.enabled = wasEnabled
                        draft.mode = .api
                        apiStatus = "未確認"
                    }
                    Text(draft.api.isOfficialOpenAI ? "OpenAI · " + draft.api.model : draft.api.model)
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("OpenAIを優先すると、歌詞を行ごとに送信し、文脈に沿って音節・発音・カタカナ読みを取得します。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("接続先・モデルを変更") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("ベースURL（末尾 /v1）", text: Binding(get: { draft.api.baseURL }, set: { url in
                            guard draft.api.baseURL != url else { return }
                            draft.api.baseURL = url
                            draft.api.enabled = false
                            key = ""; apiStatus = "未確認"
                        })).textFieldStyle(.roundedBorder)
                        TextField("モデル名", text: $draft.api.model).textFieldStyle(.roundedBorder)
                        if draft.api.isOfficialOpenAI {
                            Picker("OpenAIの接続方式", selection: Binding(get: { draft.api.openAITransport ?? .chatCompletions },
                                                                    set: { draft.api.openAITransport = $0 })) {
                                Text("Responses API").tag(APIModelConfiguration.OpenAITransport.responses)
                                Text("Chat Completions").tag(APIModelConfiguration.OpenAITransport.chatCompletions)
                            }
                        }
                    }.padding(.top, 4)
                }
                SecureField("APIキー（設定済みなら空欄）", text: $key).textFieldStyle(.roundedBorder)
                Text("入力したキーはこのMacのキーチェーンに保存します。API利用料はキーを発行した組織に計上されます。配布先の方はご自身のキーで利用できます。")
                    .font(.caption).foregroundStyle(.secondary)
                if draft.api.isOfficialOpenAI {
                    Text("対象プランのAPIクレジットを有効化した方は、連携したOpenAI組織のプロジェクトキーを使えます。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Link("APIキーを管理", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        Link("クレジット残高を確認", destination: URL(string: "https://platform.openai.com/settings/organization/billing/credit-grants")!)
                    }.font(.caption)
                }
                Toggle("このAPIへの歌詞送信を許可する", isOn: $draft.api.enabled)
                HStack {
                    Button("APIの応答をテスト") { testAPI() }.disabled(working || !draft.api.enabled)
                    Text(apiStatus).font(.callout)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
    private var selectedLocal: String? {
        models.contains(draft.localModel) ? draft.localModel : PronunciationCompletion.model(from: models) ?? models.first
    }
    private enum Target { case apple, local, api }
    private func test(_ client: ModelClient, target: Target) {
        working = true; message = "歌詞を含まない短い応答テストを実行中…"
        task = Task { @MainActor in
            defer { working = false }
            let result: String
            do { try await client.probe(); try Task.checkCancellation(); result = "応答テスト成功 · " + client.label }
            catch { result = Task.isCancelled ? "中止しました" : "応答テスト失敗：" + error.localizedDescription }
            switch target { case .apple: appleStatus = result; case .local: localStatus = result; case .api: apiStatus = result }
            message = "接続確認は発音・翻訳の正しさを保証するものではありません。"
        }
    }
    private func testAPI() {
        do {
            _ = try draft.api.endpoint()
            let typedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = typedKey.isEmpty ? try settings.apiKey(for: draft.api) : typedKey
            test(ModelClient(.api(draft.api, key: apiKey)), target: .api)
        } catch { apiStatus = error.localizedDescription }
    }
    private func scan() {
        working = true; appleStatus = ModelClient.appleAvailability.message
        task = Task { @MainActor in
            defer { working = false }
            do {
                let inventory = try await OllamaLocalModels.inventory(); try Task.checkCancellation()
                models = inventory.local
                ollamaReachable = true
                localStatus = "接続済み · このMacで使えるモデル \(models.count)件（応答テストは未実行）"
                if !inventory.excluded.isEmpty { localStatus += "。クラウド・実行先未確認 \(inventory.excluded.count)件は除外しました。" }
                if !models.contains(draft.localModel) { draft.localModel = "" }
            } catch {
                ollamaReachable = false; models = []
                localStatus = "Ollamaに接続できません。未導入、または起動していない可能性があります。"
            }
        }
    }
    private func download() {
        working = true
        task = Task { @MainActor in
            do {
                try await OllamaModelDownload.run(model: downloadModel) { message = $0 }
                let inventory = try await OllamaLocalModels.inventory(); try Task.checkCancellation()
                models = inventory.local
                if models.contains(downloadModel) { draft.localModel = downloadModel }
                localStatus = "このMacで使えるモデル \(models.count)件。応答テストで確認できます。"
                if !inventory.excluded.isEmpty { localStatus += "クラウド・実行先未確認 \(inventory.excluded.count)件は除外しました。" }
            } catch { message = Task.isCancelled ? "ダウンロードを中止しました。" : error.localizedDescription }
            working = false
        }
    }
}
