// Browser and file:// compatible. Only the prepared dictionary is read, including for new lyrics.
(() => {
  "use strict";
  const dictionary = globalThis.SingingDictionary;
  if (!dictionary) throw new Error("英語の発音辞書を読み込めませんでした。");

  // Keep a sorted row index. Expand pronunciation groups only for words in the current lyrics.
  const rows = dictionary.entries.split("\n");
  const groups = dictionary.groups.split("\n");
  delete globalThis.SingingDictionary;

  function findRow(key) {
    let left = 0;
    let right = rows.length - 1;
    while (left <= right) {
      const index = Math.floor((left + right) / 2);
      const row = rows[index];
      const entry = row.slice(0, row.indexOf("\t"));
      if (key === entry) return row;
      if (key < entry) right = index - 1;
      else left = index + 1;
    }
    return null;
  }

  function decodeForm(value) {
    const ipa = [];
    const kana = [];
    for (const id of value.split(".")) {
      const pair = groups[parseInt(id, 36)].split("\t");
      ipa.push(pair[0]);
      kana.push(pair[1]);
    }
    return { ipa, kana };
  }

  function lookup(text) {
    const key = text.toLowerCase().replace(/[‘’]/g, "'").replace(/[‐‑]/g, "-");
    let row = findRow(key);
    let start = 0;
    if (!row) {
      // A quoted word may have just one attached mark at either end of a multiword quotation.
      // The full elided spelling, when present, was checked first.
      if (key.startsWith("'")) {
        row = findRow(key.slice(1));
        if (row) start = 1;
      }
      if (!row && key.endsWith("'")) row = findRow(key.slice(0, -1));
      if (!row && key.startsWith("'") && key.endsWith("'")) {
        start = 1;
        row = findRow(key.slice(1, -1));
      }
    }
    const unknown = { text, segments: [text], ipa: [], kana: [], status: "unknown", alternatives: [] };
    if (!row) return unknown;
    const [, lengths, encoded] = row.split("\t");
    if (encoded === "?") return unknown;

    const offsets = lengths ? lengths.split(".").map(value => Number(value) + start) : [];
    let previous = 0;
    const segments = [...offsets, text.length].map(end => {
      const segment = text.slice(previous, end);
      previous = end;
      return segment;
    });
    const unaligned = encoded.startsWith("~");
    const forms = (unaligned ? encoded.slice(1) : encoded).split(",").map(decodeForm);
    if (forms.length > 1) {
      return { text, segments, ipa: [], kana: [], status: "ambiguous", alternatives: forms };
    }
    return { text, segments, ...forms[0], status: unaligned ? "unaligned" : "ok", alternatives: [] };
  }

  function analyze(lyrics) {
    const lines = lyrics.split(/\r\n?|\n/).map(original => {
      const tokens = original.match(/[‘’']?[\p{L}\p{N}][\p{L}\p{M}\p{N}]*(?:['’‐‑-][\p{L}\p{N}][\p{L}\p{M}\p{N}]*)*['’']?/gu) || [];
      return { original, words: tokens.map(lookup) };
    });
    return { lines };
  }

  globalThis.SingingEngine = Object.freeze({ analyze });
})();
