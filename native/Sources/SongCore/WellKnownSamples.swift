import Foundation

/// Familiar songs added alongside the existing multilingual samples. The source-language text is
/// a short excerpt; no Japanese translation lyrics or modern arrangement is embedded.
enum WellKnownSamples {
    private struct Item: Sendable {
        let id: String
        let title: String
        let language: String
        let region: String
        let lyric: String
        let translation: String
        let serial: Int
    }

    private static let items: [Item] = [
        .init(id: "mountain", title: "Ich bin ein Musikante（山の音楽家）", language: "de",
              region: "ドイツ民謡", lyric: "Ich bin ein Musikante und komm aus Schwabenland.",
              translation: "私は音楽家、シュヴァーベンから来ました。", serial: 200_000),
        .init(id: "cuckoo", title: "Kuckuck, Kuckuck（かっこう）", language: "de",
              region: "ドイツの童謡", lyric: "Kuckuck, Kuckuck, ruft's aus dem Wald.",
              translation: "かっこうが森から呼んでいます。", serial: 210_000),
        .init(id: "clarinet", title: "J'ai perdu le do de ma clarinette（クラリネットをこわしちゃった）", language: "fr",
              region: "フランスの童謡", lyric: "J'ai perdu le do de ma clarinette.",
              translation: "クラリネットのドの音を失くしてしまいました。", serial: 220_000),
        .init(id: "marseillaise", title: "La Marseillaise（フランス国歌）", language: "fr",
              region: "フランス国歌", lyric: "Allons enfants de la Patrie, le jour de gloire est arrivé !",
              translation: "祖国の子らよ、栄光の日が来ました。", serial: 230_000),
        .init(id: "gloria", title: "Les anges dans nos campagnes（あら野の果てに）", language: "fr",
              region: "フランスのクリスマス曲", lyric: "Les anges dans nos campagnes ont entonné l'hymne des cieux.",
              translation: "野辺の天使たちが天の讃歌を歌い始めました。", serial: 240_000),
        .init(id: "kalinka", title: "Калинка（カリンカ）", language: "ru",
              region: "ロシアの歌", lyric: "Калинка, калинка, калинка моя!",
              translation: "カリンカよ、私のカリンカよ。", serial: 250_000),
        .init(id: "korobeiniki", title: "Коробейники（コロブチカ）", language: "ru",
              region: "ロシア民謡", lyric: "Ой, полна, полна коробушка, есть и ситцы и парча.",
              translation: "行商人の箱には、布や錦がいっぱいです。", serial: 260_000),
        .init(id: "week", title: "Неделька（一週間）", language: "ru",
              region: "ロシア民謡", lyric: "В понедельник я в банюшку ходила.",
              translation: "月曜日には蒸し風呂へ行きました。", serial: 270_000),
        .init(id: "danny", title: "Danny Boy（ダニーボーイ）", language: "en",
              region: "アイルランドの旋律", lyric: "Oh, Danny boy, the pipes, the pipes are calling.",
              translation: "ダニーよ、笛の音があなたを呼んでいます。", serial: 280_000),
        .init(id: "auld", title: "Auld Lang Syne（蛍の光の原曲）", language: "en",
              region: "スコットランド民謡", lyric: "Should auld acquaintance be forgot and never brought to mind?",
              translation: "古い友を忘れ、思い出さずにいてよいでしょうか。", serial: 290_000)
    ]

    static let entries: [SampleEntry] = items.map { item in
        SampleEntry(id: item.id, title: item.title, languageCode: item.language,
                    subtitle: "\(item.region) · 原語の冒頭 · 旋律付き",
                    details: "原語歌詞の冒頭と資料に基づく旋律。音節と音符の対応は未校訂です。",
                    factory: { make(item) })
    }

    private static func make(_ item: Item) -> SongDocument {
        let words = Syllabifier.tokenize(item.lyric, language: item.language).map { token in
            let candidate = Syllabifier.syllabify(token, language: item.language)
            let sounds = candidate.syllables.enumerated().map { index, syllable in
                SampleCatalog.SyllableSpec(syllable, "", candidate.readings?[safe: index] ?? "")
            }
            return SampleCatalog.WordSpec(token.surface, "", sounds)
        }
        let line = SampleCatalog.LineSpec(text: item.lyric, translation: item.translation,
                                          words: words, pitches: [], durations: [])
        var base = SampleCatalog.makeSong(title: item.title, language: item.language,
                                          notes: "原語詞の冒頭のみ。音節は規則による候補です。",
                                          bpm: 96, serialStart: item.serial, withMusic: false, lines: [line])
        base.metadata.notes = base.metadata.notes.replacingOccurrences(
            of: "読みとIPAは練習用の近似です。", with: "発音記号とカタカナは未入力です。")
        return SourceMelodies.attaching(item.id, to: base)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
