import SwiftUI
import SongCore

struct SwingSheet: View {
    let song: SongDocument
    let selection: BeatRange?
    let apply: (SongDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var subdivision: SwingSettings.Subdivision
    @State private var percent: Double
    @State private var scope: Scope
    @State private var convertPerformed = false
    @State private var error: String?

    private enum Scope: String, CaseIterable { case existing = "現在の範囲を維持", whole = "曲全体", selection = "選択した小節" }

    init(song: SongDocument, selection: BeatRange?, apply: @escaping (SongDocument) -> Void) {
        self.song = song; self.selection = selection; self.apply = apply
        let settings = song.music.swing ?? SwingSettings(enabled: false)
        _enabled = State(initialValue: settings.enabled)
        _subdivision = State(initialValue: settings.subdivision)
        _percent = State(initialValue: settings.percent)
        _scope = State(initialValue: settings.ranges.isEmpty ? .whole : .existing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("スウィング設定").font(.title2.bold())
            Text("楽譜と音符は通常の音価で保ち、再生時の長短の比率を調整します。オフにすると等間隔に戻ります。")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Toggle("スウィングを有効にする", isOn: $enabled)
            Picker("単位", selection: $subdivision) {
                ForEach(SwingSettings.Subdivision.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("長い音の割合")
                    Slider(value: $percent, in: 50...75, step: 0.1).accessibilityLabel("スウィングの比率")
                    Text("\(percent.formatted(.number.precision(.fractionLength(1))))%")
                        .monospacedDigit().frame(width: 58, alignment: .trailing)
                }
                HStack {
                    Button("均等 50%") { percent = 50 }
                    Button("軽め 60%") { percent = 60 }
                    Button("2:1（66.7%）") { percent = 200 / 3 }
                    Button("強め 75%") { percent = 75 }
                }
                Text("50%は均等、66.7%は長短2:1。16分を選ぶと、8分音符の位置を保って16分音符の組を跳ねさせます。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("適用する範囲", selection: $scope) {
                if !(song.music.swing?.ranges.isEmpty ?? true) { Text(Scope.existing.rawValue).tag(Scope.existing) }
                Text(Scope.whole.rawValue).tag(Scope.whole)
                if selection != nil { Text(Scope.selection.rawValue).tag(Scope.selection) }
            }
            Text(rangeSummary).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if song.music.swing == nil {
                GroupBox("取り込んだ音符の変換") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("すでに跳ねている音符を、通常の音価へ戻す", isOn: $convertPerformed)
                        Text("演奏タイミングが保存されたMIDIなどで使います。選んだ単位・比率・範囲のスウィングを取り除き、再生設定に移します。三連符からの自動判定は行いません。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if convertPerformed {
                            Text("音符の位置・長さを変換します。歌詞や音高、対応付けは保ち、⌘Zで戻せます。")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(convertPerformed ? "変換して適用" : "適用") { commit() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 600)
    }

    private var ranges: [BeatRange] {
        switch scope {
        case .whole: []
        case .existing: song.music.swing?.ranges ?? []
        case .selection: selection.map { [$0] } ?? []
        }
    }

    private var rangeSummary: String {
        guard !ranges.isEmpty else { return "曲全体に適用します。" }
        let measures = MeasureProjection(song: song).slices
        let labels = ranges.map { range in
            let included = measures.filter { range.start <= $0.range.start && $0.range.end <= range.end }
            if let first = included.first, let last = included.last { return "\(first.number)〜\(last.number)小節" }
            return "\(range.start.doubleValue.formatted())〜\(range.end.doubleValue.formatted())拍"
        }
        return labels.joined(separator: "、") + "に適用します。それ以外の区間はストレートです。"
    }

    private func commit() {
        do {
            // The displayed triplet preset is 66.7%, but retains exactly 2/3 internally.
            let ratio = abs(percent - 200 / 3) < 0.000_001 || abs(percent - 66.7) < 0.000_001
                ? try Beat(2, 3) : try Beat(Int64((percent * 10).rounded()), 1000)
            let settings = SwingSettings(enabled: enabled, subdivision: subdivision, longFraction: ratio, ranges: ranges)
            try settings.validate()
            let next = convertPerformed
                ? try SwingConversion.normalizingPerformedTiming(in: song, settings: settings)
                : try song.editing { $0.music.swing = settings }
            apply(next); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
