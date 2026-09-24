# -*- coding: utf-8 -*-
"""
pd_songs.py

著作権フリー（パブリックドメイン／伝承曲）の英語の歌・チャンツのミニライブラリ。

- ここに収録するのは、作詞者の没後70年を超える等でパブリックドメインと考えられる
  伝承曲・古典童謡のみ。これらの歌詞本文の複製・配布・改変は著作権の制限を受けない。
- 収録の根拠（初出年・作者）を各曲の "note" に明記している。
  ※ ただし PD 判定は最終的にはご自身/設置者でご確認ください（版によって編曲・追補詞に
     新しい権利が乗る場合があります。ここでは古くからの標準的な詞のみを収録）。
- 著作権のある楽曲の歌詞はここには入れない（このアプリの設計思想）。

データ形式:
    SONGS = [ {"title": 表示名, "note": PD根拠, "text": 歌詞本文}, ... ]
"""

SONGS = [
    {
        "title": "Twinkle, Twinkle, Little Star",
        "note": "詞: Jane Taylor 1806 (The Star)。作者没後70年超のためPD。",
        "text": (
            "Twinkle, twinkle, little star,\n"
            "How I wonder what you are!\n"
            "Up above the world so high,\n"
            "Like a diamond in the sky.\n"
            "Twinkle, twinkle, little star,\n"
            "How I wonder what you are!"
        ),
    },
    {
        "title": "Mary Had a Little Lamb",
        "note": "詞: Sarah Josepha Hale 1830。作者没後70年超のためPD。",
        "text": (
            "Mary had a little lamb,\n"
            "Little lamb, little lamb,\n"
            "Mary had a little lamb,\n"
            "Its fleece was white as snow.\n"
            "And everywhere that Mary went,\n"
            "Mary went, Mary went,\n"
            "And everywhere that Mary went,\n"
            "The lamb was sure to go."
        ),
    },
    {
        "title": "Row, Row, Row Your Boat",
        "note": "伝承曲（記録上1852年頃、作者不詳の古典童謡）。PD。",
        "text": (
            "Row, row, row your boat,\n"
            "Gently down the stream.\n"
            "Merrily, merrily, merrily, merrily,\n"
            "Life is but a dream."
        ),
    },
    {
        "title": "Old MacDonald Had a Farm",
        "note": "伝承曲（古典童謡、作者不詳）。PD。",
        "text": (
            "Old MacDonald had a farm,\n"
            "E-I-E-I-O!\n"
            "And on his farm he had a cow,\n"
            "E-I-E-I-O!\n"
            "With a moo moo here,\n"
            "And a moo moo there,\n"
            "Here a moo, there a moo,\n"
            "Everywhere a moo moo.\n"
            "Old MacDonald had a farm,\n"
            "E-I-E-I-O!"
        ),
    },
    {
        "title": "Baa, Baa, Black Sheep",
        "note": "伝承曲（初出1744年頃の古典童謡）。PD。",
        "text": (
            "Baa, baa, black sheep,\n"
            "Have you any wool?\n"
            "Yes sir, yes sir,\n"
            "Three bags full.\n"
            "One for the master,\n"
            "And one for the dame,\n"
            "And one for the little boy\n"
            "Who lives down the lane."
        ),
    },
    {
        "title": "London Bridge Is Falling Down",
        "note": "伝承曲（古典童謡、作者不詳）。PD。",
        "text": (
            "London Bridge is falling down,\n"
            "Falling down, falling down,\n"
            "London Bridge is falling down,\n"
            "My fair lady."
        ),
    },
    {
        "title": "Bingo",
        "note": "伝承曲（記録上1780年頃、作者不詳）。PD。",
        "text": (
            "There was a farmer had a dog,\n"
            "And Bingo was his name-o.\n"
            "B-I-N-G-O,\n"
            "B-I-N-G-O,\n"
            "B-I-N-G-O,\n"
            "And Bingo was his name-o."
        ),
    },
    {
        "title": "The Alphabet Song (A B C)",
        "note": "詞・曲ともに1835年頃の古典。PD。",
        "text": (
            "A B C D E F G,\n"
            "H I J K L M N O P,\n"
            "Q R S, T U V,\n"
            "W X, Y and Z.\n"
            "Now I know my A B C,\n"
            "Next time won't you sing with me?"
        ),
    },
]
