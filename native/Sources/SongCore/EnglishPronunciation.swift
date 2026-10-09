import Foundation

/// Offline US English pronunciations. Spelling, phonemes and singing groups are kept separate.
/// CMUdict supplies whole-word phones; syllable boundaries and kana are reviewable app rules.
public enum EnglishPronunciation {
    public struct Candidate: Sendable, Equatable {
        public let ipa: [String]
        public let readings: [String]
        public let stressIndex: Int?
    }

    public struct Report: Sendable, Equatable {
        public var changedWords = 0
        public var reviewWords = 0
        public var protectedWords = 0
        public var reviewSurfaces: [String] = []

        mutating func review(_ word: String) {
            reviewWords += 1
            if !reviewSurfaces.contains(word) { reviewSurfaces.append(word) }
        }
    }

    public static let source = FieldSource(.dictionary, provider: "CMUdict + EnglishPronunciation")

    // Keep the distributable dictionary intact, including its licence and pinned revision.
    private static let dictionary: [String: [String]] = {
        guard let url = Bundle.module.url(forResource: "cmudict", withExtension: "dict", subdirectory: "CMUDict"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: [String]] = [:]
        text.enumerateLines { line, _ in
            guard let content = line.split(separator: "#", maxSplits: 1).first else { return }
            let fields = content.split(separator: " ", maxSplits: 1)
            guard fields.count == 2 else { return }
            let key = String(fields[0].split(separator: "(", maxSplits: 1)[0])
            result[key, default: []].append(String(fields[1]))
        }
        return result
    }()

    public static func supports(_ language: String) -> Bool {
        language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "en"
    }

    private static func key(_ surface: String) -> String {
        let value = surface.lowercased().replacingOccurrences(of: "’", with: "'")
        return value.trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }

    /// Written hiatus exceptions: ea is two vowel nuclei here, unlike "creature".
    public static func spelling(for surface: String) -> [String]? {
        let parts: [String: [Int]] = [
            "create": [3, 3], "creates": [3, 4], "created": [3, 1, 3], "creating": [3, 1, 4],
            "creation": [3, 1, 4], "creations": [3, 1, 5], "creative": [3, 1, 4],
            "creator": [3, 1, 3], "creators": [3, 1, 4], "cation": [3, 1, 2], "cations": [3, 1, 3]
        ]
        guard let lengths = parts[surface.lowercased()] else { return nil }
        let characters = Array(surface)
        var offset = 0
        return lengths.map { length in
            defer { offset += length }
            return String(characters[offset..<(offset + length)])
        }
    }

    private static func phones(for surface: String) -> [[String]] {
        let word = key(surface)
        if let values = dictionary[word] ?? dictionary[word + "'"] {
            return values.map { $0.split(separator: " ").map(String.init) }
        }
        // Apostrophized -in' / -in's is the colloquial -ing / -ing's, with /n/ for /ŋ/.
        let hasApostrophe = surface.contains("'") || surface.contains("’")
        if hasApostrophe, word.hasSuffix("in") || word.hasSuffix("in's") {
            let full = word.hasSuffix("in's") ? String(word.dropLast(2)) + "g's" : word + "g"
            let values = dictionary[full] ?? (word.hasSuffix("in's") ? dictionary[String(word.dropLast(2)) + "g"] : nil)
            return (values ?? []).map { value in
                var items = value.split(separator: " ").map(String.init)
                if let index = items.lastIndex(of: "NG") { items[index] = "N" }
                if word.hasSuffix("in's"), items.last != "Z" { items.append("Z") }
                return items
            }
        }
        return []
    }

    private static func base(_ phone: String) -> String { phone.filter { !$0.isNumber } }
    private static func isVowel(_ phone: String) -> Bool { phone.last?.isNumber == true }

