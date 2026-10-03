import SwiftUI
import SongCore
import SongServices
import SongPrint
import AppKit
import UniformTypeIdentifiers

enum WorkspaceMode: String, CaseIterable { case reading = "読む", singing = "歌う" }
enum SingingLayout: String, CaseIterable { case overview = "一覧", detail = "詳細" }
enum PitchDisplay: String, CaseIterable { case pianoRoll = "ピアノロール", staff = "楽譜" }
enum PlaybackScope: String, CaseIterable { case whole = "曲を通して", once = "選択範囲を1回", loop = "選択範囲をループ" }
enum NoteTool: String, CaseIterable { case edit = "音符を編集", step = "ステップ入力" }

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var mode = WorkspaceMode.reading
    @Published var phraseID: UUID?
    @Published var wordID: UUID?
    @Published var syllableID: UUID?
    @Published var eventID: UUID?
    /// The part that note entry and alignment act on; nil means the first part.
    @Published var partID: UUID?
    @Published var noteTool = NoteTool.edit
    /// Step entry position; nil continues after the part's last note.
    @Published var stepCursor: Beat?
    @Published var showingParts = false
    @Published var showingAlignment = false
    @Published var showInspector = false
    @Published var showNotes = false
    @Published var guideState = GuideState.stopped
    @Published var singingLayout = SingingLayout.overview
    @Published var pitchDisplay = PitchDisplay.pianoRoll
    @Published var playbackScope = PlaybackScope.whole
    @Published var practiceRange: BeatRange?
    @Published var practiceCandidate: BeatRange?
    @Published var detailIndex = 0
    @Published var followPlayback = true
    @Published var showReading = true
    @Published var showIPA = false
    @Published var position = 0.0
    @Published var bpm = 88.0
    @Published var error: String?
    @Published var textScale = 1.0
    let guide = GuideTonePlayer()

    func activeRange(for song: SongDocument) -> BeatRange? {
        if playbackScope != .whole { return practiceRange }
        let end = MeasureProjection.songEnd(song)
        return end > .zero ? .init(start: .zero, end: end) : nil
    }

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
    }
}

