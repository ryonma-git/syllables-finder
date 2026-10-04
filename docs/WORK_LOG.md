# 作業記録 — 2026-09-27

## 2026-10-04 意味の上下配置の試用・第九の劇ドイツ語

- `codex/lyrics-layout-trial` を `codex/mary-lyrics-sheet` の `4c7ad58` から作成。試用前のbranchを保持。mainへの採用ではない。
- 読む画面に意味の上/下切替を追加。初期値は元の上配置。PDF/Wordも選択に従い、PDFの行間は据置。
- 第九に標準/劇ドイツ語の選択を追加。IPAとカタカナを同時切替し、標準で完全復帰。手修正値を保持。保存形式はoptional項目追加で旧文書を読み込める。
- Swift 82件（Core 71、Print 5、Services 4、Notation 2）、既存Pythonの母音例と23件成功。ビルド成功。
- 別bundle IDの試用アプリで上下・標準/劇の往復、日本語の曲名入力、Word保存ダイアログを実操作。WordのXMLはCLI出力と一致。
- 発音選択の保存・復帰はencode/decodeの自動試験で確認。別bundle IDの試用アプリでは新規.songproj保存ボタンが無効で、保存後の再起動を伴う実画面試験は未完了。既存の曲ファイルへの書込みは行っていない。
- PDFをPopplerで描画し、上/下とも1ページ・日本語見出し・カタカナ・IPAを目視確認。Wordは同梱rendererで日本語が欠ける既知の環境差があり、Pagesで2ページすべてを目視確認した。Microsoft Word自体での表示は未検証。
- 生成資料は書類フォルダの `SingingWorkspaceExamples/Meaning-Below-2026-10-04` に置き、Git対象外。Inagawa作業フォルダは `codex/lyrics-alignment-review-fixes` でcleanを確認。
- 元へ戻す操作は「単語の意味：上（元の配置）」「第九の発音：標準ドイツ語」。実装ごと試用前に戻す場合はcleanを確認して保持branchへ通常のswitch後、ランチャーで再buildする。stash/reset/rebaseは使わない。

## 2026-09-28 追加作業: Claudeによる歌詞×旋律の割付・多言語・声部・楽譜（branch `claude/lyrics-melody-alignment`）

- ChatGPT（GPT-6 Astra高）との設計相談が利用上限で中断したため、利用者の依頼でClaude Opus 5.5が意思を引き継いだ。ChatGPT側と分けるため `codex/native-singing-foundation`（`1a0af6b`）から別branchを作成。`main`・Codexの作業フォルダ（`~/.codex/worktrees/53dd`、clean）には触れていない。
- 設計: [LYRICS_MELODY_DESIGN.md](LYRICS_MELODY_DESIGN.md) を新設、REQUIREMENTS（目的・R15〜R20）、DECISIONS（ADR011〜016）、DATA_MODEL、IMPLEMENTATION_PLAN、MUSIC_IO、READMEの記述を更新。
- 楽譜: 旧表示を画像で再現し、符頭が譜線間隔の半分・音部/拍子記号のずれ・小節線なし・旗が文字、を確認。譜線間隔基準の記譜レイアウト（SongCore `StaffEngraving`）と共通描画（新モジュール `SongNotation`）に置き換え、五線の下に歌詞（ハイフン・メリスマ延長線・エリジオン連結）、複数声部は括弧付きの段。検証用 `SongStaffTool`（PNG出力）を追加。
- 保存形式 schemaVersion 2（声部 Part、event.partID、Phrase.language、FieldSource.rule）。v1は開くときに移行し、保存時に元JSONを `preserved/document-v1.json` に残す。
- 音節分割（独・西・仏・伊・羅・露・英・日のモーラ・韓・中の試験版）を規則ベースで実装。歌詞入力に言語選択と入力中の分割プレビュー、単語パネルに区切りの修正と「規則で分け直す」。
- 割付: 一音符一音節を基本仮説とする動的計画法（タイは1音、メリスマ・エリジオン、人の修正は固定）。サンプル3曲の元の割付を完全再現。確認シートから1回のUndoで適用。
- 旋律入力: ステップ入力（画面鍵盤・CoreMIDIの全入力、上書き入力、拍子/テンポ設定）、声部の管理（混声四部の用意、音部記号）、MIDIファイル読込（MUSIC_IOのテストゲート、クオンタイズは明示選択、原ファイル保持）。
- 検証: Swift 73テスト（SongCore 66、SongServices 4、SongPrint 1、SongNotation 2）成功、アプリbuild成功、既存Python 12例＋23件成功。楽譜はPNG（サンプル・2声部の自作検証曲）とアプリの `ScoreRow` のオフスクリーン描画で目視確認。
- **未確認**: 画面がロックされていたため、実画面での操作（歌詞入力画面、単語パネル、割付シート、声部シート、ステップ入力、MIDI読込画面、楽譜の選択・再生追従）は未確認。MIDI鍵盤の実機、音の実聴、日本語IME入力も未確認。確認手順は [HANDOFF-2026-09-28-CLAUDE.md](HANDOFF-2026-09-28-CLAUDE.md)。

