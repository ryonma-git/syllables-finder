import Foundation

/// A short, public-domain song with one melody note per sung syllable.
public enum TwinkleSample {
    private struct WordSpec {
        let surface: String
        let meaning: String
        let syllables: [String]
    }

    private struct LineSpec {
        let text: String
        let translation: String
        let words: [WordSpec]
        let pitches: [Int]
    }

    public static func make() -> SongDocument {
        func beat(_ value: Int) -> Beat { try! Beat(Int64(value)) }
        var serial = 1_000
        func id() -> UUID {
            serial += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", serial))!
        }

        let opening = [60, 60, 67, 67, 69, 69, 67]
        let answer = [65, 65, 64, 64, 62, 62, 60]
        let middle = [67, 67, 65, 65, 64, 64, 62]
        let lines: [LineSpec] = [
            .init(text: "Twinkle, twinkle, little star,", translation: "きらきら光る小さな星よ、", words: [
                .init(surface: "Twinkle,", meaning: "きらきら光る", syllables: ["Twin", "kle"]),
                .init(surface: "twinkle,", meaning: "きらきら光る", syllables: ["twin", "kle"]),
                .init(surface: "little", meaning: "小さな", syllables: ["lit", "tle"]),
                .init(surface: "star,", meaning: "星", syllables: ["star"])
            ], pitches: opening),
            .init(text: "How I wonder what you are!", translation: "あなたはいったい何なのだろう。", words: [
                .init(surface: "How", meaning: "どのように", syllables: ["How"]),
                .init(surface: "I", meaning: "私が", syllables: ["I"]),
                .init(surface: "wonder", meaning: "不思議に思う", syllables: ["won", "der"]),
                .init(surface: "what", meaning: "何", syllables: ["what"]),
                .init(surface: "you", meaning: "あなたが", syllables: ["you"]),
                .init(surface: "are!", meaning: "である", syllables: ["are"])
            ], pitches: answer),
            .init(text: "Up above the world so high,", translation: "世界のはるか上に、", words: [
                .init(surface: "Up", meaning: "上に", syllables: ["Up"]),
                .init(surface: "above", meaning: "より上に", syllables: ["a", "bove"]),
                .init(surface: "the", meaning: "その", syllables: ["the"]),
                .init(surface: "world", meaning: "世界", syllables: ["world"]),
                .init(surface: "so", meaning: "とても", syllables: ["so"]),
                .init(surface: "high,", meaning: "高く", syllables: ["high"])
            ], pitches: middle),
            .init(text: "Like a diamond in the sky.", translation: "空のダイヤモンドのように。", words: [
                .init(surface: "Like", meaning: "〜のように", syllables: ["Like"]),
                .init(surface: "a", meaning: "ひとつの", syllables: ["a"]),
                .init(surface: "diamond", meaning: "ダイヤモンド", syllables: ["dia", "mond"]),
                .init(surface: "in", meaning: "〜の中に", syllables: ["in"]),
                .init(surface: "the", meaning: "その", syllables: ["the"]),
                .init(surface: "sky.", meaning: "空", syllables: ["sky"])
            ], pitches: middle),
            .init(text: "Twinkle, twinkle, little star,", translation: "きらきら光る小さな星よ、", words: [
                .init(surface: "Twinkle,", meaning: "きらきら光る", syllables: ["Twin", "kle"]),
                .init(surface: "twinkle,", meaning: "きらきら光る", syllables: ["twin", "kle"]),
                .init(surface: "little", meaning: "小さな", syllables: ["lit", "tle"]),
                .init(surface: "star,", meaning: "星", syllables: ["star"])
            ], pitches: opening),
            .init(text: "How I wonder what you are!", translation: "あなたはいったい何なのだろう。", words: [
                .init(surface: "How", meaning: "どのように", syllables: ["How"]),
                .init(surface: "I", meaning: "私が", syllables: ["I"]),
                .init(surface: "wonder", meaning: "不思議に思う", syllables: ["won", "der"]),
                .init(surface: "what", meaning: "何", syllables: ["what"]),
                .init(surface: "you", meaning: "あなたが", syllables: ["you"]),
                .init(surface: "are!", meaning: "である", syllables: ["are"])
            ], pitches: answer)
        ]

        var doc = SongDocument()
        doc.id = id()
        doc.metadata = .init(title: "Twinkle, Twinkle, Little Star", sourceLanguage: "en")
        doc.metadata.notes = "Jane Taylor『The Star』(1806) と伝承曲『Ah! vous dirai-je, maman』の旋律。教育用にハ長調の単旋律を入力。発音は一般的な米語の教材用近似。diamondは歌の2音節に合わせています。歌声は含みません。"
        doc.music.tempos = [.init(bpm: 96)]
        let pronunciation: [String: [(ipa: String, reading: String)]] = [
            "twinkle": [("twɪŋ", "トゥウィン"), ("kəl", "クル")],
            "little": [("lɪt", "リト"), ("əl", "ル")],
            "star": [("stɑːr", "スター")],
            "how": [("haʊ", "ハウ")], "i": [("aɪ", "アイ")],
            "wonder": [("wʌn", "ワン"), ("dər", "ダー")],
            "what": [("wʌt", "ワット")], "you": [("juː", "ユー")],
            "are": [("ɑːr", "アー")], "up": [("ʌp", "アップ")],
            "above": [("ə", "ア"), ("bʌv", "バヴ")],
            "the": [("ðə", "ザ")], "world": [("wɝːld", "ワールド")],
            "so": [("soʊ", "ソウ")], "high": [("haɪ", "ハイ")],
            "like": [("laɪk", "ライク")], "a": [("ə", "ア")],
            "diamond": [("daɪ", "ダイ"), ("mənd", "マンド")],
            "in": [("ɪn", "イン")], "sky": [("skaɪ", "スカイ")]
        ]
        let sectionID = id()
        for (lineNumber, line) in lines.enumerated() {
            let start = lineNumber * 8
            let phraseID = id()
            let measures = (0..<2).map { offset in
                Measure(id: id(), number: String(lineNumber * 2 + offset + 1),
                        range: .init(start: beat(start + offset * 4), end: beat(start + (offset + 1) * 4)))
            }
            doc.music.measures.append(contentsOf: measures)
            let durations = [1, 1, 1, 1, 1, 1, 2]
            var cursor = start
            var eventIDs: [UUID] = []
            for (pitch, duration) in zip(line.pitches, durations) {
                let event = MusicalEvent(id: id(), onset: beat(cursor), duration: beat(duration),
                                         measureID: measures[cursor < start + 4 ? 0 : 1].id,
                                         content: .note(.init(pitch: pitch)))
                doc.music.events.append(event)
                eventIDs.append(event.id)
                cursor += duration
            }
            var wordIDs: [UUID] = []
            var noteIndex = 0
            for item in line.words {
                var word = Word(id: id(), parentPhraseID: phraseID, surface: item.surface)
                word.contextualMeaning = .init(item.meaning)
                word.lemma = .init(item.surface.trimmingCharacters(in: .punctuationCharacters).lowercased())
                let key = item.surface.trimmingCharacters(in: .punctuationCharacters).lowercased()
                let sounds = pronunciation[key]!
                precondition(sounds.count == item.syllables.count)
                for (index, text) in item.syllables.enumerated() {
                    let sound = sounds[index]
                    let syllable = Syllable(id: id(), parentWordID: word.id, text: text,
                                            ipa: sound.ipa, reading: sound.reading)
                    word.syllableIDs.append(syllable.id)
                    doc.syllables.append(syllable)
                    doc.alignments.append(.init(id: id(), languageTargets: [.init(.syllable, syllable.id)],
                                                musicTargets: [.event(eventIDs[noteIndex])], relation: .syllabic))
                    noteIndex += 1
                }
                wordIDs.append(word.id)
                doc.words.append(word)
            }
            precondition(noteIndex == eventIDs.count)
            let range = BeatRange(start: beat(start), end: beat(start + 8))
            doc.phrases.append(.init(id: phraseID, originalText: line.text, translation: line.translation,
                                     wordIDs: wordIDs, timeRange: range, musicalEventIDs: eventIDs))
            doc.music.spans.append(.init(id: id(), kind: .phrase, title: line.text, range: range, eventIDs: eventIDs))
        }
        doc.sections = [.init(id: sectionID, title: "第1節", phraseIDs: doc.phrases.map(\.id))]
        return doc
    }
}
