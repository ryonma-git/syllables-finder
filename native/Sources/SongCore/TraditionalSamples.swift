import Foundation

/// Short, annotated reading samples from historical or traditional songs.
/// These do not invent a melody or imply that a modern arrangement was transcribed.
enum TraditionalSamples {
    private typealias Word = SampleCatalog.WordSpec
    private typealias Line = SampleCatalog.LineSpec

    static let entries: [SampleEntry] = [
        .init(id: "entchen", title: "Alle meine Entchen", languageCode: "de",
              subtitle: "ドイツの童謡 · 第1節 · 歌詞のみ",
              details: "小さなアヒルの童謡。ドイツ語の読みを練習できます。音符は未入力です。", factory: entchen),
        .init(id: "pollitos", title: "Los pollitos dicen", languageCode: "es",
              subtitle: "チリの童謡 · 冒頭 · 歌詞のみ",
              details: "ひよこが鳴く童謡。スペイン語の母音と音節を練習できます。音符は未入力です。", factory: pollitos),
        .init(id: "martino", title: "Fra Martino", languageCode: "it",
              subtitle: "イタリア語版の伝承歌 · 冒頭 · 歌詞のみ",
              details: "Frère Jacques のイタリア語版。発音の違いを比べられます。音符は未入力です。", factory: martino),
        .init(id: "adeste", title: "Adeste Fideles", languageCode: "la",
              subtitle: "ラテン語の聖歌 · 冒頭 · 歌詞のみ",
              details: "教会式ラテン語の読みを練習できます。音符は未入力です。", factory: adeste),
        .init(id: "birch", title: "Во поле берёза стояла", languageCode: "ru",
              subtitle: "ロシア民謡 · 冒頭 · 歌詞のみ",
              details: "白樺を歌うロシア民謡。強勢と音節を確認できます。音符は未入力です。", factory: birch),
        .init(id: "sakura", title: "さくら さくら", languageCode: "ja",
              subtitle: "日本古謡 · 冒頭 · 歌詞のみ",
              details: "日本語の拍とかなを確認できます。音符は未入力です。", factory: sakura),
        .init(id: "arirang", title: "아리랑（アリラン）", languageCode: "ko",
              subtitle: "韓国の伝承歌 · 京畿道系のリフレイン · 歌詞のみ",
              details: "アリランの代表的な歌い出し。地域で歌詞と旋律が異なります。音符は未入力です。", factory: arirang),
        .init(id: "jasmine", title: "茉莉花（モーリーホア）", languageCode: "zh",
              subtitle: "中国・江蘇省の民謡 · 伝承詞の冒頭 · 歌詞のみ",
              details: "ジャスミンの花を歌う伝承詞。普通話の読みは学習用の近似です。音符は未入力です。", factory: jasmine)
    ]

    private static func word(_ surface: String, _ meaning: String,
                             _ sounds: [(String, String, String)]) -> Word {
        .init(surface, meaning, sounds.map { .init($0.0, $0.1, $0.2) })
    }

    private static func line(_ text: String, _ translation: String, _ words: [Word]) -> Line {
        .init(text: text, translation: translation, words: words, pitches: [], durations: [])
    }

    private static func song(_ title: String, _ language: String, _ serial: Int,
                             _ source: String, _ lines: [Line]) -> SongDocument {
        SampleCatalog.makeSong(title: title, language: language,
                               notes: "伝承・歴史資料を基にした短い読解サンプル。原詞の版は資料によって異なります。出典: \(source)。音符は未入力。",
                               bpm: 96, serialStart: serial, withMusic: false, lines: lines)
    }

