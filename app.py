# -*- coding: utf-8 -*-
"""
app.py

英語テキストを入力すると、発音上の母音核にあたる文字だけを赤字にした .docx / PDF を
生成するローカルGUIアプリ（tkinter）。

用途:
    小学生が英語の歌・チャンツを流暢に「読める」ようにするための教材づくり。
    ユーザー自身が入力した英文をローカルで処理する汎用ツール。

主な機能:
    - 母音核の赤字化 → .docx 出力（Arial / 24pt など指定可）
    - 同じデザインの PDF 出力（タイトル付きの見出し帯・凡例・なまえ欄）
    - プレビュー（赤字対象を [ ] で表示）
    - うた・チャンツ ライブラリ（著作権フリー / PD のみ内蔵。検索→選択→入力欄へ）
    - 「曲名でブラウザ検索」（アプリは取得・保存しない。歌詞のコピーは先生の手）
    - 利用上の注意（著作権法35条・SARTRAS）を常時表示

【著作権について（重要）】
    著作権のある歌詞のインターネット自動取得（スクレイピング）は行いません。
    それはアプリによる複製にあたり、著作権法35条（先生の授業目的の複製）では
    免責されないためです。ライブラリに入れるのはPD（著作権フリー）曲のみです。

実行:
    .venv/bin/python app.py     （Homebrew Python / Tk 9.0 の venv を使うこと）
"""

import os
import sys
import json
import time
import webbrowser
import tkinter as tk
from tkinter import filedialog, messagebox
from urllib.parse import quote_plus

from vowel_marker import preview_text
from pd_songs import SONGS

DEFAULT_FILENAME = "red_vowel_output.docx"
DEFAULT_FONT = "Arial"
DEFAULT_SIZE = 24

# 利用上の注意（黄色い帯）の再表示間隔。× で消してからこの日数が過ぎると再表示する。
# 状態ファイル(.ui_state.json)が消えた/壊れた場合も“キャッシュ切れ”として再表示する。
NOTICE_INTERVAL_DAYS = 30
STATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".ui_state.json")

SAMPLE_TEXT = (
    "I will go to the stars\n"
    "We can make a dream\n"
    "The train runs through the night"
)

NOTICE_TEXT = (
    "【利用上の注意】このツールは、先生が入力した英文をローカルで処理する教材作成補助です。　"
    "著作権のある歌詞は「紙での配布・当該授業内での利用」に限り（著作権法35条）、本文は改変せず色だけを付けてください。　"
    "タブレット配信・オンライン等の“公衆送信”を行う場合は、設置者のSARTRAS（授業目的公衆送信補償金）加入をご確認ください。　"
    "左のライブラリの曲は著作権フリー（PD）です。"
)