    private static let onsets: Set<String> = [
        "P", "B", "T", "D", "K", "G", "F", "V", "TH", "DH", "S", "Z", "SH", "ZH", "HH", "CH", "JH", "M", "N", "L", "R", "W", "Y",
        "P L", "P R", "B L", "B R", "T R", "D R", "K L", "K R", "G L", "G R", "F L", "F R", "TH R", "SH R",
        "S P", "S T", "S K", "S M", "S N", "S L", "S W", "T W", "D W", "K W", "G W",
        "P Y", "B Y", "T Y", "D Y", "K Y", "G Y", "F Y", "V Y", "M Y", "N Y", "HH Y",
        "S P L", "S P R", "S T R", "S K L", "S K R", "S K W", "S K Y", "S P Y"
    ]

    private static func splitPhones(_ original: [String], texts: [String] = []) -> [[String]] {
        // ER before another vowel carries its r into the following onset (a-round).
        let phones = original.enumerated().flatMap { index, phone in
            phone == "ER0" && index + 1 < original.count && isVowel(original[index + 1]) ? ["AH0", "R"] : [phone]
        }
        let nuclei = phones.indices.filter { isVowel(phones[$0]) }
        guard !nuclei.isEmpty else { return [] }
        var starts = [0]
        for index in nuclei.indices.dropFirst() {
            let left = nuclei[index - 1] + 1, right = nuclei[index]
            let possible = (left..<right).filter { onsets.contains(phones[$0..<right].joined(separator: " ")) }
            // Preserve visible onsets when spelling makes them clear: ex-pla-, es-pe-.
            let written = texts.count == nuclei.count ? String(texts[index].lowercased().prefix { !"aeiouy".contains($0) }) : ""
            let start = possible.first { !written.isEmpty && phones[$0..<right].joined().lowercased() == written }
                ?? possible.first ?? right
            starts.append(start)
        }
        return starts.enumerated().map { i, start in
            Array(phones[start..<(i + 1 < starts.count ? starts[i + 1] : phones.count)])
        }
    }

    private static func ipa(_ phones: [String]) -> String {
        let symbols = ["AA": "ɑ", "AE": "æ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ", "EH": "ɛ", "EY": "eɪ",
                       "IH": "ɪ", "IY": "iː", "OW": "oʊ", "OY": "ɔɪ", "UH": "ʊ", "UW": "uː",
                       "B": "b", "CH": "tʃ", "D": "d", "DH": "ð", "F": "f", "G": "ɡ", "HH": "h", "JH": "dʒ",
                       "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ", "P": "p", "R": "r", "S": "s",
                       "SH": "ʃ", "T": "t", "TH": "θ", "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ"]
        let mark = phones.contains { $0.hasSuffix("1") } ? "ˈ" : phones.contains { $0.hasSuffix("2") } ? "ˌ" : ""
        return mark + phones.map { phone in
            if base(phone) == "AH" { return phone.hasSuffix("0") ? "ə" : "ʌ" }
            if base(phone) == "ER" { return phone.hasSuffix("0") ? "ər" : "ɜːr" }
            if phone == "IY0" { return "i" }
            if phone == "UW0" { return "u" }
            return symbols[base(phone)] ?? ""
        }.joined()
    }

    /// Used only for comparing broad IPA candidates, not for writing a user's transcription.
    public static func comparableIPA(_ text: String) -> String {
        text.replacingOccurrences(of: "ɹ", with: "r").replacingOccurrences(of: "ɚ", with: "ər")
            .replacingOccurrences(of: "ɝ", with: "ɜr").replacingOccurrences(of: "g", with: "ɡ")
            .replacingOccurrences(of: "ɒ", with: "ɑ")
            .filter { !"/[]ˈˌː:.·> \n\t".contains($0) }
    }

