import SwiftUI
import AppKit
import SongCore
import SongServices

struct PronunciationReviewSheet: View {
    let song: SongDocument
    @ObservedObject var settings: ModelSettings
    let saveReviews: (SongDocument, [UUID: PronunciationReview.Result]) -> Void
    let edit: (PronunciationAudit.Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pronunciationReviewModel.v1") private var selection = "automatic"
    @State private var entries: [PronunciationAudit.Entry] = []
    @State private var clients: [ModelClient] = []
    @State private var results: [UUID: PronunciationReview.Result] = [:]
    @State private var task: Task<Void, Never>?
    @State private var runID: UUID?
    @State private var scanning = false
    @State private var message = ""
    @State private var onlyConcerns = false

    private var visibleEntries: [PronunciationAudit.Entry] {
        entries.filter { !onlyConcerns || $0.status != .matched || results[$0.id]?.verdict == .review || results[$0.id]?.verdict == .uncertain }
    }
    private var selectedClients: [ModelClient] {
        selection == "dictionary" ? [] : selection == "automatic" ? clients : clients.filter { PronunciationReview.selectionID($0) == selection }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("発音をチェック").font(.title2.bold())
            Text("辞書照合とAIの見解を別々に表示します。歌詞・IPA・読みは変更せず、閉じると検証結果を保存します。")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("検証用AI", selection: $selection) {
                    Text("自動（別モデル優先）").tag("automatic")
                    Text("辞書のみ").tag("dictionary")
                    ForEach(clients, id: \.label) { client in
                        Text(client.label).tag(PronunciationReview.selectionID(client))
                    }
                    if !["automatic", "dictionary"].contains(selection), !clients.contains(where: { PronunciationReview.selectionID($0) == selection }) {
                        Text("選択したAIは現在利用できません").tag(selection)
                    }
                }.disabled(runID != nil || scanning)
                Button("AIを再検索") { scan() }.disabled(runID != nil || scanning)
                Button("AIでチェック") { start() }
                    .disabled(runID != nil || scanning || selectedClients.isEmpty || entries.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            Text("生成用AIの設定は変わりません。自動では別モデルを優先し、使えなければ同じモデルで再確認します。AIの回答は正しさの保証ではなく、録音との照合は行いません。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(song.metadata.englishPronunciationStyle.label) · 辞書一致 \(entries.filter { $0.status == .matched }.count)語 / 要確認・未照合 \(entries.filter { $0.status != .matched }.count)語")
                    .font(.callout)
                Spacer()
                Toggle("要確認・未照合のみ", isOn: $onlyConcerns).toggleStyle(.checkbox)
            }
            if scanning || runID != nil { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleEntries) { entry in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.surface).font(.headline)
                                    if entry.manuallyEdited { Text("手修正あり").font(.caption) }
                                    Spacer()
                                    Text(entry.status.label).font(.caption).foregroundStyle(entry.status == .matched ? Color.secondary : Color.orange)
                                    Button("単語を開く") { edit(entry) }.disabled(runID != nil)
                                }
                                Text(entry.context).font(.caption).foregroundStyle(.secondary)
                                Text("現在のIPA：\(entry.ipa.joined(separator: " · "))　読み：\(entry.readings.joined(separator: "・"))")
                                    .textSelection(.enabled)
                                if !entry.dictionaryIPA.isEmpty {
                                    Text("辞書候補：" + entry.dictionaryIPA.joined(separator: " / ")).font(.callout).textSelection(.enabled)
                                }
                                ForEach(entry.issues, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
                                let sources = Set(entry.aiSources.map { ($0.provider ?? "不明") + " · " + ($0.model ?? "モデル不明") }).sorted()
                                Text("発音の生成元：" + (sources.isEmpty ? "辞書・手入力など（AI生成元の記録なし）" : sources.joined(separator: "、")))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let result = results[entry.id] {
                                    Text("\(result.reviewer) · \(result.kind.label) · \(verdictLabel(result.verdict))").font(.callout.bold())
                                    Text(result.explanation).font(.callout).textSelection(.enabled)
                                    if !result.expectedIPA.isEmpty {
                                        Text("AIの発音候補：\(result.expectedIPA)").font(.callout).textSelection(.enabled)
                                    }
                                } else { Text("AI：未検証").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                }.padding(.trailing, 8)
            }
            Divider()
            HStack {
                Text("辞書との相違には、別の発音・弱形・歌唱上の区切りも含まれます。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if runID != nil { Button("検証を中止") { cancel(); message = "中止しました。未検証の語が残っています。" } }
                Button("閉じる") { cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(22)
            .frame(width: min(880, (NSScreen.main?.visibleFrame.width ?? 1100) - 80),
                   height: min(700, (NSScreen.main?.visibleFrame.height ?? 850) - 120))
            .onAppear { reload(); scan() }
            .onDisappear { cancel(); saveReviews(song, results) }
            .onChange(of: song) { _, _ in reload(); message = "内容が変わったため、AI検証結果を取り消しました。再確認してください。" }
            .onChange(of: selection) { _, _ in
                cancel(); results = [:]; message = "検証先を変更しました。AIでチェックを押すと実行します。"
            }
            .onChange(of: settings.preferences) { _, _ in cancel(); results = [:]; scan() }
    }
    private func verdictLabel(_ verdict: PronunciationReview.Result.Verdict) -> String {
        switch verdict { case .ok: "AIの指摘なし"; case .review: "AIも要確認"; case .uncertain: "判断保留・未検証" }
    }
    private func reload() { cancel(); entries = PronunciationAudit.entries(in: song); results = [:] }
    private func cancel() { task?.cancel(); task = nil; runID = nil; scanning = false }
    private func scan() {
        cancel(); scanning = true
        task = Task { @MainActor in
            let found = await settings.reviewClients()
            guard !Task.isCancelled else { return }
            clients = found; scanning = false
            message = clients.isEmpty ? "利用できるAIがありません。辞書照合は完了しています。接続は「AI接続」で設定できます。" : "\(clients.count)件の検証先を検出しました。実行時に応答と生成元との違いを確認します。"
        }
    }
    private func start() {
        cancel(); results = [:]
        let id = UUID(), snapshot = song, available = selectedClients
        runID = id
        task = Task { @MainActor in
            do {
                try await PronunciationReview.run(document: snapshot, clients: available, update: { word, result in
                    if runID == id { results[word] = result }
                }, progress: { value in if runID == id { message = value } })
                if runID == id {
                    let reviewed = results.values.filter { $0.verdict == .review }.count
                    let uncertain = results.values.filter { $0.verdict == .uncertain }.count
                    message = "AI検証終了：要確認 \(reviewed)語、判断保留・未検証 \(uncertain)語。辞書照合の指摘は下欄に保持しています。"
                    runID = nil
                }
            } catch {
                if runID == id { message = "検証を完了できませんでした。\(error.localizedDescription)"; runID = nil }
            }
        }
    }
}
