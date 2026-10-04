import Foundation

public struct SampleEntry: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let languageCode: String
    public let subtitle: String
    public let details: String
    private let factory: @Sendable () -> SongDocument

    public init(id: String, title: String, languageCode: String, subtitle: String, details: String,
                factory: @escaping @Sendable () -> SongDocument) {
        self.id = id; self.title = title; self.languageCode = languageCode
        self.subtitle = subtitle; self.details = details
        self.factory = factory
    }

    public var languageName: String {
        switch languageCode {
        case "la": "ラテン語"
        case "zh": "中国語"
        default: Syllabifier.displayName(for: languageCode)
        }
    }
    public func make() -> SongDocument { factory() }
}

public enum SampleCatalog {
    public static let entries: [SampleEntry] = [
        .init(id: "twinkle", title: "きらきら星", languageCode: "en", subtitle: "12小節 · 42音節",
              details: "よく知られた旋律で、音節と音符を一つずつ確かめられます。", factory: TwinkleSample.make),
        .init(id: "mary", title: "Mary Had a Little Lamb", languageCode: "en", subtitle: "8小節 · 26音節",
              details: "隣り合う音の上下と、長い語尾を練習します。", factory: makeMary),
        .init(id: "frere", title: "Frère Jacques", languageCode: "fr", subtitle: "8小節 · 32音節",
              details: "繰り返しの旋律で、読みとIPAを見比べます。", factory: makeFrereJacques),
        .init(id: "ninth", title: "第九・歓喜の歌（歌詞）", languageCode: "de", subtitle: "第1節4行 · 歌詞のみ",
              details: "写真にある『歓喜の歌』第1節。原語・意味・音節・IPA・カタカナを読むためのサンプルです。音符は未入力です。", factory: makeNinth),
        .init(id: "morning", title: "Morning light", languageCode: "en", subtitle: "オリジナル · 2小節",
              details: "短い操作練習用のサンプルです。", factory: SampleSongDocument.make)
    ] + TraditionalSamples.entries

    struct SyllableSpec {
        let text: String
        let ipa: String
        let reading: String
        init(_ text: String, _ ipa: String, _ reading: String) {
            self.text = text; self.ipa = ipa; self.reading = reading
        }
    }
    struct WordSpec {
        let surface: String
        let meaning: String
        let syllables: [SyllableSpec]
        init(_ surface: String, _ meaning: String, _ syllables: [SyllableSpec]) {
            self.surface = surface; self.meaning = meaning; self.syllables = syllables
        }
    }
    struct LineSpec {
        let text: String
        let translation: String
        let words: [WordSpec]
        let pitches: [Int]
        let durations: [Double]
    }

    static func makeSong(title: String, language: String, notes: String,
                                 bpm: Double, serialStart: Int, withMusic: Bool = true,
                                 lines: [LineSpec]) -> SongDocument {
        var serial = serialStart
        func id() -> UUID {
            serial += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", serial))!
        }
        func beat(_ value: Double) -> Beat { try! Beat.grid(value, divisions: 2) }
        var song = SongDocument()
        song.id = id()
        song.metadata = .init(title: title, sourceLanguage: language)
        song.metadata.notes = notes + " 読みとIPAは練習用の近似です。" +
            (withMusic ? "ガイド音はこのアプリ内で単旋律から生成します。" : "")
        song.music.tempos = [.init(bpm: bpm)]
        var cursor = 0.0
        let sectionID = id()
        for line in lines {
            precondition(line.pitches.count == line.durations.count)
            precondition(!withMusic || line.words.flatMap(\.syllables).count == line.pitches.count)
            let phraseID = id()
            let start = cursor
            var eventIDs: [UUID] = []
            for (pitch, duration) in zip(line.pitches, line.durations) {
                let event = MusicalEvent(id: id(), onset: beat(cursor), duration: beat(duration),
                                         content: .note(.init(pitch: pitch)))
                song.music.events.append(event)
                eventIDs.append(event.id)
                cursor += duration
            }
            var wordIDs: [UUID] = []
            var noteIndex = 0
            for item in line.words {
                var word = Word(id: id(), parentPhraseID: phraseID, surface: item.surface)
                word.contextualMeaning = .init(item.meaning)
                word.lemma = .init(item.surface.trimmingCharacters(in: .punctuationCharacters).lowercased())
                for sound in item.syllables {
                    let syllable = Syllable(id: id(), parentWordID: word.id,
                                            text: sound.text, ipa: sound.ipa, reading: sound.reading)
                    song.syllables.append(syllable)
                    word.syllableIDs.append(syllable.id)
                    if withMusic {
                        song.alignments.append(.init(id: id(), languageTargets: [.init(.syllable, syllable.id)],
                                                     musicTargets: [.event(eventIDs[noteIndex])], relation: .syllabic))
                        noteIndex += 1
                    }
                }
                song.words.append(word)
                wordIDs.append(word.id)
            }
            let range = BeatRange(start: beat(start), end: beat(cursor))
            song.phrases.append(.init(id: phraseID, originalText: line.text, translation: line.translation,
                                      wordIDs: wordIDs, timeRange: withMusic ? range : nil,
                                      musicalEventIDs: eventIDs))
            if withMusic {
                song.music.spans.append(.init(id: id(), kind: .phrase, title: line.text, range: range, eventIDs: eventIDs))
            }
        }
        let measureCount = withMusic ? Int(ceil(cursor / 4)) : 0
        song.music.measures = (0..<measureCount).map { index in
            Measure(id: id(), number: "\(index + 1)",
                    range: .init(start: beat(Double(index * 4)), end: beat(min(cursor, Double((index + 1) * 4)))))
        }
        song.sections = [.init(id: sectionID, title: "第1節", phraseIDs: song.phrases.map(\.id))]
        if withMusic {
            song.ensureParts(defaultPartID: id())
        } else {
            song.music.parts = [.init(id: id(), name: "歌詞のみ")]
        }
        return song
    }

