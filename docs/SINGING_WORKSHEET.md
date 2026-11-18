# 歌唱練習シート

歌唱練習シート（Singing Worksheet）は公開研究会向けの教材作成アプリです。参加者が歌詞を入力し、音節・発音・日本語訳を編集して、A4の教材を作れます。英語（米国）の発音辞書を同梱しています。

## 教材を作る

1. 曲名と歌詞を入力します。歌うまとまりごとに改行して「教材を作成」を選びます。
2. 単語を選び、音節・カタカナ読み・発音記号・意味を直します。Macは「適用」、Web・iPadは「反映」で確定します。日本語訳は行ごとに入力できます。
3. Macは「書き出す」、Web・iPadは「印刷・PDF」からA4に出力します。iPad版の「PDFを共有」ではファイルへの保存もできます。Mac版はWord書き出しにも対応しています。
4. 編集を続けるときは教材データ（JSON）を保存します。Macは「ファイル」→「開く」、Web・iPadは「教材を開く」で3版間の受け渡しができます。

「OpenAIで補完…」から利用者自身のOpenAI APIキーを入力し、送信を確定すると、歌詞を行ごとに解析して音節・読み・日本語の意味を補います。Macは希望したときだけキーをキーチェーンに保存します。Web・iPadは処理中だけキーを保持します。講師用のキーは配布物に含めません。会場LANのHTTPで開いた場合は、辞書と手動編集を利用できます。

## 配布物を作る

| 対象 | 作成方法 | 配布形式 |
| --- | --- | --- |
| Mac（macOS 14以降） | `native/scripts/build-worksheet-app.sh /absolute/path/Singing-Worksheet-Mac.zip` | Apple Silicon・Intel共通のアプリZIP。Developer IDでの署名には `WORKSHEET_SIGN_IDENTITY` を指定。通常の公開配布には別途公証が必要 |
| iPad（iPadOS 16以降） | `ipad/SingingWorksheet.xcodeproj` のSingingWorksheetスキームをビルド | 端末向け配布には主催者のAppleチームで署名して配布。詳細は [iPad版](../ipad/README.md) |
| Web | `web/build-dictionary.sh` を実行 | `web/dist/` を静的サーバーへ配置。PCに渡す場合は同フォルダの中身をまとめてZIP化し、展開後に `index.html` を開く |

### 会場のWi-Fiで使う

Web版ZIPには講師用の `serve-classroom.command` が付いています。Python 3が使えるMacで、展開したフォルダの中から起動します。参加者は同じWi-Fiに接続し、講師の画面に出たURLをブラウザで開きます。端末間通信が使えるネットワークが必要です。講師のMacは教材画面と辞書のファイルを配信し、参加者の入力と編集用データは各端末に残ります。終了するときは講師のMacで Control + C を押します。

### 検証

`web/build-dictionary.sh` のあと、`node --test web/tools/*.test.cjs` で辞書とOpenAI応答の検証を実行できます。Web版は米国英語の新規作成を対象としています。Mac版では言語と発音を選択できます。歌手の節回しに合わせた調整は単語編集で行えます。
