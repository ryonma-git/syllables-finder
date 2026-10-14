import Foundation
import SongCore

/// Completes missing fields locally, then merges only words that have not changed while awaiting AI.
public struct PronunciationCompletion: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public static func missingWords(in song: SongDocument, phraseIDs: Set<UUID>) -> [Word] {
        song.words.filter { word in
            guard phraseIDs.contains(word.parentPhraseID) else { return false }
            let syllables = song.syllables(in: word)
            return syllables.isEmpty || syllables.contains {
                $0.ipa.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                $0.reading.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    public static func model(from models: [String]) -> String? {
        if models.contains("qwen3.5:9b") { return "qwen3.5:9b" }
        return models.sorted().first { $0.lowercased().hasPrefix("qwen") }
    }

    /// Never replace the document wholesale: title, translation, manual corrections, new lines,
    /// syllable IDs and note alignments may have changed since the request started.
    public static func merge(_ result: SongDocument, from original: SongDocument,
                             phraseID: UUID, into song: inout SongDocument) {
        guard song.id == original.id, result.id == original.id,
              song.metadata.englishPronunciationStyle == original.metadata.englishPronunciationStyle,
              result.metadata.englishPronunciationStyle == original.metadata.englishPronunciationStyle,
              let before = original.phrase(phraseID), let current = song.phrase(phraseID),
              before.originalText == current.originalText, before.wordIDs == current.wordIDs,
              original.language(of: before) == song.language(of: current) else { return }
        for word in original.words(in: before) {
            guard song.word(word.id) == word, let updated = result.word(word.id),
                  let wordIndex = song.words.firstIndex(where: { $0.id == word.id }) else { continue }
            var comparable = updated
            comparable.syllableIDs = word.syllableIDs; comparable.wholePronunciation = word.wholePronunciation
            guard comparable == word else { continue }
            let baseline = original.syllables(in: word)
            guard song.syllables(in: word) == baseline else { continue }
            let next = result.syllables(in: updated)
            if next.map(\.id) != baseline.map(\.id) {
                // An alignment created while AI was running must prevent a stale structural repair.
                guard original.canRepairPronunciationStructure(word), song.canRepairPronunciationStructure(word),
                      next.map(\.text.value).joined() == baseline.map(\.text.value).joined(),
                      next.allSatisfy({ $0.parentWordID == word.id && $0.phonemeIDs.isEmpty && $0.moraIDs.isEmpty }) else { continue }
                let ids = Set(word.syllableIDs)
                let insertion = song.syllables.firstIndex { ids.contains($0.id) } ?? song.syllables.count
                song.syllables.removeAll { ids.contains($0.id) }
                song.syllables.insert(contentsOf: next, at: min(insertion, song.syllables.count))
                song.words[wordIndex].syllableIDs = updated.syllableIDs
            } else {
                for old in baseline {
                    guard let index = song.syllables.firstIndex(where: { $0.id == old.id }),
                          let next = result.syllable(old.id) else { continue }
                    song.syllables[index].text = next.text
                    song.syllables[index].ipa = next.ipa
                    song.syllables[index].reading = next.reading
                    song.syllables[index].stress = next.stress
                }
            }
            song.words[wordIndex].wholePronunciation = updated.wholePronunciation
        }
    }

    /// Apply validated results incrementally, falling back to another configured model when
    /// a backend cannot provide a valid pronunciation. Never send to an unconfigured API.
    @discardableResult
    @MainActor
    public func run(phraseIDs: [UUID], clients: [ModelClient]? = nil, verifyCandidates: Bool = true, current: () -> SongDocument,
                    apply: (SongDocument, SongDocument, UUID) -> Void,
                    progress: (String) -> Void) async throws -> [PronunciationIssue] {
        try Task.checkCancellation()
        let documentID = current().id
        let initial = current()
        // The offline stage runs even with no AI, before missing-word selection.
        for id in phraseIDs {
            let snapshot = current()
            var repaired = snapshot
            EnglishPronunciation.repairAutomaticSegmentation(in: &repaired, phraseIDs: [id])
            EnglishPronunciation.apply(to: &repaired, phraseIDs: [id])
            if repaired != snapshot { apply(repaired, snapshot, id) }
        }
        let work = phraseIDs.filter { !Self.missingWords(in: current(), phraseIDs: [$0]).isEmpty }
        guard !work.isEmpty else { return [] }
        let available: [ModelClient]
        if let clients { available = clients }
        else {
            // Legacy command/test entry point. The app supplies its native-first configured chain.
            let models = try await OllamaProvider.models(session: session)
            let preferred = Self.model(from: models)
            let ordered = models.sorted().filter { $0 != preferred }
            available = ((preferred.map { [$0] } ?? []) + ordered).map { ModelClient(.ollama($0), session: session) }
        }
        guard !available.isEmpty else {
            throw ProviderError.unavailable("利用できるAIがありません。辞書の発音は適用済みです。「AI接続」で確認できます。")
        }
        var issues: [UUID: PronunciationIssue] = [:]
        var lastFailure: Error?
        var appliedAny = false
        var unavailable = Set<Int>()
        for (index, id) in work.enumerated() {
            // One bounded recovery pass removes spelling groups from the model's task.
            // This permits a whole pronunciation even when no model can allocate its sounds.
            for wholeOnly in [false, true] {
                for (clientIndex, client) in available.enumerated() where !unavailable.contains(clientIndex) {
                    try Task.checkCancellation()
                    guard current().id == documentID else { throw CancellationError() }
                    let snapshot = current()
                    guard let phrase = snapshot.phrase(id) else { break }
                    let pending = Self.missingWords(in: snapshot, phraseIDs: [id]).filter {
                        !wholeOnly || (EnglishPronunciation.supports(snapshot.language(of: phrase)) &&
                            snapshot.pronunciationDisplay(for: $0).whole == nil &&
                            EnglishPronunciation.dictionaryIPA(for: $0.surface, style: snapshot.metadata.englishPronunciationStyle).isEmpty)
                    }
                    if pending.isEmpty { break }
                    progress("\(wholeOnly ? "単語全体を再確認中" : "発音を補完中") \(index + 1) / \(work.count)行（\(client.label)）")
                    let provider = OllamaPronunciationProvider(client: client)
                    do {
                        let result = try await provider.annotateWithReport(phrase: phrase, in: snapshot, wordIDs: Set(pending.map(\.id)), wholeWordOnly: wholeOnly)
                        try Task.checkCancellation()
                        apply(result.document, snapshot, id); appliedAny = true
                        for issue in result.issues { issues[issue.wordID] = issue }
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        lastFailure = error
                        let malformed = error is DecodingError || (error as? ProviderError).map({
                            if case .malformedResponse = $0 { return true }; return false
                        }) == true
                        // No per-word request storm: retain this line and proceed to another model
                        // or the next line. Connection failures are not retried for every phrase.
                        if !malformed { unavailable.insert(clientIndex) }
                        for word in pending {
                            issues[word.id] = .init(wordID: word.id, phraseID: id, surface: word.surface,
                                reason: malformed ? "AIの回答を読み取れませんでした。" : "AIへ接続・生成できませんでした。")
                        }
                    }
                }
            }
        }
        if !appliedAny, !unavailable.isEmpty, unavailable.count == available.count, let lastFailure { throw lastFailure }
        var reviewIssues: [PronunciationIssue] = []
        if verifyCandidates {
            let snapshot = current()
            let selected = Set(snapshot.words.filter {
                phraseIDs.contains($0.parentPhraseID) && $0.wholePronunciation?.source.kind == .ai &&
                $0.wholePronunciation != initial.word($0.id)?.wholePronunciation
            }.map(\.id))
            if !selected.isEmpty {
                try await PronunciationReview.run(document: snapshot, clients: available, wordIDs: selected, update: { id, review in
                    guard current().id == documentID, let word = snapshot.word(id),
                          let index = snapshot.words.firstIndex(where: { $0.id == id }) else { return }
                    var checked = snapshot
                    checked.words[index].wholePronunciation?.verification = .init(reviewer: review.reviewer,
                        verdict: review.verdict.rawValue, explanation: review.kind.label + "。" + review.explanation, context: snapshot.phrase(word.parentPhraseID)?.originalText)
                    apply(checked, snapshot, word.parentPhraseID)
                    if review.verdict != .ok,
                       current().word(id)?.wholePronunciation?.verification == checked.words[index].wholePronunciation?.verification {
                        reviewIssues.append(.init(wordID: id, phraseID: word.parentPhraseID, surface: word.surface,
                            reason: review.kind.label + "：" + review.explanation))
                    }
                }, progress: progress)
            }
        }
        let remaining = Self.missingWords(in: current(), phraseIDs: Set(phraseIDs))
        return reviewIssues + remaining.filter { word in !reviewIssues.contains { $0.wordID == word.id } }.map { word in
            if current().pronunciationDisplay(for: word).notice != nil {
                return .init(wordID: word.id, phraseID: word.parentPhraseID, surface: word.surface,
                             reason: "単語全体の読みを表示しています。音節対応は要確認です。")
            }
            return issues[word.id] ?? .init(wordID: word.id, phraseID: word.parentPhraseID, surface: word.surface,
                                           reason: "手修正・詳細な音素構造、または辞書候補を確認してください。")
        }
    }
}
