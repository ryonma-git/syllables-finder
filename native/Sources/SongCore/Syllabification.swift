import Foundation

/// The result of splitting one written word into sung syllables (Japanese: morae).
public struct SyllabifiedWord: Sendable, Equatable {
    /// Syllable texts without surrounding punctuation. For alphabetic languages they concatenate to
    /// the letters of the word; for Japanese they are the kana of the reading.
    public var syllables: [String]
    /// Index of the syllable with primary stress, when the rules can tell.
    public var stressIndex: Int?
    /// Per-syllable reading (Japanese katakana, Mandarin pinyin); nil when not produced.
    public var readings: [String]?
    /// An explanation for doubtful results (shown with the candidate, never as a fact).
    public var note: String?
    public init(syllables: [String], stressIndex: Int? = nil, readings: [String]? = nil, note: String? = nil) {
        self.syllables = syllables; self.stressIndex = stressIndex; self.readings = readings; self.note = note
    }
}

public struct LyricToken: Sendable, Equatable {
    /// The written word including attached punctuation (kept as Word.surface).
    public var surface: String
    /// Reading given in the lyrics, e.g. `漢字（かんじ）`.
    public var reading: String?
    public init(surface: String, reading: String? = nil) { self.surface = surface; self.reading = reading }
}

/// Rule-based, dictionary-free syllabification for lyric entry (ADR013). Results are candidates.
public enum Syllabifier {
    public struct Language: Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
    }

    /// In the priority order agreed for the app.
    public static let languages: [Language] = [
        .init(id: "de", name: "ドイツ語"), .init(id: "es", name: "スペイン語"), .init(id: "fr", name: "フランス語"),
        .init(id: "it", name: "イタリア語"), .init(id: "la", name: "ラテン語（教会式）"), .init(id: "ru", name: "ロシア語"),
        .init(id: "en", name: "英語"), .init(id: "ja", name: "日本語"), .init(id: "ko", name: "韓国語"),
        .init(id: "zh", name: "中国語・普通話（試験的）")
    ]

    public static func supports(_ language: String) -> Bool { languages.contains { $0.id == language } }

    public static func displayName(for language: String) -> String {
        languages.first { $0.id == language }?.name ?? language
    }

    // MARK: Tokenizing a lyric line

    public static func tokenize(_ line: String, language: String) -> [LyricToken] {
        switch language {
        case "ja", "zh": return tokenizeCJK(line, language: language)
        default:
            var tokens: [LyricToken] = []
            var pendingLeading = ""
            for raw in line.split(whereSeparator: \.isWhitespace).map(String.init) {
                if raw.contains(where: \.isLetter) {
                    tokens.append(.init(surface: pendingLeading.isEmpty ? raw : pendingLeading + " " + raw)); pendingLeading = ""
                } else if tokens.isEmpty {
                    pendingLeading += raw
                } else {
                    // Free-standing punctuation (French "vous ?") belongs to the previous word.
                    tokens[tokens.count - 1].surface += " " + raw
                }
            }
            if !pendingLeading.isEmpty && !tokens.isEmpty { tokens[0].surface = pendingLeading + " " + tokens[0].surface }
            return tokens
        }
    }

    private static func tokenizeCJK(_ line: String, language: String) -> [LyricToken] {
        // Explicit readings: 漢字（かんじ） or 漢字(かんじ).
        var readings: [(range: Range<String.Index>, base: String, reading: String)] = []
        let pattern = #"([\p{Han}々〆ヵヶ]+)[（(]([\p{Hiragana}\p{Katakana}ー]+)[）)]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = line as NSString
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard let range = Range(match.range, in: line) else { continue }
                readings.append((range, ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2))))
            }
        }
        var tokens: [LyricToken] = []
        var cursor = line.startIndex
        func segment(_ text: Substring) {
            guard !text.isEmpty else { return }
            let string = String(text)
            let cf = string as CFString
            let locale = Locale(identifier: language) as CFLocale
            let tokenizer = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)), kCFStringTokenizerUnitWord, locale)
            var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
            var last = 0
            while type != [] {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                let ns = string as NSString
                let gap = ns.substring(with: NSRange(location: last, length: range.location - last))
                if !tokens.isEmpty, !gap.trimmingCharacters(in: .whitespaces).isEmpty { tokens[tokens.count - 1].surface += gap.trimmingCharacters(in: .whitespaces) }
                let word = ns.substring(with: NSRange(location: range.location, length: range.length))
                var reading: String?
                if language == "ja", !word.unicodeScalars.allSatisfy({ isKana($0) }),
                   let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                    let mutable = NSMutableString(string: latin)
                    CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
                    reading = (mutable as String).replacingOccurrences(of: " ", with: "")
                }
                if word.contains(where: { $0.isLetter }) { tokens.append(.init(surface: word, reading: reading)) }
                else if !tokens.isEmpty { tokens[tokens.count - 1].surface += word }
                last = range.location + range.length
                type = CFStringTokenizerAdvanceToNextToken(tokenizer)
            }
            let tail = (string as NSString).substring(from: last).trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty && !tokens.isEmpty { tokens[tokens.count - 1].surface += tail }
        }
        for item in readings {
            segment(line[cursor..<item.range.lowerBound])
            tokens.append(.init(surface: item.base, reading: katakanaToHiragana(item.reading)))
            cursor = item.range.upperBound
        }
        segment(line[cursor...])
        return tokens
    }

    // MARK: One word

    public static func syllabify(_ token: LyricToken, language: String) -> SyllabifiedWord {
        switch language {
        case "ja": return japanese(token)
        case "ko": return korean(token.surface)
        case "zh": return mandarin(token.surface)
        default: return alphabetic(token.surface, language: language)
        }
    }

    public static func syllabify(_ word: String, language: String) -> SyllabifiedWord {
        let tokens = tokenize(word, language: language)
        if (language == "ja" || language == "zh"), tokens.count > 1 {
            // A multi-token word: join the parts in order.
            let parts = tokens.map { syllabify($0, language: language) }
            let readings = parts.allSatisfy { $0.readings != nil } ? parts.flatMap { $0.readings! } : nil
            return .init(syllables: parts.flatMap(\.syllables), readings: readings, note: parts.compactMap(\.note).first)
        }
        return syllabify(tokens.first ?? .init(surface: word), language: language)
    }

    // MARK: Japanese, Korean, Mandarin

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
    }

    private static func katakanaToHiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60)! : scalar
        }))
    }

    private static func hiraganaToKatakana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x3041...0x3096).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x60)! : scalar
        }))
    }

    /// Splits kana into morae: small kana join the previous mora; ん, っ and ー are morae of their own.
    public static func morae(_ kana: String) -> [String] {
        let small: Set<Character> = ["ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ", "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ", "ヮ"]
        var result: [String] = []
        for character in kana where character.unicodeScalars.allSatisfy({ isKana($0) }) {
            if small.contains(character), !result.isEmpty { result[result.count - 1].append(character) }
            else { result.append(String(character)) }
        }
        return result
    }

    private static func japanese(_ token: LyricToken) -> SyllabifiedWord {
        let letters = token.surface.filter { $0.isLetter || $0 == "ー" }
        let isKanaOnly = !letters.isEmpty && letters.unicodeScalars.allSatisfy { isKana($0) }
        let reading = isKanaOnly ? letters : token.reading ?? ""
        guard !reading.isEmpty else {
            return .init(syllables: [], note: "読みを推定できませんでした。「漢字（かんじ）」の形で読みを書けます。")
        }
        let units = morae(reading)
        return .init(syllables: units, readings: units.map(hiraganaToKatakana),
                     note: isKanaOnly || token.reading == nil ? nil : "読みは推定です。確認してください。")
    }

    private static func korean(_ word: String) -> SyllabifiedWord {
        var syllables: [String] = []
        for character in word where character.isLetter {
            if character.unicodeScalars.first.map({ (0xAC00...0xD7A3).contains($0.value) }) == true || syllables.isEmpty {
                syllables.append(String(character))
            } else { syllables[syllables.count - 1].append(character) }
        }
        return .init(syllables: syllables)
    }

    private static func mandarin(_ word: String) -> SyllabifiedWord {
        let characters = word.filter { $0.isLetter }.map(String.init)
        let mutable = NSMutableString(string: characters.joined())
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        let pinyin = (mutable as String).split(separator: " ").map(String.init)
        return .init(syllables: characters, readings: pinyin.count == characters.count ? pinyin : nil,
                     note: "ピンインは文脈を見ない推定です。多音字を確認してください。")
    }

    // MARK: Alphabetic languages

    private struct Letter {
        let character: Character
        let base: Character   // lowercased letter without diacritics
        let marks: Set<UInt32>
        var vowel = false
        var combining = false
    }

    private static func letters(_ core: String) -> [Letter] {
        core.map { character in
            let scalars = String(character).decomposedStringWithCanonicalMapping.unicodeScalars
            let base = scalars.first.map { Character(String($0).lowercased()) } ?? character
            let marks = Set(scalars.dropFirst().map(\.value))
            var letter = Letter(character: character, base: base, marks: marks)
            // A combining acute typed by the user (U+0301 after the letter) marks stress explicitly.
            letter.combining = String(character).unicodeScalars.contains { $0.value == 0x0301 }
            return letter
        }
    }

    private static let vowelBases: [String: Set<Character>] = [
        "ru": Set("аеёиоуыэюя"),
        "default": Set("aeiouyæœ")
    ]

    private static func splitCore(_ surface: String) -> (leading: String, core: String, trailing: String) {
        let characters = Array(surface)
        guard let first = characters.firstIndex(where: { $0.isLetter }),
              let last = characters.lastIndex(where: { $0.isLetter }) else { return (surface, "", "") }
        return (String(characters[..<first]), String(characters[first...last]), String(characters[(last + 1)...]))
    }

    static func alphabetic(_ surface: String, language: String) -> SyllabifiedWord {
        let core = splitCore(surface).core
        guard !core.isEmpty else { return .init(syllables: []) }
        // Hyphenated compounds (Dormez-vous) split at the hyphen; each part follows the rules.
        let parts = core.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        if parts.count > 1 {
            let results = parts.map { alphabeticPart($0, language: language) }
            // French stresses the end of the group; the other languages the first stressed part.
            let lastOffset = results.dropLast().reduce(0) { $0 + $1.syllables.count }
            let stress = language == "fr" ? results.last!.stressIndex.map { lastOffset + $0 } : results.first!.stressIndex
            return .init(syllables: results.flatMap(\.syllables), stressIndex: stress, note: results.compactMap(\.note).first)
        }
        return alphabeticPart(core, language: language)
    }

    private static func alphabeticPart(_ core: String, language: String) -> SyllabifiedWord {
        var letters = letters(core)
        let (nuclei, note) = orthographicNuclei(in: &letters, language: language)
        let n = letters.count
        guard !nuclei.isEmpty else { return .init(syllables: [core]) }
        // Onsets: how many consonant letters before each nucleus (after the first) start its syllable.
        var starts = [0]
        for k in 1..<nuclei.count {
            let clusterStart = nuclei[k - 1].upperBound, clusterEnd = nuclei[k].lowerBound
            let onset = onsetLength(letters, clusterStart..<clusterEnd, language: language,
                                    finalLE: language == "en" && k == nuclei.count - 1 && syllabicLE(letters, nucleus: nuclei[k]))
            starts.append(clusterEnd - onset)
        }
        // German inseparable prefixes keep their own syllable when the rest starts with a valid onset (be-tre-ten).
        if language == "de", nuclei.count >= 2 {
            let lower = String(letters.map(\.base))
            let onsets: Set<String> = ["tr", "br", "pr", "gr", "kr", "fr", "dr", "bl", "pl", "kl", "gl", "fl", "schr", "str", "spr",
                                       "sch", "st", "sp", "zw", "schw", "schl", "schm", "schn", "pfl", "pfr", "ch", "qu"]
            for prefix in ["ver", "zer", "ent", "emp", "be", "ge"] where lower.hasPrefix(prefix) {
                let end = prefix.count
                guard nuclei[0].upperBound <= end, nuclei[1].lowerBound >= end else { continue }
                let cluster = String(lower[lower.index(lower.startIndex, offsetBy: end)..<lower.index(lower.startIndex, offsetBy: nuclei[1].lowerBound)])
                if cluster.count <= 1 || onsets.contains(cluster) { starts[1] = end }
                break
            }
        }
        let characters = letters.map(\.character)
        var syllables: [String] = []
        for k in 0..<starts.count {
            let end = k + 1 < starts.count ? starts[k + 1] : n
            syllables.append(String(characters[starts[k]..<end]))
        }
        return .init(syllables: syllables, stressIndex: stress(letters, nuclei: nuclei, syllables: syllables, language: language), note: note)
    }

    /// Character offsets for written vowel cues. The same rules drive syllabification and print coloring.
    /// These are orthographic hints, not a phonetic transcription.
    public static func orthographicVowelNuclei(in text: String, language: String) -> [Range<Int>] {
        let code = String(language.prefix(2)).lowercased()
        guard ["en", "de", "fr", "es", "it", "la", "ru"].contains(code) else { return [] }
        let characters = Array(text)
        guard let first = characters.firstIndex(where: { $0.isLetter }),
              let last = characters.lastIndex(where: { $0.isLetter }) else { return [] }
        var letters = letters(String(characters[first...last]))
        return orthographicNuclei(in: &letters, language: code).ranges.map {
            (first + $0.lowerBound)..<(first + $0.upperBound)
        }
    }

    private static func orthographicNuclei(in letters: inout [Letter], language: String) -> (ranges: [Range<Int>], note: String?) {
        let vowels = vowelBases[language] ?? vowelBases["default"]!
        let n = letters.count
        for i in 0..<n { letters[i].vowel = vowels.contains(letters[i].base) }
        // Language-specific consonantal vowels.
        for i in 0..<n {
            let base = letters[i].base
            let previous = i > 0 ? letters[i - 1].base : nil
            let nextIsVowel = i + 1 < n && vowels.contains(letters[i + 1].base)
            switch language {
            case "en", "fr", "de", "es", "it":
                if base == "y" {
                    if i == 0 && nextIsVowel { letters[i].vowel = false }
                    else if i > 0 && nextIsVowel && letters[i - 1].vowel && language != "de" { letters[i].vowel = false } // beyond, payer
                    else if language == "es" && i == n - 1 && i > 0 && letters[i - 1].vowel { letters[i].vowel = true }
                    else if language == "es" && i < n - 1 { letters[i].vowel = false }
                }
                if base == "u" && (previous == "q" || (previous == "g" && i + 1 < n && "eiéí".contains(letters[i + 1].base))) && nextIsVowel {
                    letters[i].vowel = false // qu, gue/gui
                }
                if language == "it" && base == "i" && i > 0 && (previous == "c" || previous == "g" || (previous == "l" && i > 1 && letters[i - 2].base == "g")) && nextIsVowel && letters[i].marks.isEmpty {
                    letters[i].vowel = false // cia, gio, glio: the i only softens the consonant
                }
                if language == "it" && base == "i" && i > 1 && previous == "c" && letters[i - 2].base == "s" && nextIsVowel {
                    letters[i].vowel = false // scia
                }
            case "la":
                if base == "u" && (previous == "q" || (previous == "g" && i > 1 && letters[i - 2].base == "n")) && nextIsVowel { letters[i].vowel = false }
                if (base == "i" || base == "j") && nextIsVowel && (i == 0 || letters[i - 1].vowel) { letters[i].vowel = false } // iam, eius
                if base == "j" { letters[i].vowel = false }
            default: break
            }
            if language == "en" && base == "w" && previous.map({ "aeo".contains($0) }) == true && !nextIsVowel { letters[i].vowel = true } // aw ew ow
        }
        // Nuclei: runs of vowel letters, joined by language rules.
        var nuclei: [Range<Int>] = []
        var i = 0
        while i < n {
            guard letters[i].vowel else { i += 1; continue }
            var end = i + 1
            while end < n && letters[end].vowel && joins(letters, from: i, to: end, language: language) { end += 1 }
            nuclei.append(i..<end)
            i = end
        }
        var note: String?
        // Silent or mute final e.
        if let last = nuclei.last, nuclei.count > 1 {
            let tail = String(letters[last.lowerBound...].map(\.base))
            let before = last.lowerBound > 0 ? letters[last.lowerBound - 1] : nil
            if language == "en" && !syllabicLE(letters, nucleus: last) && last.count == 1 && letters[last.lowerBound].base == "e"
                && ["e", "es", "ed"].contains(tail) && before.map({ !$0.vowel }) == true {
                let previousTwo = last.lowerBound > 1 ? String([letters[last.lowerBound - 2].base, letters[last.lowerBound - 1].base]) : ""
                let sibilant = before.map { "sxzcg".contains($0.base) } == true || ["sh", "ch"].contains(previousTwo)
                let dental = before.map { "td".contains($0.base) } == true
                let sounded = (tail == "es" && sibilant) || (tail == "ed" && dental)
                if !sounded { nuclei.removeLast() }
            }
            if language == "fr" && ["e", "es", "ent"].contains(tail) && last.count == 1 {
                note = "語末のeは歌唱では1音節として数えます（次の語が母音で始まれば省略されることがあります）。"
            }
        }
        return (nuclei, note)
    }

    /// English "-le" after a consonant is its own syllable (lit-tle, ta-ble), unlike "whale".
    private static func syllabicLE(_ letters: [Letter], nucleus: Range<Int>) -> Bool {
        let e = nucleus.lowerBound
        return nucleus.count == 1 && e == letters.count - 1 && letters[e].base == "e" && e >= 2
            && letters[e - 1].base == "l" && !letters[e - 2].vowel && letters[e - 2].base != "l"
    }

    private static func joins(_ letters: [Letter], from start: Int, to next: Int, language: String) -> Bool {
        let run = String(letters[start...next].map(\.base))
        let pair = String(letters[(next - 1)...next].map(\.base))
        let current = letters[next], previous = letters[next - 1]
        switch language {
        case "de":
            return ["aa", "ee", "oo", "ie", "ei", "ai", "au", "eu", "äu", "ey", "ay"].contains(pair) && next - start == 1
        case "fr":
            if next - start == 1 { return ["ai", "ei", "au", "ou", "eu", "oi", "ui", "ie", "oe", "œu", "ay", "ey", "oy", "ea", "ue"].contains(pair) }
            return next - start == 2 && ["eau", "oeu", "oui", "ieu", "uie"].contains(run)
        case "es", "it":
            let weak: (Letter) -> Bool = { ("iuü".contains($0.base) || ($0.base == "y")) && !$0.character.lowercased().contains(where: { "íúìù".contains($0) }) }
            let accentedWeak = { (l: Letter) in l.character.lowercased().contains { "íúìù".contains($0) } }
            if accentedWeak(current) || accentedWeak(previous) { return false }
            if previous.base == current.base { return false }
            return weak(current) || weak(previous)
        case "la":
            return ["ae", "oe", "au"].contains(pair) && next - start == 1
        case "en":
            if next - start >= 2 { return ["eau", "iew"].contains(run) }
            return ["ai", "ay", "ea", "ee", "ei", "ey", "ie", "oa", "oe", "oi", "oo", "ou", "ow", "oy", "ue", "ui", "au", "aw", "ew", "uy", "eu"].contains(pair)
        default:
            return false // ru: every vowel letter is a syllable
        }
    }

    private static func onsetLength(_ letters: [Letter], _ cluster: Range<Int>, language: String, finalLE: Bool) -> Int {
        let bases = letters[cluster].map(\.base)
        guard !bases.isEmpty else { return 0 }
        // Group consonant letters into units (digraphs stay together).
        let digraphs: [String]
        switch language {
        case "de": digraphs = ["sch", "ch", "ck", "ph", "th", "qu"]
        case "fr": digraphs = ["ch", "ph", "th", "gn", "qu", "gu"]
        case "es": digraphs = ["ch", "ll", "rr", "qu", "gu"]
        case "it": digraphs = ["ch", "gh", "gn", "gl", "sc", "qu", "gu"]
        case "la": digraphs = ["ch", "ph", "th", "qu", "gu", "gn"]
        case "en": digraphs = ["tch", "th", "sh", "ch", "ph", "wh", "ck", "ng", "gh", "qu"]
        case "ru": digraphs = []
        default: digraphs = []
        }
        var units: [String] = []
        var index = 0
        while index < bases.count {
            if language == "ru", "ьъ".contains(bases[index]), !units.isEmpty { units[units.count - 1].append(bases[index]); index += 1; continue }
            // A consonantal vowel letter (the i of "glio"/"cia", the u of "sanguis") belongs to its consonant.
            if "iuy".contains(bases[index]), !units.isEmpty { units[units.count - 1].append(bases[index]); index += 1; continue }
            if let match = digraphs.first(where: { d in
                index + d.count <= bases.count && String(bases[index..<index + d.count]) == d
            }) {
                units.append(match); index += match.count
            } else { units.append(String(bases[index])); index += 1 }
        }
        func length(_ count: Int) -> Int { units.suffix(count).reduce(0) { $0 + $1.count } }
        let liquids: Set<String> = ["bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "pl", "pr", "tr", "vr", "kr", "kl", "tl"]
        let last = units.last!
        if units.count == 1 {
            switch language {
            case "en" where ["ck", "ng", "x", "tch"].contains(last): return 0
            case "la" where last == "x": return 0
            default: return length(1)
            }
        }
        let lastTwo = units.suffix(2).joined()
        switch language {
        case "es", "fr", "it", "la":
            if language == "la", units.contains("x") { return units.last == "x" ? 0 : length(units.count - units.lastIndex(of: "x")! - 1) }
            if language == "it", let j = units.indices.dropLast().last(where: { units[$0] == "s" && ($0 == 0 || units[$0 - 1] != "s") }) {
                return length(units.count - j) // s impura starts the syllable: pa-sta, mo-stro
            }
            if language == "la", units.count == 2, units[0] == "s", ["c", "p", "t"].contains(last) { return length(2) } // Chri-ste
            if liquids.contains(lastTwo) && units[units.count - 2] != last { return length(2) }
            return length(1)
        case "de":
            return length(1)
        case "ru":
            let sonorants: Set<Character> = ["л", "м", "н", "р"]
            if units[0] == "й" { return length(units.count - 1) }
            if units.count >= 2, units[0] == units[1] { return length(units.count - 1) }
            if let first = units[0].first, sonorants.contains(first) { return length(units.count - 1) }
            return length(units.count)
        case "en":
            if finalLE { return length(min(2, units.count)) } // twin-kle, lit-tle: the consonant before -le starts it
            if liquids.contains(lastTwo) && !["ck", "ng"].contains(units[units.count - 2]) { return length(2) }
            if ["ck", "ng", "x"].contains(last) { return 0 }
            return length(1)
        default:
            return length(1)
        }
    }

    private static func stress(_ letters: [Letter], nuclei: [Range<Int>], syllables: [String], language: String) -> Int? {
        let count = nuclei.count
        if let marked = nuclei.firstIndex(where: { nucleus in letters[nucleus].contains { $0.combining } }) { return marked }
        switch language {
        case "es":
            if let accented = nuclei.firstIndex(where: { nucleus in letters[nucleus].contains { "áéíóú".contains($0.character.lowercased()) } }) { return accented }
            guard count > 1, let last = letters.last?.base else { return count == 1 ? 0 : nil }
            return "aeiouns".contains(last) ? count - 2 : count - 1
        case "it":
            if let accented = nuclei.firstIndex(where: { nucleus in letters[nucleus].contains { "àèéìòóù".contains($0.character.lowercased()) } }) { return accented }
            return count > 1 ? count - 2 : 0
        case "de":
            guard count > 1 else { return 0 }
            let word = String(letters.map(\.base))
            return ["be", "ge", "ver", "zer", "ent", "emp"].contains { word.hasPrefix($0) && syllables[0].lowercased() == $0 } ? 1 : 0
        case "fr":
            guard count > 1 else { return 0 }
            let lastSyllable = syllables[count - 1].lowercased()
            let mute = ["e", "es", "ent"].contains { lastSyllable.hasSuffix($0) } && letters[nuclei[count - 1]].count == 1 && letters[nuclei[count - 1].lowerBound].base == "e"
            return mute ? count - 2 : count - 1
        case "la":
            return count == 2 ? 0 : count == 1 ? 0 : nil
        case "ru":
            if let yo = nuclei.firstIndex(where: { nucleus in letters[nucleus].contains { $0.base == "ё" || $0.character.lowercased() == "ё" } }) { return yo }
            return count == 1 ? 0 : nil
        default:
            return count == 1 ? 0 : nil
        }
    }
}
