import SwiftUI
import CoreMIDI
import SongCore

// MARK: Lyric alignment proposal

struct AlignmentProposalSheet: View {
    let song: SongDocument
    let initialPartID: UUID?
    let apply: (LyricAlignmentProposal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var partID: UUID?
    @State private var proposal: LyricAlignmentProposal?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("歌詞を音符に割り当てる").font(.title2.bold())
            Text("一音符に一音節を基本に、音の数が合わない所だけメリスマ（1音節を複数の音へ）やエリジオン（2音節を1音へ）を提案します。手で直した対応は動かしません。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if song.music.parts.count > 1 {
                Picker("声部", selection: $partID) {
                    ForEach(song.music.parts) { Text($0.name).tag(Optional($0.id)) }
                }.frame(width: 260)
            }
            if let proposal {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow { Text("音節").foregroundStyle(.secondary); Text("\(proposal.syllableCount)") ; Text("歌う音（タイは1音）").foregroundStyle(.secondary); Text("\(proposal.sungNoteCount)") }
                    GridRow { Text("1音節＝1音").foregroundStyle(.secondary); Text("\(proposal.oneToOneCount)"); Text("固定した対応").foregroundStyle(.secondary); Text("\(proposal.anchorCount)") }
                    GridRow { Text("メリスマ").foregroundStyle(.secondary); Text("\(proposal.melismaCount)"); Text("エリジオン").foregroundStyle(.secondary); Text("\(proposal.elisionCount)") }
                }.font(.callout.monospacedDigit())
                Divider()
                Text(proposal.issues.isEmpty ? "確認が必要な箇所はありません。" : "確認してほしい箇所（\(proposal.issues.count)）")
                    .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(proposal.issues.prefix(80).enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: icon(issue.kind)).font(.callout)
                                .foregroundStyle(issue.kind == .unsungSyllable || issue.kind == .noteWithoutLyric ? Color.orange : Color.primary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 180)
                Text("適用後に音節を選び「選んだ音節の対応を変更…」で直すと、その対応は固定され、再計算しても動きません。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let failure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack {
                Button("キャンセル", role: .cancel) { dismiss() }
                Spacer()
                Button("割り当てる") { if let proposal { apply(proposal); dismiss() } }
                    .buttonStyle(.borderedProminent).disabled(proposal == nil || proposal?.alignments.isEmpty == true)
            }
        }.padding(26).frame(width: 520)
            .onAppear { partID = initialPartID ?? song.music.parts.first?.id; compute() }
            .onChange(of: partID) { _, _ in compute() }
    }

    private func compute() {
        guard let partID else { proposal = nil; failure = "音符がありません。先に旋律を入力してください。"; return }
        do { proposal = try LyricAligner.propose(song: song, partID: partID); failure = nil }
        catch { proposal = nil; failure = error.localizedDescription }
    }

    private func icon(_ kind: LyricAlignmentProposal.Issue.Kind) -> String {
        switch kind {
        case .melisma: "arrow.left.and.right"
        case .elision: "link"
        case .unsungSyllable: "text.badge.xmark"
        case .noteWithoutLyric: "music.note"
        case .countMismatch: "number"
        }
    }
}

// MARK: Parts