    private static func makeNinth() -> SongDocument {
        // Schiller's text, as printed in the user's reference. These four lines are a reading
        // sample; no melody is inferred from the photograph. IPA and kana are rehearsal guides.
        func w(_ surface: String, _ meaning: String, _ sounds: [(String, String, String)]) -> WordSpec {
            .init(surface, meaning, sounds.map { .init($0.0, $0.1, $0.2) })
        }
        return makeSong(title: "第九・歓喜の歌（歌詞）", language: "de",
                        notes: "シラー『歓喜に寄す』の第1節（提示された写真の範囲）。歌詞レイアウト確認用。音符は未入力。",
                        bpm: 100, serialStart: 40_000, withMusic: false, lines: [
            .init(text: "Freude, schöner Götterfunken, Tochter aus Elysium!",
                  translation: "歓喜よ、美しい神々の火花よ、エリュシオンから来た娘よ！",
                  words: [
                    w("Freude,", "歓喜", [("Freu", "ˈfʁɔʏ", "フロイ"), ("de", "də", "デ")]),
                    w("schöner", "美しい", [("schö", "ˈʃøː", "シェー"), ("ner", "nɐ", "ナー")]),
                    w("Götterfunken,", "神々の火花", [("Göt", "ˈɡœt", "ゲッ"), ("ter", "ɐ", "ター"), ("fun", "ˌfʊŋ", "フン"), ("ken", "kən", "ケン")]),
                    w("Tochter", "娘", [("Toch", "ˈtɔx", "トホ"), ("ter", "tɐ", "ター")]),
                    w("aus", "〜から", [("aus", "aʊs", "アウス")]),
                    w("Elysium!", "エリュシオン", [("E", "e", "エ"), ("ly", "ˈlyː", "リュー"), ("si", "zi", "ズィ"), ("um", "ʊm", "ウム")])
                  ], pitches: [], durations: []),
            .init(text: "Wir betreten feuertrunken, Himmlische, dein Heiligtum!",
                  translation: "私たちは炎に酔うように、天上の存在よ、あなたの聖域へ足を踏み入れる。",
                  words: [
                    w("Wir", "私たちは", [("Wir", "viːɐ", "ヴィーア")]),
                    w("betreten", "足を踏み入れる", [("be", "bə", "ベ"), ("tre", "ˈtʁeː", "トレー"), ("ten", "tən", "テン")]),
                    w("feuertrunken,", "炎に酔って", [("feu", "ˈfɔʏ", "フォイ"), ("er", "ɐ", "アー"), ("trun", "ˌtʁʊŋ", "トゥルン"), ("ken", "kən", "ケン")]),
                    w("Himmlische,", "天上の存在よ", [("Himm", "ˈhɪm", "ヒム"), ("li", "lɪ", "リ"), ("sche", "ʃə", "シェ")]),
                    w("dein", "あなたの", [("dein", "daɪn", "ダイン")]),
                    w("Heiligtum!", "聖域", [("Hei", "ˈhaɪ", "ハイ"), ("lig", "lɪç", "リヒ"), ("tum", "tuːm", "トゥーム")])
                  ], pitches: [], durations: []),
            .init(text: "Deine Zauber binden wieder, was die Mode streng geteilt;",
                  translation: "あなたの魔法は、時代の風潮が厳しく分けたものを再び結び合わせる。",
                  words: [
                    w("Deine", "あなたの", [("Dei", "ˈdaɪ", "ダイ"), ("ne", "nə", "ネ")]),
                    w("Zauber", "魔法", [("Zau", "ˈtsaʊ", "ツァウ"), ("ber", "bɐ", "バー")]),
                    w("binden", "結ぶ", [("bin", "ˈbɪn", "ビン"), ("den", "dən", "デン")]),
                    w("wieder,", "再び", [("wie", "ˈviː", "ヴィー"), ("der", "dɐ", "ダー")]),
                    w("was", "〜するもの", [("was", "vas", "ヴァス")]),
                    w("die", "その", [("die", "diː", "ディー")]),
                    w("Mode", "時代の風潮", [("Mo", "ˈmoː", "モー"), ("de", "də", "デ")]),
                    w("streng", "厳しく", [("streng", "ʃtʁɛŋ", "シュトレング")]),
                    w("geteilt;", "分けた", [("ge", "ɡə", "ゲ"), ("teilt", "ˈtaɪlt", "タイルト")])
                  ], pitches: [], durations: []),
            .init(text: "alle Menschen werden Brüder, wo dein sanfter Flügel weilt.",
                  translation: "すべての人は兄弟となる、あなたの優しい翼がとどまるところで。",
                  words: [
                    w("alle", "すべての", [("al", "ˈal", "ア"), ("le", "lə", "レ")]),
                    w("Menschen", "人々", [("Men", "ˈmɛn", "メン"), ("schen", "ʃən", "シェン")]),
                    w("werden", "〜となる", [("wer", "ˈveːɐ", "ヴェーア"), ("den", "dən", "デン")]),
                    w("Brüder,", "兄弟", [("Brü", "ˈbʁyː", "ブリュー"), ("der", "dɐ", "ダー")]),
                    w("wo", "〜する所で", [("wo", "voː", "ヴォー")]),
                    w("dein", "あなたの", [("dein", "daɪn", "ダイン")]),
                    w("sanfter", "優しい", [("sanf", "ˈzanf", "ザンフ"), ("ter", "tɐ", "ター")]),
                    w("Flügel", "翼", [("Flü", "ˈflyː", "フリュー"), ("gel", "ɡəl", "ゲル")]),
                    w("weilt.", "とどまる", [("weilt", "vaɪlt", "ヴァイルト")])
                  ], pitches: [], durations: [])
        ])
    }

