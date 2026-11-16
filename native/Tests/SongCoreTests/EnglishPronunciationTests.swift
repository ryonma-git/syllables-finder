import Foundation
import Testing
import SongCore

struct EnglishPronunciationTests {
    @Test func consonantHomographsWaitForContextAndRecheckOldAutomaticFields() throws {
        var song = SongDocument()
        song.appendPhrase(text: "We use it", language: "en", syllabify: true)
        song.appendPhrase(text: "Close it", language: "en", syllabify: true)
        for surface in ["use", "Close"] {
            let word = try #require(song.words.first { $0.surface == surface })
            #expect(song.syllables(in: word).allSatisfy { $0.ipa.value.isEmpty && $0.reading.value.isEmpty })
            let i = try #require(song.syllables.firstIndex { $0.parentWordID == word.id })
            song.syllables[i].ipa = .init(surface == "use" ? "ˈjuːs" : "ˈkloʊs", source: EnglishPronunciation.source)
            song.syllables[i].reading = .init(surface == "use" ? "ユース" : "クロウス", source: EnglishPronunciation.source)
        }
        let ids = song.syllables.map(\.id)
        let report = EnglishPronunciation.apply(to: &song)
        #expect(report.changedWords == 2)
        #expect(report.reviewSurfaces.contains("use") && report.reviewSurfaces.contains("Close"))
        for word in song.words where ["use", "Close"].contains(word.surface) {
            #expect(song.syllables(in: word).allSatisfy { $0.ipa.value.isEmpty && $0.reading.value.isEmpty })
        }
        #expect(song.syllables.map(\.id) == ids)
        let repeated = EnglishPronunciation.apply(to: &song)
        #expect(repeated.changedWords == 0)
        try song.validate()
    }

    @Test func contextualPronunciationRetainsManualAndAISelections() throws {
        for source in [FieldSource(.manual), FieldSource(.ai, provider: "test", model: "context-model")] {
            var song = SongDocument()
            song.appendPhrase(text: "use", language: "en", syllabify: true)
            song.syllables[0].ipa = .init("ˈjuːz", source: source, userEdited: source.kind == .manual)
            song.syllables[0].reading = .init("ユーズ", source: source, userEdited: source.kind == .manual)
            EnglishPronunciation.apply(to: &song)
            EnglishPronunciation.apply(to: &song)
            #expect(song.syllables[0].ipa.value == "ˈjuːz")
            #expect(!song.syllables[0].reading.value.isEmpty)
            #expect(song.syllables[0].ipa.source == source)
        }
    }

    @Test func lexicalStressAmbiguityDoesNotReturnAsAWholeWordFallback() throws {
        var song = SongDocument()
        song.appendPhrase(text: "increase", language: "en", syllabify: true)
        #expect(song.syllables.allSatisfy { $0.ipa.value.isEmpty })
        #expect(song.words[0].wholePronunciation == nil)
        let texts = song.syllables.map(\.text.value)
        let forms = EnglishPronunciation.candidates(for: "increase", texts: texts)
        #expect(Set(forms.compactMap(\.stressIndex)) == [0, 1])
        for form in forms {
            let retained = EnglishPronunciation.candidate(for: "increase", texts: texts, currentIPA: form.ipa)
            #expect(retained == form)
        }
    }

    @Test func multilingualIPAAdmitsOfficialSymbolsAndRequiresPhones() {
        for ipa in ["beˈβe", "baχ", "ħa", "ǃa", "ɲɔ̃", "a˥˩", "t͡ʃ", "ŋ"] {
            #expect(EnglishPronunciation.isValidIPA(ipa), "\(ipa)")
        }
        for text in ["...", "/[]", "ˈˌː", "̃", "123", "カタカナ", "<script>"] {
            #expect(!EnglishPronunciation.isValidIPA(text), "\(text)")
        }
    }

    @Test func newInputUsesDictionaryCountForAdjacentVowelHiatus() {
        #expect(EnglishPronunciation.reading(forIPA: "raː") == "ラー")
        #expect(EnglishPronunciation.reading(forIPA: "wɪnd") == "ウィンド")
        #expect(Syllabifier.syllabify("quietly", language: "en").syllables == ["qui", "et", "ly"])
        #expect(Syllabifier.syllabify("quiet", language: "en").syllables == ["qui", "et"])
        var song = SongDocument()
        song.appendPhrase(text: "quietly", language: "en", syllabify: true)
        #expect(song.syllables.allSatisfy { !$0.ipa.value.isEmpty && !$0.reading.value.isEmpty })
    }

