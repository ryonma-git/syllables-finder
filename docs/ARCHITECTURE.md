# Architecture

依存方向: SingingWorkspace → SongServices → SongCore。SongCore は Foundation のみ。
`native/` は Swift Package。既存 Python アプリと環境・起動経路を分離する。

## 境界

- SongCore: Codable 値型、参照検証、時間、編集 transaction、サンプル。UI/AI SDK 非依存。
- SongServices: AIProvider / LinguisticAnalysisService、候補の検証・保護 merge、I/O adapter 境界。
- SingingWorkspace: SwiftUI DocumentGroup / FileDocument、画面、UndoManager、選択・transport。
- platform adapters: AVFoundation単旋律ガイド音はUI targetに追加済み。CoreMIDI、FoundationModels、Keychain、印刷は後続。

SongDocument だけが曲の SSOT。選択、再生位置、zoom、pane表示、解析中フラグは session state。
FileDocument は package の `document.json` と原資料を所有。package のその他の子要素も保存時に保持する。
SwiftData/ネットワーク/ユーザー設定を曲の正本にしない。

## 編集と非同期

編集は document の copy → mutation → 全体検証 → 一括 commit。
失敗時は原本を保持し理由を表示。ドラッグは終了時に1 undo transaction。
言語分割編集では削除される ID の Alignment を勝手に転用しない。再対応付け候補を提示する。
AI request は revision と対象ID・原文を捕捉する。戻り時に revision が変わった場合は
適用を拒否して再試行を促す。UI から cloud fallback しない。

## 保存・移行

`Song.songproj/document.json` は UTF-8 の versioned Codable。
schemaVersion=1。読み書きとも validate。未知 version は開かず、元ファイルを変更しない。
将来は version decoder → 純粋 migration → validator。バックアップ後に OS の atomic document save。
未知 JSON schema は丸めて読まない。MusicXML 等の未知要素は原資料を別に保持（MUSIC_IO参照）。
package の不明な regular file/directory は保持、symlink は安全性のため拒否する。
添付資料は読み込み時にData/ディレクトリの値型へsnapshotし、background saveとの共有可変状態を避ける。

## 性能と UI

次の実装では [歌唱練習の実装引継ぎ](SINGING_PRACTICE_PLAN.md) に従い、Phrase固定のviewportを小節単位へ置き換える。
SongCoreの純粋な小節投影・TempoMap・PlaybackPlanを、詳細/一覧/ピアノロール/楽譜が共有する。
編集選択・練習範囲・viewport・transportを分け、ページ送りで音声を再開始しない。
音声はバックグラウンドPCM生成とplayer sample clock、nodeのloop予約、generationによるcancel保護で実装する。
初期の音声対応範囲は練習速度で5分以内。長曲の描画/保存は制限せず、長時間の音声streamingは後続。
これらは設計済み・実装前。以下は現行実装の制約。

言語/音楽 lookup は ID ベース。最初は配列で順序を明示。大曲では document revision 単位で index を構築する。
Reading は LazyVGrid、Singing は選択 Phrase のみ表示。全曲の巨大 Canvas は作らない。
初回UIは128拍を超える単一Phraseを表示せず、分割viewportは後続工程。
playhead は派生した時間表示で、document を毎フレーム更新しない。
初回は無音の視覚 transport。単旋律ガイド音の追加後はAVAudioPlayerNodeのsample timeから再生位置を派生し、画面側の独立時計を持たない。

## 根拠

[FileDocument](https://developer.apple.com/documentation/swiftui/filedocument) /
[macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
に従い標準 document lifecycle・メニュー・ウィンドウを利用。
Command Line Tools の Swift 6.4 で build/test できる構成。配布署名・notarization は別工程。
