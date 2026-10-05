# 内蔵サンプルの旋律資料

内蔵の23曲には単旋律の音符データがあります。既存の「きらきら星」「Mary Had a Little Lamb」「Frère Jacques」「Morning light」は従来の音節と音符の対応を保持しています。下記の19曲は公開されたABC譜またはMIDIの旋律パートから音高と長さを入力しました。元資料の調、反復、歌う節がアプリの短い歌詞見本と一致するとは限りません。**音節と音符の対応は未校訂**で、歌唱用に使う際は利用者が確認してください。

| 地域 | 曲・ID | 旋律資料 |
| --- | --- | --- |
| ドイツ | Alle meine Entchen (`entchen`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fdemo%2FTunes%2FAlleMeineEntchen%2F0000) |
| ドイツ | 第九・歓喜の歌 (`ninth`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fdemo%2FTunes%2FOdeToJoy%2F0000) |
| ドイツ | 山の音楽家 (`mountain`) | [Mu-techの譜面とMIDI](https://www.mu-tech.org/WorldTrad/Ich_bin_ein_Musikante.html) |
| ドイツ | かっこう (`cuckoo`) | [Mu-techの譜面とMIDI](https://www.mu-tech.org/WorldTrad/cuckoo.html) |
| フランス | クラリネットをこわしちゃった (`clarinet`) | [Mu-techの譜面とMIDI](https://www.mu-tech.org/WorldTrad/Clarinet.html) |
| フランス | フランス国歌 (`marseillaise`) | [ABC譜](https://abcnotation.com/tunePage?a=serpent.serpentpublications.org%2F~lconrad%2Fmusic%2Fdelisle%2Fmarseillaise%2F0000) |
| フランス | あら野の果てに (`gloria`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fmirror%2Fwww.stephenmerrony.co.uk%2FAngels_We_Have_Heard_On_High%2F0000) |
| ロシア | 白樺 (`birch`) | [mfilesの譜面とMIDI](https://www.mfiles.co.uk/scores/the-birch-tree.htm) |
| ロシア | カリンカ (`kalinka`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2FRussia%2FKalinka%2F0002) |
| ロシア | コロブチカ (`korobeiniki`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2FKlezmer%2Ftune%2FKorobushka%2F0000) |
| ロシア | 一週間 (`week`) | [Mu-techの譜面とMIDI](https://www.mu-tech.org/WorldTrad/one_week.html) |
| アイルランド／スコットランド | ダニーボーイ (`danny`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fmirror%2Ftroseandassociates.com%2Fabc%2FDannyBoy%2F0001) |
| スコットランド | 蛍の光の原曲 (`auld`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fsong%2FAuld_Lang_Syne%2F0000) |
| イタリア | Fra Martino (`martino`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fmirror%2Fmusicaviva.com%2Ffrance%2Ffrere-jaques-d%2Ffrere-jaques-d%2F0000) |
| ラテン語 | Adeste Fideles (`adeste`) | [ABC譜](https://abcnotation.com/tunePage?a=www.godsongs.net%2F2016%2F12%2Fadeste-fideles-o-come-all-ye-faithful.html%2F0001) |
| スペイン語 | Los pollitos dicen (`pollitos`) | [Mu-techの譜面とMIDI](https://www.mu-tech.org/WorldTrad/LosPollitos.html) |
| 日本 | さくら さくら (`sakura`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fmirror%2Fmusicaviva.com%2Ftunes%2Fjapan%2Fsakura%2F0000) |
| 韓国 | アリラン (`arirang`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2Fsession%2FRusticRoots%2Fwaltz%2FArirang-G-32-4w4%2F0000) |
| 中国 | 茉莉花 (`jasmine`) | [ABC譜](https://abcnotation.com/tunePage?a=trillian.mit.edu%2F~jc%2Fmusic%2Fabc%2FChina%2FMoLiHua_F%2F0000) |

ABC譜の音符列、Mu-techのMIDIでは主旋律チャンネル、白樺では譜面の冒頭に対応するMIDIパートを使用しています。音符はアプリ内で1拍480 tickのデータとして保持し、`.songproj` を生成すると `source/Melody.mid` を書き出します。追加した10曲の歌詞は原語の短い一行だけで、発音記号とカタカナは未入力です。

「カチューシャ」は1938年の作曲作品であり、上記の伝承曲と同列には扱いません。作曲者の権利者は[IMSLP](https://imslp.org/wiki/Katyusha_(Blanter,_Matvey))上で音楽のCC BY-SA利用を認めていますが、歌詞の許諾は別です。このリポジトリには同曲の旋律・歌詞を収録しません。
