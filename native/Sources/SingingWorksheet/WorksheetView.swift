import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import SongCore
import SongServices
import SongPrint

struct WorksheetView: View {
    @Binding var file: WorksheetFile
    @Environment(\.newDocument) private var newDocument
    @State private var title = ""
    @State private var lyrics = ""
    @State private var language = "en"
    @State private var style = EnglishPronunciationStyle.american
    @State private var selected: UUID?
    @State private var editingWord: Word?
    @State private var preview: Preview?
    @State private var showAI = false
    @State private var message = ""
    @State private var selectionError: String?
    @State private var issues: [PronunciationIssue] = []
    @State private var run: Task<Void, Never>?
    @State private var runID: UUID?
    private var song: SongDocument { file.song }
    private var phrase: Phrase? { selected.flatMap(song.phrase) ?? song.phrases.first }
    private var busy: Bool { runID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if song.phrases.isEmpty { entry.disabled(busy) } else { worksheet }
            if !message.isEmpty || busy {
                Divider()
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Text(message).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if busy { Button("中止", action: cancel) }
                }.padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .tint(Color(red: 0.03, green: 0.46, blue: 0.49))
        .sheet(item: $editingWord) { word in
            WordEditor(song: song, word: word, save: revise)
        }
        .sheet(isPresented: $showAI) { OpenAISetup(lineCount: song.phrases.count, start: analyze) }
        .sheet(item: $preview) { value in PrintPreview(data: value.data) }
        .alert("教材を確認してください", isPresented: Binding(get: { selectionError != nil }, set: { if !$0 { selectionError = nil } })) {
            Button("閉じる", role: .cancel) { selectionError = nil }
        } message: { Text(selectionError ?? "") }
        .onDisappear { run?.cancel(); runID = nil }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("歌唱練習シートを作る").font(.largeTitle.bold())
            Text("歌詞を1行ずつ入力してください。空行で節が分かれます。").foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("曲名").font(.caption.weight(.semibold))
                    TextField("曲名", text: $title).textFieldStyle(.roundedBorder)
                }
                Picker("言語", selection: $language) {
                    ForEach(Syllabifier.languages) { Text($0.name).tag($0.id) }
                }.fixedSize()
                if language == "en" {
                    Picker("発音", selection: $style) {
                        ForEach(EnglishPronunciationStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.fixedSize()
                }
            }
            Text("歌詞").font(.headline)
            TextEditor(text: $lyrics).font(.system(size: 16)).padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                .accessibilityLabel("歌詞")
            HStack {
                Text("初回は端末内の規則と英語辞書で作成します。").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("教材を作成", action: generate).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(busy || lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24)
    }

    private var worksheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("曲名", text: Binding(get: { song.metadata.title }, set: { value in
                        guard value != song.metadata.title else { return }
                        revise { $0.metadata.title = String(value.prefix(200)) }
                    })).font(.title2.bold()).textFieldStyle(.plain).accessibilityLabel("教材の曲名")
                    Text("\(Syllabifier.displayName(for: song.metadata.sourceLanguage))  ·  \(song.phrases.count)行")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("OpenAIで補完…", systemImage: "sparkles") { showAI = true }.disabled(busy)
                Button("印刷プレビュー", systemImage: "doc.text.magnifyingglass") {
                    do { preview = .init(data: try PDFSheet.render(PrintSheet(song: song))) }
                    catch { selectionError = error.localizedDescription }
                }
                Menu("書き出す") {
                    Button("A4 PDF…") { export(.pdf) }
                    Button("Word文書…") { export(.docx) }
                    Button("教材データ（Web版と共有）…") { export(.json) }
                }.menuStyle(.borderedButton)
            }.padding(.horizontal, 18).padding(.vertical, 13)
            Divider()
            HSplitView {
                List(selection: $selected) {
                    ForEach(song.sections) { section in
                        Section(section.title) {
                            ForEach(section.phraseIDs, id: \.self) { id in
                                if let row = song.phrase(id) { Text(row.originalText).lineLimit(2).tag(id) }
                            }
                        }
                    }
                }.frame(minWidth: 135, idealWidth: 205, maxWidth: 300)
                ScrollView {
                    if let phrase { editableLine(phrase) }
                }.frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = song.phrases.first?.id } }
        .toolbar {
            Button("新しい教材", systemImage: "doc.badge.plus") { newDocument(WorksheetFile()) }
        }
    }

    private func editableLine(_ phrase: Phrase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(phrase.originalText).font(.system(size: 25, weight: .medium, design: .serif))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            TextField("この行の日本語訳", text: Binding(get: { song.phrase(phrase.id)?.translation.value ?? "" }, set: { value in
                guard let i = song.phrases.firstIndex(where: { $0.id == phrase.id }),
                      song.phrases[i].translation.value != value else { return }
                revise { $0.phrases[i].translation.edit(value) }
            }), axis: .vertical).textFieldStyle(.roundedBorder)
            Divider().padding(.vertical, 2)
            Text("単語を選ぶと音節・読み・訳を編集できます。").font(.callout).foregroundStyle(.secondary)
            ForEach(song.words(in: phrase)) { word in
                Button { editingWord = word } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            wordText(word, language: song.language(of: phrase))
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                        let pronunciation = song.selectedPronunciation(for: word)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if !pronunciation.reading.isEmpty { Text(pronunciation.reading) }
                            if !pronunciation.ipa.isEmpty { Text("/" + pronunciation.ipa + "/").foregroundStyle(.secondary) }
                            if !word.contextualMeaning.value.isEmpty { Text(word.contextualMeaning.value) }
                        }.font(.callout)
                        if let issue = issues.first(where: { $0.wordID == word.id }) {
                            Text(issue.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(word.surface + "を編集")
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func wordText(_ word: Word, language: String) -> Text {
        let syllables = song.syllables(in: word).map { PrintSyllable(text: $0.text.value, language: language) }
        let printed = PrintWord(original: word.surface, meaning: "", syllables: syllables, ipa: "", reading: "")
        var text = AttributedString()
        for fragment in printed.displayFragments {
            var piece = AttributedString(fragment.text)
            if fragment.isColored { piece.foregroundColor = .teal }
            text.append(piece)
        }
        return Text(text).font(.system(size: 18, weight: .semibold))
    }

    @discardableResult
    private func revise(_ mutation: (inout SongDocument) throws -> Void) -> Bool {
        do {
            file.song = try song.editing(mutation)
            return true
        } catch {
            selectionError = error.localizedDescription
            return false
        }
    }

    private func generate() {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SongGenerationRequest(title: label.isEmpty ? "歌唱練習シート" : label,
            sourceLanguage: language, lyrics: lyrics, englishPronunciation: language == "en" ? style : nil)
        let id = UUID()
        runID = id; message = "端末内で音節を解析しています。"
        run = Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) { try request.makeDocument() }.value
                guard !Task.isCancelled, runID == id else { return }
                file.song = result; selected = result.phrases.first?.id
                message = "教材を作成しました。単語を選んで読みや訳を確認できます。"
            } catch { if runID == id { selectionError = error.localizedDescription; message = "" } }
            if runID == id { runID = nil; run = nil }
        }
    }

    private func analyze(key: String) {
        guard !busy else { return }
        var config = APIModelConfiguration(); config.enabled = true
        let client = ModelClient(.api(config, key: key))
        let ids = song.phrases.map(\.id), id = UUID()
        runID = id; issues = []; message = "OpenAIに接続しています。"
        run = Task { @MainActor in
            defer { if runID == id { run = nil; runID = nil } }
            let progress: (String) -> Void = { if runID == id { message = $0 } }
            do {
                let held = try await OpenAILyricPronunciation.run(phraseIDs: ids, client: client,
                    current: { file.song }, apply: { result, original, phraseID in
                        guard runID == id else { return }
                        revise { OpenAILyricPronunciation.merge(result, from: original, phraseID: phraseID, into: &$0) }
                    }, progress: progress)
                try Task.checkCancellation()
                guard runID == id else { return }
                issues = held
                try await MeaningCompletion.run(phraseIDs: ids, providers: [ModelAnalysisProvider(client: client)],
                    current: { file.song }, apply: { result, original, phraseID in
                        guard runID == id else { return }
                        revise { MeaningCompletion.merge(result, from: original, phraseID: phraseID, into: &$0) }
                    }, progress: progress)
                if runID == id {
                    message = held.isEmpty ? "補完が終了しました。読みと訳を確認してください。" : "補完が終了しました。発音・音節の要確認は\(held.count)語です。"
                }
            } catch {
                if runID == id { message = "補完を終了しました。" + error.localizedDescription }
            }
        }
    }

    private func cancel() {
        run?.cancel(); run = nil; runID = nil; message = "中止しました。反映済みの内容は保存できます。"
    }

    private enum Format: String { case pdf, docx, json }
    private func export(_ format: Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
        let safeTitle = song.metadata.title.replacingOccurrences(of: "/", with: "／").replacingOccurrences(of: ":", with: "：")
        panel.nameFieldStringValue = safeTitle + "." + format.rawValue
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch format {
            case .pdf: data = try PDFSheet.render(PrintSheet(song: song))
            case .docx: data = try WordSheet.render(PrintSheet(song: song))
            case .json: data = try song.encoded()
            }
            try data.write(to: url, options: .atomic)
            message = url.lastPathComponent + " を書き出しました。"
        } catch { selectionError = error.localizedDescription }
    }
}

private struct Preview: Identifiable {
    let id = UUID()
    let data: Data
}

private struct PrintPreview: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("A4 印刷プレビュー").font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            PDFPreview(data: data)
        }.frame(minWidth: 500, idealWidth: 620, minHeight: 380, idealHeight: 610)
    }
}

private struct PDFPreview: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(data: data); view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}
