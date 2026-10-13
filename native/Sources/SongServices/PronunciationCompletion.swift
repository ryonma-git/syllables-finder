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
            guard song.word(word.id) == word, result.word(word.id) == word else { continue }
            let baseline = original.syllables(in: word)
            guard song.syllables(in: word) == baseline,
                  result.syllables(in: word).map(\.id) == baseline.map(\.id) else { continue }
            for old in baseline {
                guard let index = song.syllables.firstIndex(where: { $0.id == old.id }),
                      let next = result.syllable(old.id) else { continue }
                song.syllables[index].text = next.text
                song.syllables[index].ipa = next.ipa
                song.syllables[index].reading = next.reading
                song.syllables[index].stress = next.stress
            }
        }
    }

    /// Apply validated results incrementally, falling back to another configured model when
    /// a backend cannot provide a valid pronunciation. Never send to an unconfigured API.
    @MainActor
    public func run(phraseIDs: [UUID], clients: [ModelClient]? = nil, current: () -> SongDocument,
                    apply: (SongDocument, SongDocument, UUID) -> Void,
                    progress: (String) -> Void) async throws {
        try Task.checkCancellation()
        let documentID = current().id
        let work = phraseIDs.filter { !Self.missingWords(in: current(), phraseIDs: [$0]).isEmpty }
        guard !work.isEmpty else { return }
        let available: [ModelClient]
        if let clients { available = clients }
        else {
            // Legacy command/test entry point. The app supplies its native-first configured chain.
            let models = try await OllamaProvider.models(session: session)
            available = Self.model(from: models).map { [ModelClient(.ollama($0), session: session)] } ?? []
        }
        guard !available.isEmpty else {
            throw ProviderError.unavailable("利用できるAIがありません。辞書の発音は適用済みです。「AI接続」で確認できます。")
        }
        var lastFailure: Error?
        var appliedAny = false
        var unavailable = Set<Int>()
        for (index, id) in work.enumerated() {
            for (clientIndex, client) in available.enumerated() where !unavailable.contains(clientIndex) {
                try Task.checkCancellation()
                guard current().id == documentID else { throw CancellationError() }
                let snapshot = current()
                guard let phrase = snapshot.phrase(id) else { break }
                let pending = Self.missingWords(in: snapshot, phraseIDs: [id])
                if pending.isEmpty { break }
                progress("発音を補完中 \(index + 1) / \(work.count)行（\(client.label)）")
                let provider = OllamaPronunciationProvider(client: client)
                do {
                    let result = try await provider.annotate(phrase: phrase, in: snapshot, wordIDs: Set(pending.map(\.id)))
                    try Task.checkCancellation()
                    apply(result, snapshot, id); appliedAny = true
                } catch is CancellationError { throw CancellationError() }
                catch {
                    lastFailure = error
                    // Isolate malformed word results; connection/model availability failures
                    // move straight to the next backend.
                    guard error is DecodingError || (error as? ProviderError).map({
                        if case .malformedResponse = $0 { return true }; return false
                    }) == true else { unavailable.insert(clientIndex); continue }
                    for word in pending {
                        try Task.checkCancellation()
                        let latest = current()
                        guard latest.id == documentID else { throw CancellationError() }
                        guard let line = latest.phrase(id), latest.word(word.id) == snapshot.word(word.id),
                              latest.syllables(in: word) == snapshot.syllables(in: word) else { continue }
                        do {
                            let result = try await provider.annotate(phrase: line, in: latest, wordIDs: [word.id])
                            try Task.checkCancellation()
                            apply(result, latest, id); appliedAny = true
                        } catch is CancellationError { throw CancellationError() }
                        catch { lastFailure = error }
                    }
                }
            }
        }
        if !appliedAny, let lastFailure { throw lastFailure }
    }
}
