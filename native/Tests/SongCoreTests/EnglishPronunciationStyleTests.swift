import Foundation
import Testing
import SongCore

struct EnglishPronunciationStyleTests {
    @Test func britishVowelQualityLengthAndWholeWordSyllables() throws {
        for (word, ipa, kana) in [
            ("mountain", "maʊntɪn", "マウンティン"), ("falling", "fɔːlɪŋ", "フォーリング"),
            ("from", "frɒm", "フロム"), ("gone", "ɡɒn", "ゴン"), ("soft", "sɒft", "ソフト"),
            ("go", "ɡəʊ", "ゴウ"), ("here", "hɪə", "ヒア"), ("are", "ɑː", "アー")
        ] {
            var song = SongDocument()
            song.metadata.englishPronunciation = .british
            song.appendPhrase(text: word, language: "en", syllabify: true)
            #expect(EnglishPronunciation.phoneticKey(song.syllables.map(\.ipa.value).joined()) == ipa, "\(word)")
            #expect(song.syllables.map(\.reading.value).joined() == kana, "\(word)")
            #expect(song.syllables.allSatisfy { $0.ipa.source.provider?.contains("British") == true })
            try song.validate()
        }
        #expect(EnglishPronunciation.reading(forIPA: "frɒm") == "フロム")
        #expect(EnglishPronunciation.reading(forIPA: "frʌm") == "フラム")
        #expect(EnglishPronunciation.reading(forIPA: "ˈfɔːlɪŋ") == "フォーリング")
        #expect(EnglishPronunciation.phoneticKey("fɔːl") != EnglishPronunciation.phoneticKey("fɔl"))
        #expect(EnglishPronunciation.comparableIPA("ɒ") != EnglishPronunciation.comparableIPA("ɑ"))
    }

    @Test func unknownBritishWordsNeverUseUSDictionarySilently() throws {
        #expect(EnglishPronunciation.dictionaryIPA(for: "coming").isEmpty == false)
        #expect(EnglishPronunciation.dictionaryIPA(for: "coming", style: .british).isEmpty)
        var song = SongDocument()
        song.appendPhrase(text: "coming", language: "en", syllabify: true)
        #expect(song.syllables.allSatisfy { !$0.ipa.value.isEmpty })
        let ids = song.syllables.map(\.id)
        let report = EnglishPronunciationStyle.apply(.british, to: &song)
        #expect(song.syllables.allSatisfy { $0.ipa.value.isEmpty && $0.reading.value.isEmpty })
        #expect(song.syllables.map(\.id) == ids)
        #expect(report.reviewSurfaces == ["coming"])
        EnglishPronunciationStyle.apply(.american, to: &song)
        #expect(song.syllables.allSatisfy { !$0.ipa.value.isEmpty })
        #expect(song.syllables.map(\.id) == ids)
    }

    @Test func accentSwitchPreservesManualWordsForeignLinesIDsAndNotes() throws {
        var song = SongDocument()
        song.appendPhrase(text: "from mountain falling", language: "en", syllabify: true)
        song.appendPhrase(text: "bonjour", language: "fr", syllabify: true)
        song.syllables[0].reading.edit("歌唱用のフロム")
        let part = song.addPart(name: "旋律")
        for (index, syllable) in song.syllables.enumerated() {
            let note = try song.enterStep(partID: part, onset: Beat(Int64(index)), duration: Beat(1), pitch: 60)
            try song.align(syllableID: syllable.id, to: [note])
        }
        let original = song
        let report = EnglishPronunciationStyle.apply(.british, to: &song)
        #expect(report.protectedWords == 1)
        #expect(song.syllables[0] == original.syllables[0])
        #expect(song.syllables.last == original.syllables.last)
        #expect(song.syllables.map(\.id) == original.syllables.map(\.id))
        #expect(song.music == original.music && song.alignments == original.alignments)
        #expect(song.words == original.words && song.phrases == original.phrases)
        #expect(song.syllables[2].ipa.value == "tɪn")
        try song.validate()
    }

    @Test func oldMetadataKeepsAmericanAndNewChoiceSurvivesSave() throws {
        let old = Data(#"{"title":"Old","sourceLanguage":"en","translationLanguage":"ja","notes":""}"#.utf8)
        let metadata = try JSONDecoder().decode(SongMetadata.self, from: old)
        #expect(metadata.englishPronunciation == nil)
        #expect(metadata.englishPronunciationStyle == .american)
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "from", language: "en", syllabify: true)
        let saved = try JSONDecoder().decode(SongDocument.self, from: song.encoded())
        #expect(saved == song)
        #expect(saved.metadata.englishPronunciationStyle == .british)
    }

    @Test func generationAPIHonorsExplicitAccentAndKeepsLegacyDefault() throws {
        let input = Data(#"{"title":"発音確認","sourceLanguage":"en","lyrics":"from mountain falling","englishPronunciation":"british"}"#.utf8)
        let request = try JSONDecoder().decode(SongGenerationRequest.self, from: input)
        let song = try request.makeDocument()
        #expect(song.metadata.englishPronunciationStyle == .british)
        #expect(song.syllables.map(\.reading.value) == ["フロム", "マウン", "ティン", "フォー", "リング"])
        let old = try SongGenerationRequest(title: "Old", sourceLanguage: "en", lyrics: "from").makeDocument()
        #expect(old.metadata.englishPronunciationStyle == .american)
    }

    @Test func strongAndWeakFormsAndManualIPAStayDistinct() throws {
        let weak = try #require(EnglishPronunciation.candidate(for: "from", texts: ["from"], currentIPA: ["frəm"], style: .british))
        #expect(weak.ipa == ["frəm"] && weak.readings == ["フラム"])
        var song = SongDocument()
        song.metadata.englishPronunciation = .british
        song.appendPhrase(text: "from", language: "en", syllabify: true)
        song.syllables[0].ipa.edit("frɑm")
        song.syllables[0].reading = .init("")
        EnglishPronunciation.apply(to: &song)
        #expect(song.syllables[0].ipa.value == "frɑm")
        #expect(song.syllables[0].reading.value.isEmpty)
        #expect(EnglishPronunciation.candidate(for: "wind", texts: ["wind"], style: .british) == nil)
        #expect(EnglishPronunciation.candidate(for: "mountain", texts: ["mountain"], style: .british) == nil)
    }
}