    private static func entchen() -> SongDocument {
        song("Alle meine Entchen", "de", 50_000,
             "https://s9.imslp.org/files/imglnks/usimg/0/03/IMSLP618750-PMLP993990-Sothilander-Kinderlieder_zu_zwei_Stimmen-Aufl1.pdf", [
            line("Alle meine Entchen schwimmen auf dem See,", "私の子アヒルたちはみな湖で泳いでいます。", [
                word("Alle", "すべての", [("Al", "ˈa", "ア"), ("le", "lə", "レ")]),
                word("meine", "私の", [("mei", "ˈmaɪ", "マイ"), ("ne", "nə", "ネ")]),
                word("Entchen", "子アヒル", [("Ent", "ˈɛnt", "エント"), ("chen", "çən", "ヒェン")]),
                word("schwimmen", "泳ぐ", [("schwim", "ˈʃvɪm", "シュヴィム"), ("men", "mən", "メン")]),
                word("auf", "〜の上で", [("auf", "aʊf", "アウフ")]),
                word("dem", "その", [("dem", "deːm", "デーム")]),
                word("See,", "湖", [("See", "zeː", "ゼー")])
            ]),
            line("Köpfchen in das Wasser, Schwänzchen in die Höh'.", "頭を水に入れ、しっぽを高く上げます。", [
                word("Köpfchen", "小さな頭", [("Köpf", "ˈkœpf", "ケプフ"), ("chen", "çən", "ヒェン")]),
                word("in", "〜の中へ", [("in", "ɪn", "イン")]),
                word("das", "その", [("das", "das", "ダス")]),
                word("Wasser,", "水", [("Was", "ˈvas", "ヴァス"), ("ser", "ɐ", "サー")]),
                word("Schwänzchen", "小さなしっぽ", [("Schwänz", "ˈʃvɛnts", "シュヴェンツ"), ("chen", "çən", "ヒェン")]),
                word("in", "〜へ", [("in", "ɪn", "イン")]),
                word("die", "その", [("die", "diː", "ディー")]),
                word("Höh'.", "高い所", [("Höh", "høː", "ヘー")])
            ])
        ])
    }

    private static func pollitos() -> SongDocument {
        song("Los pollitos dicen", "es", 60_000,
             "https://www.chileparaninos.gob.cl/639/w3-article-662011.html", [
            line("Los pollitos dicen pío, pío, pío,", "ひよこたちはピヨピヨと鳴きます。", [
                word("Los", "その", [("Los", "los", "ロス")]),
                word("pollitos", "ひよこたち", [("po", "po", "ポ"), ("lli", "ˈʝi", "イ"), ("tos", "tos", "トス")]),
                word("dicen", "言う・鳴く", [("di", "ˈdi", "ディ"), ("cen", "sen", "セン")]),
                word("pío,", "ピヨ", [("pí", "ˈpi", "ピー"), ("o", "o", "オ")]),
                word("pío,", "ピヨ", [("pí", "ˈpi", "ピー"), ("o", "o", "オ")]),
                word("pío,", "ピヨ", [("pí", "ˈpi", "ピー"), ("o", "o", "オ")])
            ]),
            line("cuando tienen hambre, cuando tienen frío.", "おなかがすいたとき、寒いときに。", [
                word("cuando", "〜するとき", [("cuan", "ˈkwan", "クアン"), ("do", "do", "ド")]),
                word("tienen", "持っている", [("tie", "ˈtje", "ティエ"), ("nen", "nen", "ネン")]),
                word("hambre,", "空腹", [("ham", "ˈam", "アン"), ("bre", "bɾe", "ブレ")]),
                word("cuando", "〜するとき", [("cuan", "ˈkwan", "クアン"), ("do", "do", "ド")]),
                word("tienen", "持っている", [("tie", "ˈtje", "ティエ"), ("nen", "nen", "ネン")]),
                word("frío.", "寒さ", [("frí", "ˈfɾi", "フリー"), ("o", "o", "オ")])
            ])
        ])
    }

    private static func martino() -> SongDocument {
        song("Fra Martino", "it", 70_000,
             "https://www.acrchorus.it/Coro/pdf/Fra%20Martino%20Campanaro.pdf", [
            line("Fra Martino, campanaro, dormi tu?", "鐘つきのマルティーノさん、眠っているの？", [
                word("Fra", "修道士", [("Fra", "fra", "フラ")]),
                word("Martino,", "マルティーノ", [("Mar", "mar", "マル"), ("ti", "ˈti", "ティ"), ("no", "no", "ノ")]),
                word("campanaro,", "鐘つき", [("cam", "kam", "カン"), ("pa", "pa", "パ"), ("na", "ˈna", "ナ"), ("ro", "ro", "ロ")]),
                word("dormi", "眠る", [("dor", "ˈdor", "ドル"), ("mi", "mi", "ミ")]),
                word("tu?", "あなたは", [("tu", "tu", "トゥ")])
            ]),
            line("Suona le campane, din don dan!", "鐘を鳴らして、ディン、ドン、ダン！", [
                word("Suona", "鳴らして", [("Suo", "ˈswɔ", "スオ"), ("na", "na", "ナ")]),
                word("le", "その", [("le", "le", "レ")]),
                word("campane,", "鐘", [("cam", "kam", "カン"), ("pa", "ˈpa", "パ"), ("ne", "ne", "ネ")]),
                word("din", "鐘の音", [("din", "din", "ディン")]),
                word("don", "鐘の音", [("don", "don", "ドン")]),
                word("dan!", "鐘の音", [("dan", "dan", "ダン")])
            ])
        ])
    }

