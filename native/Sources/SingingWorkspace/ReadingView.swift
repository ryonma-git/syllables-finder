import SwiftUI
import SongCore
import SongPrint

struct ReadingView: View {
    let song: SongDocument
    let phrase: Phrase
    @ObservedObject var session: WorkspaceSession
    var body: some View {
        ScrollView {
            LyricsFlowLayout(horizontalSpacing: 11 * session.textScale, verticalSpacing: 18 * session.textScale) {
                ForEach(song.words(in: phrase)) { word in
                    Button {
                        session.wordID = word.id; session.syllableID = nil; session.showInspector = true
                    } label: {
                        InterlinearWord(word: word, syllables: song.syllables(in: word),
                                        language: phrase.language ?? song.metadata.sourceLanguage,
                                        selected: session.wordID == word.id, scale: session.textScale)
                    }
                        .buttonStyle(.plain).accessibilityLabel("\(word.surface)、\(word.contextualMeaning.value)、詳細を編集")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30).padding(.bottom, 30)
        }
    }
}

private struct InterlinearWord: View {
    let word: Word
    let syllables: [Syllable]
    let language: String
    let selected: Bool
    let scale: Double
    private var printWord: PrintWord {
        PrintWord(original: word.surface, meaning: word.contextualMeaning.value,
                  syllables: syllables.map { PrintSyllable(text: $0.text.value, language: language) },
                  ipa: syllables.isEmpty || syllables.contains(where: { $0.ipa.value.isEmpty }) ? "" :
                    "/" + syllables.map(\.ipa.value).joined(separator: "·") + "/",
                  reading: syllables.isEmpty || syllables.contains(where: { $0.reading.value.isEmpty }) ? "" :
                    syllables.map(\.reading.value).joined(separator: "・"))
    }
    private var columnWidth: CGFloat {
        let item = printWord
        let lyricWidth = CGFloat(item.segmented.count) * 13.5 * scale
        let annotationWidth = CGFloat(max(item.meaning.count, item.ipa.count, item.reading.count)) * 8.5 * scale
        return max(54 * scale, min(180 * scale, max(lyricWidth, annotationWidth) + 5))
    }
    private var coloredLyric: Text {
        printWord.displayFragments.reduce(Text("")) { result, fragment in
            result + Text(fragment.text).foregroundColor(fragment.isVowelNucleus ? .teal : .primary)
        }
    }
    var body: some View {
        let item = printWord
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(item.meaning.isEmpty ? "意味未設定" : item.meaning)
                .font(.system(size: 11 * scale)).foregroundStyle(.secondary).lineLimit(2)
                .frame(height: 29 * scale, alignment: .bottomLeading)
            coloredLyric.font(.system(size: 22 * scale, weight: .semibold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(item.ipa.isEmpty ? "IPA未設定" : item.ipa)
                .font(.system(size: 11 * scale)).foregroundStyle(.secondary).lineLimit(1)
            Text(item.reading.isEmpty ? "読み未設定" : item.reading)
                .font(.system(size: 11 * scale)).foregroundStyle(.secondary).lineLimit(1)
            Rectangle().fill(selected ? Color.teal : .clear).frame(height: 2 * scale)
        }
        .frame(width: columnWidth, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct LyricsFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        let rows = arrange(subviews, maxWidth: width)
        return CGSize(width: width, height: rows.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, maxWidth: bounds.width)
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var result: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + verticalSpacing; rowHeight = 0
            }
            result.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return result
    }
}

typealias SongMutation = (String, (inout SongDocument) throws -> Void) -> Void

struct WordInspector: View {
    let song: SongDocument
    let wordID: UUID?
    let mutate: SongMutation
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ことばの詳細").font(.headline)
                if let wordID, let word = song.word(wordID) {
                    Text(word.surface).font(.title2.bold())
                    SyllableSplitEditor(song: song, word: word, mutate: mutate).id(word.id)
                    field("文脈での意味", word: word, keyPath: \.contextualMeaning)
                    field("辞書の意味", word: word, keyPath: \.dictionaryMeaning)
                    field("原形", word: word, keyPath: \.lemma)
                    field("品詞", word: word, keyPath: \.partOfSpeech)
                    field("補足", word: word, keyPath: \.notes)
                    Divider()
                    ForEach(song.syllables(in: word)) { syllable in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(syllable.text.value).font(.headline).foregroundStyle(.teal)
                            syllableField("音節", syllable: syllable, keyPath: \.text)
                            syllableField("IPA", syllable: syllable, keyPath: \.ipa)
                            syllableField("カタカナ読み", syllable: syllable, keyPath: \.reading)
                            syllableField("強勢", syllable: syllable, keyPath: \.stress)
                            DisclosureGroup("音素・モーラ") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(song.phonemes.filter { $0.parentSyllableID == syllable.id }.map(\.ipa.value).joined(separator: " · "))
                                    ForEach(song.moras.filter { $0.parentSyllableID == syllable.id }) { mora in
                                        Text("\(mora.text.value)  /\(mora.ipa.value)/")
                                    }
                                }.font(.callout).padding(.top, 8)
                            }.font(.caption)
                        }
                    }
                    Label("手修正した値は再解析でも保持します", systemImage: "lock").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                } else { Text("単語を選ぶと、意味や発音を編集できます。").font(.callout).foregroundStyle(.secondary) }
            }.padding(22)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    private func field(_ title: String, word: Word, keyPath: WritableKeyPath<Word, TextFieldValue>) -> some View {
        LabeledEditor(title: title, manual: word[keyPath: keyPath].userEdited, text: Binding(
            get: { song.word(word.id)?[keyPath: keyPath].value ?? "" },
            set: { value in mutate(title + "を編集") { doc in
                if let i = doc.words.firstIndex(where: { $0.id == word.id }) { doc.words[i][keyPath: keyPath].edit(value) }
            }}))
    }
    private func syllableField(_ title: String, syllable: Syllable, keyPath: WritableKeyPath<Syllable, TextFieldValue>) -> some View {
        LabeledEditor(title: title, manual: syllable[keyPath: keyPath].userEdited, text: Binding(
            get: { song.syllable(syllable.id)?[keyPath: keyPath].value ?? "" },
            set: { value in mutate(title + "を編集") { doc in
                if let i = doc.syllables.firstIndex(where: { $0.id == syllable.id }) { doc.syllables[i][keyPath: keyPath].edit(value) }
            }}))
    }
}

