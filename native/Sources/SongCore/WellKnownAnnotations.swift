import Foundation

/// Short, reviewed pronunciation guides for the built-in well-known song excerpts.
/// Most initial candidates came from local Ollama; the source syllable count and text are checked at runtime.
enum WellKnownAnnotations {
    private typealias Sound = (text: String, ipa: String, reading: String)
    private static let values: [String: [Sound]] = [
        "mountain": [
            ("Ich", "ɪç", "イヒ"),
            ("bin", "bɪn", "ビン"),
            ("ein", "aɪ̯n", "アイン"),
            ("Mu", "mu", "ム"),
            ("si", "ziː", "ジー"),
            ("kan", "ˈkan", "カン"),
            ("te", "tə", "テ"),
            ("und", "ʊnt", "ウント"),
            ("komm", "kɔm", "コム"),
            ("aus", "aʊ̯s", "アウス"),
            ("Schwa", "ʃvaː", "シュヴァー"),
            ("ben", "bən", "ベン"),
            ("land", "lant", "ランド"),
        ],
        "cuckoo": [
            ("Ku", "ˈkʊ", "ク"),
            ("ckuck", "kʊk", "クック"),
            ("Ku", "ˈkʊ", "ク"),
            ("ckuck", "kʊk", "クック"),
            ("ruft's", "ʁuːfts", "ルーフツ"),
            ("aus", "aʊs", "アウス"),
            ("dem", "deːm", "デーム"),
            ("Wald", "valt", "ヴァルト"),
        ],
        "clarinet": [
            ("J'ai", "ʒe", "ジェ"),
            ("per", "pɛʁ", "ペル"),
            ("du", "dy", "デュ"),
            ("le", "lə", "ル"),
            ("do", "do", "ド"),
            ("de", "də", "ドゥ"),
            ("ma", "ma", "マ"),
            ("cla", "kla", "クラ"),
            ("ri", "ʁi", "リ"),
            ("nette", "nɛt", "ネット"),
        ],
        "marseillaise": [
            ("Al", "a", "ア"),
            ("lons", "lɔ̃", "ロン"),
            ("en", "ɑ̃", "アン"),
            ("fants", "fɑ̃", "ファン"),
            ("de", "də", "ドゥ"),
            ("la", "la", "ラ"),
            ("Pa", "pa", "パ"),
            ("trie", "tʁi", "トリ"),
            ("le", "lə", "ル"),
            ("jour", "ʒuʁ", "ジュール"),
            ("de", "də", "ドゥ"),
            ("gloire", "ɡlwaʁ", "グロワール"),
            ("est", "ɛ", "エ"),
            ("ar", "ta", "タ"),
            ("ri", "ʁi", "リ"),
            ("vé", "ve", "ヴェ"),
        ],
        "gloria": [
            ("Les", "le", "レ"),
            ("anges", "zɑ̃ʒ", "ザンジュ"),
            ("dans", "dɑ̃", "ダン"),
            ("nos", "no", "ノ"),
            ("cam", "kɑ̃", "カン"),
            ("pagnes", "paɲ", "パーニュ"),
            ("ont", "ɔ̃", "オン"),
            ("en", "tɑ̃", "タン"),
            ("ton", "tɔ", "ト"),
            ("né", "ne", "ネ"),
            ("l'hymne", "limn", "リムヌ"),
            ("des", "de", "デ"),
            ("cieux", "sjø", "シュー"),
        ],
        "kalinka": [
            ("Ка", "kɐ", "カ"),
            ("лин", "ˈlʲin", "リン"),
            ("ка", "kə", "カ"),
            ("ка", "kɐ", "カ"),
            ("лин", "ˈlʲin", "リン"),
            ("ка", "kə", "カ"),
            ("ка", "kɐ", "カ"),
            ("лин", "ˈlʲin", "リン"),
            ("ка", "kə", "カ"),
            ("мо", "mɐ", "マ"),
            ("я", "ˈja", "ヤ"),
        ],
        "korobeiniki": [
            ("Ой", "oj", "オイ"),
            ("пол", "pɐl", "パル"),
            ("на", "ˈna", "ナ"),
            ("пол", "pɐl", "パル"),
            ("на", "ˈna", "ナ"),
            ("ко", "kɐ", "カ"),
            ("ро", "ˈro", "ロー"),
            ("бу", "bʊ", "ブ"),
            ("шка", "ʂkə", "シュカ"),
            ("есть", "jestʲ", "イェスチ"),
            ("и", "i", "イ"),
            ("си", "ˈsʲi", "シ"),
            ("тцы", "t͡sɨ", "ツィ"),
            ("и", "i", "イ"),
            ("пар", "pɐr", "パル"),
            ("ча", "ˈt͡ɕa", "チャ"),
        ],
        "week": [
            ("В", "f", "フ"),
            ("по", "pə", "パ"),
            ("не", "nʲɪ", "ニェ"),
            ("дель", "ˈdʲelʲ", "デリ"),
            ("ник", "nʲɪk", "ニク"),
            ("я", "ja", "ヤ"),
            ("в", "v", "ヴ"),
            ("ба", "ˈba", "バ"),
            ("ню", "nʲʊ", "ニュ"),
            ("шку", "ʂkʊ", "シュク"),
            ("хо", "xɐ", "ハ"),
            ("ди", "ˈdʲi", "ディ"),
            ("ла", "lə", "ラ"),
        ],
        "danny": [
            ("Oh", "oʊ", "オー"),
            ("Dan", "ˈdæ", "ダ"),
            ("ny", "ni", "ニー"),
            ("boy", "bɔɪ", "ボーイ"),
            ("the", "ðə", "ザ"),
            ("pipes", "paɪps", "パイプス"),
            ("the", "ðə", "ザ"),
            ("pipes", "paɪps", "パイプス"),
            ("are", "ɑːr", "アー"),
            ("cal", "ˈkɔː", "コー"),
            ("ling", "lɪŋ", "リング"),
        ],
        "auld": [
            ("Should", "ʃʊd", "シュッド"),
            ("auld", "ɔːld", "オールド"),
            ("ac", "ə", "ア"),
            ("quain", "ˈkweɪn", "クウェイン"),
            ("tance", "təns", "タンス"),
            ("be", "bi", "ビー"),
            ("for", "fə", "フォ"),
            ("got", "ˈɡɒt", "ゴット"),
            ("and", "ænd", "アンド"),
            ("ne", "ˈnɛ", "ネ"),
            ("ver", "vər", "ヴァー"),
            ("brought", "brɔːt", "ブロート"),
            ("to", "tu", "トゥー"),
            ("mind", "maɪnd", "マインド"),
        ],
    ]