    public static func candidates(for surface: String, texts: [String]) -> [Candidate] {
        let word = key(surface)
        var result: [Candidate] = []
        for phones in phones(for: surface) {
            var groups = splitPhones(phones, texts: texts)
            // A user may explicitly sing creation as "crea / tion". This is grouping, not a
            // claim that its dictionary pronunciation has only two syllables.
            if word == "creation", texts.map({ $0.lowercased() }) == ["crea", "tion"], groups.count == 3 {
                groups = [groups[0] + groups[1], groups[2]]
            }
            guard groups.count == texts.count, !groups.isEmpty else { continue }
            var readings = groups.enumerated().map { kana($0.element, geminate: $0.offset == groups.count - 1) }
            if let preferred = preferredReadings[word], preferred.count == groups.count { readings = preferred }
            if word == "creation", groups.count == 2 { readings = ["クリエイ", "ション"] }
            let candidate = Candidate(ipa: groups.map(ipa), readings: readings,
                                      stressIndex: groups.firstIndex { $0.contains { $0.hasSuffix("1") } })
            if !result.contains(candidate) { result.append(candidate) }
        }
        return result
    }

    public static func dictionaryIPA(for surface: String) -> [String] {
        phones(for: surface).map { splitPhones($0).map(ipa).joined() }
    }

    /// Homographs need context. Retain a matching pronunciation; otherwise only auto-select
    /// when the dictionary has one vowel sequence (or a specified common function-word form).
    public static func candidate(for surface: String, texts: [String], currentIPA: [String] = []) -> Candidate? {
        let candidates = candidates(for: surface, texts: texts)
        if let matching = candidates.first(where: { comparableIPA($0.ipa.joined()) == comparableIPA(currentIPA.joined()) }) {
            return matching
        }
        let defaults: Set<String> = ["a", "are", "the", "for", "to", "of", "and", "that", "can", "been", "your", "you're"]
        if defaults.contains(key(surface)) { return candidates.first }
        let vowels = Set(candidates.map { comparableIPA($0.ipa.joined()).filter { "ɑæɔaʊɪɛeiouəʌɜ".contains($0) } })
        return vowels.count == 1 ? candidates.first : nil
    }

    /// Repair in place, preserving IDs, note links, manual fields and explicit phoneme/mora data.
    /// Never change the number of syllables in an existing document.
    @discardableResult
    public static func apply(to song: inout SongDocument, phraseIDs: Set<UUID>? = nil) -> Report {
        var report = Report()
        for phrase in song.phrases where supports(song.language(of: phrase)) && (phraseIDs?.contains(phrase.id) ?? true) {
            for word in song.words(in: phrase) {
                let current = song.syllables(in: word)
                guard !current.isEmpty else { report.review(word.surface); continue }
                var texts = current.map(\.text.value)
                let spelling = spelling(for: key(word.surface))
                let canResplit = !word.structureUserEdited && current.allSatisfy {
                    !$0.structureUserEdited && !$0.text.userEdited && !$0.ipa.userEdited && !$0.reading.userEdited
                        && $0.phonemeIDs.isEmpty && $0.moraIDs.isEmpty
                }
                if let spelling, spelling.count == texts.count,
                   spelling != texts.map({ $0.lowercased() }), !canResplit {
                    // A spelling-boundary repair must not mix new sounds with hand-corrected
                    // readings intended for the old groups. Leave the whole word for review.
                    report.review(word.surface); report.protectedWords += 1; continue
                }
                if canResplit, let spelling, spelling.count == texts.count {
                    // Retain capitalization while correcting only the known spelling exception.
                    let letters = Array(texts.joined())
                    if letters.count == spelling.joined().count {
                        var offset = 0
                        texts = spelling.map { part in
                            defer { offset += part.count }
                            return String(letters[offset..<(offset + part.count)])
                        }
                    }
                }
                guard let candidate = candidate(for: word.surface, texts: texts, currentIPA: current.map(\.ipa.value)) else {
                    report.review(word.surface); continue
                }
                var changed = false, protected = false
                for (position, syllable) in current.enumerated() {
                    guard let index = song.syllables.firstIndex(where: { $0.id == syllable.id }) else { continue }
                    guard !syllable.structureUserEdited, syllable.moraIDs.isEmpty, syllable.phonemeIDs.isEmpty else {
                        protected = true; continue
                    }
                    if texts[position] != syllable.text.value, canResplit {
                        song.syllables[index].text.accept(texts[position], source: .init(.rule, provider: "EnglishPronunciation"))
                    }
                    protected = protected || syllable.ipa.userEdited || syllable.reading.userEdited
                    // A manually changed IPA can express a deliberate accent or singing variant.
                    // Do not assign a contradictory reading to it.
                    if !syllable.ipa.userEdited {
                        song.syllables[index].ipa.accept(candidate.ipa[position], source: source)
                        song.syllables[index].reading.accept(candidate.readings[position], source: source)
                        song.syllables[index].stress.accept(position == candidate.stressIndex ? "強" : "", source: source)
                    } else if comparableIPA(syllable.ipa.value) == comparableIPA(candidate.ipa[position]) {
                        song.syllables[index].reading.accept(candidate.readings[position], source: source)
                    }
                    changed = changed || song.syllables[index] != syllable
                }
                if changed { report.changedWords += 1 }
                if protected { report.protectedWords += 1 }
            }
        }
        return report
    }

