# AI providers

## OpenAIで音節・発音を解析する

1. 「AI接続」で「OpenAIを優先する」を選ぶ。初期モデルは `gpt-6.2-sol`、接続方式は Responses API。
2. OpenAIのプロジェクトキーを入力し、「このAPIへの歌詞送信を許可する」を選ぶ。権限を限定する場合は Responses の Write を許可する。「APIの応答をテスト」で接続を確認して「設定を保存」を押す。
3. 「歌詞を追加」で「音節に分ける」を選ぶ。入力中は端末の仮区切りを表示し、追加後に行の原文をもとに音節、IPA、カタカナを解析する。保存済みの曲は「読む」の「OpenAIで音節・発音を解析」から実行できる。手直しした発音や音符との対応を保護し、整合しない候補は「保留の理由」で確認できる。

配布先では各利用者が自分のキーを登録する。クレジットはキーを発行したAPI組織に計上される。対象のChatGPTプランの特典は、有効化した組織のプロジェクトで利用できる。各Macのキーチェーンに登録したキーを優先し、公式URLに限りアプリ起動時の環境変数 `OPENAI_API_KEY` も利用できる。[特典の条件](https://help.openai.com/en/articles/20001626-api-credits-benefit-for-eligible-chatgpt-subscriptions)・[モデル料金](https://developers.openai.com/api/docs/models/gpt-6.2-sol)

## 現行実装（2026-11-18）

- 「辞書のみ」は通常の意味・発音補完でAIの探索・生成を行わない。
- 「自動」「ローカルLLM優先」「API優先」は利用できるproviderを設定に従って並べ、未設定項目の候補を作る。Apple Foundation Modelsは対応OS・端末で利用可能な場合のみ候補になる。自動の意味補完では利用可能なQwen 3.5を優先する。
- 外部APIは初期状態で無効。送信を許可した接続先・モデル・キーが揃った場合だけ候補に加える。公式OpenAIのプリセットは `store: false` で呼び出す。既存のChat Completions設定も利用できる。自動切替先もこの許可条件を満たすものに限る。HTTPSを必須とし、loopbackのみHTTPを許可。リダイレクトは拒否する。
- Ollamaのloopback接続は端末内実行の保証ではない。`/api/tags`と`/api/show`の実行先・重み情報で端末内モデルを確認し、生成直前にも再確認する。明示的なクラウド名、remoteモデル、情報不足のモデルを除外し、除外件数を接続画面に表示する。Ollama Cloudはこの経路では使わず、外部AIは許可済みAPI経路で扱う。確認にはモデル名だけを送り、歌詞は送らない。
- 辞書の同綴異音語は子音や強勢も含めて候補差を判定し、自動的に一つの読みを完成扱いにしない。旧辞書生成の曖昧な発音は再点検対象へ戻す。手修正と文脈を使ったAI候補は保護する。
- APIキーは文書・UserDefaults・ログに保存しない。実サービスの品質や通信をunit testで保証せず、通信を使わないfixtureで送信境界・失敗・手修正保護を検証する。

以降は共通設計と拡張方針。実装済みproviderと将来adapterを区別する。

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
現行routerは上記の設定と許可条件を使う。未許可の外部サービスへのfallbackは禁止する。

## 接続・秘密

Mockはテスト・明示的な試用に使用する。Ollamaはloopbackで、端末内実行の確認を経て照会/解析する。タイムアウト・接続失敗を表示。
外部endpointは明示設定と送信許可で有効化する。解析中cancelと並行編集revision検査が必須。
API Keyは Keychain service/account に保存。文書・ログ・fixture・Gitへ入れない。
cloud 呼出前に送信範囲/provider をUIで提示する。unit testは外部APIを呼ばない。

資料: [Apple guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)、
[Ollama models](https://docs.ollama.com/api/tags)、[Ollama chat](https://docs.ollama.com/api/chat)。
Apple FMは実行時availabilityを確認する。機種・言語ごとの候補品質は実機で検証する。