    private static func adeste() -> SongDocument {
        song("Adeste Fideles", "la", 80_000,
             "https://imslp.org/wiki/Adeste_Fideles_(Wade,_John_Francis)", [
            line("Adeste fideles, laeti triumphantes,", "来てください、信徒たちよ、喜びに満ち勝利を喜ぶ人々よ。", [
                word("Adeste", "来なさい", [("A", "a", "ア"), ("des", "ˈdɛs", "デス"), ("te", "te", "テ")]),
                word("fideles,", "信徒たち", [("fi", "fi", "フィ"), ("de", "ˈde", "デー"), ("les", "les", "レス")]),
                word("laeti", "喜んでいる", [("lae", "ˈlɛ", "レ"), ("ti", "ti", "ティ")]),
                word("triumphantes,", "勝利を喜ぶ", [("tri", "tri", "トリ"), ("um", "um", "ウン"), ("phan", "ˈfan", "ファン"), ("tes", "tes", "テス")])
            ]),
            line("venite, venite in Bethlehem.", "来てください、ベツレヘムへ。", [
                word("venite,", "来なさい", [("ve", "ve", "ヴェ"), ("ni", "ˈni", "ニー"), ("te", "te", "テ")]),
                word("venite", "来なさい", [("ve", "ve", "ヴェ"), ("ni", "ˈni", "ニー"), ("te", "te", "テ")]),
                word("in", "〜へ", [("in", "in", "イン")]),
                word("Bethlehem.", "ベツレヘム", [("Beth", "bet", "ベト"), ("le", "le", "レ"), ("hem", "ɛm", "エム")])
            ])
        ])
    }

    private static func birch() -> SongDocument {
        song("Во поле берёза стояла", "ru", 90_000,
             "https://imslp.org/wiki/6_Russian_Songs_with_Variations,_Op.1_(Khandoshkin,_Ivan)", [
            line("Во поле берёза стояла,", "野原に白樺が立っていました。", [
                word("Во", "〜に", [("Во", "vo", "ヴォ")]),
                word("поле", "野原", [("по", "ˈpo", "ポ"), ("ле", "lʲɪ", "リェ")]),
                word("берёза", "白樺", [("бе", "bʲɪ", "ビェ"), ("рё", "ˈrʲo", "リョ"), ("за", "zə", "ザ")]),
                word("стояла,", "立っていた", [("сто", "stɐ", "スタ"), ("я", "ˈja", "ヤ"), ("ла", "lə", "ラ")])
            ]),
            line("во поле кудрявая стояла.", "野原に、葉の茂った白樺が立っていました。", [
                word("во", "〜に", [("во", "vo", "ヴォ")]),
                word("поле", "野原", [("по", "ˈpo", "ポ"), ("ле", "lʲɪ", "リェ")]),
                word("кудрявая", "葉の茂った", [("ку", "kʊ", "ク"), ("дря", "ˈdrʲa", "ドリャ"), ("ва", "və", "ヴァ"), ("я", "jə", "ヤ")]),
                word("стояла.", "立っていた", [("сто", "stɐ", "スタ"), ("я", "ˈja", "ヤ"), ("ла", "lə", "ラ")])
            ])
        ])
    }