    @Test func wholeWordDictionaryPreventsSpellingFragmentPronunciations() throws {
        let cases: [(String, String, [String]?)] = [
            ("coming", "kʌmɪŋ", ["カ", "ミング"]), ("comin’", "kʌmɪn", ["カ", "ミン"]),
            ("creation", "krieɪʃən", ["クリ", "エイ", "ション"]),
            ("heaven", "hɛvən", ["ヘ", "ヴン"]), ("I've", "aɪv", ["アイヴ"]),
            ("won't", "woʊnt", nil), ("you've", "juv", ["ユーヴ"]), ("wonder", "wʌndər", nil),
            ("action", "ækʃən", ["アク", "ション"]),
            ("creature", "kritʃər", nil), ("explanation", "ɛkspləneɪʃən", nil),
            ("feelin's", "filɪnz", nil), ("lookin'", "lʊkɪn", nil), ("tellin'", "tɛlɪn", nil)
        ]
        for (word, ipa, readings) in cases {
            let split = Syllabifier.syllabify(word, language: "en")
            let result = try #require(EnglishPronunciation.candidate(for: word, texts: split.syllables), "\(word)")
            #expect(EnglishPronunciation.comparableIPA(result.ipa.joined()) == ipa, "\(word): \(result.ipa)")
            if let readings { #expect(result.readings == readings, "\(word)") }
        }
        // CMUdict also contains /kwɛʃən/. Distinct consonant forms now wait for selection;
        // both whole-word pronunciations remain available, including the previously expected form.
        let questionSplit = Syllabifier.syllabify("question", language: "en").syllables
        let questionCandidates = EnglishPronunciation.candidates(for: "question", texts: questionSplit)
        #expect(Set(questionCandidates.map { EnglishPronunciation.comparableIPA($0.ipa.joined()) }) == ["kwɛstʃən", "kwɛʃən"])
        #expect(EnglishPronunciation.candidate(for: "question", texts: questionSplit) == nil)
        let selected = try #require(questionCandidates.first { EnglishPronunciation.comparableIPA($0.ipa.joined()) == "kwɛstʃən" })
        let retained = EnglishPronunciation.candidate(for: "question", texts: questionSplit, currentIPA: selected.ipa)
        #expect(retained == selected)
        #expect(Syllabifier.syllabify("Creation!", language: "en").syllables == ["Cre", "a", "tion"])
        #expect(Syllabifier.syllabify("station", language: "en").syllables == ["sta", "tion"])
        #expect(Syllabifier.syllabify("cation", language: "en").syllables == ["cat", "i", "on"])
        #expect(Syllabifier.orthographicVowelNuclei(in: "creation", language: "en") == [2..<3, 3..<4, 6..<7])
        #expect(Syllabifier.syllabify("creature", language: "en").syllables.count == 2)
    }

    @Test func newLyricsHaveDictionaryIPAAndRequestedKanaWithoutAnLLM() throws {
        var song = SongDocument()
        song.appendPhrase(text: "are the coming creation", language: "en", syllabify: true)
        try song.validate()
        #expect(song.syllables.map(\.reading.value) == ["アー", "ザ", "カ", "ミング", "クリ", "エイ", "ション"])
        #expect(song.syllables.allSatisfy { $0.ipa.source.kind == .dictionary && !$0.ipa.value.isEmpty })
    }

    @Test func legacyRepairPreservesNotesAndManualCorrections() throws {
        var song = SongDocument()
        song.appendPhrase(text: "creation are the coming", language: "en", syllabify: true)
        for index in song.syllables.indices {
            song.syllables[index].ipa = .init("wrong", source: .init(.ai))
            song.syllables[index].reading = .init("コウ", source: .init(.ai))
        }
        for (index, text) in ["crea", "ti", "on"].enumerated() {
            song.syllables[index].text = .init(text, source: .init(.rule))
        }
        song.syllables[3].reading.edit("自分のアー")
        song.syllables[4].ipa.edit("ðiː")
        song.syllables[4].reading.edit("自分のザ")
        let part = song.addPart(name: "旋律")
        for (index, syllable) in song.syllables.enumerated() {
            let note = try song.enterStep(partID: part, onset: Beat(Int64(index)), duration: Beat(1), pitch: 60)
            try song.align(syllableID: syllable.id, to: [note])
        }
        let before = song
        let report = EnglishPronunciation.apply(to: &song)
        #expect(report.changedWords == 3 && report.protectedWords == 2)
        #expect(song.syllables.prefix(3).map(\.text.value) == ["cre", "a", "tion"])
        #expect(song.syllables.prefix(3).map(\.reading.value) == ["クリ", "エイ", "ション"])
        #expect(song.syllables[3].reading == before.syllables[3].reading)
        #expect(song.syllables[4] == before.syllables[4])
        #expect(song.syllables.map(\.id) == before.syllables.map(\.id))
        #expect(song.alignments == before.alignments && song.music == before.music)
        #expect(song.phrases == before.phrases && song.words == before.words)
        let once = song
        #expect(EnglishPronunciation.apply(to: &song).changedWords == 0)
        #expect(song == once)
        try song.validate()
    }

    @Test func explicitTwoSingingGroupsRemainTwo() throws {
        var song = SongDocument()
        song.appendPhrase(text: "creation", language: "en", syllabify: true)
        try song.setSyllables(wordID: song.words[0].id, texts: ["crea", "tion"])
        let ids = song.syllables.map(\.id)
        EnglishPronunciation.apply(to: &song)
        #expect(song.syllables.map(\.id) == ids)
        #expect(song.syllables.map(\.text.value) == ["crea", "tion"])
        #expect(song.syllables.map(\.reading.value) == ["クリエイ", "ション"])
        #expect(EnglishPronunciation.comparableIPA(song.syllables.map(\.ipa.value).joined()) == "krieɪʃən")
    }

    @Test func boundaryCorrectionsDoNotMixWithManualKanaOrPhonemeData() throws {
        var song = SongDocument()
        song.appendPhrase(text: "creation coming", language: "en", syllabify: true)
        for (index, text) in ["crea", "ti", "on"].enumerated() {
            song.syllables[index].text = .init(text, source: .init(.rule))
        }
        song.syllables[0].reading.edit("クリエイ")
        let coming = song.syllables[3]
        let phoneme = Phoneme(parentSyllableID: coming.id, symbol: "k")
        song.phonemes.append(phoneme)
        song.syllables[3].phonemeIDs = [phoneme.id]
        song.syllables[3].ipa.edit("kə")
        let before = song
        let report = EnglishPronunciation.apply(to: &song)
        #expect(report.reviewSurfaces == ["creation"])
        #expect(Array(song.syllables.prefix(4)) == Array(before.syllables.prefix(4)))
        #expect(song.phonemes == before.phonemes)
    }

    @Test func kanaIsDrivenByPhonesAndKeepsEnglishRAndConsonantClustersReadable() throws {
        for (word, expected) in [("car", "カー"), ("door", "ドー"), ("care", "ケア"),
                                 ("put", "プット"), ("touch", "タッチ"), ("it's", "イッツ"),
                                 ("wish", "ウィッシュ"), ("can", "キャン")] {
            let texts = Syllabifier.syllabify(word, language: "en").syllables
            let candidate = try #require(EnglishPronunciation.candidate(for: word, texts: texts), "\(word)")
            #expect(candidate.readings.joined() == expected, "\(word)")
        }
        let explanation = try #require(EnglishPronunciation.candidate(for: "explanation", texts: ["ex", "pla", "na", "tion"]))
        #expect(explanation.ipa == ["ˌɛks", "plə", "ˈneɪ", "ʃən"])
    }

    @Test func doNotForceAmbiguousWordsCountsOrOtherLanguages() throws {
        #expect(EnglishPronunciation.candidate(for: "wind", texts: ["wind"]) == nil)
        #expect(EnglishPronunciation.candidate(for: "wind", texts: ["wind"], currentIPA: ["wɪnd"]) != nil)
        #expect(EnglishPronunciation.candidate(for: "zzqvzz", texts: ["zzqvzz"]) == nil)
        var song = SongDocument()
        song.appendPhrase(text: "creation", language: "en", syllabify: true)
        try song.setSyllables(wordID: song.words[0].id, texts: ["c", "re", "a", "tion"])
        song.appendPhrase(text: "the", language: "fr", syllabify: true)
        let before = song
        #expect(EnglishPronunciation.apply(to: &song).reviewWords == 1)
        #expect(song.syllables == before.syllables && song.alignments == before.alignments)
        #expect(song.words[0].wholePronunciation != nil)
        #expect(song.words[1] == before.words[1])
    }
}
