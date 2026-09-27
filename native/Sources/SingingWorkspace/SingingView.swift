import SwiftUI
import SongCore
import AppKit

struct SingingView: View {
    let song: SongDocument
    let phrase: Phrase
    @ObservedObject var session: WorkspaceSession
    let applyRange: (BeatRange) -> Void
    let seek: (Double) -> Void
    @State private var followedRow: Int?

    private var projection: MeasureProjection { MeasureProjection(song: song) }

    var body: some View {
        GeometryReader { geometry in
            let slices = projection.slices
            let columns = overviewColumns(slices: slices, availableWidth: geometry.size.width)
            let rows = session.singingLayout == .detail
                ? projection.detailWindows
                : stride(from: 0, to: slices.count, by: columns).map { Array(slices[$0..<min($0 + columns, slices.count)]) }
            VStack(alignment: .leading, spacing: 8) {
                controls(slices: slices)
                if let warning = projection.warning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(.horizontal, 20)
                }
                if slices.isEmpty {
                    ContentUnavailableView {
                        Label("旋律はまだありません", systemImage: "music.note")
                    } description: {
                        Text("MIDI鍵盤か画面の鍵盤で旋律を入力し、歌詞を音符に割り当てられます。歌詞と発音は「読む」で編集できます。")
                    } actions: {
                        Button("旋律をステップ入力する") { session.showNotes = true; session.noteTool = .step }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollViewReader { reader in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(rows.indices, id: \.self) { index in
                                    if session.singingLayout == .overview || index == session.detailIndex {
                                        let scale = session.singingLayout == .detail ? 120 : Self.overviewScale
                                        if session.pitchDisplay == .staff && ScoreRow.issue(song: song, measures: rows[index]) == nil {
                                            ScoreRow(song: song, measures: rows[index], scale: scale,
                                                     session: session, onMeasureTap: selectMeasure, seek: seek)
                                                .id(index)
                                        } else {
                                            SingingTimelineRow(song: song, measures: rows[index], scale: scale,
                                                               session: session, onMeasureTap: selectMeasure, seek: seek)
                                                .id(index)
                                        }
                                    }
                                }
                            }.padding(.horizontal, 18).padding(.bottom, 24)
                        }
                        .modifier(ManualScrollTracking(session: session))
                        .onChange(of: session.position) { _, newPosition in
                            follow(newPosition, columns: columns, reader: reader)
                        }
                        .onChange(of: session.followPlayback) { _, following in
                            // Turning follow back on returns to the current playback position.
                            followedRow = nil
                            if following { follow(session.position, columns: columns, reader: reader) }
                        }
                        .onChange(of: session.singingLayout) { _, _ in followedRow = nil }
                        .onChange(of: columns) { _, _ in followedRow = nil }
                    }
                }
            }
            .onChange(of: session.phraseID) { _, _ in
                guard session.guideState != .playing, let range = phrase.timeRange else { return }
                session.detailIndex = projection.containing(range.start.doubleValue) / 2
            }
        }
    }

    /// 4 measures per row only when a whole row of the widest 4 consecutive measures fits;
    /// otherwise 2 (for example with the inspector open). Wider rows still scroll horizontally.
    private func overviewColumns(slices: [MeasureSlice], availableWidth: Double) -> Int {
        var quarters = 0.0
        for index in slices.indices {
            let group = slices[index..<min(index + 4, slices.count)]
            guard let first = group.first, let last = group.last else { continue }
            quarters = max(quarters, last.range.end.doubleValue - first.range.start.doubleValue)
        }
        let leading = session.pitchDisplay == .staff ? ScoreRow.leftMargin(song: song, scale: Self.overviewScale) : 58.0
        let rowChrome = leading + 16 + 36       // keyboard or clef column, row trailing space, list padding
        return availableWidth >= rowChrome + quarters * Self.overviewScale ? 4 : 2
    }

    static let overviewScale = 54.0

    private func follow(_ position: Double, columns: Int, reader: ScrollViewProxy) {
        guard session.followPlayback else { return }
        let sliceIndex = projection.containing(position)
        let next = session.singingLayout == .detail ? sliceIndex / 2 : sliceIndex / columns
        if session.singingLayout == .detail { session.detailIndex = next }
        // Scroll only when playback enters another row, not on every clock tick.
        guard followedRow != next else { return }
        followedRow = next
        withAnimation(.easeInOut(duration: 0.2)) { reader.scrollTo(next, anchor: .top) }
    }

    private func controls(slices: [MeasureSlice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("表示", selection: $session.singingLayout) {
                    ForEach(SingingLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 175)
                Picker("音高", selection: $session.pitchDisplay) {
                    ForEach(PitchDisplay.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 230)
                if song.music.parts.count > 1 {
                    Picker("声部", selection: Binding(get: { song.music.part(session.partID)?.id ?? song.music.parts.first?.id },
                                                     set: { session.partID = $0; session.stepCursor = nil })) {
                        ForEach(song.music.parts) { Text($0.name).tag(Optional($0.id)) }
                    }.frame(width: 170)
                }
                Button("声部…") { session.showingParts = true }
                Button("歌詞を割り当てる…") { session.showingAlignment = true }
                    .disabled(song.music.events.isEmpty || song.syllables.isEmpty)
                Spacer(minLength: 0)
                Toggle("読み", isOn: $session.showReading).toggleStyle(.checkbox)
                Toggle("IPA", isOn: $session.showIPA).toggleStyle(.checkbox)
                Toggle("再生位置に追従", isOn: $session.followPlayback).toggleStyle(.checkbox)
            }
            HStack(spacing: 10) {
                if session.singingLayout == .detail {
                    Button("前の2小節", systemImage: "chevron.left") {
                        session.detailIndex = max(0, session.detailIndex - 1); session.followPlayback = false
                    }.disabled(session.detailIndex == 0)
                    Button("次の2小節", systemImage: "chevron.right") {
                        session.detailIndex = min(max(0, projection.detailWindows.count - 1), session.detailIndex + 1)
                        session.followPlayback = false
                    }.disabled(session.detailIndex >= projection.detailWindows.count - 1)
                    Button("表示中の2小節を練習") {
                        let window = projection.detailWindows[min(session.detailIndex, max(0, projection.detailWindows.count - 1))]
                        if let first = window.first, let last = window.last {
                            applyRange(.init(start: first.range.start, end: last.range.end))
                        }
                    }
                }
                Button("このフレーズを練習") {
                    guard let range = phrase.timeRange else { return }
                    let matching = slices.filter { $0.range.start < range.end && range.start < $0.range.end }
                    if let first = matching.first, let last = matching.last {
                        applyRange(.init(start: first.range.start, end: last.range.end))
                    }
                }.disabled(phrase.timeRange == nil)
                if let candidate = session.practiceCandidate {
                    Text("候補: \(measureLabel(for: candidate, slices: slices))").font(.caption).foregroundStyle(.secondary)
                    Button("範囲を適用") { applyRange(candidate) }
                }
                if let range = session.practiceRange {
                    Text("練習: \(measureLabel(for: range, slices: slices))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("読みは原音の近似です").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 20).padding(.vertical, 9)
    }

    private func measureLabel(for range: BeatRange, slices: [MeasureSlice]) -> String {
        let selected = slices.filter { $0.range.start < range.end && range.start < $0.range.end }
        guard let first = selected.first, let last = selected.last else { return "拍 \(range.start.doubleValue)–\(range.end.doubleValue)" }
        return first.id == last.id ? "\(first.number)小節" : "\(first.number)–\(last.number)小節"
    }

    private func selectMeasure(_ measure: MeasureSlice) {
        if NSEvent.modifierFlags.contains(.shift), let existing = session.practiceCandidate {
            session.practiceCandidate = .init(start: min(existing.start, measure.range.start),
                                              end: max(existing.end, measure.range.end))
        } else { session.practiceCandidate = measure.range }
        session.followPlayback = false
        if session.singingLayout == .overview,
           let index = projection.slices.firstIndex(where: { $0.id == measure.id }) {
            session.detailIndex = index / 2
        }
    }
}

private struct ManualScrollTracking: ViewModifier {
    @ObservedObject var session: WorkspaceSession
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    session.followPlayback = false
                }
            }
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { _ in
                session.followPlayback = false
            })
        }
    }
}

