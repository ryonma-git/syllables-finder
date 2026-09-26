import SwiftUI
import SongCore

struct SingingView: View {
    let song: SongDocument
    let phrase: Phrase
    @ObservedObject var session: WorkspaceSession
    private let unit = 145.0
    private var range: BeatRange? { phrase.timeRange }
    private var origin: Double { range?.start.doubleValue ?? 0 }
    private var extent: Double { max(range?.length ?? 4, 1) }
    private func x(_ beat: Double) -> Double { (beat - origin) * unit + 18 }
    private var events: [MusicalEvent] { phrase.musicalEventIDs.compactMap { song.event($0) } }

    var body: some View {
        if let range, range.length <= 128 {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 18) {
                    timeline(range)
                    HStack(spacing: 18) {
                        Label("音節", systemImage: "rectangle.fill").foregroundStyle(.teal)
                        Label("ガイド音符", systemImage: "music.note").foregroundStyle(.secondary)
                        Spacer()
                        Text("ひとつの音節に、複数の音符をつなげられます").foregroundStyle(.secondary)
                    }.font(.caption)
                }.padding(.horizontal, 30).padding(.bottom, 25)
            }
        } else {
            ContentUnavailableView("この範囲の時間軸は表示できません", systemImage: "music.note", description: Text("Readingで意味や発音を編集できます。128拍を超えるフレーズの表示には、今後分割表示を追加します。"))
        }
    }

    private func timeline(_ range: BeatRange) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
            ForEach(0...Int(ceil(extent)), id: \.self) { tick in
                VStack(spacing: 10) {
                    Text("\(Int(origin) + tick + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1, height: 285)
                }.position(x: 18 + Double(tick) * unit, y: 158)
            }
            ForEach(song.words(in: phrase)) { word in
                let spans = song.syllables(in: word).flatMap { song.ranges(for: .init(.syllable, $0.id)) }
                if let first = spans.map(\.start).min(), let last = spans.map(\.end).max() {
                    Button {
                        session.wordID = word.id; session.showInspector = true
                        session.position = first.doubleValue
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(word.surface).font(.system(size: 21, weight: .semibold, design: .serif))
                            Text(word.contextualMeaning.value).font(.caption).foregroundStyle(.secondary)
                        }.frame(width: max(50, (last.doubleValue - first.doubleValue) * unit - 10), alignment: .leading)
                    }.buttonStyle(.plain).offset(x: x(first.doubleValue) + 8, y: 48)
                }
            }
            ForEach(song.words(in: phrase).flatMap { song.syllables(in: $0) }) { syllable in
                let spans = song.ranges(for: .init(.syllable, syllable.id))
                if let first = spans.map(\.start).min(), let last = spans.map(\.end).max() {
                    Button {
                        session.syllableID = syllable.id; session.wordID = syllable.parentWordID
                        session.position = first.doubleValue
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(syllable.text.value).font(.system(size: 19, weight: .semibold))
                                Text(syllable.ipa.value).font(.system(size: 14))
                            }
                            Spacer(minLength: 0)
                            if spans.count > 1 { Image(systemName: "link").font(.caption) }
                        }.padding(13)
                            .frame(width: max(45, (last.doubleValue - first.doubleValue) * unit - 8), height: 76)
                            .background(Color.teal.opacity(session.syllableID == syllable.id ? 0.23 : 0.11), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(session.syllableID == syllable.id ? 1 : 0.25), lineWidth: session.syllableID == syllable.id ? 2 : 1))
                    }.buttonStyle(.plain).foregroundStyle(.primary).offset(x: x(first.doubleValue) + 4, y: 119)
                        .accessibilityLabel("音節 \(syllable.text.value)、\(spans.count)個の音符に対応")
                }
            }
            ForEach(events) { event in
                Button {
                    session.eventID = event.id; session.showNotes = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: event.note == nil ? "pause" : "music.note")
                        Text(event.note?.name ?? "休符").fontWeight(.medium)
                        Spacer(minLength: 0)
                    }.font(.caption).padding(.horizontal, 10)
                        .frame(width: max(28, event.duration.doubleValue * unit - 10), height: 33)
                        .background(session.eventID == event.id ? Color.teal.opacity(0.3) : Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(session.eventID == event.id ? Color.teal : .clear))
                }.buttonStyle(.plain).offset(x: x(event.onset.doubleValue) + 5, y: 235 + Double(67 - (event.note?.pitch ?? 60)) * 3)
                    .accessibilityLabel("\(event.note?.name ?? "休符")、\(event.duration.doubleValue)拍、音符を編集")
            }
            Rectangle().fill(Color.teal).frame(width: 2, height: 312)
                .overlay(alignment: .top) { Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(.teal).offset(y: -3) }
                .offset(x: x(min(range.end.doubleValue, max(origin, session.position))), y: 20)
                .allowsHitTesting(false).accessibilityHidden(true)
        }.frame(width: extent * unit + 36, height: 345)
    }
}