struct PartsSheet: View {
    let song: SongDocument
    @ObservedObject var session: WorkspaceSession
    let mutate: SongMutation
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: Part?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("声部").font(.title2.bold())
            Text("声部はすべて同じ小節・拍で揃います。単声の曲は声部1つです。歌詞と意味は全声部で共有し、音符への割り当ては声部ごとです。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if song.music.parts.isEmpty {
                Text("まだ声部がありません。旋律を入力すると「旋律」声部ができます。").foregroundStyle(.secondary)
            }
            ForEach(song.music.parts) { part in
                HStack(spacing: 10) {
                    TextField("名前", text: binding(part, \.name)).textFieldStyle(.roundedBorder).frame(width: 150)
                    TextField("略称", text: binding(part, \.abbreviation)).textFieldStyle(.roundedBorder).frame(width: 60)
                    Picker("音部記号", selection: Binding(get: { song.music.part(part.id)?.clef ?? .treble }, set: { clef in
                        mutate("音部記号を変更") { doc in if let i = doc.music.parts.firstIndex(where: { $0.id == part.id }) { doc.music.parts[i].clef = clef } }
                    })) { ForEach(Clef.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 190)
                    Text("\(song.music.events(in: part.id).filter { $0.note != nil }.count)音").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button(role: .destructive) { pendingRemoval = part } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).accessibilityLabel("\(part.name)を削除")
                }
            }
            HStack {
                Button("声部を追加", systemImage: "plus") {
                    mutate("声部を追加") { doc in
                        doc.addPart(name: "声部\(doc.music.parts.count + 1)")
                    }
                }
                Button("混声四部（S・A・T・B）を用意") {
                    mutate("混声四部を用意") { doc in
                        for (name, abbreviation, clef) in [("ソプラノ", "S", Clef.treble), ("アルト", "A", .treble), ("テノール", "T", .treble8vb), ("バス", "B", .bass)]
                        where !doc.music.parts.contains(where: { $0.abbreviation == abbreviation }) {
                            doc.addPart(name: name, abbreviation: abbreviation, clef: clef)
                        }
                    }
                }
                Spacer()
                Button("閉じる") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 600)
            .alert("声部を削除しますか？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                Button("削除", role: .destructive) {
                    if let part = pendingRemoval { mutate("声部を削除") { try $0.removePart(id: part.id) } }
                    pendingRemoval = nil
                }
                Button("キャンセル", role: .cancel) { pendingRemoval = nil }
            } message: { Text("この声部の音符と、その音符への歌詞の割り当ても削除します（取り消しで戻せます）。") }
    }

    private func binding(_ part: Part, _ keyPath: WritableKeyPath<Part, String>) -> Binding<String> {
        Binding(get: { song.music.part(part.id)?[keyPath: keyPath] ?? "" }, set: { value in
            guard !(keyPath == \Part.name && value.trimmingCharacters(in: .whitespaces).isEmpty) else { return }
            mutate("声部を編集") { doc in if let i = doc.music.parts.firstIndex(where: { $0.id == part.id }) { doc.music.parts[i][keyPath: keyPath] = value } }
        })
    }
}

// MARK: Step entry

enum StepValue: Double, CaseIterable, Identifiable {
    case whole = 4, half = 2, quarter = 1, eighth = 0.5, sixteenth = 0.25
    var id: Double { rawValue }
    var label: String {
        switch self { case .whole: "全音符"; case .half: "2分"; case .quarter: "4分"; case .eighth: "8分"; case .sixteenth: "16分" }
    }
}

struct StepInputPanel: View {
    let song: SongDocument
    @ObservedObject var session: WorkspaceSession
    let mutate: SongMutation
    @StateObject private var midi = MIDIInputMonitor()
    @State private var value = StepValue.quarter
    @State private var dotted = false
    @State private var octave = 4