## 追加作業: Swift版のサンプル選択とA4練習シート

- 新規文書とツールバーから開ける「サンプルを表示」画面を追加。きらきら星、Mary Had a Little Lamb、Frère Jacques、Morning lightを選択し、歌詞プレビューから開ける。新しい2曲には単旋律、音節と音符の対応、日本語訳、IPA、カタカナ読みを含む。
- 現在の文書からA4のWord（docx）またはPDFを書き出す。アプリと同じ青緑の見出しを用い、原文・訳・語の意味・IPA・カタカナ読みを印刷用の表に配置。五線譜の印刷は後続。
- Swift版の別bundle IDの検証用アプリで、サンプル選択→Maryを開く→歌唱画面→PDF/Word保存を操作。保存したPDFはA4・2ページで日本語テキストを確認し、WordはQuick Lookで日本語と表を目視、python-docxで4表と読みを確認。Microsoft Word本体での表示は未確認。
- Swiftの30テストとアプリbuild、既存Pythonの12例と23件は成功。PDFはきらきら星のA4・3ページも画像で確認。旧Tkの実画面操作は今回のコード変更対象外のため再実施していない。
- きらきら星は元データで12小節。最初の「Twin・kle・twin・kle」は4/4拍子の1小節に各1拍で入り、「lit・tle・star」は2小節目。ユーザーが見た配置はこの音符データと一致。拍子や音符を変更した一時検証ファイルを開いていたアプリは終了した。

## 追加作業: CodexによるClaude引継ぎ後の楽譜・歌唱行の修正

- `codex/native-singing-foundation`の`751a40c`から開始し、作業ツリーclean、`origin`（Inagawa canonical）と`github`の同branchが一致することをfetchで確認。`main`はmergeしていない。
- 五線の左余白にト音記号と現在の拍子を並べ、小節途中の拍子変更はその小節線の上に表示。楽譜を実画面で開き、冒頭の4/4と2小節目の2/2が読めることを確認。
- 一時文書で16分・8分・付点・♯から♮への取消・小節をまたぐタイ・3拍休符を表示。休符字形が環境のフォントで`?`になるのを発見し、Canvasの描画に変更。再表示で付点2分休符を確認。検証文書はGit外で、元の例示文書を変更していない。
- 歌唱段の下端に重なるフレーズの日本語訳を表示。IPA ONと文字拡大で音節と五線の間隔を広げ、狭い音節枠の全文はツールチップに残す。高密度の一時文書でIPA ONの行間を実画面確認。単語・音節が短い拍へ密集する場合は表示を枠内で省略する。
- Swiftの28テストとアプリbuildを確認。音声の実聴、IMEでの変換入力、Word初回利用規約を越えた表示確認は未実施。macOS 14のホイールで追従OFF、鍵盤の押下中だけ鳴る試聴は引き続き計画との差として扱う。VoiceOverの読み上げ自体は未確認（AXには鍵盤の音名・試聴ラベルがある）。

## 追加作業: 実画面の受入確認（アクセシビリティ権限付与後）