    private static func makeMary() -> SongDocument {
        let first: [WordSpec] = [
            .init("Mary", "メリー", [.init("Ma", "mɛ", "メ"), .init("ry", "ri", "リー")]),
            .init("had", "飼っていた", [.init("had", "hæd", "ハド")]),
            .init("a", "一匹の", [.init("a", "ə", "ア")]),
            .init("little", "小さな", [.init("lit", "lɪt", "リト"), .init("tle", "əl", "ル")]),
            .init("lamb,", "子羊", [.init("lamb", "læm", "ラム")])
        ]
        let second: [WordSpec] = [
            .init("little", "小さな", [.init("lit", "lɪt", "リト"), .init("tle", "əl", "ル")]),
            .init("lamb,", "子羊", [.init("lamb", "læm", "ラム")]),
            .init("little", "小さな", [.init("lit", "lɪt", "リト"), .init("tle", "əl", "ル")]),
            .init("lamb,", "子羊", [.init("lamb", "læm", "ラム")])
        ]
        let last: [WordSpec] = [
            .init("Its", "その", [.init("Its", "ɪts", "イツ")]),
            .init("fleece", "羊毛", [.init("fleece", "fliːs", "フリース")]),
            .init("was", "だった", [.init("was", "wəz", "ワズ")]),
            .init("white", "白い", [.init("white", "waɪt", "ワイト")]),
            .init("as", "〜のように", [.init("as", "æz", "アズ")]),
            .init("snow.", "雪", [.init("snow", "snoʊ", "スノウ")])
        ]
        return makeSong(title: "Mary Had a Little Lamb", language: "en",
                        notes: "Sarah Josepha Hale『Mary's Lamb』(1830)。伝承的な旋律を教材用に単旋律で入力。現代の録音・MIDI素材は使用していません。",
                        bpm: 104, serialStart: 20_000,
                        lines: [
                            .init(text: "Mary had a little lamb,", translation: "メリーには小さな子羊がいました。",
                                  words: first, pitches: [64, 62, 60, 62, 64, 64, 64], durations: [1, 1, 1, 1, 1, 1, 2]),
                            .init(text: "Little lamb, little lamb,", translation: "小さな子羊、小さな子羊。",
                                  words: second, pitches: [62, 62, 62, 64, 67, 67], durations: [1, 1, 2, 1, 1, 2]),
                            .init(text: "Mary had a little lamb,", translation: "メリーには小さな子羊がいました。",
                                  words: first, pitches: [64, 62, 60, 62, 64, 64, 64], durations: [1, 1, 1, 1, 1, 1, 1]),
                            .init(text: "Its fleece was white as snow.", translation: "その毛は雪のように白かったのです。",
                                  words: last, pitches: [64, 62, 62, 64, 62, 60], durations: [1, 1, 1, 1, 1, 4])
                        ])
    }