    private var partID: UUID? { song.music.part(session.partID)?.id ?? song.music.parts.first?.id }
    private var cursor: Beat { session.stepCursor ?? partID.map { song.partEnd($0) } ?? .zero }
    private var length: Beat { (try? Beat.grid(value.rawValue * (dotted ? 1.5 : 1), divisions: 16)) ?? (try! Beat(1)) }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("声部: \(partID.flatMap { song.music.part($0)?.name } ?? "旋律（新規）")").font(.callout.weight(.medium))
                    Text("入力位置 \(positionLabel(cursor))").font(.callout.monospacedDigit()).foregroundStyle(.teal)
                }
                HStack(spacing: 6) {
                    Button { move(by: -1) } label: { Image(systemName: "chevron.left") }.help("入力位置を戻す").disabled(cursor == .zero)
                    Button { move(by: 1) } label: { Image(systemName: "chevron.right") }.help("入力位置を進める")
                    Button("末尾へ") { session.stepCursor = nil }.disabled(session.stepCursor == nil)
                }
                Picker("音価", selection: $value) { ForEach(StepValue.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 300).labelsHidden()
                HStack(spacing: 12) {
                    Toggle("付点", isOn: $dotted).toggleStyle(.checkbox)
                    Button("休符", systemImage: "pause") { enter(nil) }
                    Button("1つ戻す", systemImage: "delete.left") { removeLast() }.disabled(cursor == .zero)
                }
                if song.music.events.isEmpty { meterAndTempo }
                Label(midi.status, systemImage: midi.sourceNames.isEmpty ? "pianokeys" : "cable.connector")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(width: 330, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button { octave = max(1, octave - 1) } label: { Image(systemName: "minus") }.help("1オクターブ下")
                    Text("C\(octave)–B\(octave + 1)").font(.caption.monospacedDigit()).frame(width: 64)
                    Button { octave = min(6, octave + 1) } label: { Image(systemName: "plus") }.help("1オクターブ上")
                    Text("鍵盤を押すと入力位置に書き込みます（同じ声部の既存の音は上書き）。").font(.caption).foregroundStyle(.secondary)
                }
                PianoKeys(low: (octave + 1) * 12, octaves: 2) { enter($0) }
            }
        }
        .onAppear {
            midi.onNoteOn = { pitch, _ in enter(pitch) }
            midi.start()
        }
        .onDisappear { midi.onNoteOn = nil; midi.stop() }
    }

    private var meterAndTempo: some View {
        HStack(spacing: 10) {
            Picker("拍子", selection: Binding(get: { "\(song.music.meters.first?.numerator ?? 4)/\(song.music.meters.first?.denominator ?? 4)" }, set: { text in
                let parts = text.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                mutate("拍子を設定") { doc in doc.music.meters = [.init(numerator: parts[0], denominator: parts[1])]; doc.music.measures = [] }
            })) { ForEach(["2/4", "3/4", "4/4", "2/2", "3/8", "6/8", "9/8", "12/8"], id: \.self) { Text($0).tag($0) } }.frame(width: 120)
            Stepper("テンポ \(Int(song.music.tempos.first?.bpm ?? 88))", onIncrement: { setTempo(+4) }, onDecrement: { setTempo(-4) })
        }.font(.callout)
    }

    private func setTempo(_ delta: Double) {
        mutate("テンポを設定") { doc in
            let bpm = min(300, max(20, (doc.music.tempos.first?.bpm ?? 88) + delta))
            doc.music.tempos = [.init(bpm: bpm)]
        }
        session.bpm = song.music.tempos.first?.bpm ?? session.bpm
    }

    private func positionLabel(_ beat: Beat) -> String {
        let measures = MeasureProjection(song: song).slices
        if let measure = measures.first(where: { $0.range.start <= beat && beat < $0.range.end }) {
            let meter = song.music.meters.last { $0.onset <= measure.range.start } ?? .init()
            let unit = 4 / Double(meter.denominator)
            let inBar = (beat.doubleValue - measure.range.start.doubleValue) / unit + 1
            return "\(measure.number)小節 \(inBar.formatted(.number.precision(.fractionLength(0...2))))拍目"
        }
        return "曲末（\((beat.doubleValue + 1).formatted(.number.precision(.fractionLength(0...2))))拍）"
    }

    private func move(by steps: Int) {
        let delta = length.doubleValue * Double(steps)
        let next = max(0, cursor.doubleValue + delta)
        session.stepCursor = try? Beat.grid(next, divisions: 48)
    }

    private func enter(_ pitch: Int?) {
        let onset = cursor, duration = length
        var enteredPart = partID
        mutate(pitch == nil ? "休符を入力" : "音符を入力") { doc in
            if doc.music.parts.isEmpty { enteredPart = doc.addPart(name: "旋律") }
            guard let part = enteredPart else { return }
            try doc.enterStep(partID: part, onset: onset, duration: duration, pitch: pitch)
        }
        if let enteredPart { session.partID = enteredPart }
        session.stepCursor = try? onset.adding(duration)
        if let pitch { session.guide.audition(pitch: pitch) }
    }

    private func removeLast() {
        guard let part = partID else { return }
        let at = cursor
        guard let previous = song.music.events.filter({ $0.partID == part && (try? $0.range.end) == at }).first else {
            session.stepCursor = try? at.subtracting(length) ; return
        }
        mutate("入力を1つ戻す") { $0.removeNote(id: previous.id) }
        session.stepCursor = previous.onset
    }
}