class VowelMarkerApp:
    def __init__(self, root):
        self.root = root
        root.title("Red Vowel Maker — 母音核 赤字メーカー")
        root.geometry("1040x780")

        # オプション変数
        self.use_exceptions = tk.BooleanVar(value=True)
        self.silent_e = tk.BooleanVar(value=True)
        self.y_as_vowel = tk.BooleanVar(value=True)
        self.font_name = tk.StringVar(value=DEFAULT_FONT)
        self.font_size = tk.StringVar(value=str(DEFAULT_SIZE))
        self.out_name = tk.StringVar(value=DEFAULT_FILENAME)
        self.sheet_title = tk.StringVar(value="")   # プリント上部の帯に出すタイトル（任意）

        # ライブラリ検索・ブラウザ検索用
        self.lib_filter = tk.StringVar()
        self.browser_query = tk.StringVar()
        self._filtered_songs = list(SONGS)

        self._build_ui()

    # -------------------------------------------------------- 状態ファイル
    def _load_state(self):
        try:
            with open(STATE_PATH, encoding="utf-8") as f:
                return json.load(f)
        except Exception:  # 無い/壊れている = キャッシュ切れ扱い
            return {}

    def _save_state_key(self, key, value):
        state = self._load_state()
        state[key] = value
        try:
            with open(STATE_PATH, "w", encoding="utf-8") as f:
                json.dump(state, f, ensure_ascii=False)
        except Exception:
            pass  # 保存できなくても動作は続行（次回また表示されるだけ）

    def _should_show_notice(self):
        ts = self._load_state().get("notice_dismissed_at")
        if not ts:
            return True
        return (time.time() - ts) > NOTICE_INTERVAL_DAYS * 86400

    def on_dismiss_notice(self):
        self.notice_frame.grid_remove()
        self._save_state_key("notice_dismissed_at", time.time())

    # ------------------------------------------------------------------ UI
    def _build_ui(self):
        # 上部: 利用上の注意（× で消せる。消すと約1ヶ月/状態ファイル消失まで非表示） ----
        self.notice_frame = tk.Frame(self.root, background="#fff6d6")
        self.notice_frame.grid(row=0, column=0, columnspan=2, sticky="ew")
        tk.Label(
            self.notice_frame, text=NOTICE_TEXT, justify="left", anchor="w",
            wraplength=960, background="#fff6d6", foreground="#5a4a00",
            padx=10, pady=6,
        ).pack(side="left", fill="x", expand=True)
        tk.Button(
            self.notice_frame, text="✕", command=self.on_dismiss_notice,
            relief="flat", background="#fff6d6", foreground="#5a4a00",
            activebackground="#f0e4b0", borderwidth=0, padx=8,
        ).pack(side="right", anchor="n", padx=4, pady=4)
        if not self._should_show_notice():
            self.notice_frame.grid_remove()

        self.root.grid_rowconfigure(1, weight=1)
        self.root.grid_columnconfigure(1, weight=1)

        # 左: うた・チャンツ ライブラリ ---------------------------------
        self._build_library(self.root)

        # 右: 作業エリア -----------------------------------------------
        self._build_workarea(self.root)

    def _build_library(self, parent):
        frame = tk.LabelFrame(parent, text="うた・チャンツ ライブラリ（著作権フリー / PD）")
        frame.grid(row=1, column=0, sticky="ns", padx=(8, 4), pady=8)

        tk.Label(frame, text="絞り込み（曲名）:").pack(anchor="w", padx=8, pady=(8, 0))
        search = tk.Entry(frame, textvariable=self.lib_filter,
                          background="white", foreground="black",
                          insertbackground="black", width=30)
        search.pack(fill="x", padx=8, pady=2)
        self.lib_filter.trace_add("write", lambda *_: self._refresh_song_list())

        list_wrap = tk.Frame(frame)
        list_wrap.pack(fill="both", expand=True, padx=8, pady=4)
        scroll = tk.Scrollbar(list_wrap, orient="vertical")
        self.song_list = tk.Listbox(
            list_wrap, height=12, width=32, yscrollcommand=scroll.set,
            background="white", foreground="black",
            selectbackground="#3b7ddd", selectforeground="white",
            activestyle="none", exportselection=False,
        )
        scroll.config(command=self.song_list.yview)
        scroll.pack(side="right", fill="y")
        self.song_list.pack(side="left", fill="both", expand=True)
        self.song_list.bind("<Double-Button-1>", lambda _e: self.on_load_song())

        tk.Button(frame, text="▶ 選んだ曲を入力欄へ読み込む",
                  command=self.on_load_song).pack(fill="x", padx=8, pady=(2, 4))

        # PD根拠の表示
        self.song_note = tk.Label(frame, text="", justify="left", anchor="w",
                                  wraplength=260, foreground="#555")
        self.song_note.pack(fill="x", padx=8, pady=(0, 6))
        self.song_list.bind("<<ListboxSelect>>", lambda _e: self._show_song_note())
        self._refresh_song_list()  # song_note 生成後に初期一覧を描画

        # 区切り
        tk.Frame(frame, height=1, background="#ccc").pack(fill="x", padx=8, pady=6)

        # B: ブラウザで歌詞を検索（取得・保存はしない）
        tk.Label(frame, text="曲名で歌詞をブラウザ検索:",
                 font=("", 10, "bold")).pack(anchor="w", padx=8)
        tk.Label(frame,
                 text="※ アプリは取得・保存しません。開いたページから\n"
                      "　 コピーするのは先生ご自身の操作です（35条の範囲で）。",
                 justify="left", foreground="#777").pack(anchor="w", padx=8)
        q = tk.Entry(frame, textvariable=self.browser_query,
                     background="white", foreground="black",
                     insertbackground="black", width=30)
        q.pack(fill="x", padx=8, pady=2)
        q.bind("<Return>", lambda _e: self.on_browser_search())
        tk.Button(frame, text="🔎 ブラウザで検索",
                  command=self.on_browser_search).pack(fill="x", padx=8, pady=(2, 8))

    def _build_workarea(self, parent):
        pad = {"padx": 8, "pady": 4}
        area = tk.Frame(parent)
        area.grid(row=1, column=1, sticky="nsew", padx=(4, 8), pady=8)
        area.grid_rowconfigure(1, weight=3)
        area.grid_rowconfigure(7, weight=2)
        area.grid_columnconfigure(0, weight=1)

        # 入力欄
        tk.Label(area, text="英語テキスト（複数行・貼り付け可）",
                 font=("", 11, "bold")).grid(row=0, column=0, sticky="w")
        self.input_text = tk.Text(area, height=10, wrap="word", font=("Arial", 13),
                                  background="white", foreground="black",
                                  insertbackground="black")
        self.input_text.grid(row=1, column=0, sticky="nsew", pady=4)
        self.input_text.insert("1.0", SAMPLE_TEXT)

        # オプション
        opt = tk.LabelFrame(area, text="オプション")
        opt.grid(row=2, column=0, sticky="ew", pady=4)
        row1 = tk.Frame(opt)
        row1.pack(fill="x", **pad)
        tk.Label(row1, text="フォント名:").pack(side="left")
        tk.Entry(row1, textvariable=self.font_name, width=12,
                 background="white", foreground="black",
                 insertbackground="black").pack(side="left", padx=(2, 16))
        tk.Label(row1, text="サイズ(pt):").pack(side="left")
        tk.Entry(row1, textvariable=self.font_size, width=6,
                 background="white", foreground="black",
                 insertbackground="black").pack(side="left", padx=2)
        row2 = tk.Frame(opt)
        row2.pack(fill="x", **pad)
        tk.Checkbutton(row2, text="例外辞書を使う",
                       variable=self.use_exceptions).pack(side="left", padx=(0, 12))
        tk.Checkbutton(row2, text="silent e を赤字にしない",
                       variable=self.silent_e).pack(side="left", padx=(0, 12))
        tk.Checkbutton(row2, text="y を母音として扱う",
                       variable=self.y_as_vowel).pack(side="left")

        # タイトル・出力ファイル名
        row3 = tk.Frame(area)
        row3.grid(row=3, column=0, sticky="ew", pady=4)
        tk.Label(row3, text="タイトル（任意）:").pack(side="left")
        tk.Entry(row3, textvariable=self.sheet_title, width=28,
                 background="white", foreground="black",
                 insertbackground="black").pack(side="left", padx=(2, 16))
        tk.Label(row3, text="出力ファイル名:").pack(side="left")
        tk.Entry(row3, textvariable=self.out_name,
                 background="white", foreground="black",
                 insertbackground="black").pack(side="left", fill="x",
                                                 expand=True, padx=4)

        # ボタン
        row4 = tk.Frame(area)
        row4.grid(row=4, column=0, sticky="ew", pady=6)
        tk.Button(row4, text="プレビュー  ( make → m[a]ke )",
                  command=self.on_preview).pack(side="left")
        tk.Button(row4, text="docx を生成", command=self.on_generate,
                  font=("", 11, "bold")).pack(side="left", padx=8)
        tk.Button(row4, text="PDF を生成", command=self.on_generate_pdf,
                  font=("", 11, "bold")).pack(side="left")

        # プレビュー
        tk.Label(area, text="プレビュー（赤字対象を [ ] で表示）",
                 font=("", 11, "bold")).grid(row=6, column=0, sticky="w", pady=(8, 0))
        self.preview = tk.Text(area, height=7, wrap="word", font=("Arial", 13),
                               state="disabled", background="#f7f7f7",
                               foreground="black", insertbackground="black")
        self.preview.grid(row=7, column=0, sticky="nsew", pady=4)

    # -------------------------------------------------------- library logic
    def _refresh_song_list(self):
        key = self.lib_filter.get().strip().lower()
        self._filtered_songs = [s for s in SONGS if key in s["title"].lower()]
        self.song_list.delete(0, "end")
        for s in self._filtered_songs:
            self.song_list.insert("end", s["title"])
        self.song_note.config(text="")

    def _selected_song(self):
        sel = self.song_list.curselection()
        if not sel:
            return None
        return self._filtered_songs[sel[0]]

    def _show_song_note(self):
        song = self._selected_song()
        self.song_note.config(text=("PD根拠: " + song["note"]) if song else "")

    def on_load_song(self):
        song = self._selected_song()
        if not song:
            messagebox.showinfo("曲を選択", "リストから曲を選んでください。")
            return
        self.input_text.delete("1.0", "end")
        self.input_text.insert("1.0", song["text"])
        self.sheet_title.set(song["title"])
        self.on_preview()

    def on_browser_search(self):
        query = self.browser_query.get().strip()
        if not query:
            messagebox.showinfo("曲名を入力", "検索したい曲名を入力してください。")
            return
        ok = messagebox.askokcancel(
            "ブラウザで歌詞を検索",
            "既定のブラウザで「{} lyrics」を検索します。\n\n"
            "・アプリは歌詞を取得・保存しません。\n"
            "・開いたページからコピーするかどうかは先生ご自身の判断・操作です。\n"
            "・著作権のある歌詞は、紙での授業内利用（35条）に留めてください。\n\n"
            "続けますか？".format(query),
        )
        if not ok:
            return
        url = "https://www.google.com/search?q=" + quote_plus(query + " lyrics")
        webbrowser.open(url)

    # ------------------------------------------------------------- helpers
    def _opts(self):
        return dict(
            use_exceptions=self.use_exceptions.get(),
            silent_e=self.silent_e.get(),
            y_as_vowel=self.y_as_vowel.get(),
        )

    def _get_font_size(self):
        try:
            size = float(self.font_size.get())
            if size <= 0:
                raise ValueError
            return size
        except ValueError:
            messagebox.showerror("入力エラー",
                                 "フォントサイズは正の数で入力してください。")
            return None

    # -------------------------------------------------------------- events
    def on_preview(self):
        text = self.input_text.get("1.0", "end-1c")
        result = preview_text(text, **self._opts())
        self.preview.configure(state="normal")
        self.preview.delete("1.0", "end")
        self.preview.insert("1.0", result)
        self.preview.configure(state="disabled")

    def on_generate(self):
        self._generate("docx")

    def on_generate_pdf(self):
        self._generate("pdf")

    def _show_missing_package(self, package):
        cmd = '"{}" -m pip install {}'.format(sys.executable, package)
        messagebox.showerror(
            "{} が見つかりません".format(package),
            "{} が未インストールです。\n".format(package) +
            "下のコマンドを「そのまま」ターミナルに貼り付けて実行してください\n"
            "（今アプリを動かしている Python に入れる必要があります）:\n\n"
            + cmd +
            "\n\nインストール後、アプリを開き直してください。",
        )

    def _generate(self, kind):
        """kind = "docx" / "pdf"。どちらも同じデザイン・同じオプションで書き出す。"""
        substitute = None
        try:
            if kind == "pdf":
                from pdf_writer import write_pdf as writer, font_substitute
            else:
                from docx_writer import write_docx as writer
        except ImportError:
            self._show_missing_package("reportlab" if kind == "pdf" else "python-docx")
            return

        text = self.input_text.get("1.0", "end-1c")
        if not text.strip():
            messagebox.showwarning("入力なし", "英語テキストを入力してください。")
            return

        size = self._get_font_size()
        if size is None:
            return

        ext = "." + kind
        filename = self.out_name.get().strip() or DEFAULT_FILENAME
        stem, current_ext = os.path.splitext(filename)
        if current_ext.lower() in (".docx", ".pdf"):
            filename = stem + ext
        elif not filename.lower().endswith(ext):
            filename += ext

        label = "PDF" if kind == "pdf" else "docx"
        filepath = filedialog.asksaveasfilename(
            title="{} の保存先".format(label),
            defaultextension=ext,
            initialfile=filename,
            filetypes=[("PDF", "*.pdf")] if kind == "pdf" else [("Word document", "*.docx")],
        )
        if not filepath:
            return

        font_name = self.font_name.get().strip() or DEFAULT_FONT
        try:
            writer(
                text,
                filepath,
                font_name=font_name,
                font_size=size,
                title=self.sheet_title.get().strip(),
                **self._opts(),
            )
            if kind == "pdf":
                substitute = font_substitute(font_name)
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("生成に失敗しました", str(exc))
            return

        if kind == "pdf":
            note = (
                "※ 完全自動ではありません。歌では音符割りと発音がずれることがあります。\n"
                "  PDF は赤字を後から直せないため、直したいときは docx を生成して\n"
                "  Word で修正し、Word から PDF に書き出してください。"
            )
            if substitute:
                note += "\n\n※ PDF ではフォント「{}」が見つからなかったため、{} で作成しました。".format(
                    font_name, substitute)
        else:
            note = (
                "※ 完全自動ではありません。歌では音符割りと発音がずれることがあります。\n"
                "  最後に先生が耳で確認し、Word 上で赤字を微修正してください。"
            )
        messagebox.showinfo(
            "完了",
            "{} を生成しました。\n\n{}\n\n{}".format(label, os.path.basename(filepath), note),
        )

def main():
    root = tk.Tk()
    VowelMarkerApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