    private static func makeFrereJacques() -> SongDocument {
        let name: [WordSpec] = [
            .init("Frère", "修道士の兄弟", [.init("Frè", "fʁɛ", "フレ"), .init("re", "ʁə", "ル")]),
            .init("Jacques,", "ジャック", [.init("Jac", "ʒa", "ジャ"), .init("ques", "kə", "ク")])
        ]
        let question: [WordSpec] = [
            .init("Dormez-vous ?", "眠っていますか", [.init("Dor", "dɔʁ", "ドル"),
                                                  .init("mez", "me", "メ"), .init("vous", "vu", "ヴー")])
        ]
        let bells: [WordSpec] = [
            .init("Sonnez", "鳴らして", [.init("Son", "sɔ", "ソン"), .init("nez", "ne", "ネ")]),
            .init("les", "その", [.init("les", "le", "レ")]),
            .init("matines,", "朝の鐘", [.init("ma", "ma", "マ"), .init("ti", "ti", "ティ"), .init("nes", "nə", "ヌ")])
        ]
        let chime: [WordSpec] = [
            .init("Ding", "鐘の音", [.init("Ding", "dɛ̃", "ディン")]),
            .init("dang", "鐘の音", [.init("dang", "dɑ̃", "ダン")]),
            .init("dong !", "鐘の音", [.init("dong", "dɔ̃", "ドン")])
        ]
        return makeSong(title: "Frère Jacques", language: "fr",
                        notes: "フランスの伝承歌。教育用にハ長調の単旋律を入力。現代の録音・MIDI素材は使用していません。",
                        bpm: 96, serialStart: 30_000,
                        lines: [
                            .init(text: "Frère Jacques, Frère Jacques,", translation: "ジャック兄弟、ジャック兄弟。",
                                  words: name + name, pitches: [60, 62, 64, 60, 60, 62, 64, 60], durations: Array(repeating: 1, count: 8)),
                            .init(text: "Dormez-vous ? Dormez-vous ?", translation: "眠っていますか、眠っていますか。",
                                  words: question + question, pitches: [64, 65, 67, 64, 65, 67], durations: [1, 1, 2, 1, 1, 2]),
                            .init(text: "Sonnez les matines, sonnez les matines,", translation: "朝の鐘を鳴らして、朝の鐘を鳴らして。",
                                  words: bells + bells, pitches: [67, 69, 67, 65, 64, 60, 67, 69, 67, 65, 64, 60],
                                  durations: [0.5, 0.5, 0.5, 0.5, 1, 1, 0.5, 0.5, 0.5, 0.5, 1, 1]),
                            .init(text: "Ding, dang, dong ! Ding, dang, dong !", translation: "ディン、ダン、ドン。ディン、ダン、ドン。",
                                  words: chime + chime, pitches: [60, 67, 60, 60, 67, 60], durations: [1, 1, 2, 1, 1, 2])
                        ])
    }
}
