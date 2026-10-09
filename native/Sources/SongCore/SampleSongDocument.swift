import Foundation

public enum SampleSongDocument {
    /// Original teaching fixture. Stable IDs support previews and reproducible tests.
    public static func make() -> SongDocument {
        // All literal beat values below are positive, bounded integers.
        func beat(_ n: Int64) -> Beat { try! Beat(n) }
        var counter = 0
        func id() -> UUID {
            counter += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
        }
        var doc = SongDocument()
        doc.id = id()
        doc.metadata = .init(title: "Morning light", sourceLanguage: "en")
        doc.metadata.notes = "このアプリのために作成した練習サンプル。読みは原音の近似です。"
        let p1 = id(), p2 = id(), sectionID = id()
        let m1 = Measure(id: id(), number: "1", range: .init(start: .zero, end: beat(4)))
        let m2 = Measure(id: id(), number: "2", range: .init(start: beat(4), end: beat(8)))
        doc.music.measures = [m1, m2]
        let pitches = [60, 62, 64, 67, 65, 64, 62, 60]
        doc.music.events = pitches.enumerated().map { offset, pitch in
            .init(id: id(), onset: beat(Int64(offset)), duration: beat(1), measureID: offset < 4 ? m1.id : m2.id, content: .note(.init(pitch: pitch)))
        }
        let data: [(UUID, String, String, String, [(String, String, String, [String], [Int])])] = [
            (p1, "Morning", "朝の", "朝・午前", [("Morn", "mɔːr", "モー", ["m", "ɔː", "r"], [0, 1]), ("ing", "nɪŋ", "ニング", ["n", "ɪ", "ŋ"], [2])]),
            (p1, "light", "光", "光・明かり", [("light", "laɪt", "ライト", ["l", "aɪ", "t"], [3])]),
            (p2, "softly", "やさしく", "静かに・柔らかく", [("soft", "sɔft", "ソフト", ["s", "ɔ", "f", "t"], [4]), ("ly", "li", "リー", ["l", "i"], [5])]),
            (p2, "glow", "輝いて", "柔らかく光る", [("glow", "ɡloʊ", "グロウ", ["ɡ", "l", "oʊ"], [6, 7])])
        ]
        for (phraseID, surface, meaning, dictionary, syllableData) in data {
            var word = Word(id: id(), parentPhraseID: phraseID, surface: surface)
            word.lemma = .init(surface.lowercased()); word.contextualMeaning = .init(meaning)
            word.dictionaryMeaning = .init(dictionary); word.partOfSpeech = .init(surface == "softly" ? "副詞" : surface == "glow" ? "動詞" : "名詞")
            for (text, ipa, reading, sounds, indices) in syllableData {
                var syllable = Syllable(id: id(), parentWordID: word.id, text: text, ipa: ipa, reading: reading)
                for sound in sounds {
                    let phoneme = Phoneme(id: id(), parentSyllableID: syllable.id, symbol: sound)
                    syllable.phonemeIDs.append(phoneme.id); doc.phonemes.append(phoneme)
                }
                word.syllableIDs.append(syllable.id); doc.syllables.append(syllable)
                doc.alignments.append(.init(id: id(), languageTargets: [.init(.syllable, syllable.id)],
                                            musicTargets: indices.map { .event(doc.music.events[$0].id) },
                                            relation: indices.count > 1 ? .melisma : .syllabic))
            }
            doc.words.append(word)
        }
        doc.phrases = [
            .init(id: p1, originalText: "Morning light,", translation: "朝の光よ、", wordIDs: doc.words.filter { $0.parentPhraseID == p1 }.map(\.id), timeRange: m1.range, musicalEventIDs: Array(doc.music.events.prefix(4)).map(\.id)),
            .init(id: p2, originalText: "softly glow.", translation: "やさしく輝いて。", wordIDs: doc.words.filter { $0.parentPhraseID == p2 }.map(\.id), timeRange: m2.range, musicalEventIDs: Array(doc.music.events.suffix(4)).map(\.id))
        ]
        doc.sections = [.init(id: sectionID, title: "練習 1", phraseIDs: [p1, p2])]
        doc.music.spans = doc.phrases.map { .init(id: id(), kind: .phrase, title: $0.originalText, range: $0.timeRange!, eventIDs: $0.musicalEventIDs) }
        doc.ensureParts(defaultPartID: id())
        return doc
    }

    public static func japanese() -> SongDocument {
        var doc = SongDocument()
        doc.metadata = .init(title: "ひかり", sourceLanguage: "ja")
        var phrase = Phrase(originalText: "ひかり")
        var word = Word(parentPhraseID: phrase.id, surface: "ひかり")
        for (text, sounds) in [("ひ", ["ç", "i"]), ("か", ["k", "a"]), ("り", ["ɾ", "i"])] {
            var syllable = Syllable(parentWordID: word.id, text: text, ipa: sounds.joined(), reading: text)
            var mora = Mora(parentSyllableID: syllable.id, text: text, ipa: sounds.joined())
            for sound in sounds {
                let phoneme = Phoneme(parentSyllableID: syllable.id, parentMoraID: mora.id, symbol: sound)
                doc.phonemes.append(phoneme); mora.phonemeIDs.append(phoneme.id); syllable.phonemeIDs.append(phoneme.id)
            }
            syllable.moraIDs = [mora.id]; doc.moras.append(mora); doc.syllables.append(syllable); word.syllableIDs.append(syllable.id)
        }
        phrase.wordIDs = [word.id]; doc.words = [word]; doc.phrases = [phrase]
        doc.sections = [.init(title: "日本語", phraseIDs: [phrase.id])]
        return doc
    }
}