struct NoteEditor: View {
    let song: SongDocument
    let phrase: Phrase
    @ObservedObject var session: WorkspaceSession
    let mutate: SongMutation
    @State private var pitch = 60
    @State private var onset = 0.0
    @State private var duration = 1.0
    @State private var velocity = 80
    @State private var showingAlignment = false
    private var event: MusicalEvent? { session.eventID.flatMap { song.event($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("音符を編集", systemImage: "pianokeys").font(.headline)
                Spacer()
                if session.syllableID != nil {
                    Button("選んだ音節の対応を変更…") { showingAlignment = true }.font(.caption)
                }
                Button("音符を追加", systemImage: "plus") { addNote() }.font(.caption)
            }
            if let event, event.note != nil {
                HStack(alignment: .bottom, spacing: 15) {
                    numeric("音高 (MIDI)", value: $pitch)
                    decimal("開始 (拍)", value: $onset)
                    decimal("長さ (拍)", value: $duration)
                    numeric("強さ", value: $velocity)
                    Button("適用") {
                        mutate("音符を編集") { doc in
                            try doc.updateNote(id: event.id, pitch: pitch, onset: Beat.grid(onset), duration: Beat.grid(duration), velocity: velocity)
                        }
                    }.buttonStyle(.borderedProminent)
                    Button("削除", role: .destructive) { mutate("音符を削除") { $0.removeNote(id: event.id) } }
                }
                Text("開始は曲頭を0拍とした位置です。フレーズの範囲内で編集できます。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("時間軸の音符を選ぶと、音高・開始・長さ・強さを変更できます。")
                    .foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .onAppear { load() }.onChange(of: session.eventID) { _, _ in load() }
            .onChange(of: song.revision) { _, _ in load() }
            .sheet(isPresented: $showingAlignment) {
                if let id = session.syllableID, let syllable = song.syllable(id) {
                    AlignmentSheet(song: song, phrase: phrase, syllable: syllable, mutate: mutate)
                }
            }
    }
    private func numeric(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
        }
    }
    private func decimal(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder).frame(width: 90)
        }
    }
    private func load() {
        guard let event, let note = event.note else { return }
        pitch = note.pitch; velocity = note.velocity; onset = event.onset.doubleValue; duration = event.duration.doubleValue
    }
    private func addNote() {
        guard let range = phrase.timeRange else { return }
        let id = UUID()
        mutate("音符を追加") { doc in
            let onset = range.start
            let length = try Beat.grid(min(1, range.length))
            let measure = doc.music.measures.first { $0.range.start <= onset && onset < $0.range.end }?.id
            doc.music.events.append(.init(id: id, onset: onset, duration: length, measureID: measure, content: .note(.init(pitch: 60))))
            if let index = doc.phrases.firstIndex(where: { $0.id == phrase.id }) { doc.phrases[index].musicalEventIDs.append(id) }
        }
        if song.event(id) != nil { session.eventID = id }
    }
}

struct AlignmentSheet: View {
    let song: SongDocument
    let phrase: Phrase
    let syllable: Syllable
    let mutate: SongMutation
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("「\(syllable.text.value)」をのせる音符").font(.title2.bold())
            Text("複数の音符を選ぶと、ひとつの音節をのばせます。").foregroundStyle(.secondary)
            ForEach(phrase.musicalEventIDs.compactMap { song.event($0) }) { event in
                Toggle(isOn: Binding(get: { selection.contains(event.id) }, set: { enabled in
                    if enabled { selection.insert(event.id) } else { selection.remove(event.id) }
                })) { Text("\(event.note?.name ?? "休符") · 開始 \(event.onset.doubleValue, specifier: "%.2f") 拍") }
            }
            HStack {
                Button("キャンセル", role: .cancel) { dismiss() }
                Spacer()
                Button("対応を保存") {
                    mutate("音節の対応を変更") { doc in
                        try doc.align(syllableID: syllable.id, to: phrase.musicalEventIDs.filter { selection.contains($0) })
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 430)
            .onAppear {
                selection = Set(song.alignments.filter { $0.languageTargets.contains(.init(.syllable, syllable.id)) }.flatMap(\.musicTargets).compactMap {
                    if case .event(let id, _) = $0 { return id }; return nil
                })
            }
    }
}

#if DEBUG
private struct SingingPreview: View {
    @StateObject private var session = WorkspaceSession()
    private let song = SampleSongDocument.make()
    var body: some View {
        SingingView(song: song, phrase: song.phrases[0], session: session)
            .frame(width: 1050, height: 520)
    }
}

struct SingingPreviews: PreviewProvider {
    static var previews: some View {
        SingingPreview().previewDisplayName("Singing · syllable timeline")
    }
}
#endif
