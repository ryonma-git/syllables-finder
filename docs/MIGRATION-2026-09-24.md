# SSOT移行・検証記録（2026-09-24）

## 対象と保全

- ユーザーから `syllables-finder` の慎重な移行と一貫した検証の依頼を受けて実施。
- 元の `/Users/ryon/Projects/syllables-finder` はGit未初期化だったため、レビューした直下9ファイルのコピーから新しい履歴を開始。
- 元の9ファイルと最初のcommit `10b04cb6dfffc0eca021e474261c9c8c41e94209` の内容をSHA-256で照合。
- `.venv`、キャッシュ、`.DS_Store`を取り込まず、既存フォルダや既存環境に書き込まない。
- 初期の運用文書・テスト追加commit: `8c9118fe60e44e68c223b803b0df62ce9dbaf8dc`。

## 変更の内容

アプリ本体、母音判定、例外辞書110語、内蔵8曲、Word出力、既存ランチャーと既存テストは元のバイト列を保持。READMEのMBP用作業パスを更新し、`.gitignore`、固定依存版、`AGENTS.md`、SSOT手順書、回帰テストを追加した。

## 実行環境

| 項目 | Ishibashi | Inagawa |
|---|---|---|
| Python | 3.14.6 | 3.14.7 |
| Tk | 9.0 | 9.0 |
| python-docx | 1.2.0 | 1.2.0 |
| lxml | 6.1.1 | 6.1.1 |
| typing_extensions | 4.15.0 | 4.15.0 |

各Macの既存Homebrew Pythonから新しいclone内だけに専用 `.venv` を作成し、固定した3パッケージをPyPIから取得した。OS全体へのインストール、Python/Tkの更新、sudo、ネットワーク設定変更は行っていない。

## 検証結果

- 移行前の母音判定12例: PASS。
- Ishibashiの独立環境: 既存12例、追加11テスト、依存整合性チェックにPASS。
- Inagawaの独立環境: 同じ検証にPASS。
- 追加11テストはWordの色・フォント・サイズ・改行・空行・日本語、母音オプション、GUIの入力・ライブラリ選択・不正サイズ・空入力・保存・キャンセル・表示状態を確認。
- 自動GUIテストは実際のTk widgetsとcallbacksを使い、保存ダイアログと通知だけを置き換える。個人データを使わず、一時フォルダで合成文書を生成。
- MBPで新cloneの `起動.command` から実アプリを起動し、日本語画面を確認。

## 確認の限界

画面操作ツールではTkウインドウの表示を取得できたものの、クリック・文字入力が反映されず、実画面を操作してのWord保存は未検証。Inagawaの画面を遠隔で目視する検証、Finderからのダブルクリック、Microsoft Wordでの表示、物理的に回線を切断する検証は行っていない。これらを自動テストのPASSに含めない。

Codexのプロジェクト一覧への追加は未実施。利用可能なアプリ操作ツールがCodex自身の操作を禁止しているため、その制限を迂回して設定ファイルを書き換えない。今後の作業場所として `/Users/ryon/Projects-Ishibashi/syllables-finder` を選ぶ。

## 同期・復旧

この文書をMBPの新cloneでcommitしてcanonicalへpushし、Inagawaの新cloneへfast-forwardで取り込む。その後Inagawaから引継ぎ記録を通常pushし、MBPで取り込む往復検証を行う。最終結果と3地点のcommit IDはInagawa `~/Ops/ssot/migrations/syllables-finder` の記録に保存する。

問題があれば新しい変更を保持したまま、元フォルダのランチャーで移行前のアプリを利用できる。元フォルダへの上書き、削除、force push、履歴巻戻しは行わない。mini2018への世代バックアップは未構成。
