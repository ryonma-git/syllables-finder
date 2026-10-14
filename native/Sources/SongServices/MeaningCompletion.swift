import Foundation
import SongCore

/// Fills missing meanings without replacing existing translations or concurrent edits.
public enum MeaningCompletion {
    private static func needs(_ field: TextFieldValue) -> Bool {
        !field.userEdited && field.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func missing(in song: SongDocument, phraseIDs: Set<UUID>) -> (words: Int, lines: Int) {
        (song.words.filter { phraseIDs.contains($0.parentPhraseID) && needs($0.contextualMeaning) }.count,
         song.phrases.filter { phraseIDs.contains($0.id) && needs($0.translation) }.count)
    }

    public static func merge(_ result: SongDocument, from original: SongDocument,
                             phraseID: UUID, into song: inout SongDocument) {
        guard song.id == original.id, result.id == original.id,
              let before = original.phrase(phraseID), let current = song.phrase(phraseID),
              before.originalText == current.originalText, before.wordIDs == current.wordIDs,
              original.language(of: before) == song.language(of: current),
              original.words(in: before).map(\.surface) == song.words(in: current).map(\.surface),
              let p = song.phrases.firstIndex(where: { $0.id == phraseID }),
              let translated = result.phrase(phraseID) else { return }
        if needs(before.translation), current.translation == before.translation {
            song.phrases[p].translation = translated.translation
        }
        for old in original.words(in: before) {
            guard let i = song.words.firstIndex(where: { $0.id == old.id }),
                  let next = result.word(old.id) else { continue }
            for field in [\Word.lemma, \Word.partOfSpeech, \Word.contextualMeaning, \Word.dictionaryMeaning] {
                if needs(old[keyPath: field]), song.words[i][keyPath: field] == old[keyPath: field] {
                    song.words[i][keyPath: field] = next[keyPath: field]
                }
            }
        }
    }

    @MainActor
    public static func run(phraseIDs: [UUID], providers: [any AIProvider], current: () -> SongDocument,
                           apply: (SongDocument, SongDocument, UUID) -> Void,
                           progress: (String) -> Void) async throws {
        try Task.checkCancellation()
        let documentID = current().id
        let work = phraseIDs.filter {
            let count = missing(in: current(), phraseIDs: [$0])
            return count.words + count.lines > 0
        }
        guard !work.isEmpty else { return }
        guard !providers.isEmpty else {
            throw ProviderError.unavailable("意味・全文訳を補完できるAIがありません。「AI接続」で確認してください。辞書定義は単語の詳細で確認できます。")
        }
        var unavailable = Set<Int>()
        var failure: Error?
        for (index, id) in work.enumerated() {
            for (providerIndex, provider) in providers.enumerated() where !unavailable.contains(providerIndex) {
                try Task.checkCancellation()
                let snapshot = current()
                guard snapshot.id == documentID else { throw CancellationError() }
                guard let phrase = snapshot.phrase(id) else { break }
                let count = missing(in: snapshot, phraseIDs: [id])
                if count.words + count.lines == 0 { break }
                progress("意味・訳を補完中 \(index + 1) / \(work.count)行（\(provider.displayName)）")
                do {
                    let request = LinguisticAnalysisRequest(document: snapshot, phrase: phrase)
                    let analysis = try await provider.analyze(request: request)
                    guard !analysis.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          analysis.words.allSatisfy({ !$0.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                        throw ProviderError.malformedResponse
                    }
                    let result = try LinguisticAnalysisService().apply(analysis, request: request, source: provider.source, to: snapshot)
                    try Task.checkCancellation()
                    apply(result, snapshot, id)
                    break
                } catch is CancellationError { throw CancellationError() }
                catch {
                    failure = error
                    if case ProviderError.unavailable = error { unavailable.insert(providerIndex) }
                    if error is URLError { unavailable.insert(providerIndex) }
                }
            }
        }
        let remaining = missing(in: current(), phraseIDs: Set(phraseIDs))
        if remaining.words + remaining.lines > 0, let failure { throw failure }
    }
}
