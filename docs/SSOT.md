# syllables-finder の作業場所と運用

2026-09-24に、Git管理されていなかったソースのコピーから履歴を開始しました。移行前のソースはそのまま保持しています。

| 役割 | パス |
|---|---|
| 今後のMBP / Ishibashi作業場所 | `/Users/ryon/Projects-Ishibashi/syllables-finder` |
| Inagawaの正本 | `/Users/ryon/Git/remotes/syllables-finder.git` |
| Inagawaの作業場所 | `/Users/ryon/Projects-Inagawa/syllables-finder` |
| 移行前の保管用 | Ishibashi `/Users/ryon/Projects/syllables-finder` |

今後Codexで改修する際は、上記の新しい作業場所をプロジェクトフォルダとして選びます。既に開いているタスクの作業場所が自動で切り替わることは前提にしません。アプリは新しいフォルダ内の `起動.command` をダブルクリックします。元のランチャーを開いた場合は、引き続き移行前のアプリが動きます。

## 日々の流れ

作業開始時にInagawaとの差分を確認し、安全に取り込める更新を取得します。各Macのファイルを編集し、テストしてcommitします。そのcommitをcanonicalへpushして、他のMacが続きを取得できる状態にします。ファイル保存だけ・commitだけではInagawaに反映されません。

基本branchはmainです。同時に複数のMacでmainを進めて分岐した場合は、force pushせず履歴を比較します。コード変更をCodexに依頼した際の開始・終了手順は `AGENTS.md` に記載しています。通信できないときも手元で編集・commitでき、未push分は手元に保持します。

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
