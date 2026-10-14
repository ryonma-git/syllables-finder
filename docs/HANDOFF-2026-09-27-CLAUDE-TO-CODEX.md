# Claude → Codex 引継ぎ（2026-09-27）

> **Codex追記（同日）:** この文書はClaudeから受け取った時点の記録。後続の拍子・休符・歌唱行の修正と確認は[WORK_LOG.md](WORK_LOG.md)の最新項目を参照。`main`へはmergeしていない。

Swift版の歌唱練習（[SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md) S1〜S4）の続き。
**実装は完了していない**。主要な再生・表示・保存は実画面で動作を確認したが、下の「残作業」が受入条件に残る。
経緯の詳細は[WORK_LOG.md](WORK_LOG.md)の上から3項目、全体像は[IMPLEMENTATION_CHECKPOINT_2026-09-27.md](IMPLEMENTATION_CHECKPOINT_2026-09-27.md)。

## 作業場所と状態

- フォルダ `/Users/ryon/Projects-Inagawa/syllables-finder`、branch `codex/native-singing-foundation`。
- Claudeの開始 `20d0e9c` → `2b3262e` → `fe1273d` → 本書のcommit。origin（Inagawa canonical）→ github の順に通常push済み。
- `main` は `e0b1410` のまま。**mergeしない**（利用者の指示）。
- 旧 `/Users/ryon/Projects/syllables-finder` には触れていない。Python/Tk本体は変更していない。
- 開始時は AGENTS.md どおり status/fetch（origin, github）で差分と利用者の新しい作業を確認する。

## Claudeが直したもの（テスト追加・実画面確認済み）

| 内容 | 主なファイル |
|---|---|
| 文書を開くだけで文字欄が同じ値を書き戻し、revision 0→1で自動保存・サンプル読みが手修正扱いになる不具合 | `SongCore/Language.swift`（同値の`edit`は無変更）、`WorkspaceView.mutate`（内容が同じ編集はUndo/保存に載せない） |
| 音声出力の構成変更で再生/準備を取消し、停止したengineで`resume`しない（例外防止） | `GuideTonePlayer.swift`（`onInterrupted`）、`WorkspaceView` |
| 一時停止中のテンポ変更は旧計画を破棄し位置保持で停止、再生中は現在位置から再準備 | `WorkspaceView.tempoChanged()` |
| 追従は別の段/2小節に入った時だけスクロール。追従を再ONで現在位置へ戻る | `SingingView.follow` |
| 小節線をまたぐタイの続き音に臨時記号を付け直さない | `NotationProjection.swift` |
| 詳細パネルを開いた狭い幅で一覧の4小節目が切れる → 4小節の段が入る時だけ4小節/段、他は2 | `SingingView.overviewColumns` |

## 実画面で確認済み（Claude、別bundle IDの確認用ビルド + サンプルのコピー）

範囲1回（3–4小節、9→17拍・約5秒で停止）、範囲loop（一時停止→再開後に次周も全範囲）、停止で範囲先頭、
曲通しの詳細追従（1–2→…→11–12、96 BPM相当、曲末で停止）、目盛りseek（停止中/再生中で表示と位置一致）、
楽譜の音高位置（C4加線/G4/A4/2分音符）、読み編集→Undo→Redo→保存→再読込、狭い幅の一覧、
旧Tkの日本語行・タイトル・プレビュー・docx生成（生成docxの本文/タイトル/赤字をpython-docxで確認）。

## 残作業（優先順）

1. **楽譜の拍子記号**: 五線に4/4等が表示されない（計画「小節線・拍子」未達）。`SingingView`の五線描画（`StaffView`相当、`SingingView.swift`後半）に曲頭と拍子変更位置の拍子を描く。
2. **楽譜の難例の実画面確認**: 休符字形・付点・16分・臨時記号の取消・小節をまたぐタイは単体テストのみ。Git外のテスト用文書（例: SongSampleToolや一時文書）で該当小節を作り、描画を確認・修正。未対応小節の退避表示も確認。
3. **UI仕上げ（計画5）**: 歌唱段のフレーズ全文訳表示、IPA ON時の行の重なり、文字拡大（その他メニュー）、横スクロール、鍵盤のVoiceOver/キーボードfocus。
4. **計画との差の判断**: 鍵盤試聴は「押している間だけ鳴る」でなくクリックで短音。macOS 14ではスクロールホイールで追従OFFにならない可能性（15+は検出済み、本機はmacOS 27）。直すか、差として記録する。
5. **利用者側の確認が必要なもの**: スピーカーでの実聴（音量・途切れ・loop継ぎ目）、IMEでの日本語変換入力（Claudeは貼り付けで代替）、Word本体での新デザインdocx表示（Wordは初回起動の同意画面で止めた。同意操作は利用者が行う）。
6. **完了処理**: 本書・CHECKPOINT・SINGING_PRACTICE_PLANの状態表示・WORK_LOG・READMEを更新。`git diff --check`、秘密/生成物確認、明示pathだけcommit、origin→github通常push。mainへmergeしない。

## 検証コマンド

```sh
cd /Users/ryon/Projects-Inagawa/syllables-finder
native/scripts/swift-tool.sh test        # 現在 SongCore 24件 + SongServices 4件
native/scripts/build-app.sh              # native/build/Singing Workspace.app（Git外）
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python test_vowel_marker.py
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m unittest discover -s tests -v   # 23件
```

## 実画面確認のやり方と注意（Claudeが使った方法）

- 同じbundle ID（`org.syllablesfinder.workspace`）のインスタンスが複数起動していると、文書の受け渡しやSystem Eventsの対象が混ざる。
  ビルドを一時フォルダへコピーし、`Info.plist`の`CFBundleIdentifier`/`CFBundleName`/`CFBundleExecutable`を別名にして`codesign --force --sign -`、`lsregister -f`してから起動すると分離できる（Git外で行う）。
- `open -n -a <確認用app> <サンプルのコピー.songproj>`。元の `~/Documents/SingingWorkspaceExamples/*.songproj` は開かない（開くと自動保存され得る）。
- SwiftUIのAXツリーはAppleScriptの`entire contents`では0件になる。`AXUIElement`で子要素を再帰的にたどる小さなSwiftツールを作るとボタン/値/座標が取れる（Claudeはスクラッチに置いたのでGitには無い）。
- 文字入力は1文字ずつのキーイベントでは入らず、クリップボード貼り付けが確実。`pbcopy`は`LANG=en_US.UTF-8`にしないと日本語が文字化けする。使った後は利用者のクリップボードに注意。
- 画面座標は論理座標（本機は2048pt幅、スクリーンショットは2倍）。
- Claudeの操作でmacOSの「claude.appがFinderを制御」許可ダイアログが出た。セキュリティ設定なので押していない（利用者判断）。
- 確認用アプリ・Wordは確認後に終了済み。既存の他インスタンス（`/tmp/Singing Workspace QA.app`等）は利用者/前担当のものなので触れない。