    private static func sakura() -> SongDocument {
        song("さくら さくら", "ja", 100_000,
             "https://imslp.org/wiki/Sakura_Sakura_(Traditional_Japanese)", [
            line("さくら さくら", "桜の花が咲いています。", [
                word("さくら", "桜の花", [("さ", "sa", "サ"), ("く", "kɯ", "ク"), ("ら", "ɾa", "ラ")]),
                word("さくら", "桜の花", [("さ", "sa", "サ"), ("く", "kɯ", "ク"), ("ら", "ɾa", "ラ")])
            ]),
            line("やよいの空は 見わたす限り", "春の空の下、見渡すかぎり。", [
                word("やよい", "春の季節", [("や", "ja", "ヤ"), ("よ", "jo", "ヨ"), ("い", "i", "イ")]),
                word("の", "〜の", [("の", "no", "ノ")]),
                word("空は", "空は", [("そ", "so", "ソ"), ("ら", "ɾa", "ラ"), ("は", "wa", "ワ")]),
                word("見わたす", "見渡す", [("み", "mi", "ミ"), ("わ", "wa", "ワ"), ("た", "ta", "タ"), ("す", "sɯ", "ス")]),
                word("限り", "かぎり", [("か", "ka", "カ"), ("ぎ", "ɡi", "ギ"), ("り", "ɾi", "リ")])
            ])
        ])
    }

    private static func arirang() -> SongDocument {
        song("아리랑（アリラン）", "ko", 110_000,
             "https://ich.unesco.org/en/RL/arirang-lyrical-folk-song-in-the-republic-of-korea-00445", [
            line("아리랑 아리랑 아라리요", "アリラン、アリラン、アラリヨ。", [
                word("아리랑", "アリラン", [("아", "a", "ア"), ("리", "ɾi", "リ"), ("랑", "ɾaŋ", "ラン")]),
                word("아리랑", "アリラン", [("아", "a", "ア"), ("리", "ɾi", "リ"), ("랑", "ɾaŋ", "ラン")]),
                word("아라리요", "歌のはやし言葉", [("아", "a", "ア"), ("라", "ɾa", "ラ"), ("리", "ɾi", "リ"), ("요", "jo", "ヨ")])
            ]),
            line("아리랑 고개로 넘어간다", "アリラン峠を越えてゆきます。", [
                word("아리랑", "アリラン", [("아", "a", "ア"), ("리", "ɾi", "リ"), ("랑", "ɾaŋ", "ラン")]),
                word("고개로", "峠へ", [("고", "ko", "コ"), ("개", "ɡɛ", "ゲ"), ("로", "ɾo", "ロ")]),
                word("넘어간다", "越えてゆく", [("넘", "nʌm", "ノム"), ("어", "ʌ", "オ"), ("간", "ɡan", "ガン"), ("다", "da", "ダ")])
            ])
        ])
    }

    private static func jasmine() -> SongDocument {
        song("茉莉花（モーリーホア）", "zh", 120_000,
             "https://www.nlb.gov.sg/main/api/MusicDetailPage/ViewPdf?resourceUuid=f552ac57-9827-4a59-bee0-a74cea7a329a", [
            line("好一朵茉莉花，好一朵茉莉花。", "なんと美しいジャスミンの花でしょう。", [
                word("好", "なんと", [("好", "xɑʊ˨˩˦", "ハオ")]),
                word("一朵", "一輪の", [("一", "i˥", "イー"), ("朵", "twɔ˨˩˦", "ドゥオ")]),
                word("茉莉花，", "ジャスミンの花", [("茉", "mwɔ˥˩", "モー"), ("莉", "li˥˩", "リー"), ("花", "xwa˥", "ホア")]),
                word("好", "なんと", [("好", "xɑʊ˨˩˦", "ハオ")]),
                word("一朵", "一輪の", [("一", "i˥", "イー"), ("朵", "twɔ˨˩˦", "ドゥオ")]),
                word("茉莉花。", "ジャスミンの花", [("茉", "mwɔ˥˩", "モー"), ("莉", "li˥˩", "リー"), ("花", "xwa˥", "ホア")])
            ]),
            line("满园花草香也香不过它。", "庭いっぱいの花も、その香りにはかなわない。", [
                word("满园", "庭いっぱいの", [("满", "man˨˩˦", "マン"), ("园", "ɥɛn˧˥", "ユエン")]),
                word("花草", "花や草", [("花", "xwa˥", "ホア"), ("草", "tsʰɑʊ˨˩˦", "ツァオ")]),
                word("香", "香る", [("香", "ɕjɑŋ˥", "シアン")]),
                word("也", "〜でも", [("也", "jɛ˨˩˦", "イエ")]),
                word("香不过", "香りで及ばない", [("香", "ɕjɑŋ˥", "シアン"), ("不", "pu˧˥", "ブー"), ("过", "kwɔ˥˩", "グオ")]),
                word("它。", "それ（茉莉花）", [("它", "tʰa˥", "ター")])
            ])
        ])
    }
}
