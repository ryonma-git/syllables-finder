# Swift歌唱画面の実装チェックポイント（2026-09-27）

ユーザーの5時間制限に合わせ、ここで実装作業を止めた。次の担当がClaudeでも、この文書と[SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md)から再開できる。**機能は実装途中で、受入確認は未完了**。

## 作業場所と保全

- SSOT作業フォルダ: `/Users/ryon/Projects-Inagawa/syllables-finder`、ブランチ: `codex/native-singing-foundation`。`main`へは未採用。
- `origin`はInagawa canonical `/Users/ryon/Git/remotes/syllables-finder.git`、`github`は公開ミラー。AGENTS.mdの順に通常pushする。IshibashiからGitHubへ直接pushしない。
- 開始時HEAD `3387cbe`、作業ツリーclean、origin/github同branchと一致。旧`/Users/ryon/Projects/syllables-finder`には触れていない。
- このチェックポイントのcommitを基点に再開。最初にbranch/status/remotesを再確認してfetchし、ユーザーの新しい作業を保全する。

## 今回実装したもの

- `SongCore/MusicTimeline.swift`: 小節投影、重複/欠落小節の表示用退避、詳細2小節窓、TempoMap、全曲のPlaybackPlan。曲頭テンポに対する練習倍率を途中テンポにも適用。連続する明示tieだけ結合。
- `SongCore/GuidePCMRenderer.swift`: 全範囲のガイド音を44.1kHz mono Floatで生成。重複音をmixし、音量・短いfadeを処理。練習速度で5分上限、cancel可能。
- `SingingWorkspace/GuideTonePlayer.swift`: バックグラウンドrender後にAVAudioPlayerNodeへ予約。全曲/範囲1回/範囲loop、pause/resume、途中からのloop、sample clockから再生位置、generationで古い完了通知を無効化。鍵盤試聴用nodeを別に追加。
- `SingingWorkspace/WorkspaceView.swift`: 読む/歌うを保ち、歌唱一覧を初期表示に。詳細/一覧、ピアノロール/楽譜、再生範囲を独立させた。表示切替や歌詞・音符選択で再生を止めず、明示seekと再生範囲適用だけtransportを更新。
- `SingingWorkspace/SingingView.swift`: 一覧は標準幅4小節/段、詳細は2小節。小節・拍幅の時間軸、カタカナ/IPA表示、鍵盤、五線、ページ送り、範囲選択を実装。macOS 15+の手動スクロール検出を追加。
- `SongCore/NotationProjection.swift`: ト音記号の単旋律表示向け音価分割、空白休符、加線位置、臨時記号状態、タイ表示情報。対応しない小節は理由を示してピアノロールに退避。
- `SongCore/TwinkleSample.swift`: 42音節のIPA/カタカナ近似を追加。既存IDを維持し、保存済み文書を自動上書きしない。
- `SongCoreTests/MusicTimelineTests.swift`: 30秒/1,323,000 frames、境界音声、途中テンポ往復、小節弱起、拍子変更、tie、音価退避、読み/保存を確認。

## 実行済みの検証

- `native/scripts/swift-tool.sh test`: SongCore 22件 + SongServices 4件成功。
- `native/scripts/build-app.sh`: ビルド成功。開発用appは`native/build/Singing Workspace.app`（Git外）。既に走っている同名アプリのプロセスは更新しない。
- 指定Python検証: `test_vowel_marker.py`の12例、`unittest discover`の23件成功。旧Tk画面を手操作したわけではない。
- Git外に新しい例示packageを生成: `/Users/ryon/Documents/SingingWorkspaceExamples/Twinkle-Twinkle-Little-Star-Reading.songproj`。42読み/IPA、安定ID、414byte MIDIを検証。元の`Twinkle-Twinkle-Little-Star.songproj`は保持。
- 別インスタンス`/tmp/Singing Workspace Practice QA.app`の実画面でサンプルを開き、一覧の小節/鍵盤/読み、五線、詳細の3–4小節への移動を確認。曲通し再生中に表示を切り替えても再生ボタンは一時停止のままで、位置が進んだ。停止/一時停止も操作した。

## 未確認・残作業（優先順）

1. **実画面の残り**: 範囲1回/loopで3–4小節を実際に選び、途中再開で次周が全範囲か確認。詳細の追従で1–2→3–4へ移ること、明示seekと再生位置の一致、読み編集→Undo→保存→再読込を確認。別インスタンスはファイルメニューを開いた状態で中断した。画面操作の対象が更新されるエラーが1回出たので、操作前に最新AX状態を取り直す。
2. **音の実聴**: ツールではスピーカーの出音を聴けない。PCMテストは通るが、音量・途切れ・実デバイスのloopは実聴未確認。実聴できなければ、そのまま未確認と報告する。
3. **コードレビュー**: `GuideTonePlayer`のAVAudioEngine構成変更時cancel、prepare失敗/連続seek/loop切替の状態を点検。macOS 14のスクロールホイールは自動追従OFFにならない可能性がある（15+は検出、前後ボタンは14でもOFF）。鍵盤試聴は短い音をクリックで鳴らす方式で、押下中だけの音ではない。
4. **楽譜の確認**: 休符の字形/付点/16分音符/臨時記号取消/小節をまたぐタイを実画面で確認し、必要なら描画を修正。複数声部・1/16より細かい音価は理由付きピアノロール退避。
5. **UI仕上げ**: 歌唱段のフレーズ全文訳表示、狭幅/文字拡大/スクロールの読みやすさ、鍵盤VoiceOver/focus、日本語入力を確認。既存のReading・NoteEditor・Alignment操作も回帰確認。
6. **SSOT更新と完了**: 変更に応じて本書、SINGING_PRACTICE_PLAN、WORK_LOG、READMEを更新。`git diff --check`、秘密/生成物確認、明示pathだけcommit、origin→github通常push。mainへのmergeはしない。

## 再開コマンド

```sh
cd /Users/ryon/Projects-Inagawa/syllables-finder
git status --short --branch
git fetch origin
git fetch github
native/scripts/swift-tool.sh test
native/scripts/build-app.sh
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python test_vowel_marker.py
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m unittest discover -s tests -v
```

Appleの音声APIはガイド音であり歌声合成ではない。一般的なMIDI/MusicXML import/exportは今回の範囲外。別モデルのCLIを新たに起動する必要はない。
