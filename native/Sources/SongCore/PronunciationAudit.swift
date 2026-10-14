import Foundation

/// Read-only comparison. A dictionary match is not a judgement about context or a recording.
public enum PronunciationAudit {
    public enum Status: String, Sendable {
        case matched, review, missing, absent, unsupported
        public var label: String {
            switch self {
            case .matched: "辞書一致（文脈は未確認）"
            case .review: "要確認"
            case .missing: "未設定あり"
            case .absent: "辞書外・照合できません"
            case .unsupported: "この言語の辞書照合は未対応"
            }
        }
    }
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let phraseID: UUID
        public let surface: String
        public let context: String
        public let ipa: [String]
        public let readings: [String]
        public let dictionaryIPA: [String]
        public let issues: [String]
        public let status: Status
        public let manuallyEdited: Bool
        public let aiSources: [FieldSource]
    }

    public static func ipaKey(_ ipa: String, style: EnglishPronunciationStyle) -> String {
        // CMUdict is a broad American transcription: vowel length is not contrastively marked.
        style == .british ? EnglishPronunciation.phoneticKey(ipa) : EnglishPronunciation.comparableIPA(ipa)
    }
    private static func kanaKey(_ value: String) -> String { value.filter { !" ・·\n\t".contains($0) } }

    public static func entries(in song: SongDocument) -> [Entry] {
        let style = song.metadata.englishPronunciationStyle
        return song.phrases.flatMap { phrase in
            song.words(in: phrase).map { word in
                let units = song.syllables(in: word)
                let ipa = units.map(\.ipa.value), kana = units.map(\.reading.value)
                let english = EnglishPronunciation.supports(song.language(of: phrase))
                let dictionary = english ? EnglishPronunciation.dictionaryIPA(for: word.surface, style: style) : []
                var issues: [String] = []
                let missing = units.isEmpty || (ipa + kana).contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if missing { issues.append("IPAまたはカタカナが未設定です。") }
                if english {
                    let counts = EnglishPronunciation.dictionarySyllableCounts(for: word.surface)
                    if !counts.isEmpty, !counts.contains(units.count) {
                        issues.append("現在の区切りは\(units.count)個、辞書の音節数は\(counts.sorted().map(String.init).joined(separator: " / "))個です。歌唱上の区切りか確認してください。")
                    }
                }
                let whole = ipaKey(ipa.joined(), style: style)
                if english, !ipa.isEmpty, !ipa.contains(where: { $0.isEmpty }), !dictionary.isEmpty,
                   !dictionary.contains(where: { ipaKey($0, style: style) == whole }) {
                    issues.append("単語全体のIPAが、選択した発音基準の辞書候補と一致しません。")
                }
                let candidates = english ? EnglishPronunciation.candidates(for: word.surface, texts: units.map(\.text.value), style: style)
                    .filter { ipaKey($0.ipa.joined(), style: style) == whole } : []
                if !candidates.isEmpty, !candidates.contains(where: { candidate in
                    zip(candidate.ipa, ipa).allSatisfy { ipaKey($0, style: style) == ipaKey($1, style: style) }
                }) { issues.append("単語全体は辞書候補に一致しますが、音節への配分が辞書の候補と異なります。歌唱上の区切りか確認してください。") }
                if english, !missing {
                    // Allow documented dictionary singing conventions as well as phone-derived aids.
                    let conventional = candidates.contains { candidate in
                        zip(candidate.ipa, ipa).allSatisfy { ipaKey($0, style: style) == ipaKey($1, style: style) }
                            && candidate.readings.map(kanaKey) == kana.map(kanaKey)
                    }
                    let derived = ipa.compactMap { EnglishPronunciation.reading(forIPA: $0) }
                    if !conventional {
                        if derived.count != ipa.count { issues.append("IPAの一部をカタカナへ変換できないため、読みとの整合性を確認できません。") }
                        else if derived.map(kanaKey) != kana.map(kanaKey) {
                            issues.append("IPAから得られる読みの候補は「\(derived.joined(separator: "・"))」です。現在のカタカナと異なります。")
                        }
                    }
                }
                let sources = units.flatMap { [$0.ipa.source, $0.reading.source] }.filter { $0.kind == .ai }
                return Entry(id: word.id, phraseID: phrase.id, surface: word.surface, context: phrase.originalText,
                             ipa: ipa, readings: kana, dictionaryIPA: dictionary, issues: issues,
                             status: missing ? .missing : !english ? .unsupported : !issues.isEmpty ? .review : dictionary.isEmpty ? .absent : .matched,
                             manuallyEdited: units.contains { $0.ipa.userEdited || $0.reading.userEdited }, aiSources: sources)
            }
        }
    }
}