struct WorkspaceView: View {
    @Binding var file: SongFile
    @StateObject private var session = WorkspaceSession()
    @Environment(\.undoManager) private var undoManager
    @State private var addingLyrics = false
    @State private var showingSamples = false
    @State private var selectedSampleID = "twinkle"
    @State private var showAnalysis = false
    @State private var playTask: Task<Void, Never>?
    @State private var changingTempo = false
    @State private var input = ""
    @State private var inputLanguage = "en"
    @State private var splitSyllables = true
    @State private var pendingMIDI: PendingMIDIImport?
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
                            if session.mode == .reading {
                                ReadingView(song: song, session: session, mutate: mutate)
                            } else {
                                phraseHeader(phrase)
                                SingingView(song: song, phrase: phrase, session: session,
                                            applyRange: applyPracticeRange, seek: seek)
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
                        NoteEditor(song: song, phrase: phrase, session: session, mutate: mutate)
                            .frame(height: session.noteTool == .step ? 215 : 175)
                    }
                    Divider()
                    transport()
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
                Button { showingSamples = true } label: { Label("サンプルを表示", systemImage: "books.vertical") }
                Menu {
                    Button("Word (.docx)") { exportSheet(.word) }
                    Button("PDF (.pdf)") { exportSheet(.pdf) }
                } label: { Label("歌詞シートを書き出す", systemImage: "square.and.arrow.up") }
                Menu {
                    Button("歌詞を追加…", systemImage: "text.badge.plus") { addingLyrics = true }
                    Button("意味を解析…", systemImage: "sparkles") { showAnalysis = true }.disabled(phrase == nil)
                    Divider()
                    Button("旋律をステップ入力…", systemImage: "pianokeys") {
                        session.mode = .singing; session.showNotes = true; session.noteTool = .step
                    }.disabled(phrase == nil)
                    Button("歌詞を音符に割り当てる…", systemImage: "text.line.first.and.arrowtriangle.forward") { session.showingAlignment = true }
                        .disabled(song.music.events.isEmpty || song.syllables.isEmpty)
                    Button("声部…", systemImage: "person.3") { session.showingParts = true }
                    Button("MIDIファイルを読み込む…", systemImage: "square.and.arrow.down") { chooseMIDIFile() }
                    Divider()
                    Button("未分割の単語を音節に分ける", systemImage: "scissors") {
                        mutate("未分割の単語を音節に分ける") { doc in
                            for id in doc.phrases.map(\.id) { doc.syllabifyUnsplitWords(phraseID: id) }
                        }
                    }.disabled(!song.words.contains { $0.syllableIDs.isEmpty })
                    Divider()
                    Button("文字を大きく") { session.textScale = min(1.5, session.textScale + 0.1) }
                    Button("文字を小さく") { session.textScale = max(0.9, session.textScale - 0.1) }
                } label: { Label("その他", systemImage: "ellipsis.circle") }
                Button { session.showInspector.toggle() } label: { Label("単語の詳細", systemImage: "sidebar.right") }
                    .help("単語の詳細を表示・非表示")
            }
        }
        .onAppear {
            // Screen QA without UI scripting: `-SingingWorkspaceQA staff|roll|detail-staff`.
            if let qa = UserDefaults.standard.string(forKey: "SingingWorkspaceQA") {
                session.mode = .singing
                session.pitchDisplay = qa.hasSuffix("roll") ? .pianoRoll : .staff
                session.singingLayout = qa.hasPrefix("detail") ? .detail : .overview
            }
            if session.phraseID == nil, let phrase { session.select(phrase) }
            session.bpm = song.music.tempos.first?.bpm ?? 88
            if session.practiceRange == nil {
                let first = Array(MeasureProjection(song: song).slices.prefix(2))
                if let start = first.first?.range.start, let end = first.last?.range.end {
                    session.practiceRange = .init(start: start, end: end)
                }
            }
            session.guide.onFinished = {
                session.guideState = .stopped
                session.position = session.activeRange(for: file.song)?.end.doubleValue ?? session.position
            }
            session.guide.onInterrupted = {
                // Keep the last known position; the next play prepares a new plan on the new device.
                playTask?.cancel(); playTask = nil
                session.guideState = .stopped
            }
        }
        .onChange(of: session.bpm) { _, _ in
            guard !changingTempo else { return }
            tempoChanged()
        }
        .onChange(of: song.revision) { _, _ in
            if let id = session.eventID, song.event(id) == nil { session.eventID = nil }
            if let id = session.wordID, song.word(id) == nil { session.wordID = nil }
        }
        .onChange(of: song.music) { _, _ in
            if session.guideState != .stopped { pauseForMusicEdit() }
        }
        .task(id: session.guideState) {
            guard session.guideState == .playing else { return }
            while !Task.isCancelled && session.guideState == .playing {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                if let position = session.guide.position { session.position = position }
            }
        }
        .onDisappear { stopPlayback() }
        .sheet(isPresented: $addingLyrics) { lyricsSheet }
        .sheet(isPresented: $showingSamples) { samplePicker }
        .sheet(isPresented: $session.showingParts) { PartsSheet(song: song, session: session, mutate: mutate) }
        .sheet(item: $pendingMIDI) { pending in
            MIDIImportSheet(song: song, pending: pending) { ids, replace, grid in
                stopPlayback()
                mutate("MIDIファイルを読み込む") { doc in
                    let parts = try pending.parsed.apply(to: &doc, candidateIDs: ids, replace: replace, grid: grid)
                    if let first = parts.first { Task { @MainActor in session.partID = first } }
                }
                do { try file.package.attach(pending.data, at: ["source", pending.fileName]) }
                catch { session.error = "元のMIDIファイルを文書に保存できませんでした: \(error.localizedDescription)" }
                session.position = 0
            }
        }
        .sheet(isPresented: $session.showingAlignment) {
            AlignmentProposalSheet(song: song, initialPartID: session.partID) { proposal in
                mutate("歌詞を音符に割り当てる") { LyricAligner.apply(proposal, to: &$0) }
            }
        }
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
            if session.mode == .reading {
                Text(phrase.originalText).font(.system(size: 32 * session.textScale, weight: .semibold, design: .serif)).textSelection(.enabled)
                TextField("全文の日本語訳を追加", text: Binding(get: { file.song.phrase(phrase.id)?.translation.value ?? "" }, set: { value in
                    mutate("全文訳を編集") { doc in
                        if let i = doc.phrases.firstIndex(where: { $0.id == phrase.id }) { doc.phrases[i].translation.edit(value) }
                    }
                })).textFieldStyle(.plain).font(.system(size: 16 * session.textScale)).foregroundStyle(.secondary)
            }
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

    private func transport() -> some View {
        HStack(spacing: 18) {
            Button {
                switch session.guideState {
                case .playing: session.guide.pause(); session.guideState = .paused
                case .paused:
                    if session.guide.resume() { session.guideState = .playing } else { startGuide() }
                default: startGuide()
                }
            } label: { Image(systemName: session.guideState == .playing ? "pause.fill" : "play.fill").frame(width: 22, height: 22) }
                .buttonStyle(.borderedProminent).accessibilityLabel(session.guideState == .playing ? "一時停止" : "ガイド音を再生")
                .disabled(session.activeRange(for: song) == nil || !song.music.events.contains(where: { $0.note != nil }))
            Button { stopPlayback(); session.position = session.activeRange(for: song)?.start.doubleValue ?? 0
            } label: { Image(systemName: "stop.fill") }.buttonStyle(.borderless).accessibilityLabel("停止")
            Picker("再生範囲", selection: $session.playbackScope) {
                ForEach(PlaybackScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(width: 185).onChange(of: session.playbackScope) { _, _ in resetForScopeChange() }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("練習テンポ \(Int(session.bpm))").font(.caption.monospacedDigit())
                Slider(value: $session.bpm, in: 30...240, step: 1, onEditingChanged: { editing in
                    changingTempo = editing
                    if !editing { tempoChanged() }
                }).frame(width: 140).accessibilityLabel("練習テンポ")
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f 拍", session.position + 1)).monospacedDigit()
                Text("ガイド音のみ再生・歌声は出ません").foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(18)
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.word.spacing").font(.system(size: 48, weight: .light)).foregroundStyle(.teal)
            Text("ことばを知る。\n歌う場所が見えてくる。").font(.system(size: 30, weight: .medium, design: .serif)).multilineTextAlignment(.center)
            Text("意味と発音を読み、音節と音符をつなぐ練習帳です。").foregroundStyle(.secondary)
            Button("サンプルを表示") { showingSamples = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("自分の歌詞で始める") { addingLyrics = true }.buttonStyle(.plain).foregroundStyle(.teal)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var samplePicker: some View {
        let selected = SampleCatalog.entries.first(where: { $0.id == selectedSampleID }) ?? SampleCatalog.entries[0]
        let preview = selected.make()
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("サンプル曲").font(.title2.bold())
                Text("曲を選ぶと、歌詞・読み・音符を確認できます。")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(SampleCatalog.entries) { entry in
                    Button { selectedSampleID = entry.id } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.headline)
                            Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(selectedSampleID == entry.id ? Color.teal.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityLabel("サンプル \(entry.title)")
                }
                Spacer(minLength: 0)
            }.padding(24).frame(width: 285)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text(selected.title).font(.system(size: 29, weight: .semibold, design: .serif))
                Text(selected.details).foregroundStyle(.secondary)
                Divider()
                Text("歌詞のプレビュー").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                ForEach(Array(preview.phrases.prefix(3))) { phrase in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(phrase.originalText).font(.system(size: 17, weight: .medium, design: .serif))
                        Text(phrase.translation.value).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Button("キャンセル", role: .cancel) { showingSamples = false }
                    Spacer()
                    Button("この曲を開く") {
                        openSample(preview)
                        showingSamples = false
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 720, height: 480)
    }

    private var lyricsSheet: some View {
        let lines = input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 14) {
            Text("歌詞を追加").font(.title2.bold())
            Text("1行ずつフレーズになります。原文の空白や記号はそのまま保持します。歌詞は利用者が権利を確認したものを使ってください。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Picker("言語", selection: $inputLanguage) {
                    ForEach(Syllabifier.languages) { Text($0.name).tag($0.id) }
                }.frame(width: 260)
                Toggle("音節に分ける（規則による候補）", isOn: $splitSyllables).toggleStyle(.checkbox)
            }
            TextEditor(text: $input).font(.body).frame(width: 560, height: 150).border(Color.secondary.opacity(0.2)).accessibilityLabel("追加する歌詞")
            if splitSyllables && !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("音節の候補（追加後に単語の詳細で直せます）").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { _, line in
                                Text(syllablePreview(line)).font(.system(size: 13, design: .serif)).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: min(130, Double(min(lines.count, 12)) * 20 + 6))
                    Text(inputLanguage == "ja" ? "漢字の読みは推定です。「漢字（かんじ）」と書くと読みを指定できます。"
                         : inputLanguage == "ru" ? "強勢は母音の後に結合アクセント（◌́）を付けると指定できます。" : "・は音節の区切り、太字は推定した強勢です。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("キャンセル", role: .cancel) { addingLyrics = false }
                Spacer()
                Button("追加") {
                    let language = inputLanguage
                    let split = splitSyllables
                    mutate("歌詞を追加") { doc in
                        if doc.phrases.isEmpty { doc.metadata.sourceLanguage = language }
                        for line in input.components(separatedBy: .newlines) { doc.appendPhrase(text: line, language: language, syllabify: split) }
                    }
                    if let last = file.song.phrases.last { session.select(last) }
                    input = ""; addingLyrics = false
                }.buttonStyle(.borderedProminent).disabled(lines.isEmpty)
            }
        }.padding(28)
            .onAppear {
                let current = song.metadata.sourceLanguage
                inputLanguage = Syllabifier.supports(current) ? current : "en"
            }
    }

    private func syllablePreview(_ line: String) -> AttributedString {
        var result = AttributedString()
        for (index, token) in Syllabifier.tokenize(line, language: inputLanguage).enumerated() {
            if index > 0 { result += AttributedString("   ") }
            let split = Syllabifier.syllabify(token, language: inputLanguage)
            if split.syllables.isEmpty { result += AttributedString(token.surface + "（未分割）"); continue }
            for (position, syllable) in split.syllables.enumerated() {
                if position > 0 { result += AttributedString("・") }
                var part = AttributedString(syllable)
                if position == split.stressIndex { part.inlinePresentationIntent = .stronglyEmphasized }
                result += part
            }
            if let readings = split.readings { result += AttributedString("（\(readings.joined(separator: "・"))）") }
        }
        return result
    }

    private func mutate(_ name: String, _ mutation: (inout SongDocument) throws -> Void) {
        do {
            let next = try song.editing(mutation)
            var unchanged = next
            unchanged.revision = song.revision
            // Text fields can write back an identical value on focus; that is not an edit.
            guard unchanged != song else { return }
            session.replace(next, in: $file, undo: undoManager, name: name)
        }
        catch { session.error = error.localizedDescription }
    }

    private func openSample(_ sample: SongDocument) {
        stopPlayback()
        session.replace(sample, in: $file, undo: undoManager, name: "サンプルを読み込み")
        if let first = file.song.phrases.first { session.select(first) }
        session.bpm = file.song.music.tempos.first?.bpm ?? 88
        session.position = 0
        session.detailIndex = 0
        session.playbackScope = .whole
        let first = Array(MeasureProjection(song: file.song).slices.prefix(2))
        if let start = first.first?.range.start, let end = first.last?.range.end {
            session.practiceRange = .init(start: start, end: end)
        } else { session.practiceRange = nil }
    }

    private func chooseMIDIFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = false
        panel.message = "旋律を含むMIDIファイル（SMF）を選んでください。利用する権利のあるファイルを使ってください。"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url)
                    let parsed = try MIDIFileImport.parse(data)
                    guard !parsed.candidates.isEmpty else {
                        session.error = (["音符が見つかりませんでした。"] + parsed.diagnostics).joined(separator: "\n"); return
                    }
                    let name = url.lastPathComponent.replacingOccurrences(of: "/", with: "-")
                    pendingMIDI = .init(fileName: name, data: data, parsed: parsed)
                } catch {
                    session.error = "MIDIファイルを読み込めませんでした: \(error.localizedDescription)"
                }
            }
        }
    }

    private enum SheetFormat {
        case word, pdf
        var fileExtension: String { self == .word ? "docx" : "pdf" }
        var type: UTType { self == .pdf ? .pdf : UTType(filenameExtension: "docx")! }
    }

    private func exportSheet(_ format: SheetFormat) {
        let snapshot = song
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.canCreateDirectories = true
        let title = snapshot.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(title.isEmpty ? "歌唱練習シート" : title).\(format.fileExtension)"
        panel.message = "A4の教材として、原文・音節と母音核・IPA・カタカナ読み・語の意味・文の訳を書き出します。"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let sheet = PrintSheet(song: snapshot)
                    let data = try format == .pdf ? PDFSheet.render(sheet) : WordSheet.render(sheet)
                    try data.write(to: url, options: .atomic)
                } catch {
                    session.error = "印刷用ファイルを書き出せませんでした: \(error.localizedDescription)"
                }
            }
        }
    }

    private func startGuide() {
        guard let range = session.activeRange(for: song) else { return }
        playTask?.cancel()
        session.guide.stop()
        if session.position < range.start.doubleValue || session.position >= range.end.doubleValue {
            session.position = range.start.doubleValue
        }
        let currentSong = song
        let start = session.position
        let bpm = session.bpm
        let loop = session.playbackScope == .loop
        session.guideState = .preparing
        playTask = Task {
            do {
                try await session.guide.play(song: currentSong, range: range, fromBeat: start, bpm: bpm, loop: loop)
                if !Task.isCancelled { session.guideState = .playing }
            } catch is CancellationError {
                // A newer play or stop invalidated this preparation.
            } catch {
                if !Task.isCancelled {
                    session.guideState = .failed
                    session.error = "ガイド音を再生できませんでした: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Playing: continue from the current position at the new tempo.
    /// Paused: discard the old-tempo plan and keep the position; the play button prepares a new one.
    private func tempoChanged() {
        switch session.guideState {
        case .playing, .preparing:
            if let current = session.guide.position { session.position = current }
            startGuide()
        case .paused:
            if let current = session.guide.position { session.position = current }
            stopPlayback()
        case .stopped, .failed:
            break
        }
    }

    private func stopPlayback() {
        playTask?.cancel(); playTask = nil
        session.guide.stop()
        session.guideState = .stopped
    }

    private func pauseForMusicEdit() {
        if let current = session.guide.position { session.position = current }
        stopPlayback()
        if let range = session.activeRange(for: song) {
            session.position = min(range.end.doubleValue, max(range.start.doubleValue, session.position))
        }
    }

    private func resetForScopeChange() {
        stopPlayback()
        session.position = session.activeRange(for: song)?.start.doubleValue ?? 0
    }

    private func applyPracticeRange(_ range: BeatRange) {
        session.practiceRange = range
        session.practiceCandidate = nil
        if session.playbackScope != .whole { resetForScopeChange() }
    }

    private func seek(_ beat: Double) {
        guard let range = session.activeRange(for: song) else { return }
        let wasPlaying = session.guideState == .playing
        session.position = min(range.end.doubleValue, max(range.start.doubleValue, beat))
        if wasPlaying { startGuide() }
        else { stopPlayback() }
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
