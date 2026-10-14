import Foundation

/// Shared by the screen, audit and both exporters; a word-level fallback never pretends to
/// resolve note/syllable alignment, and never covers up a manually edited pronunciation.
public struct PronunciationDisplay: Sendable {
    public let ipa: String
    public let reading: String
    public let notice: String?
    public let whole: WholePronunciation?
    public var reviewNotice: String? {
        guard let review = whole?.verification, review.verdict != "ok" else { return nil }
        return review.verdict == "review" ? "AI検証：要確認" : "AI検証：未確認"
    }

    public init(word: Word, syllables: [Syllable], style: EnglishPronunciationStyle) {
        let incomplete = syllables.isEmpty || syllables.contains { $0.ipa.value.isEmpty || $0.reading.value.isEmpty }
        let saved = word.wholePronunciation
        let valid = saved?.surface == word.surface && saved?.style == style &&
            saved?.ipa.isEmpty == false && saved?.reading.isEmpty == false &&
            !syllables.contains { $0.ipa.userEdited || $0.reading.userEdited }
        let consistent = incomplete || saved.map {
            PronunciationAudit.ipaKey($0.ipa, style: style) == PronunciationAudit.ipaKey(syllables.map(\.ipa.value).joined(), style: style)
        } == true
        whole = valid && consistent ? saved : nil
        if incomplete, let whole {
            ipa = whole.ipa; reading = whole.reading
            notice = "単語全体の読み・音節対応は要確認"
        } else {
            ipa = syllables.isEmpty || syllables.contains { $0.ipa.value.isEmpty } ? "" : syllables.map(\.ipa.value).joined(separator: "·")
            reading = syllables.allSatisfy { $0.reading.value.isEmpty } ? "" : syllables.map { $0.reading.value.isEmpty ? "□" : $0.reading.value }.joined(separator: "・")
            notice = nil
        }
    }
}

extension SongDocument {
    public func pronunciationDisplay(for word: Word) -> PronunciationDisplay {
        var checked = word
        if let review = checked.wholePronunciation?.verification,
           review.context != phrase(word.parentPhraseID)?.originalText {
            checked.wholePronunciation?.verification = nil
        }
        return .init(word: checked, syllables: syllables(in: word), style: metadata.englishPronunciationStyle)
    }

    /// Changing IDs is safe only for untouched automatic spelling with no alignment/detail.
    public func canRepairPronunciationStructure(_ word: Word) -> Bool {
        let units = syllables(in: word)
        let ids = Set(word.syllableIDs + [word.id])
        return !word.structureUserEdited && !units.isEmpty && units.allSatisfy {
            !$0.structureUserEdited && !$0.text.userEdited && !$0.ipa.userEdited && !$0.reading.userEdited && !$0.stress.userEdited &&
            $0.phonemeIDs.isEmpty && $0.moraIDs.isEmpty
        } && !alignments.contains { $0.languageTargets.contains { ids.contains($0.id) } }
            && phrase(word.parentPhraseID)?.musicalEventIDs.isEmpty == true
    }
}
