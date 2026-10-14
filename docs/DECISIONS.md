# Decisions / ADR

## 001 — 既存を保持しnativeを併設（2026-09-27）

既存Tk画面は授業で使われている。native/へSwift Packageを追加する。
Python本体、例外辞書、内蔵曲、Word/PDF、起動.commandは変更しない。
母音核ハイライトの教育的意味・日本語保持・A4の原則・回帰例を再利用する。
廃止ファイルなし。綴りベースheuristicをIPAエンジンとして移植しない。
共有済みsheet-design-pdf(9eeeda9)を基点にcodex/native-singing-foundation。mainへ自動mergeしない。

## 002 — Swift 6 / SPM / macOS 14

Apple frameworksを優先、外部依存ゼロ。CLTだけでbuild/test、scriptで.appを構築。
Xcode project生成ツールを導入しない。将来配布時に署名/entitlement/build構成を整える。
SwiftUIはUI targetのみ、core/serviceはSendableな値型とasync protocol。

## 003 — 正規化した参照と有理数の音楽時間

PhonemeはSyllable必須/Mora任意。Mora排他enumは不採用。
音楽と歌詞をAlignmentで接続。Beatはrational、PPQ/秒を唯一の内部時間にしない。
source metadataとnotation/performanceを別管理。整数範囲外は明示エラー。

## 004 — versioned package + transactional edits

SwiftDataを正本にしない。FileDocument+Codable、validate-before-save、future version拒否。
初回Undoは小曲向けdocument snapshot。大曲ではcommand deltaへ移行する。
手修正のfield/segmentation/AlignmentをAIから保護する。

## 005 — UXはPhrase中心

UX_DESIGNの3案からB。Readingは教材風、Singingは同一データの時間投影。
Inspectorと音符panelは任意表示。初期transportは無音の位置プレビューと明示。
リアル再生がないのに再生対応と記載しない。

## 006 — 外部I/OとAIの完成を偽らない

ユーザーのstretch指定に従い、外部MIDI/XML parserより動くdocument vertical sliceを優先。
双方向I/Oを最終MVPから外す判断ではない。未知要素保存は原byte保持と意味patchの両方が必要。
Apple FMは第一級の設計対象、実装はavailability確認後。Ollamaのモデル固定/自動downloadはしない。
有料APIは呼ばない。mockはUIでもサンプル解析と明示する。

## 007 — このMacのビルド環境と画面検証

現在のCommand Line ToolsはSwift 6.4で、標準SDK 27に必要なSwiftUI macro pluginを含まない。
既存のmacOS 26.5 SDKを選ぶscriptをnative内に用意。Swift Testing macroはCLT付属pluginを明示読込。
Xcode.appは利用規約未承認のためシステム設定を変更せず使わない。外部依存も追加しない。
native `.app` は署名なし配布向けではなく、ローカルで ad-hoc 署名した開発ビルド。
画面操作ツールは全macOSアプリでwindow取得に失敗しており、実画面QAは別日に必要。

## 008 — 入力と大きなフレーズの扱い

ユーザー入力の原文はPhrase.originalTextに保持。単語は空白境界だけで生成し、音節・IPAを捏造しない。
初回Singingは128拍より長い単一Phraseの描画を保留し、空の画面で理由を表示。
大曲のviewport virtualizationを後続で実装する。

## 009 — 公開ミラーと伝承曲サンプル（2026-09-27）

InagawaのcanonicalをSSOTとし、GitHubを公開ミラーとして追加。`origin`を変更しない。
伝承曲の旋律とJane Taylorの1806年の歌詞から「Twinkle, Twinkle, Little Star」の短い第1節を教材サンプルにする。
現代の録音や出所不明のMIDIを取り込まず、音符データから単旋律MIDIを生成する。
単旋律ガイド音はAVAudioEngineで生成し、歌声合成と区別する。SMFの一般的なimport/export完了とは扱わない。

## 010 — 小節の表示窓と再生範囲を分離（2026-09-27、設計済み・未実装）

