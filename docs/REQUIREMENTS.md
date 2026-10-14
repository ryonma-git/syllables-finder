# 歌唱発音ワークスペース — 要件 SSOT

更新: 2026-09-27。実装状況は WORK_LOG.md、判断は DECISIONS.md を参照。
開発名は **Singing Workspace**。正式名称は未決定。

## 目的と境界

歌詞の意味・発音を理解し、楽曲のどこで発音するかを練習する macOS-first の
Language-first Musical Workspace。Reading / Singing は同じ SongDocument の表示。
対象は伝承曲に限らず**利用者が実際に歌う曲**。歌詞・MIDI・音源は利用者が権利処理済みのものを用意し、その Mac の文書内にだけ保存する（2026-09-28、[LYRICS_MELODY_DESIGN.md](LYRICS_MELODY_DESIGN.md)）。
音程採点、歌唱生成、本格 DAW/楽譜編集、SNS、同期、共同編集、アカウントは対象外。
参考音源の解析は割付の手がかりとしてのみ後続で扱う（採点ではない）。
既存 Python/Tk 教材アプリは独立して継続利用できること。

## 要件と受入条件

| ID | 要件 | 受入条件 |
|---|---|---|
| R01 | 言語中心の階層 | Section/Phrase/Word/Syllable/Mora/Phoneme。音素の直接所属・モーラ経由・混在を保存できる |
| R02 | 意味・訳・発音 | 文脈訳と辞書義、Phrase 全文訳は別フィールド。IPA/読み/強勢/lemma/品詞/補足を保持 |
| R03 | 音楽の独立 | Note/Rest/Measure/Tempo/Meter と音楽側 Section/Phrase の範囲を言語から分離 |
| R04 | 対応付け | Word/Syllable/Mora/Phoneme と Event/TimeRange の多対多。メリスマ、タイ、エリジオンを区別 |
| R05 | Reading | 日本語の意味、原文、IPA、読み、音節、全文訳。詳細を段階表示。編集値を保存 |
| R06 | Singing | 約2小節の詳細と複数小節の一覧。小節/拍に比例した共通時間軸、鍵盤付きピアノロール/楽譜、音名/読み表示。曲通し/範囲1回/範囲loop、tempo、playhead、連続追従 |
| R07 | 編集 | 言語情報・音符・対応付けに Undo/Redo。人の修正は再解析で保護。分割変更は明示的な差分適用 |
| R08 | MIDI | 最終 MVP は SMF import/export、追加/削除/pitch/onset/duration/velocity/複数選択/コピー/移動/quantize/track/channel/tempo |
| R09 | MusicXML | 最終 MVP は import/export。lyric/syllabic/extend/tie/measure/voice/part/tempo/meter。未知情報を保全 |
| R10 | AI | capabilities を備えた provider abstraction、Mock、Apple FM、Ollama、交換可能な cloud adapters |
| R11 | 安全な生成 | 明示操作で解析。cloud の自動呼出し禁止。鍵は Keychain、文書に入れない。failure/cancel は編集を破壊しない |
| R12 | 永続化 | versioned Codable package、保存/再読込、future schema 拒否、参照整合性検証、source 資料保持 |
| R13 | 再生・出力 | MIDI ガイド音、Word/Syllable/Phrase の音声、A4 interlinear 教材。歌唱生成はしない |
| R14 | 品質 | macOS 標準操作、VoiceOver、キーボード、文字拡大、十分なコントラスト、必要範囲だけ描画 |
| R15 | 音節分割 | 歌詞入力時に言語別の規則で音節候補を作る。独・西・仏→伊・羅・露→英・日・韓（中は試験的）。未対応言語でも手動で区切れる |
| R16 | 声部 | 1文書に複数声部。共通の小節・拍で同期。単声は声部1つ。声部ごとの書出し/取込み |
| R17 | 割付 | 一音符一音節を基本仮説に、タイ・メリスマ・エリジオンを候補化。人の確定を保護し前後だけ再計算 |
| R18 | 旋律入力 | MIDI鍵盤/画面鍵盤のステップ入力、SMF読込。リアルタイム録音・クオンタイズは後続 |
| R19 | 楽譜 | 譜線間隔を基準にした記譜（符頭・符幹・旗/連桁・加線・臨時記号・休符・小節線・音部/拍子・歌詞）。複数声部は段で表示 |
| R20 | 参考音源 | 原曲・自分の歌唱・部分の歌い直しを割付の手がかりにする（後続） |

