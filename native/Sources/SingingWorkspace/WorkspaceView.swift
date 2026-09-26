import SwiftUI
import SongCore
import SongServices

enum WorkspaceMode: String, CaseIterable { case reading = "読む", singing = "歌う" }

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var mode = WorkspaceMode.reading
    @Published var phraseID: UUID?
    @Published var wordID: UUID?
    @Published var syllableID: UUID?
    @Published var eventID: UUID?
    @Published var showInspector = false
    @Published var showNotes = false
    @Published var isPlaying = false
    @Published var loop = true
    @Published var position = 0.0
    @Published var bpm = 88.0
    @Published var error: String?
    @Published var textScale = 1.0

    func replace(_ next: SongDocument, in binding: Binding<SongFile>, undo: UndoManager?, name: String) {
        let previous = binding.wrappedValue.song
        var next = next
        guard previous.revision < UInt64.max else { error = "編集回数が上限に達しました。"; return }
        // Undo also advances revision, preventing stale asynchronous results after a restore.
        next.revision = previous.revision + 1
        undo?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.replace(previous, in: binding, undo: undo, name: name) }
        }
        undo?.setActionName(name)
        binding.wrappedValue.song = next
    }
    func select(_ phrase: Phrase) {
        phraseID = phrase.id; wordID = nil; syllableID = nil; eventID = nil
        isPlaying = false; position = phrase.timeRange?.start.doubleValue ?? 0
    }
}

