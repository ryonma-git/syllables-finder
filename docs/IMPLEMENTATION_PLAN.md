# Implementation plan

設計変更は関連SSOT文書と同じcommitで更新する。今回の実績は WORK_LOG.md。

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
これは推奨であり実行モデルの自動切替を意味しない。説明は節目と結果に限定。
[公式のモデル選択基準](https://developers.openai.com/api/docs/guides/model-selection)。
