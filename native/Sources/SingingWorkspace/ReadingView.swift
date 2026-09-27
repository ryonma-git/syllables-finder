import SwiftUI
import SongCore

struct ReadingView: View {
    let song: SongDocument
    let phrase: Phrase
    @ObservedObject var session: WorkspaceSession
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 215 * session.textScale), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(song.words(in: phrase)) { word in
                    Button {
                        session.wordID = word.id; session.syllableID = nil; session.showInspector = true
                    } label: { WordCell(word: word, syllables: song.syllables(in: word), selected: session.wordID == word.id, scale: session.textScale) }
                        .buttonStyle(.plain).accessibilityLabel("\(word.surface)、\(word.contextualMeaning.value)、詳細を編集")
                }
            }.padding(.horizontal, 30).padding(.bottom, 30)
            VStack(alignment: .leading, spacing: 8) {
                Label("読む → たしかめる → 歌う", systemImage: "leaf").font(.callout.weight(.medium)).foregroundStyle(.teal)
                Text("まず意味と音節を確かめましょう。IPAや読みは単語の詳細で追加できます。\n「歌う」に切り替えると、音節をのせる場所が見えます。")
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                .background(Color.teal.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 30).padding(.bottom, 30)
        }
    }
}

struct WordCell: View {
    let word: Word
    let syllables: [Syllable]
    let selected: Bool
    let scale: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(word.contextualMeaning.value.isEmpty ? "意味を追加" : word.contextualMeaning.value)
                    .font(.system(size: 14 * scale, weight: .medium)).foregroundStyle(.teal)
                Spacer(minLength: 4)
                if word.contextualMeaning.userEdited { Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(word.surface).font(.system(size: 27 * scale, weight: .semibold, design: .serif)).foregroundStyle(.primary)
            Text(syllables.allSatisfy { $0.ipa.value.isEmpty } ? "IPAは未設定" :
                 "/" + syllables.map { $0.ipa.value.isEmpty ? "?" : $0.ipa.value }.joined(separator: ".") + "/")
                .font(.system(size: 17 * scale)).foregroundStyle(.secondary)
            if !syllables.allSatisfy({ $0.reading.value.isEmpty }) {
                Text(syllables.map(\.reading.value).joined()).font(.system(size: 14 * scale)).foregroundStyle(.secondary)
            }
            Divider().padding(.top, 5)
            HStack(spacing: 7) {
                ForEach(syllables) { syllable in
                    Text(syllable.text.value).font(.system(size: 13 * scale, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.teal.opacity(0.08), in: Capsule())
                }
                if syllables.isEmpty { Text("音節をまだ分割していません").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
        }.padding(22).frame(maxWidth: .infinity, minHeight: 245 * scale, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.teal : Color.primary.opacity(0.09), lineWidth: selected ? 2 : 1))
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
