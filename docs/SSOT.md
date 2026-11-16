# syllables-finder の作業場所と運用

2026-09-24に、Git管理されていなかったソースのコピーから履歴を開始しました。移行前のソースはそのまま保持しています。

| 役割 | パス |
|---|---|
| 今後のMBP / Ishibashi作業場所 | `/Users/ryon/Projects-Ishibashi/syllables-finder` |
| Inagawaの正本 | `/Users/ryon/Git/remotes/syllables-finder.git` |
| Inagawaの作業場所 | `/Users/ryon/Projects-Inagawa/syllables-finder` |
| 公開GitHubミラー | `https://github.com/ryonma-git/syllables-finder` |
| 移行前の保管用 | Ishibashi `/Users/ryon/Projects/syllables-finder` |

今後Codexで改修する際は、上記の新しい作業場所をプロジェクトフォルダとして選びます。既に開いているタスクの作業場所が自動で切り替わることは前提にしません。現在の歌唱練習アプリはSwift版の **Singing Workspace** です。最新版を確認したうえで `native/新アプリを起動.command` を使います。ルートの `起動.command` は従来のPython版専用です。

## 新しいセッションでの最新版確認と起動

2026-11-16に、古いworktreeのアプリを開いてしまう問題がありました。以後、`AGENTS.md` の「新しいセッションでアプリを開く前に」を毎回実行します。ユーザーが別の版を指定しない限り、通常利用は共有済みのmainを基準にします。

Inagawaでは作業ツリーを確認し、canonicalとGitHubの両方をfetchします。Ishibashiのcheckoutと未commit作業も確認します。mainが一致していても、別branchの未採用作業と区別してください。確認先に到達できない場合は、その範囲を明示します。

```sh
git status --short --branch
git fetch origin
git fetch github
git rev-parse HEAD origin/main github/main
git worktree list
ssh Ishibashi 'git -C /Users/ryon/Projects-Ishibashi/syllables-finder status --short --branch; git -C /Users/ryon/Projects-Ishibashi/syllables-finder rev-parse HEAD; git -C /Users/ryon/Projects-Ishibashi/syllables-finder worktree list'
```

他のworktreeの未commit状態も個別に確認します。cleanで安全に切り替えられる場合だけmainへ切り替え、更新はfast-forward限定です。分岐や未保存作業をstash/resetで隠して進めないでください。

```sh
git switch main
git merge --ff-only origin/main
native/scripts/build-app.sh
```

起動先はこのcheckoutの `native/build/Singing Workspace.app` の絶対パスです。同じ名前・bundle IDを持つアプリが複数あるため、名前だけで開かないでください。ビルド前から動いているプロセスは古いままなので、未保存文書を保存して終了し、再起動してから実行パスと文書画面を確認します。

`native/新アプリを起動.command` はビルドと起動を行いますが、Gitのfetch・更新・既存プロセスの終了は行いません。先に上記の確認を済ませてください。アプリの表示バージョン `0.1.0` は複数のcommitで共通なので、版の根拠には使えません。

通常利用から除外する旧worktreeは、Inagawaの `syllables-finder-class-materials`、`syllables-finder-claude`、`.codex/worktrees/53dd/syllables-finder` です。これらの生成済みアプリ3個は2026-11-16にゴミ箱へ移しました。未保存文書はInagawaの `~/Documents/SingingWorkspaceRecovery-2026-11-16` に保存しました。ソースとGit履歴は調査用に保持し、ユーザーの明示的な依頼なしに古いアプリを再生成しません。

教材は `.songproj` を最新版で開き、アプリの共有メニューまたは同じ版の `SongPrintTool` で出力します。表示順・デザイン・色も合わせます。既存ビルドの使い回しや独自PDFレイアウトへの置き換えをしません。

```sh
binary_dir="$(native/scripts/swift-tool.sh build --show-bin-path)"
"$binary_dir/SongPrintTool" /absolute/input.songproj /absolute/output.pdf
```

