# AI providers

AIProvider は `capabilities` と async `analyze(request)`。UI は provider ID で分岐せず
登録済み provider + capability で選ぶ。model ID を domain の enum に固定しない。
LinguisticAnalysisService は辞書/G2P/手動入力/AI の orchestration。AIProvider と同一視しない。

## DTO と保護

request: document revision、sourceLanguage、Phrase原文、Word ID/surface。
response: WordAnalysis(lemma/品詞/2種類の意味/IPA/読み/音節候補)、Phrase訳。
将来 DTO を MoraAnalysis/PhonemeAnalysis/phoneticFeatures に拡張する。
provider は domain object や UUID を自由に生成して document に直接挿入しない。
service が対象ID・重複・欠落・型・revision を検証し、GeneratedField を保護して一括適用する。
構造を変える分析は差分候補として扱う。今回の文字フィールド再解析は音節を作り直さない。
読みは IPA を経由。読みやすさ優先/原音優先は将来の rendering policy。

## Provider 方針

| Provider | 方針 |
|---|---|
| Mock | ネットワーク不要、決定的fixture。failure/cancel/stale result をテスト |
| Apple Foundation Models | 第一級ローカルprovider。availability確認、@Generable DTO、guided generation。利用不可時は理由を表示 |
| Ollama | /api/tags でモデル列挙、/api/chat の structured response。利用者がモデル選択、stream=falseから開始 |
| OpenAI / Anthropic / xAI / Gemini | 別adapter。共通DTOへ変換。SDKをcoreへ露出させない |
| OpenAI-compatible | baseURL/modelは設定。互換性とcapabilitiesを確認し、全API互換と仮定しない |

capabilities: structuredOutput, streaming, toolCalling, offline, ipaGeneration, translation,
phoneticAnalysis。API機能と品質保証は別。未検証の発音精度を保証しない。
Auto router は将来。MVP は明示 provider 選択。ローカル失敗から有料cloudへ自動切替しない。

## 接続・秘密

初期は Mock。Ollama は loopback のみ、user操作でモデル照会/解析。タイムアウト・接続失敗を表示。
外部endpointは将来の明示設定で有効化する。解析中cancelと並行編集revision検査が必須。
API Keyは Keychain service/account に保存。文書・ログ・fixture・Gitへ入れない。
cloud 呼出前に送信範囲/provider をUIで提示する。unit testは外部APIを呼ばない。

資料: [Apple guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)、
[Ollama models](https://docs.ollama.com/api/tags)、[Ollama chat](https://docs.ollama.com/api/chat)。
Apple FM 実装前には実SDK availabilityと対応言語を確認する。