private struct SingingTimelineRow: View {
    let song: SongDocument
    let measures: [MeasureSlice]
    let scale: Double
    @ObservedObject var session: WorkspaceSession
    let onMeasureTap: (MeasureSlice) -> Void
    let seek: (Double) -> Void

    private let left = 58.0
    private var pianoTop: Double { 180 + (session.showIPA ? 35 : 0) + max(0, session.textScale - 1) * 80 }
    private var syllableHeight: Double { pianoTop - 125 }
    private let keyHeight = 18.0
    private var start: Double { measures.first?.range.start.doubleValue ?? 0 }
    private var end: Double { measures.last?.range.end.doubleValue ?? start }
    private var pitches: [Int] { song.music.events.compactMap { $0.note?.pitch } }
    private var low: Int { max(0, (pitches.min() ?? 60) - 2) }
    private var high: Int { min(127, (pitches.max() ?? 72) + 2) }
    private var pianoHeight: Double { Double(high - low + 1) * keyHeight }
    private var height: Double { pianoTop + max(pianoHeight, 165) + 47 }
    private var width: Double { left + (end - start) * scale + 16 }
    private func x(_ beat: Double) -> Double { left + (beat - start) * scale }
    private func clipped(_ range: BeatRange) -> (Double, Double)? {
        let from = max(start, range.start.doubleValue)
        let to = min(end, range.end.doubleValue)
        return from < to ? (from, to) : nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            ForEach(measures) { measure in
                let from = x(measure.range.start.doubleValue)
                Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: height - 18).offset(x: from, y: 16)
                Button(measure.inferred ? "\(measure.number)小節（推定）" : "\(measure.number)小節") {
                    onMeasureTap(measure)
                }.font(.caption.monospacedDigit()).buttonStyle(.plain)
                    .frame(width: max(50, measure.range.length * scale - 6), alignment: .leading)
                    .offset(x: from + 4, y: 12)
                    .accessibilityHint("Shiftキーで範囲を拡張")
                let beatUnit = song.music.meters.last(where: { $0.onset <= measure.range.start }).map { 4.0 / Double($0.denominator) } ?? 1
                if beatUnit > 0 {
                    ForEach(1..<max(1, min(64, Int(ceil(measure.range.length / beatUnit)))), id: \.self) { tick in
                        let beat = measure.range.start.doubleValue + Double(tick) * beatUnit
                        if beat < measure.range.end.doubleValue {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1, height: height - 60)
                                .offset(x: x(beat), y: 45)
                        }
                    }
                }
            }
            lyrics
            pianoRoll
            if session.pitchDisplay == .staff, let issue = ScoreRow.issue(song: song, measures: measures) {
                Text("\(issue)").font(.caption).foregroundStyle(.orange).offset(x: left, y: height - 24)
            }
            if start <= session.position && session.position <= end {
                Rectangle().fill(Color.teal).frame(width: 2, height: height - 25)
                    .offset(x: x(session.position), y: 22).allowsHitTesting(false)
            }
            let translations = song.phrases.filter { phrase in
                guard let range = phrase.timeRange else { return false }
                return range.start.doubleValue < end && start < range.end.doubleValue
            }.map(\.translation.value).filter { !$0.isEmpty }
            if !translations.isEmpty {
                Text(translations.joined(separator: " ／ "))
                    .font(.system(size: 12 * session.textScale)).foregroundStyle(.secondary)
                    .lineLimit(1).help(translations.joined(separator: " ／ "))
                    .frame(width: width - left - 12, alignment: .leading)
                    .offset(x: left + 4, y: height - 28)
            }
            // The ruler is the sole click-to-seek surface; labels and note selection do not seek.
            HStack {
                Text("拍位置をクリックして移動").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.contentShape(Rectangle()).frame(width: width - left - 10, height: 18)
                .offset(x: left, y: 39)
                .onTapGesture { location in seek(start + max(0, min(end - start, (location.x / scale)))) }
        }.frame(width: width, height: height)
    }

    /// With several parts, the lyric lanes follow the selected part so that they do not stack up.
    private var lyricPart: UUID? {
        song.music.parts.count > 1 ? (song.music.part(session.partID)?.id ?? song.music.parts.first?.id) : nil
    }

    private var lyrics: some View {
        ZStack(alignment: .topLeading) {
            ForEach(song.words) { word in
                let segments = song.syllables(in: word).flatMap { song.ranges(for: .init(.syllable, $0.id), inPart: lyricPart) }
                    .compactMap(clipped)
                if let first = segments.map(\.0).min(), let last = segments.map(\.1).max() {
                    Button {
                        session.wordID = word.id; session.syllableID = nil; session.showInspector = true
                        if let phrase = song.phrase(word.parentPhraseID) { session.phraseID = phrase.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.surface).font(.system(size: 16 * session.textScale, weight: .semibold, design: .serif))
                            Text(word.contextualMeaning.value).font(.caption2).foregroundStyle(.secondary)
                        }.lineLimit(1).frame(width: max(30, (last - first) * scale - 4), alignment: .leading)
                    }.buttonStyle(.plain).offset(x: x(first) + 3, y: 64)
                        .help("\(word.surface) · \(word.contextualMeaning.value)")
                }
            }
            ForEach(song.syllables) { syllable in
                let segments = song.ranges(for: .init(.syllable, syllable.id), inPart: lyricPart).compactMap(clipped)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Button {
                        session.syllableID = syllable.id; session.wordID = syllable.parentWordID
                        session.showInspector = true
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(syllable.text.value).font(.system(size: 14 * session.textScale, weight: .medium)).lineLimit(1)
                            if session.showReading {
                                Text(syllable.reading.value.isEmpty ? "読み未設定" : syllable.reading.value)
                                    .font(.system(size: 11 * session.textScale)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if session.showIPA { Text(syllable.ipa.value.isEmpty ? "IPA未設定" : "/\(syllable.ipa.value)/")
                                .font(.system(size: 10 * session.textScale)).foregroundStyle(.secondary).lineLimit(1) }
                        }.padding(.horizontal, 4).frame(width: max(22, (segment.1 - segment.0) * scale - 3), height: syllableHeight, alignment: .leading)
                            .background(Color.teal.opacity(session.syllableID == syllable.id ? 0.25 : 0.09), in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).offset(x: x(segment.0) + 2, y: 109)
                        .accessibilityLabel("音節 \(syllable.text.value)、読み \(syllable.reading.value.isEmpty ? "未設定" : syllable.reading.value)")
                        .help("\(syllable.text.value) · \(syllable.reading.value.isEmpty ? "読み未設定" : syllable.reading.value) · \(syllable.ipa.value.isEmpty ? "IPA未設定" : "/\(syllable.ipa.value)/")")
                }
            }
        }
    }

    private var pianoRoll: some View {
        ZStack(alignment: .topLeading) {
            ForEach(low...high, id: \.self) { pitch in
                let y = pianoTop + Double(high - pitch) * keyHeight
                let black = [1, 3, 6, 8, 10].contains(pitch % 12)
                Rectangle().fill(black ? Color.primary.opacity(0.035) : .clear)
                    .frame(width: width - left, height: keyHeight).offset(x: left, y: y)
                Button {
                    session.guide.audition(pitch: pitch)
                } label: {
                    Text(Note(pitch: pitch).name).font(.system(size: 10).monospaced())
                        .foregroundStyle(black ? Color.white : Color.primary)
                        .frame(width: left - 6, height: keyHeight, alignment: .leading)
                        .padding(.leading, 4)
                        .background(black ? Color.black.opacity(0.8) : Color.white.opacity(0.85))
                }.buttonStyle(.plain).offset(y: y).accessibilityLabel("鍵盤 \(Note(pitch: pitch).name)、試聴")
            }
            ForEach(song.music.events) { event in
                if let span = try? event.range, let segment = clipped(span) {
                    let y = pianoTop + Double(high - (event.note?.pitch ?? low)) * keyHeight
                    Button {
                        session.eventID = event.id; session.showNotes = true
                        if let phrase = song.phrases.first(where: { $0.musicalEventIDs.contains(event.id) }) { session.phraseID = phrase.id }
                    } label: {
                        Text(event.note?.name ?? "休符").font(.system(size: 10).monospaced()).lineLimit(1)
                            .frame(width: max(18, (segment.1 - segment.0) * scale - 2), height: keyHeight - 2, alignment: .leading)
                            .background(session.eventID == event.id ? Color.teal.opacity(0.75) : Color.teal.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
                    }.buttonStyle(.plain).offset(x: x(segment.0) + 1, y: y)
                        .opacity(lyricPart == nil || event.partID == lyricPart ? 1 : 0.35)
                        .accessibilityLabel("\(event.note?.name ?? "休符")、\(event.duration.doubleValue)拍、音符を編集")
                }
            }
        }
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
                Picker("音符の操作", selection: $session.noteTool) {
                    ForEach(NoteTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
                Spacer()
                if session.syllableID != nil {
                    Button("選んだ音節の対応を変更…") { showingAlignment = true }.font(.caption)
                }
                if session.noteTool == .edit { Button("音符を追加", systemImage: "plus") { addNote() }.font(.caption) }
            }
            if session.noteTool == .step {
                StepInputPanel(song: song, session: session, mutate: mutate)
            } else if let event, event.note != nil {
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
            doc.ensureParts()
            let part = doc.music.part(session.partID)?.id ?? doc.music.parts[0].id
            doc.music.events.append(.init(id: id, onset: onset, duration: length, measureID: measure, content: .note(.init(pitch: 60)), partID: part))
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
        SingingView(song: song, phrase: song.phrases[0], session: session,
                    applyRange: { _ in }, seek: { _ in })
            .frame(width: 1050, height: 520)
    }
}

struct SingingPreviews: PreviewProvider {
    static var previews: some View {
        SingingPreview().previewDisplayName("Singing · syllable timeline")
    }
}
#endif