    // Japanese singing aids, not phonetic spellings. These include the user's shared conventions.
    private static let preferredReadings: [String: [String]] = [
        "are": ["アー"], "the": ["ザ"], "a": ["ア"], "creation": ["クリ", "エイ", "ション"],
        "coming": ["カ", "ミング"], "comin": ["カ", "ミン"], "heaven": ["ヘ", "ヴン"],
        "reason": ["リー", "ズン"], "only": ["オン", "リー"], "every": ["エヴ", "リ"],
        "everything": ["エヴ", "リ", "シング"], "something": ["サム", "シング"],
        "explanation": ["エクス", "プラ", "ネイ", "ション"], "happiness": ["ハッ", "ピ", "ネス"],
        "you're": ["ユア"], "your": ["ユア"], "i've": ["アイヴ"], "you've": ["ユーヴ"],
        "there": ["ゼア"], "there's": ["ゼアズ"], "that": ["ザット"], "this": ["ズィス"],
        "of": ["オヴ"], "around": ["ア", "ラウンド"], "tomorrow": ["トゥ", "モ", "ロウ"],
        "nearest": ["ニア", "レスト"], "wonder": ["ワン", "ダー"], "ever": ["エ", "ヴァー"],
        "see": ["シー"], "seen": ["シーン"], "since": ["シンス"], "true": ["トゥルー"],
        "on": ["オン"], "not": ["ノット"], "for": ["フォー"], "clear": ["クリア"], "here": ["ヒア"],
        "especially": ["エス", "ペ", "シャ", "リ"]]