/// Edits a word's syllable boundaries as text ("Freu-de"), or re-runs the language rules.
struct SyllableSplitEditor: View {
    let song: SongDocument
    let word: Word
    let mutate: SongMutation
    @State private var text = ""

    private var current: String { song.syllables(in: word).map(\.text.value).joined(separator: "-") }
    private var language: String { song.phrase(word.parentPhraseID).map { song.language(of: $0) } ?? song.metadata.sourceLanguage }
    private var fromRules: Bool { song.syllables(in: word).contains { $0.text.source.kind == .rule } && !word.structureUserEdited }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("音節の区切り")
                Spacer()
                Text(word.syllableIDs.isEmpty ? "未分割" : fromRules ? "規則による候補" : word.structureUserEdited ? "手動" : "サンプル")
                    .foregroundStyle(word.structureUserEdited ? Color.teal : Color.secondary)
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("例: Freu-de", text: $text).textFieldStyle(.roundedBorder)
                    .onSubmit(apply).accessibilityLabel("音節の区切り（ハイフンで区切る）")
                Button("適用", action: apply).disabled(normalized(text) == current)
            }
            HStack {
                Text("ハイフン（-）で区切ります。数が変わると、その語の音符への対応は外れます。")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if Syllabifier.supports(language) && (!word.structureUserEdited || word.syllableIDs.isEmpty) {
                    Button("規則で分け直す") {
                        mutate("音節を分け直す") { try $0.resyllabify(wordID: word.id, language: language) }
                    }.font(.caption)
                }
            }
        }
        .onAppear { text = current }
        .onChange(of: current) { _, value in text = value }
    }

    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "・", with: "-").replacingOccurrences(of: "·", with: "-")
            .split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "-")
    }

    private func apply() {
        let parts = normalized(text).split(separator: "-").map(String.init)
        guard !parts.isEmpty, normalized(text) != current else { return }
        mutate("音節の区切りを変更") { try $0.setSyllables(wordID: word.id, texts: parts) }
    }
}

struct LabeledEditor: View {
    let title: String
    let manual: Bool
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                if manual { Text("手動").foregroundStyle(.teal) }
            }.font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $text, axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }
}
