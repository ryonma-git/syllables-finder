# Implementation plan

設計変更は関連SSOT文書と同じcommitで更新する。今回の実績は WORK_LOG.md。

## 直近の実装

ユーザーの歌唱練習フィードバックを優先し、[SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md) のS1〜S4をSol中で実装する。
小節/再生計画 → 連続音声 → 詳細/一覧/鍵盤 → 五線/発音サンプルと検証の順。
2026-09-27のAstra高では設計・引継ぎまで完了。ユーザーがモデルを切り替えるまで実装は開始しない。
以下の全体ロードマップは保持し、一般MIDI/XML I/Oより今回の練習体験を先に完成させる。

## 全体ロードマップ

| Phase | 成果・次へ進むゲート |
|---|---|
| 0 | repository/branch/origin/既存資産を調査。既存アプリを保持 |
| 1 | 8設計文書。時間/Alignment/保存/AI/UXの矛盾を自己レビュー |
| 2 | SongCoreのversioned domain、validator、編集transaction |
| 3 | 独自sample、Codable/hierarchy/alignment/manual-protection tests |
| 4 | DocumentGroup、package open/save、標準Undo、起動bundle |
| 5 | 日本語Reading、単語詳細編集、全文訳、文字サイズ |
| 6 | Singingの時間軸、メリスマ、選択、視覚transport/loop/tempo |
| 7 | Alignmentの明示編集とUndo、破損参照検査。dragは後続 |
| 8 | basic SMF I/O、MUSIC_IOのtest gate |
| 9 | basic XML I/O、保全layer、MUSIC_IOのtest gate |
| 10 | simple MIDI editorの全操作。初回は音符の数値編集foundationだけ |
| 11 | AIProviderとMock、service保護merge、failure/cancel |
| 12 | Apple FM availability/typed generation実機確認 |
| 13 | Ollama model discovery/structured result実接続 |
| 14 | cloud adapters + Keychain + 明示送信UI |
| 15 | accessibility/実画面/性能/印刷/回帰tests、docs整合 |

2026-09-27に公開GitHubミラーと、伝承曲の音節・音符対応サンプル、サンプル限定MIDI生成、単旋律ガイド音を先行追加した。phase 8の一般的なSMF入出力や、歌声生成は引き続き未実装。

基本の進行順は上表。ユーザー指定の「今夜のDoD」に合わせ、8/9の実装をstretchに留める場合も
境界とテスト要件は先に設計し、10/11のfoundationだけを先行する。実装完了扱いにはしない。

## 初回終了ゲート

Swift build/test、既存指定Python tests、実画面でReading/Singing・編集・Undo・保存/再読込。
未実行/skip/実AI未接続を成功としない。git diffと秘密/生成物を確認し明示pathだけcommit。
canonicalへ通常push。作業branch共有とmain採用を区別する。

## モデルの使い分け

設計/難しい整合性review: GPT-6 Astra 高推論。仕様確定後の通常実装: GPT-6 Sol 中推論。
単純な文言/記録: GPT-6 Luna 低推論。失敗や不確定要素が出たら上位へ戻す。
これは推奨であり実行モデルの自動切替を意味しない。
同じタスクで設計を引き継ぎ、通常の実装と検証はSol中で完了させる。上位への戻し条件は直近の実装引継ぎに記載。
別モデルのCLI/agentへ限定作業を任せる方式は可能だが、引継ぎ・再読込・統合レビューにもトークンを使うため、常に節約になるとは限らない。
現タスクの実行モデルを途中で直接変更する操作は利用できない。自動振分け基盤は今回作らず、モデル変更はユーザーの操作で行う。
この環境のCLI 0.155.1で`-m/--model`と`-c/--config`を確認済み。別実行の例（未実行）:

```sh
codex exec -m gpt-6-sol -c 'model_reasoning_effort="medium"' -C /Users/ryon/Projects-Inagawa/syllables-finder '限定した作業内容'
```

同じ作業ツリーを複数実行が同時に編集する運用は避ける。必要になった時点で作業範囲と引継ぎを決める。
[Codexのモデル・推論設定](https://learn.chatgpt.com/docs/config-file/config-reference) /
[公式のモデル選択基準](https://developers.openai.com/api/docs/guides/model-selection)。