ユーザーの「モード」は約2小節を拡大する詳細と、楽譜のように複数小節を見渡す一覧を指す。
一覧を歌唱練習の初期表示にする。表示の詳細/一覧、音高のピアノロール/楽譜、曲通し/範囲1回/範囲loopは独立。
ADR005のPhrase中心は読解に維持し、歌唱viewportとtransportの単位にはしない。ADR008の128拍描画制限は小節窓で置き換える。
時間幅は小節/拍に比例。将来の単語幅モードも保存時間を変えない。既存schemaのまま派生投影を追加する。
連続音声はPhraseを連結せず全music.eventsから計画し、表示追従はplayer clockを読むだけにする。
短い教材向けには5分上限の非同期PCM生成とnode loopを採用。長時間streamingは別工程。
鍵盤表示/試聴、単旋律五線、サンプルの読み補完を含む契約・受入条件は [SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md)。
設計引継ぎで一度停止し、Sol中による実装へ切り替える。別CLI/agentを自動起動してこの停止を飛ばさない。

## 011 — 実曲を対象にし、権利は利用者側で処理（2026-09-28）

アプリの本来の目的は利用者が実際に歌う曲の練習。歌詞・MIDI・音源は利用者が権利処理済みのものを用意する前提。
アプリは取得・同梱・送信をしない。利用者の素材は `.songproj` 内だけ。内蔵サンプル・テスト・Gitは伝承曲/自作のまま（ADR009を維持）。

## 012 — 声部を持つ統合形式（schemaVersion 2）

個別ファイルを後で束ねる案と、最初から統合形式にする案を比較し、統合形式＋声部単位の書出し/取込みを採用。
単声は声部1つ。小節・テンポ・拍子は全声部共通で、声部の同期は Beat。歌詞と意味・発音は共有し、割付は声部ごと。
v1 は純粋関数で移行し、保存時に元の document.json を `preserved/document-v1.json` に残す。

## 013 — 言語別の規則ベース音節分割

歌詞入力時にすぐ候補を出すため、Foundation だけの規則ベース分割器を使う（辞書・ネットワークなし）。
言語的な音節（Syllable）と歌唱上の割付（Alignment）を分ける。仏語は歌唱の規則で語末 e を数える。
日本語はモーラを歌唱単位とし、漢字の読みは macOS の推定を「推定」と明示して使う。ADR008の「音節を捏造しない」は、規則の出所（`rule`）を記録し手修正を保護する形に置き換える。

2026-10-09追記: 英語の発音には同梱CMUdictの単語全体の発音を優先し、綴りの音節分割は規則と例外を使う。
カタカナはIPAとは別の歌唱補助表記とする。既存文書の修正では音節数・ID・音符の対応と手修正を保持し、
辞書の音節数と合わない語や未確定の異読語は個別確認に回す。ネットワークなしで実行できる。
詳細は[英語の発音・カタカナ候補](ENGLISH_PRONUNCIATION.md)。

## 014 — 一音符一音節を基本仮説とする割付

音節列と歌われる音列（タイは1音）をアンカー区間ごとに動的計画法で対応。1対1をコスト0、メリスマ・エリジオンに条件付きコスト。
結果は提案として要確認箇所と共に示し、1回のUndoで適用。人の修正はアンカーとして固定。AIは同じ候補形式でのみ補助。

## 015 — 譜線間隔を単位にした記譜

旧五線表示は字形の目分量配置で、音符が五線から浮いて見えた。寸法を譜線間隔で計算する純粋な記譜レイアウトを SongCore に置き、
画面・印刷が同じ座標を描く。横位置は拍比例（ADR010）を維持し、連桁・小節線・音部/拍子・五線下の歌詞を追加する。

## 016 — 旋律入力の順序

ステップ入力（画面鍵盤＋CoreMIDI）とSMF読込を先に実装。リアルタイム録音＋クオンタイズ、歌声/原曲からの推定はその後。
どの入口も同じ Music/Part に入り、同じ割付画面へ進む。

## 初回設計の自己レビュー（実装前）

- 階層: 混在音素を二重実体化せず親参照で一意化 → DATA_MODELへ反映。
- Phrase: 言語Phraseの練習範囲と音楽側MusicSpanを区別 → ARCHITECTUREとDATA_MODEL一致。
- 時間: rationalとUI Doubleを区別、XML divisions/PPQをlossless変換 → MUSIC_IO一致。
- AI: 生成DTOを直接documentに代入しない。revision/field保護のserviceを設置。
- 保存: 元資料保持のみでXML編集round-trip完了とは呼ばない。
- UI: 視覚transportと実音を明確化、Undo/saveを最初から通す。
- scope: 初回DoDと完成MVPの差をREQUIREMENTS/PLANに明記。設計上の矛盾を解消し実装開始可能。