struct WorkspaceView: View {
    @Binding var file: SongFile
    @StateObject private var session = WorkspaceSession()
    @Environment(\.undoManager) private var undoManager
    @State private var addingLyrics = false
    @State private var showAnalysis = false
    @State private var input = ""
    private var song: SongDocument { file.song }
    private var phrase: Phrase? { session.phraseID.flatMap { song.phrase($0) } ?? song.phrases.first }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 185, ideal: 215, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let phrase {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            phraseHeader(phrase)
                            if session.mode == .reading {
                                ReadingView(song: song, phrase: phrase, session: session)
                            } else {
                                SingingView(song: song, phrase: phrase, session: session)
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        if session.showInspector {
                            Divider()
                            WordInspector(song: song, wordID: session.wordID, mutate: mutate).frame(width: 275)
                        }
                    }
                    if session.showNotes && session.mode == .singing {
                        Divider()
                        NoteEditor(song: song, phrase: phrase, session: session, mutate: mutate).frame(height: 175)
                    }
                    Divider()
                    if session.mode == .singing { transport(phrase) }
                    else {
                        HStack {
                            Label("単語を選ぶと、意味や発音を編集できます", systemImage: "hand.tap")
                            Spacer()
                            Text("読みは原音の近似です")
                        }.font(.caption).foregroundStyle(.secondary).padding(16)
                    }
                } else { welcome }
            }.background(Color(nsColor: .textBackgroundColor))
        }
        .tint(.teal).frame(minWidth: 900, minHeight: 650)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("表示モード", selection: $session.mode) {
                    ForEach(WorkspaceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 160)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("歌詞を追加…", systemImage: "text.badge.plus") { addingLyrics = true }
                    Button("意味を解析…", systemImage: "sparkles") { showAnalysis = true }.disabled(phrase == nil)
                    Divider()
                    Button("文字を大きく") { session.textScale = min(1.5, session.textScale + 0.1) }
                    Button("文字を小さく") { session.textScale = max(0.9, session.textScale - 0.1) }
                } label: { Label("その他", systemImage: "ellipsis.circle") }
                Button { session.showInspector.toggle() } label: { Label("単語の詳細", systemImage: "sidebar.right") }
                    .help("単語の詳細を表示・非表示")
            }
        }
        .onAppear {
            if session.phraseID == nil, let phrase { session.select(phrase) }
            session.bpm = song.music.tempos.first?.bpm ?? 88
        }
        .onChange(of: session.mode) { _, _ in session.isPlaying = false }
        .onChange(of: song.revision) { _, _ in
            if let id = session.eventID, song.event(id) == nil { session.eventID = nil }
            if let id = session.wordID, song.word(id) == nil { session.wordID = nil }
        }
        .task(id: session.isPlaying) {
            guard session.isPlaying, let range = phrase?.timeRange else { return }
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled && session.isPlaying {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                session.position += (now - last) * session.bpm / 60
                last = now
                if session.position >= range.end.doubleValue {
                    if session.loop { session.position = range.start.doubleValue + (session.position - range.start.doubleValue).truncatingRemainder(dividingBy: range.length) }
                    else { session.position = range.end.doubleValue; session.isPlaying = false }
                }
            }
        }
        .onDisappear { session.isPlaying = false }
        .sheet(isPresented: $addingLyrics) { lyricsSheet }
        .sheet(isPresented: $showAnalysis) {
            if let phrase {
                AnalysisSheet(song: song, phrase: phrase, apply: { next in
                    session.replace(next, in: $file, undo: undoManager, name: "解析結果を適用")
                }, currentSong: { file.song })
            }
        }
        .alert("変更を適用できませんでした", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK", role: .cancel) { session.error = nil }
        } message: { Text(session.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("SINGING WORKSPACE", systemImage: "waveform")
                .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.4)
                .foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 24)
            TextField("曲名", text: Binding(get: { file.song.metadata.title }, set: { value in
                mutate("曲名を編集") { $0.metadata.title = value }
            }))
                .textFieldStyle(.plain).font(.title2.bold()).padding(.horizontal, 18).padding(.top, 12)
                .accessibilityLabel("曲名")
            Text("歌詞から、声へ。").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.top, 5)
            List(selection: Binding(get: { phrase?.id }, set: { id in
                if let id, let selected = song.phrase(id) { session.select(selected) }
            })) {
                ForEach(song.sections) { section in
                    SwiftUI.Section(section.title) {
                        ForEach(section.phraseIDs.compactMap { song.phrase($0) }) { phrase in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(phrase.originalText).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                Text(phrase.translation.value.isEmpty ? "訳を追加できます" : phrase.translation.value)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 7).tag(phrase.id)
                        }
                    }
                }
            }.listStyle(.sidebar).padding(.top, 20)
            Button { addingLyrics = true } label: { Label("歌詞を追加", systemImage: "plus") }
                .buttonStyle(.plain).foregroundStyle(.teal).padding(18)
            Divider()
            Label("このMacに保存", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary).padding(18)
        }
    }

    private func phraseHeader(_ phrase: Phrase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.mode == .reading ? "ことばを読む" : "声をのせる場所を確かめる")
                    .font(.caption.weight(.medium)).foregroundStyle(.teal)
                Spacer()
                Text("\((song.phrases.firstIndex { $0.id == phrase.id } ?? 0) + 1) / \(song.phrases.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(phrase.originalText).font(.system(size: 32 * session.textScale, weight: .semibold, design: .serif)).textSelection(.enabled)
            TextField("全文の日本語訳を追加", text: Binding(get: { file.song.phrase(phrase.id)?.translation.value ?? "" }, set: { value in
                mutate("全文訳を編集") { doc in
                    if let i = doc.phrases.firstIndex(where: { $0.id == phrase.id }) { doc.phrases[i].translation.edit(value) }
                }
            })).textFieldStyle(.plain).font(.system(size: 16 * session.textScale)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("\(phrase.wordIDs.count) 単語", systemImage: "textformat")
                Label("\(song.words(in: phrase).flatMap(\.syllableIDs).count) 音節", systemImage: "circle.grid.2x1")
                if session.mode == .singing {
                    Spacer()
                    Button(session.showNotes ? "音符編集を閉じる" : "音符を編集", systemImage: "pianokeys") { session.showNotes.toggle() }.buttonStyle(.borderless)
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }.padding(30)
    }

    private func transport(_ phrase: Phrase) -> some View {
        HStack(spacing: 18) {
            Button {
                if let range = phrase.timeRange, session.position >= range.end.doubleValue { session.position = range.start.doubleValue }
                session.isPlaying.toggle()
            } label: { Image(systemName: session.isPlaying ? "pause.fill" : "play.fill").frame(width: 22, height: 22) }
                .buttonStyle(.borderedProminent).accessibilityLabel(session.isPlaying ? "一時停止" : "位置プレビューを再生").disabled(phrase.timeRange == nil)
            Button { session.isPlaying = false; session.position = phrase.timeRange?.start.doubleValue ?? 0
            } label: { Image(systemName: "stop.fill") }.buttonStyle(.borderless).accessibilityLabel("停止")
            Toggle(isOn: $session.loop) { Label("このフレーズをループ", systemImage: "repeat") }.toggleStyle(.button).font(.caption)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("練習テンポ \(Int(session.bpm))").font(.caption.monospacedDigit())
                Slider(value: $session.bpm, in: 30...240, step: 1).frame(width: 140).accessibilityLabel("練習テンポ")
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f 拍", session.position + 1)).monospacedDigit()
                Text("位置プレビュー・音は出ません").foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(18)
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.word.spacing").font(.system(size: 48, weight: .light)).foregroundStyle(.teal)
            Text("ことばを知る。\n歌う場所が見えてくる。").font(.system(size: 30, weight: .medium, design: .serif)).multilineTextAlignment(.center)
            Text("意味と発音を読み、音節と音符をつなぐ練習帳です。").foregroundStyle(.secondary)
            Button("練習サンプルを開く") {
                session.replace(SampleSongDocument.make(), in: $file, undo: undoManager, name: "サンプルを読み込み")
                if let first = file.song.phrases.first { session.select(first) }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("自分の歌詞で始める") { addingLyrics = true }.buttonStyle(.plain).foregroundStyle(.teal)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("歌詞を追加").font(.title2.bold())
            Text("1行ずつフレーズになります。原文の空白や記号はそのまま保持します。").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $input).font(.body).frame(width: 480, height: 180).border(Color.secondary.opacity(0.2)).accessibilityLabel("追加する歌詞")
            HStack {
                Button("キャンセル", role: .cancel) { addingLyrics = false }
                Spacer()
                Button("追加") {
                    mutate("歌詞を追加") { doc in
                        for line in input.components(separatedBy: .newlines) { doc.appendPhrase(text: line) }
                    }
                    if let last = file.song.phrases.last { session.select(last) }
                    input = ""; addingLyrics = false
                }.buttonStyle(.borderedProminent).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28)
    }

    private func mutate(_ name: String, _ mutation: (inout SongDocument) throws -> Void) {
        do { session.replace(try song.editing(mutation), in: $file, undo: undoManager, name: name) }
        catch { session.error = error.localizedDescription }
    }
}

#if DEBUG
struct WorkspacePreviews: PreviewProvider {
    static var previews: some View {
        WorkspaceView(file: .constant(SongFile(song: SampleSongDocument.make())))
            .frame(width: 1180, height: 790).previewDisplayName("Reading · Phrase workspace")
    }
}
#endif