## 次の実装範囲（2026-09-28）

R15〜R20 の設計と段階（L1〜L10）は [LYRICS_MELODY_DESIGN.md](LYRICS_MELODY_DESIGN.md)。
作業branch `claude/lyrics-melody-alignment`。以下は前回までの範囲の記録。

## 前回の実装範囲（設計済み）

R02/R05/R06/R13の歌唱練習を [SINGING_PRACTICE_PLAN.md](SINGING_PRACTICE_PLAN.md) に具体化した。
一般的な楽譜編集ではなく単旋律の練習用五線表示。画面内鍵盤、カタカナ読み、曲通し再生を実装する。
詳細/一覧と再生範囲を独立させる。初期の音声生成は練習速度で5分以内、五線譜の対応範囲外は理由付きピアノロール表示。
schema変更や既存文書の自動補完は行わない。次の実装担当はSol中、受入条件はリンク先に記載。

## 初回の到達点と将来 MVP

今回の最低到達点は build、設計8文書、基礎ドメイン/サンプル/tests、動く Reading、
Singing の対応表示、transport の視覚動作、簡易音符編集の基礎、AI protocol/Mock。
保存・Undo まで通る vertical slice を優先する。外部 I/O・実音再生・印刷・実 AI 接続は
stretch とし、完成 MVP の必須要件から削除しない。未対応操作を動くボタンで偽装しない。

対象 macOS 14+ / Swift 6。Apple FM は利用できる OS/端末でのみ有効にする。
iPadOS は今回は build 対象外。core と services に SwiftUI/AppKit 依存を入れない。

## サンプル

新規作成の短文「Morning light, softly glow.」と単純な音列を使用。
独立した日本語「ひかり」の例でモーラ構造も検証。授業入力・既存楽曲の転載は**内蔵サンプル・テストには**追加しない（利用者が自分の文書で扱うのは可）。
追加済みの「Twinkle, Twinkle, Little Star」は12小節・42音の伝承曲サンプル（ADR009）。次の実装でIPA/読みを補う。

## 調査した既存資産

基点 9eeeda9（sheet-design-pdf、origin と一致）。main=e0b1410 より1 commit進む。
21 tracked files、Python本体/テスト 2,109行。依存は Tk、python-docx、reportlab。

| ファイル群 | 評価・再利用 |
|---|---|
| app.py / 起動.command | Tk 画面・ローカル設定・出力処理。既存経路を保持。SwiftUI に直接移植しない |
| vowel_marker.py / exception_dictionary.py | 綴りの母音核ハイライト。IPA/音節エンジンではない。既存回帰例と教育上の意味を継承 |
| docx_writer.py / pdf_writer.py / sheet_design.py | A4・日本語保持・母音だけ赤の原則を再利用。新言語データの interlinear 出力は別 renderer が必要 |
| pd_songs.py | 既存8曲を保持。新アプリへ自動コピーしない |
| tests / test_vowel_marker.py | 既存機能保全の回帰検証として継続 |
| docs/SSOT.md 等 | canonical 運用を維持。生成物・文書内容は Git 外 |

調査時の旧Python版には曲の永続モデル、IPA、音節分割、MIDI/XML、Undo、AI は存在しない。
綴り範囲を音素と見なすと誤るため、旧ロジックと新モデルの意味を混同しない。
