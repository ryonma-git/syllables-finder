import SwiftUI
import SongCore

struct WordEditor: View {
    struct Unit: Identifiable {
        let id = UUID()
        var text = ""
        var reading = ""
        var ipa = ""
    }

    let word: Word
    let initial: [Syllable]
    let definition: String
    let language: String
    let canChangeGroups: Bool
    let save: ((inout SongDocument) throws -> Void) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var units: [Unit]
    @State private var meaning: String
    @State private var error: String?

    init(song: SongDocument, word: Word, save: @escaping ((inout SongDocument) throws -> Void) -> Bool) {
        self.word = word; self.save = save
        initial = song.syllables(in: word)
        definition = word.dictionaryMeaning.value
        language = song.phrase(word.parentPhraseID).map(song.language(of:)) ?? song.metadata.sourceLanguage
        let references = Set([word.id] + word.syllableIDs)
        canChangeGroups = !song.alignments.contains { $0.languageTargets.contains { references.contains($0.id) } } &&
            song.phrase(word.parentPhraseID)?.musicalEventIDs.isEmpty == true &&
            initial.allSatisfy { $0.phonemeIDs.isEmpty && $0.moraIDs.isEmpty && $0.connectedReading == nil && $0.connectedIPA == nil }
        _meaning = State(initialValue: word.contextualMeaning.value)
        _units = State(initialValue: initial.map { Unit(text: $0.text.value, reading: $0.reading.value, ipa: $0.ipa.value) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(word.surface).font(.title.bold())
            Text("単語の意味").font(.headline)
            TextField("この行での日本語訳", text: $meaning).textFieldStyle(.roundedBorder)
            if !definition.isEmpty {
                DisclosureGroup("辞書の意味") { Text(definition).font(.callout).textSelection(.enabled) }
            }
            Divider()
            HStack {
                Text("音節と発音").font(.headline)
                Spacer()
                if canChangeGroups { Button("音節を追加", systemImage: "plus") { units.append(.init()) } }
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 7, verticalSpacing: 7) {
                    GridRow { Text("音節"); Text("カタカナ"); Text("発音記号（IPA）"); Color.clear.frame(width: 20, height: 0) }
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($units) { $unit in
                        GridRow {
                            TextField("音節", text: $unit.text).disabled(!canChangeGroups)
                            TextField("カタカナ", text: $unit.reading)
                            TextField("IPA", text: $unit.ipa)
                            if canChangeGroups {
                                Button { units.removeAll { $0.id == unit.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).accessibilityLabel("この音節を取り除く")
                            } else { Color.clear.frame(width: 20, height: 0) }
                        }.textFieldStyle(.roundedBorder)
                    }
                }
            }.frame(minHeight: 75, maxHeight: 210)
            if !canChangeGroups { Text("音符や詳細な発音との対応を保つため、音節の区切りは固定されています。").font(.caption) }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("キャンセル", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("適用", action: apply).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 520)
    }

    private func apply() {
        let texts = units.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !texts.contains("") else { error = "各音節の文字を入力してください。"; return }
        let previous = initial.map(\.text.value)
        if !previous.isEmpty, language != "ja", texts.joined() != previous.joined() {
            error = "音節をつなぐと「" + previous.joined() + "」になるように区切ってください。"
            return
        }
        let changed = save { current in
            guard let i = current.words.firstIndex(where: { $0.id == word.id }),
                  current.words[i] == word, current.syllables(in: word) == initial else { throw SongError.staleAnalysis }
            if previous != texts { try current.setSyllables(wordID: word.id, texts: texts) }
            current.words[i].contextualMeaning.edit(meaning)
            for (offset, id) in current.words[i].syllableIDs.enumerated() {
                guard let index = current.syllables.firstIndex(where: { $0.id == id }) else { throw SongError.staleAnalysis }
                current.syllables[index].ipa.edit(units[offset].ipa.trimmingCharacters(in: .whitespacesAndNewlines))
                current.syllables[index].reading.edit(units[offset].reading.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if changed { dismiss() } else { error = "教材が更新されたため、単語を開き直してください。" }
    }
}
