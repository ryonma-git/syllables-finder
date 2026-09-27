# 作業記録 — 2026-09-27

## 追加作業: 歌唱練習の設計引継ぎ（実装前）

- 実装基点`30612b6`を確認。作業ツリーclean、canonical/GitHubをfetchし、canonicalの同branchとの分岐なしを確認。
- 表示を「詳細：約2小節」「一覧：複数小節」に具体化。音高表現と再生範囲を独立させ、曲通し/範囲1回/範囲loop、追従、鍵盤、五線、読みの仕様を決定。
- 現コードのPhrase選択時停止、UI監視によるloop再開始、main actorでのPCM生成を確認。TempoMap/PlaybackPlanと非同期PCM、node loop、generationによる取消の設計にまとめた。
- カタカナが見えない原因はTwinkleSampleの未入力とSingingViewの未描画。既存の保存フィールド/編集欄は残っている。新規サンプル補完と両歌唱表示への追加を次工程に含めた。
- [SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md) に操作契約、対応範囲、S1〜S4、受入条件、Sol中への開始指示を記載。関連要件/UX/構成/ADR/計画を更新。
- アプリコードと既存サンプルファイルは変更していない。今回は文書差分・参照整合のみ確認し、build/実画面/実聴/回帰テストは再実行していない。
- ユーザー指定のモデル切替地点で停止。次はSol中で実装する。CLIのversion/helpと公式設定を確認したが、別モデルの実行は起動していない。

## 追加作業: GitHub公開ミラーと既知の歌のサンプル

- 公開GitHub `ryonma-git/syllables-finder` を作成。Inagawaのcanonicalを`origin`に保ち、`github` remoteへ`main`、`sheet-design-pdf`、`codex/native-singing-foundation`を初回pushした。`main`へのSwift版採用は行っていない。
- Jane Taylor『The Star』（1806）と伝承曲『Ah! vous dirai-je, maman』を根拠に、きらきら星の第1節6行を追加。42音節をハ長調の42音符に1対1で対応。現代の録音・第三者MIDIは使用していない。
- 新規文書からきらきら星サンプルを選べるようにし、`.songproj`サンプル生成時に自作SMF format 0の`source/Twinkle.mid`を添付。単旋律のガイド音はAVAudioEngineで生成し、歌声は生成しない。
- Swiftのbuild/testは追加テストを含めSongCore 13件、SongServices 4件が成功。MIDIを実際に生成し、42 note-on/off、48拍、96 BPM、ヘッダー/トラック長を独立パーサーで確認。既存Python12例・23件成功。
- 別インスタンスの実画面で新規画面のサンプル選択、日本語訳、ReadingとSingingの音節・音符対応、再生ボタンと位置の進行・停止を確認。スピーカーからの出音はこの操作環境で聴取できず、音量・音質・同期精度は利用者の実聴確認が必要。

## 初回実装の記録

以下は初回の状態。音声/サンプルの追加後の状態は上の追記を優先し、次の作業順はIMPLEMENTATION_PLAN.mdを参照。

### 到達点

既存Python/Tk教材アプリを調査し、変更せず保持。Swift 6 / SwiftUI の新アプリを `native/` に併設。
設計SSOT 8文書を作成し、実装前に階層・音楽時間・Alignment・保存・AI・UIの矛盾をレビューした。
外部依存なし。既存のcanonicalに接続できることを確認し、`sheet-design-pdf` の 9eeeda9 を基点に
`codex/native-singing-foundation` ブランチで作業した。

### 実装したもの

- Swift Package の SongCore / SongServices / SingingWorkspace。SongSampleTool で独自サンプル文書を生成。
- versioned SongDocument、英語の直接音素/日本語のモーラ経由/混在可能な階層、exact Beat、Note/Rest/Tempo/Meter、独立した多対多Alignment。
- 参照整合性・数値範囲・未来schemaの検証、transaction編集、未知package資料のbyte保全、symlink拒否。
- SwiftUI DocumentGroup。新規文書、歌詞追加、サンプル、Reading、Singing、全文訳/単語/音節の文字編集、音節と音符の対応変更、音符の追加/削除/数値編集、Undo/Redo登録。
- Playhead、Play/Pause/Stop/Loop/練習テンポの**無音の位置プレビュー**。音声・MIDI再生は未実装とUI上に明示。
- AIProvider protocol、Mockと保護merge。明示操作でOllama model一覧取得/structured chat。既存手修正と進行中編集を保護。
- Word/Syllable/Mora/Phoneme、Codable、Alignment、melisma、schema、edit preservation、Mock failure/cancel等のSwift tests。Reading/SingingのPreview定義。

