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

## 初回設計の自己レビュー（実装前）

- 階層: 混在音素を二重実体化せず親参照で一意化 → DATA_MODELへ反映。
- Phrase: 言語Phraseの練習範囲と音楽側MusicSpanを区別 → ARCHITECTUREとDATA_MODEL一致。
- 時間: rationalとUI Doubleを区別、XML divisions/PPQをlossless変換 → MUSIC_IO一致。
- AI: 生成DTOを直接documentに代入しない。revision/field保護のserviceを設置。
- 保存: 元資料保持のみでXML編集round-trip完了とは呼ばない。
- UI: 視覚transportと実音を明確化、Undo/saveを最初から通す。
- scope: 初回DoDと完成MVPの差をREQUIREMENTS/PLANに明記。設計上の矛盾を解消し実装開始可能。