    private static let meanings: [String: [String]] = [
        "mountain": ["私は", "～です", "一人の", "音楽家", "そして", "来ます", "～から", "シュヴァーベン地方"],
        "cuckoo": ["かっこう", "かっこう", "鳴きます", "～から", "その", "森"],
        "clarinet": ["私は～を", "失くした", "その", "ドの音", "～の", "私の", "クラリネット"],
        "marseillaise": ["進もう", "子らよ", "～の", "その", "祖国", "その", "日", "～の", "栄光", "～である", "訪れた"],
        "gloria": ["その", "天使たち", "～で", "私たちの", "野原", "～した", "歌い始めた", "賛歌", "～の", "天"],
        "kalinka": ["カリンカ", "カリンカ", "カリンカ", "私の"],
        "korobeiniki": ["ああ", "いっぱい", "いっぱい", "小箱", "あります", "～も", "更紗", "～も", "錦織"],
        "week": ["～に", "月曜日", "私は", "～へ", "蒸し風呂", "行った"],
        "danny": ["ああ", "ダニー", "坊や", "その", "バグパイプ", "その", "バグパイプ", "～している", "呼んでいる"],
        "auld": ["～だろうか", "古い", "知り合い", "～される", "忘れられる", "そして", "決して～ない", "思い起こされる", "～に", "心"],
    ]

    static func apply(to song: inout SongDocument, sample: String) {
        guard let sounds = values[sample], sounds.count == song.syllables.count else {
            preconditionFailure("Missing or mismatched pronunciation for \(sample)")
        }
        guard let wordMeanings = meanings[sample], wordMeanings.count == song.words.count else {
            preconditionFailure("Missing or mismatched word meanings for \(sample)")
        }
        let source = sample == "danny"
            ? FieldSource(.sample, provider: "Manual pronunciation review")
            : FieldSource(.sample, provider: "Local Ollama candidate, reviewed", model: "qwen3.5:9b")
        for (index, sound) in sounds.enumerated() {
            precondition(song.syllables[index].text.value == sound.text,
                         "Syllable order changed for \(sample) at \(index)")
            song.syllables[index].ipa.accept(sound.ipa, source: source)
            song.syllables[index].reading.accept(sound.reading, source: source)
        }
        for (index, meaning) in wordMeanings.enumerated() {
            song.words[index].contextualMeaning.accept(meaning, source: .init(.sample))
        }
    }
}
