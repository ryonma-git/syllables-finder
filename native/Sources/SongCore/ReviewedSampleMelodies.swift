import Foundation

/// Transcriptions cover exactly the text displayed by each practice sample.
/// Source editions and intentional sung schwas/elisions are documented in SAMPLE_MELODIES.md.
enum ReviewedSampleMelodies {
    static let scores: [String: SamplePracticeScore] = [
        "mountain": .init("https://www.liederprojekt.org/medien/Lieddokumente/30261_Ich_bin_ein_Musikante.pdf",
            meter: 2, bpm: 96, pickup: "1/2", lines: [
                .init("Ich|bin|ein|Mu|si|kan|te|und|komm|aus|Schwa|ben|land",
                      "D4:1/2 G4:1/2 G4:1/2 G4:1/2 A4:1/2 B4:1 B4:1/2 B4:1/2 A4:1/2 G4:1/2 A4:1/2 B4:1/2 G4:3/2")
            ]),
        "cuckoo": .init("https://www.liederprojekt.org/medien/Lieddokumente/30266_Kuckuck_Kuckuck_rufts_aus_dem_Wald.pdf",
            meter: 3, bpm: 96, lines: [
                .init("Ku|ckuck|Ku|ckuck|ruft's|aus|dem|Wald",
                      "B4:1 G4:1 R:1 B4:1 G4:1 R:1 A4:1 G4:1 A4:1 G4:3")
            ]),
        "clarinet": .init("https://ezokashi.opal.ne.jp/otof/jaiperduledo.html", meter: 2, bpm: 88, lines: [
            .init("J'ai|per|du|le|do|de|ma|cla|ri|net|te",
                  "C4:1/2 C4:1/2 C4:1/2 C4:1/2 C4:1 G3:1/2 C4:1/2 E4:3/2 D4:1/2 C4:1 G3:1/2 R:1/2")
        ]),
        "marseillaise": .init("https://www.mysticlolly.fr/wp-content/uploads/2016/11/La-Marseillaise-Document-Eduscol.pdf", bpm: 104, pickup: "5/4", lines: [
            .init("Al|lons|en|fants|de|la|Pa|tri|e|le|jour|de|gloire|est|ar|ri|vé",
                  "C4:1/4 C4:3/4 C4:1/4 F4:1 F4:1 G4:1 G4:1 C5:3/2 A4:1/2 F4:3/4 F4:1/4 A4:3/4 F4:1/4 D4:1 Bb4:2 G4:3/4 E4:1/4 F4:2",
                  groups: "1 1 1 1 1 1 1 2 1 1 1 1 1 1 1 1 1")
        ]),
        "gloria": .init("https://www.partitions-domaine-public.fr/pdf/26/noel-les-anges-dans-nos-campagnes.html", bpm: 88, lines: [
            .init("Les|an|ges|dans|nos|cam|pa|gnes|ont|en|ton|né|l'hym|ne|des|cieux",
                  "A4:1 A4:1 A4:1 A4:1/2 C5:1/2 C5:3/2 Bb4:1/2 A4:1 F4:1 A4:1 A4:1/2 G4:1/2 A4:1 A4:1/2 C5:1/2 C5:3/2 Bb4:1/2 A4:2",
                  groups: "1 1 1 2 1 1 1 1 1 1 1 1 2 1 1 1")
        ]),
        "entchen": .init("https://trillian.mit.edu/~jc/music/abc/demo/Tunes/AlleMeineEntchen.abc", meter: 2, bpm: 88, lines: [
            .init("Al|le|mei|ne|Ent|chen|schwim|men|auf|dem|See",
                  "C4:1/2 D4:1/2 E4:1/2 F4:1/2 G4:1 G4:1 A4:1/2 A4:1/2 A4:1/2 A4:1/2 G4:2"),
            .init("Köpf|chen|in|das|Was|ser|Schwänz|chen|in|die|Höh",
                  "F4:1/2 F4:1/2 F4:1/2 F4:1/2 E4:1 E4:1 G4:1/2 G4:1/2 G4:1/2 G4:1/2 C4:2")
        ]),
        "pollitos": .init("https://www.mu-tech.org/WorldTrad/LosPollitos.html", meter: 2, bpm: 88, lines: [
            .init("Los|po|lli|tos|di|cen|pí|o|pí|o|pí|o",
                  "G4:3/4 G4:1/4 G4:1/2 B4:1/2 D5:1 D5:1 E5:3/4 E5:1/4 E5:1/2 G5:1/2 D5:1 D5:1"),
            .init("cuan|do|tie|nen|ham|bre|cuan|do|tie|nen|frí|o",
                  "C5:3/4 C5:1/4 C5:1/2 D5:1/2 B4:1 D5:1 A4:3/4 B4:1/4 A4:1/2 B4:1/2 G4:1 G4:1")
        ]),
        "martino": .init("https://www.acrchorus.it/Coro/pdf/Fra%20Martino%20Campanaro.pdf", bpm: 88, lines: [
            .init("Fra|Mar|ti|no|cam|pa|na|ro|dor|mi|tu",
                  "D4:1 E4:1 F#4:1 D4:1 D4:1 E4:1 F#4:1 D4:1 F#4:1 G4:1 A4:2"),
            .init("Suo|na|le|cam|pa|ne|din|don|dan",
                  "A4:1/2 B4:1/2 A4:1/2 G4:1/2 F#4:1 D4:1 D4:1 A3:1 D4:2")
        ]),
        "adeste": .init("https://www.godsongs.net/2016/12/adeste-fideles-o-come-all-ye-faithful.html", bpm: 88, pickup: "1", lines: [
            .init("A|des|te|fi|de|les|lae|ti|tri|um|phan|tes",
                  "F4:1 F4:2 C4:1 F4:1 G4:2 C4:2 A4:1 G4:1 A4:1 Bb4:1 A4:2 G4:1"),
            .init("ve|ni|te|ve|ni|te|in|Beth|le|hem",
                  "F4:1 F4:2 E4:1 D4:1 E4:1 F4:1 G4:1 A4:1 E4:2 D4:3/2 C4:1/2 C4:3 R:1",
                  groups: "1 1 1 1 2 1 1 1 2 1")
        ]),
        "birch": .init("https://notarhiv.ru/detskie/1/1%20(187).pdf", meter: 2, bpm: 84, lines: [
            .init("Во|по|ле|бе|рё|за|сто|я|ла",
                  "B4:1/2 B4:1/2 B4:1/2 B4:1/2 A4:1/2 A4:1/2 G4:1/2 G4:1/2 F#4:1 E4:1",
                  groups: "1 1 1 1 2 1 1 1 1"),
            .init("во|по|ле|ку|дря|ва|я|сто|я|ла",
                  "B4:1/2 B4:1/2 D5:1/2 B4:1/2 A4:1/2 F#4:1/2 G4:1/2 G4:1/2 F#4:1 E4:1")
        ]),
        "sakura": .init("https://trillian.mit.edu/~jc/music/abc/mirror/musicaviva.com/tunes/japan/sakura.abc", bpm: 72, lines: [
            .init("さ|く|ら|さ|く|ら", "A4:1 A4:1 B4:2 A4:1 A4:1 B4:2"),
            .init("や|よ|い|の|そ|ら|は|み|わ|た|す|か|ぎ|り",
                  "A4:1 B4:1 C5:1 B4:1 A4:1 B4:1/2 A4:1/2 F4:2 E4:1 C4:1 E4:1 F4:1 E4:1 E4:1/2 C4:1/2 B3:2",
                  groups: "1 1 1 1 1 2 1 1 1 1 1 1 2 1")
        ]),
        "arirang": .init("https://trillian.mit.edu/~jc/music/abc/session/RusticRoots/waltz/Arirang-G-32-4w4.abc",
            meter: 3, bpm: 72, lines: [
                .init("아|리|랑|아|리|랑|아|라|리|요",
                      "D4:3/2 E4:1/2 D4:1/2 E4:1/2 G4:3/2 A4:1/2 G4:1/2 A4:1/2 B4:1 A4:1/3 B4:1/3 A4:1/3 G4:1/2 E4:1/2 D4:3/2 E4:1/2 D4:1/2 E4:1/2",
                      groups: "1 1 2 1 1 2 1 3 2 4"),
                .init("아|리|랑|고|개|로|넘|어|간|다",
                      "G4:3/2 A4:1/2 G4:1/2 A4:1/2 B4:1/2 A4:1/2 G4:1/2 E4:1/2 D4:1/2 E4:1/2 G4:3/2 A4:1/2 G4:1 G4:2 R:1",
                      groups: "1 1 2 2 2 2 1 1 1 1")
            ]),
        "kalinka": .init("https://trillian.mit.edu/~jc/music/abc/Russia/Kalinka.abc", meter: 2, bpm: 104, pickup: "1", lines: [
            .init("Ка|лин|ка|ка|лин|ка|ка|лин|ка|мо|я",
                  "B4:1 A4:1 F#4:1/2 G4:1/2 A4:1 F#4:1/2 G4:1/2 A4:1 G4:1/2 F#4:1/2 E4:1")
        ]),
        "week": .init("https://kjzz.ru/nedelka", meter: 2, bpm: 100, pickup: "1", lines: [
            .init("В|во|скре|се|нье|я|на|яр|мар|ку|хо|ди|ла",
                  "D4:1/2 F4:1/2 A4:1/2 A4:1/2 A4:1/2 G4:1/2 A4:1/2 A4:1/2 A4:1/2 G4:1/2 A4:1/2 G4:1/2 F4:3/2 R:1/2",
                  groups: "2:1 1 1 1 1 1 1 1 1 1 1 2")
        ]),
        "korobeiniki": .init("https://notarhiv.ru/ruskomp/titovi/noti/1%20(59).pdf", bpm: 88, lines: [
            .init("Ой|пол|на|пол|на|ко|ро|бу|шка|есть|и|си|тцы|и|пар|ча",
                  "G4:3/2 A4:1/2 B4:1 C5:1 A4:1 E4:1 C5:1 B4:1/2 A4:1/2 G4:3/2 A4:1/2 B4:1 C5:1 A4:1 E4:1 E4:3/2 R:1/2")
        ]),
        "jasmine": .init("https://www.cangqiang.com.cn/bofang/29687.html", meter: 2, bpm: 66, lines: [
            .init("好|一|朵|茉|莉|花|好|一|朵|茉|莉|花",
                  "G4:1/4 F4:1/4 G4:1/4 Bb4:1/4 Bb4:1/4 Bb4:1/4 Eb5:1/4 Bb4:1/4 Bb4:1/4 G4:1/4 Bb4:1 Bb4:1/2 Eb5:1/2 F5:1/4 G5:1/4 F5:1/4 Eb5:1/4 Bb4:1/4 Eb5:1/4 Bb4:2",
                  groups: "2 1 1 2 2 4 1 1 1 2 2 1"),
            .init("满|园|花|草|香|也|香|不|过|它",
                  "Bb4:1/4 G4:1/4 Bb4:1 Bb4:1/2 Eb5:1/2 F5:1/4 G5:1/4 Eb5:1/2 Bb4:1/4 Bb4:1/4 Bb4:1/2 F4:1/2 G4:1/4 Bb4:1/4 G4:1/4 F4:1/4 Eb4:1/4 Bb3:1/4 Eb4:3/2",
                  groups: "2 2 3 3 1 1 2 1 1 3")
        ]),
        "danny": .init("https://trillian.mit.edu/~jc/music/abc/mirror/troseandassociates.com/abc/DannyBoy.abc",
            bpm: 52, pickup: "3/2", lines: [
                .init("Oh|Dan|ny|boy|the|pipes|the|pipes|are|cal|ling",
                      "E4:1/2 F4:1/2 G4:1/2 A4:3/2 G4:1/2 A4:1/2 D5:1/2 C5:1/2 A4:1/2 G4:1/2 F4:1/2 D4:3/2",
                      groups: "1 1 1 1 1 1 1 1 1 2 1")
            ]),
        "auld": .init("https://trillian.mit.edu/~jc/music/abc/song/Auld_Lang_Syne.abc", bpm: 88, pickup: "1", lines: [
            .init("Should|auld|ac|quain|tance|be|for|got|and|ne|ver|brought|to|mind",
                  "C4:1 F4:3/2 E4:1/2 F4:1 A4:1 G4:3/2 F4:1/2 G4:1 A4:1/2 G4:1/2 F4:3/2 F4:1/2 A4:1 C5:1 D5:3",
                  groups: "1 1 1 1 1 1 1 1 2 1 1 1 1 1")
        ]),
        "ninth": .init("https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode.ly", bpm: 100, lines: [
            .init("Freu|de|schö|ner|Göt|ter|fun|ken|Toch|ter|aus|E|ly|si|um",
                  "B4:1 B4:1 C5:1 D5:1 D5:1 C5:1 B4:1 A4:1 G4:1 G4:1 A4:1 B4:1 B4:3/2 A4:1/2 A4:2"),
            .init("Wir|be|tre|ten|feu|er|trun|ken|Himm|li|sche|dein|Hei|lig|tum",
                  "B4:1 B4:1 C5:1 D5:1 D5:1 C5:1 B4:1 A4:1 G4:1 G4:1 A4:1 B4:1 A4:3/2 G4:1/2 G4:2"),
            .init("Dei|ne|Zau|ber|bin|den|wie|der|was|die|Mo|de|streng|ge|teilt",
                  "A4:1 A4:1 B4:1 G4:1 A4:1 B4:1/2 C5:1/2 B4:1 G4:1 A4:1 B4:1/2 C5:1/2 B4:1 A4:1 G4:1 A4:1 D4:2",
                  groups: "1 1 1 1 1 2 1 1 1 2 1 1 1 1 1"),
            .init("al|le|Men|schen|wer|den|Brü|der|wo|dein|sanf|ter|Flü|gel|weilt",
                  "B4:1 B4:1 C5:1 D5:1 D5:1 C5:1 B4:1 A4:1 G4:1 G4:1 A4:1 B4:1 A4:3/2 G4:1/2 G4:2")
        ])
    ]
}