### 主要ファイル

`native/Sources/SongCore/`：言語・音楽・文書・保存・サンプル・編集。
`native/Sources/SongServices/`：解析境界、Mock、Ollama。
`native/Sources/SingingWorkspace/`：画面と文書アプリ。
`native/scripts/`：ローカルSDK選択と.app組立。
`native/Tests/`：Swift Testing。`native/Resources/Info.plist`：package文書宣言。
`docs/REQUIREMENTS.md`〜`docs/DECISIONS.md`：8設計SSOT。
`README.md`：開発中アプリの起動・現状。`.gitignore`：生成物を除外。

### 既存から再利用・保全

母音核ハイライトの教育上の意味、日本語を損なわない出力、A4教材方針、回帰検証を継承。
`app.py`、`vowel_marker.py`、例外辞書、内蔵曲、Word/PDF実装、旧ランチャーは無変更。
綴りの母音核判定をIPAや音節分割として転用していない。廃止ファイルなし。

### 検証

- `native/scripts/build-app.sh` 成功。Swift 6.4、既存macOS 26.5 SDKを使用。ad-hoc署名したローカル開発用.appを生成。
- `native/scripts/swift-tool.sh test`：SongCore 12件、SongServices 4件、計16件成功。
- 指定の `.venv/bin/python test_vowel_marker.py`：12例成功。
- 指定の `.venv/bin/python -m unittest discover -s tests -v`：23件成功。GUIテストはTk widget/callbackの自動試験で、実画面操作ではない。
- `SongSampleTool /tmp/SingingWorkspacePreview.songproj` でサンプルpackage作成。Git外。
- 新.appプロセス起動を確認。ただし画面操作ツールが新アプリ・Finder・メモのいずれのwindowも取得できず、**新UIの実画面操作・保存ダイアログ/再読込は未確認**。GUI成功とは扱わない。
- このMacのXcode.appは利用規約未承認。変更せずCLT経路でbuild/test。Ollama daemonは未起動で実モデル接続未確認。

### 未実装・既知の制約

SMF import/export、MusicXML import/export、実音MIDI/TTS、CoreMIDI Live I/O、Apple FM、cloud adapters/Keychain、A4 interlinear印刷、音符の複数選択/copy/quantize/drag、言語構造の分割編集、モーラ/音素の個別値編集、正式アクセシビリティQA。
Ollamaは実接続前、Mockは練習サンプルだけを扱う。
Singing表示は選択Phraseの128拍まで。全曲virtualizationは後続。
現行Undoは小曲向けdocument snapshot。長曲では差分commandへ移行。

### 次に行うこと

1. macOSユーザーセッションの実画面で新.appの「サンプル→読む→歌う→編集→Undo→保存→再読込」、日本語入力とVoiceOver/focusを確認し、UI問題を修正。
2. phase 8/9：MUSIC_IO.mdのテストゲートを先に作り、SMFとMusicXMLの基本的な双方向adapterとsource保全を実装。
3. 実音のtransport、簡易note editor全操作、A4教材出力を追加。
4. Apple FMの実SDK availability・言語対応を確認して実装し、Ollama実接続、cloud adaptersを順に進める。

### 設計上の注意

SongDocumentを唯一の曲正本にする。言語/音楽を結合せずAlignmentで参照する。
MusicXML未知要素は原byte保全だけで編集後のlossless exportが完成したとは扱わない。
AIの再解析はrevisionと手修正保護を通す。外部API keyを文書へ入れず、有料APIは明示操作のみ。
新しい機能で設計を変えた場合は、この記録ではなく対応する8設計SSOTを同時更新する。