2026-11-16の整理時点では、アプリソースの基準は `5d76d60` で、GitHub main・canonical main・Ishibashiのcheckoutが一致していました。この値は当日の記録であり、以後は毎回fetchして確認します。

## 日々の流れ

作業開始時にInagawaとの差分を確認し、安全に取り込める更新を取得します。各Macのファイルを編集し、テストしてcommitします。そのcommitをcanonicalへpushして、他のMacが続きを取得できる状態にします。ファイル保存だけ・commitだけではInagawaに反映されません。

基本branchはmainです。同時に複数のMacでmainを進めて分岐した場合は、force pushせず履歴を比較します。コード変更をCodexに依頼した際の開始・終了手順は `AGENTS.md` に記載しています。通信できないときも手元で編集・commitでき、未push分は手元に保持します。

2026-09-27からGitHubを公開ミラーに追加しました。`origin`は従来のcanonical、Inagawaの`github` remoteがGitHubを指します。Inagawaの作業コピーで検証・commitし、まずcanonicalへ通常push、同じcommitをGitHubへ通常pushします。作業branchを共有しただけの場合は、`main`に採用されたとは報告しません。

## 専用実行環境

PythonとTkは各Macの既存環境を使用し、`.venv`は各作業コピーに別々に用意します。`.venv`をGitへ入れたり、元プロジェクトの環境を移動したりしません。検証用に依存版を `requirements-lock.txt` へ記録しました。

新しいMacやcloneで環境を再作成するときは、そのclone内で次を実行します。既存の `.venv` がある場合は上書きせず状態を確認してください。以下はApple Silicon MacのHomebrew Pythonを利用する例です。

```sh
/opt/homebrew/bin/python3 -m venv .venv
.venv/bin/python -m pip install --requirement requirements-lock.txt
.venv/bin/python -c 'import tkinter, docx; print(tkinter.TkVersion)'
```

Python 3.14 / Tk 9環境での検証を基準にしています。OSのPython入替、HomebrewやTkの新規インストール、管理者権限を伴う変更はこの手順に含みません。

`起動.command` は、`.venv`がない場合に従来どおり初回セットアップを行います。2026-09-25にPDF出力を追加したため、既存の`.venv`にreportlabが無い場合は起動時に追加で入れます（通信が必要）。再現性を優先する場合は先に上記の固定版環境を用意してください。

## 検証とデータ

```sh
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python test_vowel_marker.py
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m unittest discover -s tests -v
```

既存の母音判定12例に加え、Word出力の色・フォント・改行・日本語保持・デザイン（A4、見出し帯、ページ番号、連ごとの縦線）、PDF出力（ページ割り・折り返し・フォント代用）、GUIのプレビュー・曲選択・入力エラー・Word/PDF生成の回帰テストを実行します。テストは合成テキストと一時フォルダを使い、ユーザーの教材を読み込みません。自動GUIテストは実際のTk widgetsとcallbacksを使いますが、保存ダイアログと通知は置き換えるため、実画面の操作確認とは分けて記録します。

生成docx・入力テキスト・`.ui_state.json`・個人情報・秘密情報は各Macに残すGit外データです。個人情報や授業データを正本へ送らないでください。内蔵8曲・例外辞書110語・アプリ本体は移行前の内容を保持しています。

## 問題が出た場合

新しい作業コピーを保持したまま、元の `/Users/ryon/Projects/syllables-finder/起動.command` で移行前のアプリを使えます。新しい変更があればcommit IDと未commit状態を記録し、元フォルダへ上書きコピーしません。canonicalやcloneを削除・再初期化したり、履歴を巻き戻すpushをしないでください。

mini2018への世代バックアップはまだ未構成です。二台のGitコピーは履歴の共有用で、Git外の生成文書や未push作業のバックアップを代替しません。移行・検証の詳細記録はInagawa `~/Ops/ssot/migrations/syllables-finder` に保存します。
