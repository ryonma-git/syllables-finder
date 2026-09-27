# Claude → ChatGPT（Codex）検証の引継ぎ（2026-09-28）

利用者の依頼: ChatGPTとの設計相談（2026-09-28、利用上限で中断）の意思を引き継ぎ、設計を固めて実装する。
ChatGPT側の作業と混ざらないよう別branchで作業し、ChatGPTが起きた後に「これで良いか」を検証する。
**このbranchは検証待ち。`main`にも `codex/native-singing-foundation` にもmergeしていない。**

## 作業場所と状態

- フォルダ `/Users/ryon/Projects-Inagawa/syllables-finder`、branch `claude/lyrics-melody-alignment`。
- 基点 `1a0af6b`（`codex/native-singing-foundation`）。origin（Inagawa canonical）→ github の順に通常push済み。
- Codexの作業フォルダ `~/.codex/worktrees/53dd/syllables-finder`（branch `codex/score-layout-and-design`、`1a0af6b`のまま clean）には触れていない。
- 旧 `/Users/ryon/Projects/syllables-finder`、Python/Tk本体、内蔵8曲、例外辞書は変更していない（READMEの説明文1か所のみ更新）。

## 何をしたか（commit順）

| commit | 内容 |
|---|---|
| `0e584b1` | 設計: [LYRICS_MELODY_DESIGN.md](LYRICS_MELODY_DESIGN.md)、REQUIREMENTS/DECISIONS/DATA_MODEL/PLAN/README |
| `547b76b` | 楽譜の記譜を譜線間隔基準に作り直し（`StaffEngraving`、`SongNotation`、`ScoreRow`、`SongStaffTool`）。声部と schema v2・v1移行 |
| `2f642e2` | 言語別の音節分割、歌詞入力の言語選択とプレビュー、単語パネルでの区切り修正 |
| `aabe4bd` | 一音符一音節を軸にした割付エンジン、ステップ入力・声部編集のコア |
| `1dd612f` | 画面: ステップ入力（画面鍵盤・CoreMIDI）、声部シート、割付の確認シート |
| `773ea77` | MIDIファイル読込、ピアノロールの歌詞帯を選択声部に絞る |
| この文書のcommit | WORK_LOG、設計の状態表、MUSIC_IO、本書 |

## 検証してほしいこと（優先順）

1. **設計の妥当性**: [LYRICS_MELODY_DESIGN.md](LYRICS_MELODY_DESIGN.md) が相談の合意（実曲対応、MIDI入力ワークフロー、一音符一音節の軸、参考音源、言語の優先順、声部の統合形式）と一致しているか。§12の未決事項。
2. **schema v2 の判断**: `MusicalEvent.partID` 必須化、`Part.phraseIDs` による声部ごとの歌詞順、v1の移行とバックアップ（`preserved/document-v1.json`）。v2文書は旧版アプリでは開けない（既存の未対応版の拒否動作）。
3. **楽譜の見た目（実画面）**: 利用者の指摘「音符が五線から浮いている」が解消したか。サンプルを「歌う」→「楽譜」で一覧/詳細、IPA ON、文字拡大、ダークモード。8分・16分の連桁、休符、臨時記号、タイ、加線。
4. **操作（実画面）**: 歌詞を追加（言語選択・プレビュー）→ 単語パネルで区切り修正 → 旋律をステップ入力（画面鍵盤、可能ならMIDI鍵盤）→ 声部…（混声四部）→ 歌詞を割り当てる… → 適用 → Undo/Redo → 保存・再読込。MIDIファイルを読み込む…（置き換え/追加、クオンタイズ）。
5. **音節分割の規則**: `SyllabificationTests` の期待値が教材として妥当か（特に仏語の語末e、伊語の二重母音、羅語の教会式、英語の分け方）。

Claudeは画面がロックされていたため、4と3の実画面部分は**未確認**。音の実聴・MIDI鍵盤の実機・日本語IMEも未確認。

## 検証コマンド

```sh
cd /Users/ryon/Projects-Inagawa/syllables-finder
git fetch origin && git switch claude/lyrics-melody-alignment
native/scripts/swift-tool.sh test        # 73件（SongCore 66、SongServices 4、SongPrint 1、SongNotation 2）
native/scripts/build-app.sh
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python test_vowel_marker.py
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m unittest discover -s tests -v   # 23件
BIN=$(native/scripts/swift-tool.sh build --show-bin-path)
"$BIN/SongStaffTool" frere /tmp/frere.png          # 楽譜のPNG（twinkle / mary / frere / morning / .songproj）
```

実画面の確認は、以前の引継ぎ（HANDOFF-2026-09-27）どおり別bundle IDの確認用appとサンプルのコピーで行う。
起動引数 `-SingingWorkspaceQA staff`（`roll` / `detail-staff`）で「歌う」＋楽譜表示から開ける。

## 既知の制約・判断の余地

- 横位置は拍比例（ADR010）のまま。速い音符では歌詞を最大60%まで縮めてハイフンを残す。出版譜風の間隔は将来の別投影。
- ドイツ語の複合語境界（feuer-trunken）は推定しない。英語は規則の例外が多く候補扱い。日本語の漢字の読みはmacOSの推定。
- 割付の曖昧さ（例: Morning light のどの音節をのばすか）は規則では決め切れない。人が1か所固定すると前後が再計算される。
- ステップ入力は上書き方式。タイで別音価を足す操作、3連符の入力、リアルタイム録音（L8）、参考音源（L9）、MusicXML・楽譜印刷（L10）は未着手。
- 声部ごとの歌詞順（`Part.phraseIDs`）を編集する画面はまだない（データとテストのみ）。
