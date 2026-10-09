# 歌詞から曲ファイルを作るローカルAPI

歌詞を別途用意した後、同じ入力JSONから `.songproj` を生成する入口です。歌詞を探す機能は含めず、入力した文字列を外部サービスへ送信しません。`--ollama` を指定した場合だけ、このMacの `127.0.0.1:11434` にあるOllamaへ入力を渡します。

## 入力

UTF-8 JSONの必須項目は `title`、`sourceLanguage`、`lyrics` です。`sourceNote` と `sectionTitles` は任意です。空行が節の境界になり、`sectionTitles` は段落ごとの見出しを同じ順序・件数で指定します。対応言語はアプリの歌詞入力と同じ10言語です。

```json
{
  "title": "Practice Song",
  "sourceLanguage": "en",
  "lyrics": "Morning sunlight warms the garden.\n\nWe sing together.",
  "sourceNote": "自分で用意した歌詞",
  "sectionTitles": ["第1節", "リフレイン"]
}
```

生成時に原文、節、単語、規則ベースの音節候補を作ります。ローカルOllamaを指定すると、文の訳、単語の意味、各音節のIPAとカタカナ読みも候補として追加します。発音・訳は歌唱版を聞いて確認してください。音符と歌詞・音符の対応は作りません。

## コマンド

```sh
native/scripts/swift-tool.sh build --product SongGenerateTool
native/.build/debug/SongGenerateTool /absolute/path/input.json /absolute/path/Practice.songproj
native/.build/debug/SongGenerateTool /absolute/path/input.json /absolute/path/Practice-annotated.songproj --ollama qwen3.5:9b
```

既存の `.songproj` は上書きしません。途中で解析に失敗した場合も曲ファイルは作成しません。正常終了時は保存先と行・語・音節数をJSONで返します。入力には歌詞本文が含まれるので、Git管理外に置いてください。

## HTTP API

```sh
native/scripts/swift-tool.sh build --product SongGenerateTool
.venv/bin/python native/scripts/song-project-api.py \
  --output-dir /absolute/path/to/existing-output-folder \
  --ollama-model qwen3.5:9b
```

サーバーはこのMacの `127.0.0.1:8765` にだけ待ち受けます。`POST /v1/song-projects` に上記JSONを送ると、作成した曲ファイルのパスと件数をJSONで返します。`fileName` を追加すると保存ファイル名を指定できます（フォルダ名は指定不可）。省略時は曲名から作ります。`GET /health` で待ち受けを確認できます。既存名は HTTP 409 で拒否します。歌詞や出力データをHTTPレスポンスに返したり、ログに残したりしません。

```sh
curl -H 'Content-Type: application/json' \
  --data-binary @/absolute/path/input.json \
  http://127.0.0.1:8765/v1/song-projects
```

このAPIは個人用のローカル処理です。歌詞取得、配信、公開用の認証・権利処理は担当しません。生成した曲ファイルとPDF・Wordは `Documents/SingingWorkspaceExamples` 以下に置き、アプリのコードと内蔵サンプルはGitの作業コピーに置きます。両方の保存先は自動同期されません。