- 別bundle ID・別名の確認用ビルドでサンプルのコピーを開き、AX/合成クリックで操作。元のサンプルと既存インスタンスには触れていない。
- 範囲1回: 3–4小節を小節クリック+Shiftクリックで候補にし「範囲を適用」。9.0拍から再生し17.0拍（範囲末尾）で約5秒後に停止。
- 範囲loop: 再生→一時停止（位置保持）→再開後、17拍目から9拍目へ戻り、次周も9→17拍の全範囲を反復。
- 停止で範囲先頭へ戻る。曲通し＋詳細＋追従ONで33拍→9–10小節、41拍→11–12小節へ切替。約1.6拍/秒（96 BPM）。曲末49拍で停止し最後の窓を表示。
- 目盛りseek: 停止中は位置のみ、再生中はその位置から継続。拍表示と再生位置線が一致。
- 楽譜（詳細）: C4の加線、G4第2線、A4第2間、2分音符の白抜きを確認。拍子記号は表示されない（未実装）。休符・付点・16分・臨時記号の実画面はサンプルに無く未確認（単体テストのみ）。
- 読み編集→Undo→Redo→保存→終了→再読込で値が保持。保存ファイルで編集した音節だけ`manual`、他は`sample`のまま。歌う画面にも反映。
- 修正: 単語の詳細を開いて幅が狭いと一覧の4小節目が右端で切れていた。4小節の段が入る幅のときだけ4小節/段、他は2小節/段にした（実画面で確認）。
- 旧Tk: 日本語の行とタイトルを貼り付け入力し、プレビュー（日本語保持・母音[ ]）、docx保存ダイアログ→生成を確認。生成docxは本文・タイトル・赤字が正しい。
- 未確認: IMEでの日本語変換入力（貼り付けで代替）、スピーカーの実聴、Word本体での表示（初回起動の同意画面で停止し、同意操作はしていない）、IPA表示ON、文字拡大、VoiceOver。

## 追加作業: Claudeによる引継ぎ確認と修正（開始 `20d0e9c`）

- 開始時にbranch/clean/origin・githubとの一致を確認。Swift tests 22+4、build成功を再現してから着手。
- 修正: 文書を開くだけで文字欄のフォーカスが同じ値を書き戻し、revision 0→1で自動保存されていた。同じ値の`edit`は出典・手修正フラグを変えず、内容が同じ編集はUndo/保存に載せない。サンプル読みが「手修正」扱いになる経路も塞いだ。
- 修正: 音声出力の構成変更（`AVAudioEngineConfigurationChange`）で再生と準備を取り消し、位置を保って停止状態へ戻す。停止したengineでの再開（例外）を防ぐ。
- 修正: 一時停止中のテンポ変更は旧テンポの計画を破棄し、位置を保って停止へ（次の再生で新テンポ）。再生中の変更は現在位置から再準備。
- 修正: 追従は再生が別の段/2小節へ入った時だけスクロール（33msごとの再スクロールを止めた）。追従を再ONにすると現在位置へ戻る。
- 修正: 小節線をまたぐタイの続き音に臨時記号を付け直さず、小節の臨時記号状態にも数えない。
- Swift tests SongCore 24件 + SongServices 4件、build、既存Python 12例 + 23件成功。
- 実画面: 別名の新ビルド（`Singing Workspace Claude QA`）でサンプルのコピーを開き、読む画面の日本語・IPA・カタカナ表示と、開いても文書が変更されないことを確認。この環境にはアクセシビリティ権限が無く、クリック/入力を送れないため、歌う画面・範囲再生/loop・seek・読み編集→Undo→保存→再読込・楽譜の字形・日本語入力・旧Tk画面は**未確認**。実聴も未確認。

## 追加作業: Sol中の歌唱練習実装と中断点

小節投影/テンポマップ/全曲再生計画、非同期ガイド音、詳細/一覧、鍵盤/五線、きらきら星の読みを追加。
Swift tests 22+4、build、既存Python12例+23件成功。実画面で一覧・詳細・五線・読み・曲通し再生中の表示切替を確認。
範囲loop/保存再読込/実聴は未確認。ユーザーの5時間制限に合わせ、[実装チェックポイント](IMPLEMENTATION_CHECKPOINT_2026-09-27.md)へ残作業を明記して停止。

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
