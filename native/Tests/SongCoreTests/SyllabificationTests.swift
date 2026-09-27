import Foundation
import SongCore
import Testing

struct SyllabificationTests {
    private func split(_ word: String, _ language: String) -> String {
        Syllabifier.syllabify(word, language: language).syllables.joined(separator: "-")
    }

    @Test func german() {
        let expected = [
            "Freude": "Freu-de", "schöner": "schö-ner", "Götterfunken,": "Göt-ter-fun-ken", "Tochter": "Toch-ter",
            "Elysium!": "E-ly-si-um", "Heiligtum": "Hei-lig-tum", "Zauber": "Zau-ber", "binden": "bin-den",
            "wieder": "wie-der", "Menschen": "Men-schen", "Brüder": "Brü-der", "Alle": "Al-le", "sanfter": "sanf-ter",
            "Flügel": "Flü-gel", "geteilt": "ge-teilt", "streng": "streng", "Deine": "Dei-ne", "Zucker": "Zu-cker",
            "Fenster": "Fens-ter", "singen": "sin-gen",
            "betreten": "be-tre-ten", "verstehen": "ver-ste-hen", "entfernt": "ent-fernt", "Erde": "Er-de", "Berlin": "Ber-lin"
        ]
        for (word, syllables) in expected { #expect(split(word, "de") == syllables, "\(word)") }
        #expect(Syllabifier.syllabify("Freude", language: "de").stressIndex == 0)
        #expect(Syllabifier.syllabify("geteilt", language: "de").stressIndex == 1)
        #expect(Syllabifier.syllabify("Erde", language: "de").stressIndex == 0)
    }

    @Test func spanish() {
        let expected = [
            "canción": "can-ción", "día": "dí-a", "guerra": "gue-rra", "quiero": "quie-ro", "amor": "a-mor",
            "corazón": "co-ra-zón", "hablar": "ha-blar", "estrella": "es-tre-lla", "Cielito": "Cie-li-to",
            "lindo": "lin-do", "mayo": "ma-yo", "muy": "muy", "instrumento": "ins-tru-men-to", "poeta": "po-e-ta",
            "agua": "a-gua", "noche": "no-che"
        ]
        for (word, syllables) in expected { #expect(split(word, "es") == syllables, "\(word)") }
        #expect(Syllabifier.syllabify("canción", language: "es").stressIndex == 1)
        #expect(Syllabifier.syllabify("amor", language: "es").stressIndex == 1)
        #expect(Syllabifier.syllabify("lindo", language: "es").stressIndex == 0)
        #expect(Syllabifier.syllabify("día", language: "es").stressIndex == 0)
    }

    @Test func frenchCountsSungMuteE() {
        let expected = [
            "Frère": "Frè-re", "Jacques,": "Jac-ques", "Dormez-vous": "Dor-mez-vous", "Sonnez": "Son-nez",
            "matines": "ma-ti-nes", "l'amour": "l'a-mour", "Dieu": "Dieu", "oiseau": "oi-seau", "chantent": "chan-tent",
            "oui": "oui", "table": "ta-ble", "belle": "bel-le", "enfants": "en-fants", "patrie": "pa-trie"
        ]
        for (word, syllables) in expected { #expect(split(word, "fr") == syllables, "\(word)") }
        let frere = Syllabifier.syllabify("Frère", language: "fr")
        #expect(frere.stressIndex == 0)
        #expect(frere.note != nil)
    }

    @Test func italian() {
        let expected = [
            "amore": "a-mo-re", "cuore": "cuo-re", "figlio": "fi-glio", "bacio": "ba-cio", "lasciare": "la-scia-re",
            "pasta": "pa-sta", "mostro": "mo-stro", "bello": "bel-lo", "gnocchi": "gnoc-chi", "città": "cit-tà",
            "sogno": "so-gno", "vita": "vi-ta"
        ]
        for (word, syllables) in expected { #expect(split(word, "it") == syllables, "\(word)") }
        #expect(Syllabifier.syllabify("città", language: "it").stressIndex == 1)
        #expect(Syllabifier.syllabify("amore", language: "it").stressIndex == 1)
    }

    @Test func ecclesiasticalLatin() {
        let expected = [
            "Kyrie": "Ky-ri-e", "eleison": "e-le-i-son", "Christe": "Chri-ste", "Agnus": "A-gnus", "excelsis": "ex-cel-sis",
            "Deo": "De-o", "caeli": "cae-li", "eius": "e-ius", "Iesu": "Ie-su", "laudamus": "lau-da-mus",
            "Hosanna": "Ho-san-na", "Sanctus": "Sanc-tus", "Patrem": "Pa-trem", "qui": "qui", "sanguis": "san-guis",
            "Gloria": "Glo-ri-a"
        ]
        for (word, syllables) in expected { #expect(split(word, "la") == syllables, "\(word)") }
    }

    @Test func russianWithExplicitStress() {
        let expected = ["мо́ре": "мо́-ре", "Россия": "Рос-си-я", "мама": "ма-ма", "ёлка": "ёл-ка", "земля": "зем-ля", "день": "день"]
        for (word, syllables) in expected { #expect(split(word, "ru") == syllables, "\(word)") }
        #expect(Syllabifier.syllabify("мо́ре", language: "ru").stressIndex == 0)
        #expect(Syllabifier.syllabify("ёлка", language: "ru").stressIndex == 0)
        #expect(Syllabifier.syllabify("мама", language: "ru").stressIndex == nil)
    }

    @Test func englishMatchesTheSampleSongs() {
        let expected = [
            "Twinkle,": "Twin-kle", "little": "lit-tle", "star,": "star", "wonder": "won-der", "above": "a-bove",
            "world": "world", "high,": "high", "Like": "Like", "sky.": "sky", "Mary": "Ma-ry", "lamb,": "lamb",
            "fleece": "fleece", "snow.": "snow", "How": "How", "you": "you", "are!": "are", "loves": "loves",
            "wishes": "wi-shes", "wanted": "wan-ted", "table": "ta-ble", "whale": "whale", "beyond": "be-yond"
        ]
        for (word, syllables) in expected { #expect(split(word, "en") == syllables, "\(word)") }
        // The sample sings "diamond" in two syllables: the rules give three and the aligner elides.
        #expect(split("diamond", "en") == "di-a-mond")
    }

    @Test func japaneseMoraeAndReadings() {
        #expect(Syllabifier.morae("きょうは") == ["きょ", "う", "は"])
        #expect(Syllabifier.morae("がっこう") == ["が", "っ", "こ", "う"])
        #expect(Syllabifier.morae("コーヒー") == ["コ", "ー", "ヒ", "ー"])
        let kana = Syllabifier.syllabify(LyricToken(surface: "ひかり"), language: "ja")
        #expect(kana.syllables == ["ひ", "か", "り"])
        #expect(kana.readings == ["ヒ", "カ", "リ"])
        let tokens = Syllabifier.tokenize("星（ほし）がひかる。", language: "ja")
        #expect(tokens.first == LyricToken(surface: "星", reading: "ほし"))
        #expect(tokens.map(\.surface).joined().replacingOccurrences(of: " ", with: "") == "星がひかる。")
        let estimated = Syllabifier.tokenize("夜空", language: "ja")
        #expect(estimated.count == 1)
        #expect(estimated.first?.reading?.isEmpty == false)
    }

    @Test func koreanAndMandarin() {
        #expect(split("사랑해", "ko") == "사-랑-해")
        let mandarin = Syllabifier.syllabify(LyricToken(surface: "月亮"), language: "zh")
        #expect(mandarin.syllables == ["月", "亮"])
        #expect(mandarin.readings?.count == 2)
    }

    @Test func tokenizingKeepsPunctuationWithWords() {
        #expect(Syllabifier.tokenize("Dormez-vous ? Dormez-vous ?", language: "fr").map(\.surface) == ["Dormez-vous ?", "Dormez-vous ?"])
        #expect(Syllabifier.tokenize("« Freude, schöner »", language: "de").map(\.surface) == ["« Freude,", "schöner »"])
    }
}

struct LyricEntryTests {
    @Test func enteringALineCreatesRuleSyllablesWithStress() throws {
        var song = SongDocument()
        song.metadata.sourceLanguage = "de"
        let added = song.appendPhrase(text: "Freude, schöner Götterfunken,", language: "de", syllabify: true)
        let id = try #require(added)
        try song.validate()
        let phrase = try #require(song.phrase(id))
        #expect(phrase.language == nil)
        let words = song.words(in: phrase)
        #expect(words.map(\.surface) == ["Freude,", "schöner", "Götterfunken,"])
        let freude = song.syllables(in: words[0])
        #expect(freude.map(\.text.value) == ["Freu", "de"])
        #expect(freude[0].text.source.kind == .rule && !freude[0].text.userEdited)
        #expect(freude[0].stress.value == "強" && freude[1].stress.value.isEmpty)
        let latin = song.appendPhrase(text: "Ave Maria", language: "la", syllabify: true)
        let other = try #require(latin)
        #expect(song.phrase(other)?.language == "la")
        #expect(song.words.flatMap(\.syllableIDs).count == 2 + 2 + 4 + 2 + 3)
    }

    @Test func correctingSyllablesKeepsAlignmentsOnlyWhenTheCountIsUnchanged() throws {
        var song = TwinkleSample.make()
        let diamond = try #require(song.words.first { $0.surface == "diamond" })
        let before = song.alignments.count
        try song.setSyllables(wordID: diamond.id, texts: ["di", "amond"])
        #expect(song.alignments.count == before)
        #expect(song.syllables(in: song.word(diamond.id)!).map(\.text.value) == ["di", "amond"])
        #expect(song.syllables(in: song.word(diamond.id)!)[0].text.userEdited)
        try song.setSyllables(wordID: diamond.id, texts: ["di", "a", "mond"])
        #expect(song.alignments.count == before - 2)
        try song.validate()
        #expect(throws: SongError.self) { try song.resyllabify(wordID: diamond.id, language: "en") }
    }

    @Test func unsplitWordsFromOlderEntryCanBeSplitLater() throws {
        var song = SongDocument()
        song.metadata.sourceLanguage = "es"
        song.appendPhrase(text: "Cielito lindo")
        let phrase = song.phrases[0]
        #expect(song.words.allSatisfy { $0.syllableIDs.isEmpty })
        #expect(song.syllabifyUnsplitWords(phraseID: phrase.id) == 2)
        #expect(song.syllables.map(\.text.value) == ["Cie", "li", "to", "lin", "do"])
        try song.validate()
    }
}
