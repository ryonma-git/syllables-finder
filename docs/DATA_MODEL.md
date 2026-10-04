# Data model

## 言語

SongDocument.metadata + Section(phraseIDs) → Phrase(wordIDs, translation, optional timeRange)
→ Word(surface, lemma, partOfSpeech, contextualMeaning, dictionaryMeaning, notes, syllableIDs)
→ Syllable(text, ipa, reading, stress, moraIDs, phonemeIDs)。
Mora は parentSyllableID、Phoneme は必須 parentSyllableID + optional parentMoraID。
Syllable.phonemeIDs はモーラ経由も含む全音素を順序保持。Mora.phonemeIDs はその部分集合。
直接音素とモーラ所属音素が同一音節内に混在してよい。空の階層を強制生成しない。

すべて stable UUID。親側 ordered IDs と子側 parent ID の整合性を validator で確認する。
原文・句読点・空白は Phrase.originalText が保持。単語列の単純 join で原文を再構築しない。
将来 token source spans は Unicode scalar offset と原文 revision の組で導入する。

GeneratedField<Value>: value, source(kind/provider/modelの出所), userEdited。
手修正で source=manual, userEdited=true。再解析ではこのフィールドを保持。
分割配列には別の structureUserEdited フラグを設け、構造候補の適用は後続フェーズとする。
IPA・読み・意味の未生成は空値として表示上「未設定」。AI が返した値は正解保証しない。

SongMetadata.ninthPronunciation は optional（nil/standard は標準、stage は劇ドイツ語）。
旧文書ではキー欠落を許容。第九サンプルの既知ID・綴り・未編集のIPA/読みの組だけを
プリセット間で置換し、標準への復帰は原データと一致する。変更は通常の文書編集として保存・Undo対象。
意味の上下配置は文書には保存せず、WorkspaceSession と PrintSheet の MeaningPlacement に保持する。

## 音楽

Music: measures, events, tempos, meters, sections/phrases(MusicSpan)。
MusicalEvent は共通 id/onset/duration/measureID、payload=note(NoteData) または rest。
NoteData: MIDI pitch/velocity/channel/track、任意の notation(spelling/voice/part/tieGroupID)。
Note の拍位置は onset − measure.start の派生値。矛盾する beat を二重保存しない。
MusicSpan は音楽のみの Section/Phrase。言語 Phrase と同じオブジェクトにしない。

## 声部（schemaVersion 2、[LYRICS_MELODY_DESIGN.md](LYRICS_MELODY_DESIGN.md) §4）

Music.parts: Part(id, name, abbreviation, clef[treble/treble8vb/bass], phraseIDs?)。
MusicalEvent.partID は v2 で必須、存在する Part を参照。音符があれば Part は1つ以上。
Part.phraseIDs はその声部が歌う Phrase の順序（繰返し可、nil は全 Phrase を文書順）。
Phrase.language は行ごとの言語（nil は metadata.sourceLanguage）。FieldSource に rule（規則による候補）を追加。
v1 は読み込み時に移行し、保存時に元 JSON を `preserved/document-v1.json` に残す。

## 時間

canonical は四分音符単位の有理数 Beat(numerator/denominator)、既約・非負・分母正。
MIDI tick/PPQ と MusicXML duration/divisions を正確に変換でき、三連符も丸めない。
実装の整数上限は各成分 10^9。範囲外は明示エラー（overflow や silent clamp を避ける）。
Double は画面/時計だけ。seconds は tempo map から導出し、曲時間の正本にしない。
MIDI 原 tick/PPQ・SMPTE division は原資料 metadata に保持。SMPTE は別 adapter 対応まで import 拒否。
TimeRange は [start,end) で正の長さ。Event onset/duration から範囲を導出。
tempo は beat 位置 + BPM、meter は beat 位置 + numerator/denominator。

## Alignment

独立レコード: id, languageTargets([kind,id]), musicTargets([eventID または timeRange]),
relation(oneToOne/syllabic/melisma/tie/elision/manual), userEdited。
音符内部は eventID + optional relative TimeRange。relative は音符 onset からの拍数。
oneToOne だけ1対1を強制。他は多対多。tie は同音を持続する音楽構造、melisma は1音節を複数音符へ。
音楽上の tie は notation にも保持し、Alignment の関係だけで音符を結合しない。

## 不変条件

- 全 entity ID は一意、すべての参照先が存在。ordered IDs に重複なし。
- Word は Phrase に、Syllable は Word に、Mora/Phoneme は Syllable に一意所属。
- parentMoraID があれば mora と phoneme の parentSyllableID が同じ。
- 音符 pitch 0…127、velocity 1…127、channel 0…15、track 非負。
- onset >= 0、duration > 0、tempo > 0、meter 正で分母は2のべき乗。
- event relative range は event.duration 内。削除は参照も同一 transaction で修復。
- Phrase timeRange は練習範囲。note 移動で範囲外になる場合は明示的に広げるか拒否。

Codable round-trip・破損参照・不正数値・将来 version・混在階層・many-to-many をテストする。