    /// Broad kana approximation driven by phones, never by English spelling fragments.
    private static func kana(_ phones: [String], geminate: Bool) -> String {
        guard let nucleus = phones.firstIndex(where: isVowel) else { return phones.map { coda[base($0)] ?? "" }.joined() }
        // Explicit song grouping may contain two nuclei; render each natural syllable in order.
        if phones.filter(isVowel).count > 1 {
            let groups = splitPhones(phones)
            return groups.enumerated().map { kana($0.element, geminate: geminate && $0.offset == groups.count - 1) }.joined()
        }
        let onset = Array(phones[..<nucleus]).map(base)
        var tail = Array(phones[(nucleus + 1)...]).map(base)
        if onset == ["SH"], phones[nucleus] == "AH0", tail == ["N"] { return "ション" }
        if onset == ["CH"], phones[nucleus] == "AH0", tail == ["N"] { return "チョン" }
        if onset == ["ZH"], phones[nucleus] == "AH0", tail == ["N"] { return "ジョン" }
        let vowel = base(phones[nucleus])
        let column = ["AA": 0, "AE": 0, "AH": 0, "AO": 4, "AW": 0, "AY": 0, "EH": 3, "ER": 0, "EY": 3,
                      "IH": 1, "IY": 1, "OW": 4, "OY": 4, "UH": 2, "UW": 2][vowel] ?? 0
        var suffix = ["AO": "ー", "AW": "ウ", "AY": "イ", "ER": "ー", "EY": "イ", "IY": "ー", "OW": "ウ", "OY": "イ", "UW": "ー"][vowel] ?? ""
        if ["IY0", "UW0"].contains(phones[nucleus]) { suffix = "" }
        if tail.first == "R", ["AA", "AO", "AH", "IH", "IY", "EH", "UH", "UW"].contains(vowel) {
            suffix = ["AA", "AO", "AH"].contains(vowel) ? "ー" : "ア"
            tail.removeFirst()
        }
        var prefix = onset.dropLast().map { coda[$0] ?? "" }.joined()
        if onset == ["T", "R"], column == 2 { prefix = "トゥ" }
        let row = rows[onset.last ?? ""] ?? rows[""]!
        let head = vowel == "AE" && onset.last == "K" ? "キャ" : vowel == "AE" && onset.last == "G" ? "ギャ" : row[column]
        prefix += head + suffix
        let shortVowel = ["AA", "AE", "AH", "EH", "IH", "UH"].contains(vowel) && suffix.isEmpty
        if geminate, shortVowel, let first = tail.first, ["P", "B", "T", "D", "K", "G", "CH", "SH"].contains(first) { prefix += "ッ" }
        if tail == ["T", "S"] { return prefix + "ツ" }
        return prefix + tail.map { coda[$0] ?? "" }.joined()
    }

    private static let coda = ["P": "プ", "B": "ブ", "T": "ト", "D": "ド", "K": "ク", "G": "グ", "F": "フ", "V": "ヴ",
                               "TH": "ス", "DH": "ズ", "S": "ス", "Z": "ズ", "SH": "シュ", "ZH": "ジュ", "HH": "フ", "CH": "チ", "JH": "ジ",
                               "M": "ム", "N": "ン", "NG": "ング", "L": "ル", "R": "ル", "W": "ウ", "Y": "イ"]
    private static let rows: [String: [String]] = [
        "": ["ア", "イ", "ウ", "エ", "オ"], "K": ["カ", "キ", "ク", "ケ", "コ"], "G": ["ガ", "ギ", "グ", "ゲ", "ゴ"],
        "S": ["サ", "スィ", "ス", "セ", "ソ"], "Z": ["ザ", "ズィ", "ズ", "ゼ", "ゾ"],
        "TH": ["サ", "シ", "ス", "セ", "ソ"], "DH": ["ザ", "ズィ", "ズ", "ゼ", "ゾ"],
        "SH": ["シャ", "シ", "シュ", "シェ", "ショ"], "ZH": ["ジャ", "ジ", "ジュ", "ジェ", "ジョ"],
        "CH": ["チャ", "チ", "チュ", "チェ", "チョ"], "JH": ["ジャ", "ジ", "ジュ", "ジェ", "ジョ"],
        "T": ["タ", "ティ", "トゥ", "テ", "ト"], "D": ["ダ", "ディ", "ドゥ", "デ", "ド"],
        "N": ["ナ", "ニ", "ヌ", "ネ", "ノ"], "HH": ["ハ", "ヒ", "フ", "ヘ", "ホ"], "F": ["ファ", "フィ", "フ", "フェ", "フォ"],
        "P": ["パ", "ピ", "プ", "ペ", "ポ"], "B": ["バ", "ビ", "ブ", "ベ", "ボ"], "V": ["ヴァ", "ヴィ", "ヴ", "ヴェ", "ヴォ"],
        "M": ["マ", "ミ", "ム", "メ", "モ"], "Y": ["ヤ", "イ", "ユ", "イェ", "ヨ"],
        "R": ["ラ", "リ", "ル", "レ", "ロ"], "L": ["ラ", "リ", "ル", "レ", "ロ"], "W": ["ワ", "ウィ", "ウ", "ウェ", "ウォ"]]
}
