# syllables-finder: SSOT運用

このプロジェクトはユーザーが実際に使っている日本語GUIアプリです。授業で使う動作・表示を保ち、依頼範囲内で変更してください。

## 作業場所と正本

- Ishibashi: `/Users/ryon/Projects-Ishibashi/syllables-finder`
- Inagawa: `/Users/ryon/Projects-Inagawa/syllables-finder`
- canonical: Inagawa `/Users/ryon/Git/remotes/syllables-finder.git`
- 基準branch: `main`。作業branchを使った場合は、共有済みとmainへ採用済みを区別する。
- 元の `/Users/ryon/Projects/syllables-finder` は移行前の保管用。編集、削除、移動、改名、Git初期化をしない。
- originはcanonicalを指す。Ishibashiでは `inagawa:Git/remotes/syllables-finder.git`、Inagawaでは上記のローカル絶対パス。GitHubへ送らない。

## 作業の開始

1. 実際の作業フォルダ、branch、未commit状態、originを確認する。
2. canonicalへ到達できる場合はfetchして差分を確認する。作業ツリーがcleanでfast-forward可能な場合のみ最新化する。
3. ローカルの未保存作業や分岐があれば、勝手にstash、reset、rebase、上書きしない。状態を報告して保全する。
4. オフラインなら手元の履歴で進められるが、取得できた最新版の時点と未push状態を明記する。

## 作業の終了

コード変更を依頼された作業では、ユーザーがcommit/pushを控えるよう指定していない限り、適切な検証、変更内容のレビュー、明示したファイルだけのcommit、canonicalへの通常pushまでを一連のSSOT作業として扱う。読み取り・説明だけの依頼ではcommitしない。

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
