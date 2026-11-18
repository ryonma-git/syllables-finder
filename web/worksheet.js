(() => {
  "use strict";
  const id = () => {
    if (globalThis.crypto.randomUUID) return crypto.randomUUID();
    return "10000000-1000-4000-8000-100000000000".replace(/[018]/g,
      c => (Number(c) ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> Number(c) / 4).toString(16));
  };
  function source(kind) {
    if (kind === "ai") return {kind,provider:"OpenAI",model:WorksheetAI.model};
    if (kind === "dictionary") return {kind,provider:"CMUdict + EnglishPronunciation"};
    return {kind};
  }
  const field = (value = "", kind = "rule") => ({value, source:source(kind), userEdited:kind === "manual"});
  const makeSegment = (parentWordID, text, ipa, kana, kind) => ({
    id:id(), parentWordID, text:field(text,kind === "dictionary" ? "rule" : kind), ipa:field(ipa,kind), reading:field(kana,kind),
    stress:field(ipa.includes("ˈ") ? "強" : "",kind), moraIDs:[], phonemeIDs:[], structureUserEdited:kind === "manual"
  });
  function make(title, lyrics) {
    const onset = {denominator:1,numerator:0};
    const section = {id:id(),title:"歌詞",phraseIDs:[]};
    const song = {schemaVersion:2,id:id(),revision:0,
      metadata:{title,sourceLanguage:"en",translationLanguage:"ja",englishPronunciation:"american",notes:""},
      sections:[section],phrases:[],words:[],syllables:[],moras:[],phonemes:[],alignments:[],
      music:{events:[],measures:[],parts:[],spans:[],meters:[{numerator:4,denominator:4,onset}],tempos:[{bpm:88,onset}]}};
    for (const line of SingingEngine.analyze(lyrics).lines) {
      const phrase = {id:id(),originalText:line.original,translation:field(),musicalEventIDs:[],structureUserEdited:false,wordIDs:[]};
      section.phraseIDs.push(phrase.id);
      song.phrases.push(phrase);
      for (const item of line.words) {
        const word = {id:id(),surface:item.text,parentPhraseID:phrase.id,lemma:field(),partOfSpeech:field(),
          contextualMeaning:field(),dictionaryMeaning:field(),notes:field(),structureUserEdited:false,syllableIDs:[]};
        phrase.wordIDs.push(word.id);
        song.words.push(word);
        item.segments.forEach((text,i) => {
          const segment = makeSegment(word.id,text,item.ipa[i] || "",item.kana[i] || "",
            item.status === "ok" || item.status === "unaligned" ? "dictionary" : "rule");
          song.syllables.push(segment);
          word.syllableIDs.push(segment.id);
        });
      }
    }
    return song;
  }
  function index(song) {
    const fail = () => { throw Error("対応する教材データ（形式2のJSON）を選んでください。"); };
    if (song?.schemaVersion !== 2 || !Number.isSafeInteger(song.revision) || song.revision < 0 ||
        ![song.metadata?.title,song.metadata?.sourceLanguage,song.metadata?.translationLanguage,song.metadata?.notes]
          .every(v=>typeof v === "string") || !Array.isArray(song.moras) || !Array.isArray(song.phonemes) ||
        !Array.isArray(song.sections) || !Array.isArray(song.phrases) || !Array.isArray(song.words) ||
        !Array.isArray(song.syllables) || !Array.isArray(song.alignments) || !Array.isArray(song.music?.events)) fail();
    const ids = new Set();
    const map = arr => new Map(arr.map(item => {
      if (typeof item?.id !== "string" || ids.has(item.id)) fail();
      ids.add(item.id); return [item.id,item];
    }));
    const phrases = map(song.phrases), words = map(song.words), syllables = map(song.syllables);
    function children(owners, property, table, parentKey) {
      const used = new Set(), ordered = [];
      for (const owner of owners) {
        if (!Array.isArray(owner[property])) fail();
        for (const key of owner[property]) {
          const item = table.get(key);
          if (!item || used.has(key) || (parentKey && item[parentKey] !== owner.id)) fail();
          used.add(key); ordered.push(item);
        }
      }
      if (used.size !== table.size) fail();
      return ordered;
    }
    const lines = children(song.sections,"phraseIDs",phrases);
    children(song.phrases,"wordIDs",words,"parentPhraseID");
    children(song.words,"syllableIDs",syllables,"parentWordID");
    const isField = v => typeof v?.value === "string" && typeof v.userEdited === "boolean" &&
      ["manual","sample","ai","dictionary","imported","rule"].includes(v?.source?.kind);
    if (lines.some(x => typeof x.originalText !== "string" || !Array.isArray(x.musicalEventIDs) || !isField(x.translation)) ||
        song.alignments.some(a => !Array.isArray(a?.languageTargets) || a.languageTargets.some(t=>typeof t?.id !== "string")) ||
        song.words.some(x => typeof x.surface !== "string" || !isField(x.contextualMeaning)) ||
        song.syllables.some(x => ![x.text,x.ipa,x.reading,x.stress].every(isField) ||
           (x.connectedIPA != null && !isField(x.connectedIPA)) || (x.connectedReading != null && !isField(x.connectedReading)) ||
           !Array.isArray(x.moraIDs) || !Array.isArray(x.phonemeIDs))) fail();
    return {lines,phrases,words,syllables};
  }
  const protectedField = f => f.userEdited || f.source.kind === "manual"
    || (f.value !== "" && ["sample","imported"].includes(f.source.kind));
  function setField(target, key, value, kind) {
    if (target[key].value !== value && !(kind === "ai" && protectedField(target[key]))) {
      target[key] = field(value,kind);
    }
  }
  function displayReading(song, phrase, word, units) {
    function display(readings, saved) {
      const incomplete = !readings.length || readings.some(s=>!s.ipa.value || !s.reading.value);
      if (incomplete && saved?.surface === word.surface && saved.style === (song.metadata.englishPronunciation || "american")
        && saved.ipa && saved.reading && !readings.some(s=>s.ipa.userEdited || s.reading.userEdited)) {
        return {ipa:saved.ipa,kana:saved.reading};
      }
      return {
        ipa:readings.every(s=>s.ipa.value) ? readings.map(s=>s.ipa.value).join("·") : "",
        kana:readings.some(s=>s.reading.value) ? readings.map(s=>s.reading.value || "□").join("・") : ""
      };
    }
    const base = display(units,word.wholePronunciation);
    if (song.metadata.englishReadingMode !== "connected" || !/^en(?:[-_]|$)/i.test(phrase.language || song.metadata.sourceLanguage)
        || !units.some(s=>s.connectedIPA || s.connectedReading)) return base;
    const connected = display(units.map(s=>({ipa:s.connectedIPA ?? s.ipa,reading:s.connectedReading ?? s.reading})),null);
    return {ipa:connected.ipa || base.ipa,kana:connected.kana || base.kana};
  }
  function applyWord(song, view, word, parts, meaning, kind) {
    const old = word.syllableIDs.map(i => view.syllables.get(i));
    const same = old.length === parts.length && old.every((s,i) => s.text.value === parts[i].text);
    const phrase = view.phrases.get(word.parentPhraseID);
    const details = old.some(s => s.moraIDs.length || s.phonemeIDs.length || s.connectedIPA || s.connectedReading);
    const linkedIDs = new Set([word.id,...word.syllableIDs]);
    const fixed = details || phrase.musicalEventIDs.length > 0 ||
      song.alignments.some(a=>a.languageTargets.some(t=>linkedIDs.has(t.id)));
    if (!same && fixed && kind === "manual") throw Error("音符・連音情報のある教材は、元の音節区切りを保って編集してください。");
    const protectedSound = details || word.wholePronunciation?.verification ||
      ["manual","sample","imported"].includes(word.wholePronunciation?.source?.kind) ||
      old.some(s=>[s.text,s.ipa,s.reading,s.stress].some(protectedField));
    const fixedByTeacher = word.structureUserEdited || old.some(s=>s.structureUserEdited);
    const canApply = kind === "manual" || (!protectedSound && (same || (!fixed && !fixedByTeacher)));
    if (canApply) {
      const soundChanged = !same || old.some((s,i)=>s.ipa.value !== parts[i].ipa || s.reading.value !== parts[i].kana);
      if (same || old.length === parts.length) {
        old.forEach((s,i) => {
          const p = parts[i];
          if (s.ipa.value !== p.ipa && !s.stress.userEdited) setField(s,"stress",p.ipa.includes("ˈ") ? "強" : "",kind);
          setField(s,"text",p.text,kind); setField(s,"ipa",p.ipa,kind); setField(s,"reading",p.kana,kind);
        });
      } else {
        const remove = new Set(word.syllableIDs);
        song.syllables = song.syllables.filter(s => !remove.has(s.id));
        const next = parts.map(p => makeSegment(word.id,p.text,p.ipa,p.kana,kind));
        word.syllableIDs = next.map(s => s.id);
        song.syllables.push(...next);
      }
      if (!same && kind === "manual") word.structureUserEdited = true;
      if (soundChanged && (word.wholePronunciation || kind === "ai") &&
          /^en(?:[-_]|$)/i.test(phrase.language || song.metadata.sourceLanguage)) {
        if (parts.every(p=>p.ipa && p.kana)) {
          word.wholePronunciation = {surface:word.surface,style:song.metadata.englishPronunciation || "american",
            ipa:parts.map(p=>p.ipa).join(""),reading:parts.map(p=>p.kana).join(""),source:source(kind)};
        } else { delete word.wholePronunciation; }
      }
    }
    setField(word,"contextualMeaning",meaning,kind);
  }
  globalThis.Worksheet = Object.freeze({make,index,setField,applyWord,displayReading});
})();