/// Two octaves of clickable keys; black keys sit between the white ones.
struct PianoKeys: View {
    let low: Int
    let octaves: Int
    let play: (Int) -> Void
    private let whiteWidth = 26.0, whiteHeight = 92.0

    var body: some View {
        let whites = (0..<(octaves * 12)).map { low + $0 }.filter { ![1, 3, 6, 8, 10].contains($0 % 12) }
        ZStack(alignment: .topLeading) {
            HStack(spacing: 1) {
                ForEach(whites, id: \.self) { pitch in
                    Button { play(pitch) } label: {
                        VStack { Spacer(); Text(pitch % 12 == 0 ? Note(pitch: pitch).name : "").font(.system(size: 9)).foregroundStyle(.secondary) }
                            .frame(width: whiteWidth, height: whiteHeight)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.25)))
                    }.buttonStyle(.plain).accessibilityLabel("鍵盤 \(Note(pitch: pitch).name)")
                }
            }
            ForEach(Array(whites.enumerated()), id: \.offset) { index, pitch in
                if [0, 2, 5, 7, 9].contains(pitch % 12) {
                    Button { play(pitch + 1) } label: {
                        RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.85)).frame(width: 16, height: 56)
                    }.buttonStyle(.plain).offset(x: Double(index + 1) * (whiteWidth + 1) - 8.5)
                        .accessibilityLabel("鍵盤 \(Note(pitch: pitch + 1).name)")
                }
            }
        }.frame(height: whiteHeight)
    }
}

// MARK: CoreMIDI input

/// Listens to every MIDI source and reports note-on events on the main actor.
@MainActor
final class MIDIInputMonitor: ObservableObject {
    @Published private(set) var sourceNames: [String] = []
    var onNoteOn: ((Int, Int) -> Void)?
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()

    var status: String {
        sourceNames.isEmpty ? "MIDI鍵盤は未接続です（画面の鍵盤で入力できます）" : "MIDI鍵盤: \(sourceNames.joined(separator: "、"))"
    }

    func start() {
        if client == 0 {
            let created = MIDIClientCreateWithBlock("Singing Workspace" as CFString, &client) { [weak self] _ in
                Task { @MainActor in self?.connectSources() }
            }
            guard created == noErr else { return }
            let receive: MIDIReceiveBlock = { [weak self] list, _ in
                var notes: [(Int, Int)] = []
                for packet in list.unsafeSequence() {
                    for word in packet.words() {
                        // Universal MIDI Packet, MIDI 1.0 channel voice (message type 2): status, data1, data2.
                        guard word >> 28 == 0x2 else { continue }
                        let status = (word >> 16) & 0xF0, pitch = Int((word >> 8) & 0x7F), velocity = Int(word & 0x7F)
                        if status == 0x90 && velocity > 0 { notes.append((pitch, velocity)) }
                    }
                }
                guard !notes.isEmpty else { return }
                let found = notes
                Task { @MainActor in for note in found { self?.onNoteOn?(note.0, note.1) } }
            }
            guard MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &port, receive) == noErr else { return }
        }
        connectSources()
    }

    private func connectSources() {
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(port, source, nil)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr, let value = name?.takeRetainedValue() {
                names.append(value as String)
            }
        }
        sourceNames = names
    }

    func stop() {
        if port != 0 { MIDIPortDispose(port); port = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
        sourceNames = []
    }
}
