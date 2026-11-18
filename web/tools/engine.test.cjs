const assert = require("node:assert/strict");
const { test } = require("node:test");
require("../dist/dictionary.js");
require("../dist/engine.js");
require("../openai.js");
require("../worksheet.js");

test("offline worksheet keeps original lines and uses the desktop pronunciation and spelling", () => {
  const raw = "   CREATION, read!\r\n\r\n   CREATION, read!\r\nI can’t invent Qzxzz.";
  const { lines } = SingingEngine.analyze(raw);
  assert.deepEqual(lines.map(line => line.original), raw.split("\r\n"));
  assert.deepEqual(lines[0], lines[2]);
  assert.deepEqual(lines[1].words, []);
  const [known, ambiguous] = lines[0].words;
  assert.deepEqual(known.segments, ["CRE", "A", "TION"]);
  assert.deepEqual(known.ipa, ["kri", "ˈeɪ", "ʃən"]);
  assert.deepEqual(known.kana, ["クリ", "エイ", "ション"]);
  assert.equal(ambiguous.status, "ambiguous");
  assert.deepEqual(ambiguous.ipa, []);
  assert.deepEqual(ambiguous.alternatives.map(form => form.kana[0]).sort(), ["リード", "レッド"]);
  assert.equal(lines[3].words[1].text, "can’t");
  assert.equal(lines[3].words[1].status, "ok");
  assert.equal(lines[3].words.at(-1).status, "unknown");
});

test("original spelling survives word boundaries, quotes and elisions", () => {
  const { words } = SingingEngine.analyze("‘quietly’ no‑one walkin’ 'n' goin’").lines[0];
  for (const word of words) assert.equal(word.segments.join(""), word.text);
  assert.equal(words[0].status, "ok");
  assert.equal(words[4].status, "unknown"); // Distinct goin / goin' dictionary entries
  assert.equal(words[3].status, "unknown"); // Contraction, not the letter N
});

test("imported manual pronunciation and reviewed word fallback survive completing meanings", () => {
  const song = Worksheet.make("Test", "Creation.");
  const view = Worksheet.index(song), word = song.words[0], line = view.lines[0];
  const syllables = word.syllableIDs.map(id=>view.syllables.get(id));
  syllables[1].ipa.value = "";
  syllables[1].reading.value = "";
  word.wholePronunciation = {surface:"Creation",style:"american",source:{kind:"imported"},
    ipa:"kriˈeɪʃən",reading:"クリエイション",verification:{reviewer:"teacher",verdict:"ok",explanation:"確認済み"}};
  assert.deepEqual(Worksheet.displayReading(song,line,word,syllables),{ipa:"kriˈeɪʃən",kana:"クリエイション"});
  const saved = structuredClone(word.wholePronunciation);
  const units = syllables.map(s=>({text:s.text.value,ipa:s.ipa.value,kana:s.reading.value}));
  Worksheet.applyWord(song,view,word,units,"創造","manual");
  assert.deepEqual(word.wholePronunciation,saved);
  Worksheet.applyWord(song,view,word,[{text:"Creation",ipa:"test",kana:"テスト"}],"別の訳","ai");
  assert.deepEqual(word.wholePronunciation,saved);
  assert.equal(word.contextualMeaning.value,"創造");
  syllables[0].reading.userEdited = true;
  const partial = Worksheet.displayReading(song,line,word,syllables);
  assert.equal(partial.ipa,"");
  assert.match(partial.kana,/□/);
});

test("a changed AI division records the model on new syllables and preserves other words", () => {
  const song = Worksheet.make("Test", "I Qzabc.");
  const view = Worksheet.index(song), word = song.words[1];
  const other = structuredClone(song.syllables[0]);
  Worksheet.applyWord(song,view,word,[{text:"Qz",ipa:"kəz",kana:"カズ"},{text:"abc",ipa:"æb",kana:"アブ"}],"固有名","ai");
  assert.equal(word.contextualMeaning.source.model,WorksheetAI.model);
  assert.deepEqual(word.wholePronunciation.source,{kind:"ai",provider:"OpenAI",model:WorksheetAI.model});
  assert.deepEqual(song.syllables[0],other);
  const updated = Worksheet.index(song);
  assert.ok(word.syllableIDs.every(id=>updated.syllables.get(id).ipa.source.model === WorksheetAI.model));
});
