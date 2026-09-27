# Music I/O

MIDI/XML 双方向は完成MVPの要件。初回 vertical slice の保存形式は songproj のみ。
2026-09-27のきらきら星サンプルでは、文書内の単旋律からSMF format 0を生成して`source/Twinkle.mid`へ添付する。任意ファイルのMIDI import/exportはまだ実装していない。
import/export未実装を「対応」と表示しない。adapter は SongCore を返す。

## MIDI

SMF type 0/1、PPQ時間を最初の対象。type 2/SMPTE は実装まで理由付きで拒否。
tick/PPQ → Beat。有効なnote-on/offをtrack/channel/pitchで対応付け、velocity=0 はoff。
同音重複はqueueで対応し、未対offは診断。tempo/meterをglobal mapに変換。
meta/SysEx/control/program/lyrics と元track orderは preserved source 側に残す。
export PPQは元PPQを優先し、全Beatを表現できなければLCMを上限32767内で選ぶ。
表現不可能なら丸めの警告と明示選択。黙って timing を変えない。
同tickでoff→on順を定め、track/channel/velocity/tempoを保持する。
MIDI歌詞metaでは一般の多対多・音素内rangeを完全表現できない。songprojをlosslessの正本にする。

## MusicXML

最初は score-partwise .musicxml/.xml。.mxl は安全なarchive展開adapterの後に追加。
divisionsごとのrational変換、backup/forward/chord、part/voice、休符、拍子/tempoを扱う。
lyric number/verseを識別し、syllabic(begin/middle/end/single)とextendでAlignmentを構築。
tie(sound) と tied(notation) は区別。tieをmelismaと同一視しない。
音節が欠けたnoteに勝手に語を生成しない。曖昧な割当は候補としてユーザーへ提示。

## 保全レイヤー

`preserved/` に原ファイルbyte列、source locator→stable entity ID map、import診断を保存。
意味モデルは理解した要素だけ。未変更exportは原byteを返せる構造を目指す。
編集時は元treeの該当要素のみpatch。参照が失われた場合は無理にlosslessとせず警告し、
「簡略書き出し」と「原資料」の別出力を用意。namespace/未知属性/順序を保持する。
単にsourceを保管しただけで編集後round-trip preservation完成とは見なさない。
外部entity/DTD解決は禁止。サイズ/深さ/archive path traversal/zip bomb制限を設ける。

## 再生と将来

guide音はAVFoundation/AudioToolbox adapter。tempo map → audio host clock、Pause/Stop/Loopで
all-notes-offを保証。画面timerを音源scheduleに使わない。
Live MIDI/CoreMIDI、virtual port、clock/syncは別 transport adapterとして将来追加。

## テストゲート

MIDI: running status、VLQ、tempo変化、track/channel、重複音、切れたfile、不可能PPQ。
XML: melisma、tie、elision、複数voice、backup、divisions変更、未知要素、entity攻撃。
import→export→importで既知意味が一致、未変更原資料はbyte一致を確認。
このゲート未達のadapterは提供しない。

資料: [MusicXML MIDI-compatible part](https://www.w3.org/2021/06/musicxml40/tutorial/midi-compatible-part/)、
[extend](https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/extend/)。
