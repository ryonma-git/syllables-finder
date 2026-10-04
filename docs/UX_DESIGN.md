# UX design

## 次の歌唱練習UI（設計済み・未実装）

ユーザーの2026-09-27の補足により、歌唱練習は「詳細：約2小節を大きく」と「一覧：複数小節を段組」で表示する。
一覧を初期表示とし、ピアノロール/楽譜は独立して選べる。鍵盤とC4等の音名、カタカナ読みも表示する。
小節・拍に比例した幅を使い、将来の単語幅表示は別の投影にする。
再生は「曲を通して/選択範囲を1回/選択範囲をループ」。表示・編集選択・再生範囲を分離し、詳細のページ送りで音を止めない。
操作表と境界条件は [SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md) を正とする。
以下は初回UIの設計記録。Phrase選択が練習範囲を直接変更する旧操作は上記の仕様で置き換える。

## 比較と決定

案A: 全曲タイムライン＋常設Inspector。編集効率は高いが DAW に見える。
案B: Phrase一覧＋読みやすいカード、歌う時だけ時間軸。最初の行動が明確。
案C: 見開きの教材ページ。印刷に近いが音楽編集と拡大に弱い。
**Bを採用**。SwiftUI の同じデータで Reading/Singing を比較できる preview 用 sample を用意する。

## 画面

上部: 曲名（sidebarで編集）、読む/歌う segmented control、詳細表示。
左: 節・Phrase。中央: 選択 Phrase の原文見出しと全文訳。
読む: 意味→原文→IPA→カタカナ→音節の Word Cell。選ぶと右に編集Inspector。
歌う: 拍目盛り、Word/Syllableの時間帯、その下にNote。余白を保ちメリスマを複数バーで示す。
下部: 再生/一時停止・停止・loop・tempo。音符編集は必要時だけ展開。
単旋律のガイド音を鳴らす。歌声合成とは区別し、画面には「ガイド音のみ再生・歌声は出ません」と明示する。

### 2026-10-04 配置の試用と第九の発音

読む画面の「単語の意味」で「上（元の配置）／下（試用）」を即時切替する。
初期値は上。配置はウインドウだけの一時設定で、曲データを変更しない。
下では原文・音節→意味→IPA→カタカナの順にし、行の高さ・行間は維持する。
PDF/Wordには書き出し開始時の選択を渡す。

内蔵の第九には「標準ドイツ語／劇ドイツ語」を表示する。劇では Brüder を
ブリュー・デル（/ˈbryː·dər/）とし、語末の r も子音として発音する練習用の選択肢とする。
選択は曲に保存し、標準への切替で元のサンプル発音へ戻す。
手修正・解析済みの発音と構造変更済み音節は保持する。任意のドイツ語を変換する機能ではない。
語末 r と舌先の r の方針は [Bithell, German Pronunciation and Phonology, p.30](https://api.pageplace.de/preview/DT0400.9780429889226_A35006087/preview-9780429889226_A35006087.pdf#page=52)
を参考とし、カタカナは発音の近似とする。

## 操作

Phrase 選択で練習範囲、Word/Syllable 選択で対応範囲を強調。
単語を選択→意味/IPA/読みを編集→保存→再読込までが最初の vertical slice。
音符クリックで選択、Inspector の数値で pitch/onset/duration/velocity を変更。
後続: 音節 drag→対応更新、音符端 drag→長さ、shiftクリック→複数選択。
ドラッグだけに依存せずキーボード・数値編集を併設する。
Undo/Redo は標準編集メニュー。手修正は「手動」表示。AI候補は明示適用。

## 状態

新規: 空 document と「きらきら星のサンプルを開く」「短い練習サンプルを開く」、歌詞入力の入口。
解析前: 原文は使える。未生成値は未設定。自動でネットワークを呼ばない。
解析中: 操作中表示とcancel。失敗: 原文・修正は保持、再試行可能。
読み込み失敗: 対象の理由を表示し元 package は変更しない。
空の音楽: 原文の読解を続けられる。存在しない音符を自動で捏造しない。

## 見た目・アクセス

macOS 標準 window/toolbar/sidebar。本文は system font、IPAも字形を確認。
青緑は選択・練習範囲、母音核の赤は旧教材専用。色だけに意味を依存させずラベル/枠も使用。
文字サイズ調整、キーボード focus、VoiceOver labels、light/dark、狭いウィンドウを確認する。
timeline は横スクロール、カードは折返し、右 pane は閉じられる。
実画面 QA と tests を区別。VoiceOver のラベル実装だけで読み上げ検証済みとはしない。

## 研究した原則（外観はコピーしない）

以下の一次資料から抽出した本アプリへの設計判断。

| 参考 | 採用する原則 |
|---|---|
| [カトカトーン](https://www.kyogei.co.jp/katokatone) | 見える要素を動かして構造を理解。専門設定を入口に置かない |
| [GarageBand](https://support.apple.com/guide/garageband/welcome/mac) | cycle範囲と時間軸を揃え、詳細編集は別領域 |
| [Logic Pro Inspector](https://support.apple.com/en-ae/guide/logicpro/lgcpe9cc3b1d/mac) | 選択対象に応じた詳細。常に全パラメータを見せない |
| [Ableton MIDI editing](https://www.ableton.com/en/live-manual/11/editing-midi-notes-and-velocities/) | 選択・移動・長さ・複製の一貫した直接操作 |
| [Dorico modes](https://www.steinberg.help/r/dorico-elements/6.2/en/dorico/topics/program_concepts/program_concepts_modes_c.html) | タスクでviewを切替、データは共有 |
| [MuseScore selection](https://handbook.musescore.org/basics/selecting-elements) | 単体/範囲選択を区別し編集の対象を可視化 |
| [Apple macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/) | 標準menu、window、keyboard、情報密度とresize |

## 印刷への接続

Reading を print layout DTO へ投影。A4、意味/原文/IPA/読み/全文訳を独立した行にする。
Word Cell をそのままスクリーンショット印刷しない。長い語・日本語禁則・改ページを検証する。
旧 Word/PDF 出力は継続利用可能。新 document の印刷は後続。
