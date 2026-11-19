# syllables-finder: SSOT運用

このプロジェクトはユーザーが実際に使っている日本語GUIアプリです。授業で使う動作・表示を保ち、依頼範囲内で変更してください。

## 作業場所と正本

- Ishibashi: `/Users/ryon/Projects-Ishibashi/syllables-finder`
- Inagawa: `/Users/ryon/Projects-Inagawa/syllables-finder`
- canonical: Inagawa `/Users/ryon/Git/remotes/syllables-finder.git`
- 基準branch: `main`。作業branchを使った場合は、共有済みとmainへ採用済みを区別する。
- 元の `/Users/ryon/Projects/syllables-finder` は移行前の保管用。編集、削除、移動、改名、Git初期化をしない。
- originはcanonicalを指す。Ishibashiでは `inagawa:Git/remotes/syllables-finder.git`、Inagawaでは上記のローカル絶対パス。
- GitHub公開リポジトリ `https://github.com/ryonma-git/syllables-finder` はInagawaからの公開ミラー。Inagawaの `github` remoteを使い、canonicalへ通常push後に同じcommitをpushする。IshibashiからGitHubへ直接pushしない。

## 作業の開始

1. 実際の作業フォルダ、branch、未commit状態、originを確認する。
2. canonicalへ到達できる場合はfetchして差分を確認する。作業ツリーがcleanでfast-forward可能な場合のみ最新化する。
3. ローカルの未保存作業や分岐があれば、勝手にstash、reset、rebase、上書きしない。状態を報告して保全する。
4. オフラインなら手元の履歴で進められるが、取得できた最新版の時点と未push状態を明記する。

## 新しいセッションでアプリを開く前に（必須）

2026-11-16のユーザー指示: 古いコミットのアプリを誤って開かないこと。このディレクトリで始める新しいセッションでも、毎回最新版を確認してから起動する。過去の会話にあるcommit IDや既存のビルド成果物を、そのまま最新版として扱わない。

1. 上記の開始手順に加え、Inagawaでは `git fetch origin` と `git fetch github` を行い、`HEAD`・`origin/main`・`github/main` と各作業branchの差分を確認する。Ishibashiのcheckout・未commit変更・作業worktreeもSSHで確認する。接続できない対象があれば、その対象の最新版は未確認と明記する。
2. 通常利用の基準は共有済みの `main`。最新の作業branchがmainに未採用なら、その違いを報告し、勝手に統合しない。cleanな作業ツリーでのみ `git switch main`、必要なら `git merge --ff-only origin/main` を行う。分岐・未commit変更・remote間の不一致を隠して古い版を開かない。
3. アプリ起動前に `native/scripts/build-app.sh` を実行し、そのcheckoutから再ビルドする。アプリ表示の `0.1.0`、フォルダの更新日時、既に起動中であることだけでは版を判定しない。
4. 起動先は作業場所を明示した `native/build/Singing Workspace.app`。Inagawaでは `/Users/ryon/Projects-Inagawa/syllables-finder/native/build/Singing Workspace.app`。アプリ名やbundle IDだけで選択すると別worktreeの旧版に接続し得るため、必ず絶対パスで選択する。既存プロセスはビルドし直しても更新されないので、旧プロセスの文書を保存して終了し、新しいプロセスを起動する。
5. 起動後に実行ファイルのパスと対象文書の画面を確認し、確認したcommit IDを報告する。未保存文書はGit外へ退避保存する。強制終了や「削除して終了」で消さない。

`syllables-finder-class-materials`、`syllables-finder-claude`、`.codex/worktrees/53dd/syllables-finder` は通常利用の起動先にしない。履歴調査で参照しても、明示的な依頼なしに古いアプリを再ビルド・起動しない。commit IDを名前に付けた一時的な `.app` の複製も常用しない。

### songprojと教材出力

- 「いつもの仕様」「いつもの形」「いつもの形式」「いつもの歌唱教材」は [docs/USUAL_LYRICS_SPEC.md](docs/USUAL_LYRICS_SPEC.md) の最新版を指す。生成前に必ず読み、今回の明示指示を優先する。発音・読み切替・表示・出力の仕様を変更した場合、またはユーザーが継続的な希望を更新した場合は、同じ作業で同文書と変更履歴を更新し、両Macが共有するGit履歴へ反映する。
- ユーザーの `.songproj` を上記で確認したアプリで開き、歌詞・読み・意味を確認してから出力する。
- 保存済み `.songproj` のPDF・Word出力には同じcheckoutからビルドした `SongPrintTool`、またはアプリの共有メニューを使う。出力する表示順・デザイン・色をアプリ設定と合わせる。独自に別レイアウトのPDFを作成しない。
- 各フレーズの通しの原文を、音節色付けの単語欄とは別に出力する。読みは単語単体だけでなく、行の文脈でリエゾン・連音も確認する。音源を確認していない場合は歌手の実演と一致すると断定しない。
- `SongPrintTool` のパスは `native/scripts/swift-tool.sh build --show-bin-path` で取得する。`SongPrintTool /absolute/input.songproj /absolute/output.pdf` が既存の出力経路。HTTP APIは歌詞からのプロジェクト生成用であり、PDF出力APIと混同しない（`docs/SONG_GENERATION_API.md`）。
- 起動・版確認の詳細は `docs/SSOT.md` を参照する。

## 作業の終了

コード変更を依頼された作業では、ユーザーがcommit/pushを控えるよう指定していない限り、適切な検証、変更内容のレビュー、明示したファイルだけのcommit、canonicalとGitHubへの通常pushまでを一連のSSOT作業として扱う。読み取り・説明だけの依頼ではcommitしない。

push前に変更対象と履歴を確認し、生成文書・入力テキスト・個人情報・秘密情報・巨大データを含めない。自分の変更以外をまとめてcommitしない。push失敗時はforceで通さず、ローカルcommitを保持して原因を報告する。push先とcommit IDを最終報告に残す。

## 検証

既存の `.venv/bin/python` を使う。環境がなければ `docs/SSOT.md` の専用環境の手順に従い、既存ソースの仮想環境やシステムPythonの設定は変更しない。

```sh
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python test_vowel_marker.py
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m unittest discover -s tests -v
```

GUI smoke testにはTkを利用できるmacOSユーザーセッションが必要。GUI未実行やskipは成功として報告しない。GUI変更時には日本語表示・入力・プレビュー・Word出力も実画面で確認する。

## Git外に置くもの

`.venv`、キャッシュ、`.ui_state.json`、生成docx、授業入力データ、個人情報、`.env`、credentials、モデル、大容量データはGit外。`.gitignore`だけで秘密検査の代わりにしない。例外辞書や内蔵曲の編集は依頼がある場合に限定する。

削除やforce pushによる復旧は禁止。移行前のソースを使って戻す場合も、新cloneの作業はそのまま保持し、差分と再開する場所を記録する。
