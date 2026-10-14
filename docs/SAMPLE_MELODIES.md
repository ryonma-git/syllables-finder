# 内蔵サンプルの旋律と歌詞の対応

2026-10-13、内蔵23曲の歌詞と単旋律の対応を確認しました。既存の「きらきら星」「Mary Had a Little Lamb」「Frère Jacques」「Morning light」は従来の対応を保持し、下記19曲は譜面・ABC譜の歌唱旋律を、**アプリに表示する原語歌詞の範囲**に合わせて入力し直しています。短い抜粋の練習用データであり、原曲全体の収録ではありません。

各音節を音符へ明示的に対応づけています。一音節を複数音で歌うメリスマ、複数の言語単位を一音で歌う結合、休符、弱起を区別しています。全音節と全歌唱音符の対応、フレーズ範囲、MIDIの音高・開始時刻・長さ・拍子の再読み込みをテストしています。再生音はガイド音です。

| 地域 | 曲・ID | 使用資料 |
| --- | --- | --- |
| ドイツ | Alle meine Entchen (`entchen`) | [採譜資料](https://trillian.mit.edu/~jc/music/abc/demo/Tunes/AlleMeineEntchen.abc) |
| ドイツ | 第九・歓喜の歌 (`ninth`) | [採譜資料](https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode.ly) |
| ドイツ | 山の音楽家 (`mountain`) | [採譜資料](https://www.liederprojekt.org/medien/Lieddokumente/30261_Ich_bin_ein_Musikante.pdf) |
| ドイツ | かっこう (`cuckoo`) | [採譜資料](https://www.liederprojekt.org/medien/Lieddokumente/30266_Kuckuck_Kuckuck_rufts_aus_dem_Wald.pdf) |
| フランス | クラリネットをこわしちゃった (`clarinet`) | [採譜資料](https://ezokashi.opal.ne.jp/otof/jaiperduledo.html) |
| フランス | フランス国歌 (`marseillaise`) | [採譜資料](https://www.mysticlolly.fr/wp-content/uploads/2016/11/La-Marseillaise-Document-Eduscol.pdf) |
| フランス | あら野の果てに (`gloria`) | [採譜資料](https://www.partitions-domaine-public.fr/pdf/26/noel-les-anges-dans-nos-campagnes.html) |
| ロシア | 白樺 (`birch`) | [採譜資料](https://notarhiv.ru/detskie/1/1%20(187).pdf) |
| ロシア | カリンカ (`kalinka`) | [採譜資料](https://trillian.mit.edu/~jc/music/abc/Russia/Kalinka.abc) |
| ロシア | コロブチカ (`korobeiniki`) | [採譜資料](https://notarhiv.ru/ruskomp/titovi/noti/1%20(59).pdf) |
| ロシア | 一週間 (`week`) | [採譜資料](https://kjzz.ru/nedelka) |
| アイルランド／スコットランド | ダニーボーイ (`danny`) | [採譜資料](https://trillian.mit.edu/~jc/music/abc/mirror/troseandassociates.com/abc/DannyBoy.abc) |
| スコットランド | 蛍の光の原曲 (`auld`) | [採譜資料](https://trillian.mit.edu/~jc/music/abc/song/Auld_Lang_Syne.abc) |
| イタリア | Fra Martino (`martino`) | [採譜資料](https://www.acrchorus.it/Coro/pdf/Fra%20Martino%20Campanaro.pdf) |
| ラテン語 | Adeste Fideles (`adeste`) | [採譜資料](https://www.godsongs.net/2016/12/adeste-fideles-o-come-all-ye-faithful.html) |
| スペイン語 | Los pollitos dicen (`pollitos`) | [採譜資料](https://www.mu-tech.org/WorldTrad/LosPollitos.html) |
| 日本 | さくら さくら (`sakura`) | [採譜資料](https://trillian.mit.edu/~jc/music/abc/mirror/musicaviva.com/tunes/japan/sakura.abc) |
| 韓国 | アリラン (`arirang`) | [採譜資料](https://trillian.mit.edu/~jc/music/abc/session/RusticRoots/waltz/Arirang-G-32-4w4.abc) |
| 中国 | 茉莉花 (`jasmine`) | [採譜資料](https://www.cangqiang.com.cn/bofang/29687.html) |

## 歌唱形と版の選択

- 山の音楽家はドイツ語の歌唱譜に合わせた2/4拍子・八分音符の弱起です。かっこうは3/4拍子で、呼びかけの後の休符も保持しています。
- フランス語では歌う語末の e を保持しています。`clarinette` は `cla|ri|net|te`、`Patrie` は `Pa|tri|e`、`anges` は `an|ges`、`campagnes` は `cam|pa|gnes`、`l'hymne` は `l'hym|ne`。歌唱譜に合わせた発音・カタカナも設定しています。
- フランス国歌の弱起は上記資料の記譜に従います。書かれた最初の三音の音価を保持し、標準的な演奏の唯一の形とはしていません。
- Alle meine Entchen の `schwimmen auf dem See`、Fra Martino の各句の反復は、従来の表示歌詞に合わせて省略しています。
- 一週間は原語の「日曜日に市場へ行った」の句を使用します。子音だけの前置詞 `В` と次の `во` は一音にまとめ、語尾のメリスマも対応づけています。
- コロブチカは掲載された Titov の歌唱譜の冒頭を使用しています。広く知られる器楽版とは旋律が異なります。
- 茉莉花は既存の `好一朵茉莉花…满园花草香也香不过它` に対応する江蘇の伝統的な歌唱譜を採用しています。`好一朵美丽的茉莉花` の別歌詞・別旋律へ置換していません。
- 第九は4行・16小節の旋律を確認し、3行目のメリスマと各句末の音価を修正しています。アリランの三連符は再生位置・長さを保持しますが、現行の楽譜画面では変則音価の略譜表示になります。
- 各曲の練習テンポは学習用設定です。市販録音のテンポや構成を再現するものではありません。

## 保存と既存ファイル

`SongSampleTool` で生成した `.songproj` には `document.json` と `source/Melody.mid` が入ります。MIDIは480 tick/四分音符で、音高・音価・テンポ・拍子を出力します。歌詞、IPA、カタカナ、音節ID、音符との対応は `.songproj` 側に保存します。

変更が適用されるのは新しく開く内蔵サンプルです。保存済みの文書や「このMacの曲」を自動で上書きしません。私用曲を整える場合も、元ファイルを保持した別コピーで行い、既存の手修正・音節ID・音符ID・対応を比較します。元の音符がない曲に旋律を追加する場合は、その資料と確認状況を記録します。

私用の曲は「サンプルを表示」→「このMacの曲を追加…」から登録できます。登録文書は `~/Library/Application Support/SingingWorkspace/LocalSamples/` にコピーされ、元ファイルは保持されます。私用歌詞、入力資料、生成文書、音源、モデルはリポジトリに含めません。

「カチューシャ」は内蔵23曲には含めていません。私用文書の旋律データと、歌詞を追加できる状態は別に管理します。歌詞が未入力の文書を歌詞対応済みとは表示しません。
