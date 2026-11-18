import Foundation
import SongCore

// Keep the web export on the same dictionary, spelling, IPA and kana rules as the desktop app.
// Each distinct IPA/kana pair is stored once. Rows store spelling offsets and base-36 pair IDs.
struct PhonemeGroup: Hashable {
    let ipa: String
    let kana: String
}

struct Lexicon {
    private var groupIDs: [PhonemeGroup: Int] = [:]
    var groups: [String] = []
    var entries: [String] = []

    mutating func encode(_ form: EnglishPronunciation.Candidate, whole: Bool) -> String {
        let pairs = whole
            ? [PhonemeGroup(ipa: form.ipa.joined(), kana: form.readings.joined())]
            : zip(form.ipa, form.readings).map { PhonemeGroup(ipa: $0.0, kana: $0.1) }
        return pairs.map { pair in
            let id = groupIDs[pair] ?? groups.count
            if id == groups.count {
                groups.append(pair.ipa + "\t" + pair.kana)
                groupIDs[pair] = id
            }
            return String(id, radix: 36)
        }.joined(separator: ".")
    }

    // Syllabifier returns written letters. Keep any hyphen or apostrophe at the original offset.
    func offsets(_ pieces: [String], in word: String) -> [Int]? {
        var cursor = word.startIndex
        var ends: [Int] = []
        for piece in pieces {
            guard let range = word[cursor...].range(of: piece),
                  word[cursor..<range.lowerBound].allSatisfy({ $0 == "-" || $0 == "'" }) else { return nil }
            cursor = range.upperBound
            ends.append(word.distance(from: word.startIndex, to: cursor))
        }
        guard word[cursor...].allSatisfy({ $0 == "-" || $0 == "'" }) else { return nil }
        return Array(ends.dropLast())
    }

    mutating func add(_ word: String, usable: Bool) {
        guard usable else {
            entries.append(word + "\t\t?") // Keep true elisions distinct from ordinary quoted words.
            return
        }
        let pieces = Syllabifier.syllabify(word, language: "en").syllables
        let offsets = offsets(pieces, in: word)
        var choices = EnglishPronunciation.candidates(for: word, texts: pieces)
        let whole = choices.isEmpty || offsets == nil
        var marker = ""
        if whole {
            // Where spelling and dictionary nuclei do not align, offer the complete word.
            choices = EnglishPronunciation.wholeCandidates(for: word, style: .american)
            marker = "~"
        } else if choices.count > 1,
                  let selected = EnglishPronunciation.candidate(for: word, texts: pieces) {
            choices = [selected]
        }
        guard !choices.isEmpty else {
            entries.append(word + "\t\t?")
            return
        }
        var codes: [String] = []
        for form in choices {
            let code = encode(form, whole: whole)
            if !codes.contains(code) { codes.append(code) }
        }
        let boundaries = whole ? "" : (offsets ?? []).map { String($0) }.joined(separator: ".")
        entries.append([word, boundaries, marker + codes.joined(separator: ",")].joined(separator: "\t"))
    }
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let raw = try String(contentsOf: input.appendingPathComponent("cmudict.dict"), encoding: .utf8)
let license = try String(contentsOf: input.appendingPathComponent("LICENSE"), encoding: .utf8)
var forms: [String: [Substring]] = [:]
for line in raw.split(separator: "\n") {
    let fields = line.split(separator: "#", maxSplits: 1)[0].split(separator: " ", maxSplits: 1)
    guard fields.count == 2 else { continue }
    let word = String(fields[0].prefix(while: { $0 != "(" }))
    guard word.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'" || $0 == "-") }) else { continue }
    forms[word, default: []].append(fields[1])
}
guard forms.count > 100_000 else { fatalError("Incomplete CMU pronunciation dictionary") }
var words = Set(forms.keys)
// Include the spoken -in' form that the native engine derives from a known -ing form.
for word in forms.keys where word.hasSuffix("ing") && word.count > 4 {
    let elision = String(word.dropLast()) + "'"
    if forms[String(word.dropLast())] == nil { words.insert(elision) }
}
var lexicon = Lexicon()
for word in words.sorted() {
    // Native lookup trims surrounding apostrophes. Avoid assigning a different dictionary word's
    // phones to elisions such as 'cause or goin' when the bare spelling also exists.
    let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    let resolved = forms[bare] ?? forms[bare + "'"]
    let usable = forms[word] == nil || forms[word] == resolved
    lexicon.add(word, usable: usable)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
let payload = ["groups": lexicon.groups.joined(separator: "\n"), "entries": lexicon.entries.joined(separator: "\n")]
var script = Data(("/* Derived from CMUdict (see CMUdict-LICENSE.txt).\n" + license + "*/\nglobalThis.SingingDictionary = ").utf8)
script.append(try encoder.encode(payload))
script.append(Data(";\n".utf8))
try script.write(to: output, options: .atomic)
print("Built \(lexicon.entries.count) US English entries (\(script.count) bytes).")
