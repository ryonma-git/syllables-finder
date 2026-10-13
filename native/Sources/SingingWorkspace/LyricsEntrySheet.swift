import SwiftUI
import AppKit
import SongCore

/// The editor and preview scroll inside a bounded sheet; actions never move below the Dock.
struct LyricsEntrySheet: View {
    @Binding var input: String
    @Binding var language: String
    @Binding var splitSyllables: Bool
    let method: String
    let cancel: () -> Void
    let add: () -> Void

    private var lines: [String] {
        input.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var availableSize: CGSize {
        (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1000, height: 750)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歌詞を追加").font(.title2.bold())
            Text("1行ずつ追加します。空白や記号を保持します。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("言語", selection: $language) {
                    ForEach(Syllabifier.languages) { Text($0.name).tag($0.id) }
                }.frame(width: 235)
                Toggle("音節に分ける", isOn: $splitSyllables).toggleStyle(.checkbox)
            }
            TextEditor(text: $input)
                .font(.body).frame(minHeight: 100, maxHeight: .infinity)
                .border(Color.secondary.opacity(0.2)).accessibilityLabel("追加する歌詞")
            if splitSyllables && !lines.isEmpty {
                Text("音節の候補（先頭3行）").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                            Text(preview(line)).font(.system(size: 13, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 70)
            }
            if splitSyllables {
                Text("追加後の発音補完：\(method)。手修正は保持します。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text("\(lines.count)行").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("キャンセル", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("追加", action: add).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(lines.isEmpty)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: min(680, availableSize.width - 60), height: min(580, availableSize.height - 120), alignment: .topLeading)
    }

    private func preview(_ line: String) -> String {
        Syllabifier.tokenize(line, language: language).map { token in
            let parts = Syllabifier.syllabify(token, language: language).syllables
            return parts.isEmpty ? token.surface + "（未分割）" : parts.joined(separator: "・")
        }.joined(separator: "   ")
    }
}
