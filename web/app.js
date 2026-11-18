(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const element = (tag, cl, text) => {
    const n = document.createElement(tag);
    if (cl) n.className = cl;
    if (text !== undefined) n.textContent = text;
    return n;
  };
  const button = (label, fn, cl) => {
    const b = element("button",cl,label); b.type = "button"; b.addEventListener("click",fn); return b;
  };
  const example = {title:"Morning Song",lyrics:"Little birds sing in the morning.\nWe listen to the sky."};
  const keyName = "singing-worksheet-draft-v1";
  const bridge = globalThis.webkit?.messageHandlers?.worksheet;
  const toggles = ["kana","ipa","meaning"];
  const printCSS = `
@page{size:A4;margin:15mm}
@media print{body{margin:0!important;background:white!important}body>.mast,.editor,.toolbar,#status,dialog,.todo,.ui-only{display:none!important}main,.workspace,#paper{display:block!important;margin:0!important;padding:0!important;max-width:none!important;border:0!important;box-shadow:none!important;min-height:0!important}.sheet-title{font-size:24pt!important}.line{break-inside:avoid}.original{font-size:16pt!important}.token{border:0!important;box-shadow:none!important;background:transparent!important;padding:2px 6px!important}.translation{border:0!important;color:#202925!important;padding:0!important}.stanza{min-height:10pt!important}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
`;
  const nativeCSS = `
*{box-sizing:border-box}body{color:#202925;font:12pt -apple-system,sans-serif;margin:0}h1{font: bold 24pt Georgia,serif}
.line{border-top:1px solid #bdc9bd;padding:9pt 0;break-inside:avoid}.original{font: bold 16pt Georgia,serif;white-space:pre-wrap;overflow-wrap:anywhere}
.translation{font-size:10pt;margin:4pt 0}.word-list{display:flex;flex-wrap:wrap;gap:5pt;margin-top:5pt}
.token{display:inline-flex;flex-direction:column;align-items:flex-start;font-size:9pt;padding:2pt 3pt}.spelling{font:bold 14pt Georgia,serif}
.spelling span:nth-child(even){color:#12665d}.stanza{height:10pt}.ui-only,.todo{display:none}
`;
  document.head.append(element("style","",printCSS));
  let song, view, edited = false, sourceLyrics, sourceTitle, job, timer, cancelDialog;
  const say = msg => { $("status").textContent = msg; };
  const value = (title,lyrics) => ({title:title.trim() || "歌唱練習シート",lyrics:lyrics.replace(/\r\n?/g,"\n")});
  const inputs = () => value($("title").value,$("lyrics").value);
  const stale = () => inputs().title !== sourceTitle || inputs().lyrics !== sourceLyrics;
  function install(next) {
    const idx = Worksheet.index(next);
    song = next; view = idx;
    sourceTitle = song.metadata.title;
    sourceLyrics = view.lines.map(p => p.originalText).join("\n");
    $("title").value = sourceTitle; $("lyrics").value = sourceLyrics;
    render();
  }
  function persist() {
    try { localStorage.setItem(keyName,JSON.stringify({song,title:$("title").value,lyrics:$("lyrics").value,
      options:toggles.map(k=>$(k).checked),edited})); }
    catch { say("この端末では自動保存できません。「教材データを保存」で保存してください。"); }
  }
  function changed() { edited = true; song.revision++; view = Worksheet.index(song); render(); persist(); }
  function pending() {
    clearTimeout(timer); timer = setTimeout(persist,350);
    say(stale() ? "入力に変更があります。「教材を作成」でプレビューに反映します。" : "");
  }
  function dialog(title) {
    cancelDialog?.(); cancelDialog = null;
    if ($("dialog").open) $("dialog").close();
    const body = $("dialogBody"), foot = $("dialogFoot");
    body.replaceChildren(element("h2","",title)); foot.replaceChildren();
    $("dialog").setAttribute("aria-label",title);
    return {body,foot,show:()=>$("dialog").showModal(),close:()=>$("dialog").close()};
  }
  $("dialogForm").onsubmit = e => e.preventDefault();
  $("dialog").addEventListener("cancel",() => { cancelDialog?.(); cancelDialog = null; });
  $("dialog").addEventListener("close",() => {
    const password = $("dialog").querySelector("input[type=password]");
    if (password) password.value = "";
  });
  function confirmAction(message, action) {
    return new Promise(resolve => {
      const d = dialog("教材の確認");
      const finish = ans => {cancelDialog = null; d.close(); resolve(ans);};
      cancelDialog = () => resolve(false);
      d.body.append(element("p","",message));
      d.foot.append(button("戻る",()=>finish(false)),button(action,()=>finish(true),"primary")); d.show();
    });
  }
  function formInput(parent,label,initial,type="text") {
    const wrap = element("label","form-label",label), input = element(type === "textarea" ? "textarea" : "input");
    if (type !== "textarea") input.type = type;
    input.value = initial; wrap.append(input); parent.append(wrap); return input;
  }
  function showHelp() {
    const d = dialog("歌唱練習シートの使い方");
    ["1　曲名と歌詞を入力し、「教材を作成」を選びます。空行や同じ行の繰り返しも残ります。",
     "2　プレビューの単語を選ぶと、音節・カタカナ・発音記号・単語の意味を直せます。「行の訳を入力」でフレーズの日本語訳を付けます。",
     "3　載せる項目を選び、「印刷・PDF」でA4に印刷、またはPDFとして保存します。「教材データを保存」で編集用JSONを持ち帰れます。",
     "英語（米国）の辞書はオフラインで使えます。読みが複数ある語は文脈に合う候補を選んでください。"
    ].forEach(s=>d.body.append(element("p","",s)));
    d.foot.append(button("閉じる",d.close,"primary")); d.show();
  }
  function editPhrase(p) {
    const d = dialog("行の日本語訳"); d.body.append(element("p","original",p.originalText));
    const input = formInput(d.body,"日本語訳",p.translation.value,"textarea");
    d.foot.append(button("戻る",d.close),button("反映",()=>{
      Worksheet.setField(p,"translation",input.value.trim(),"manual"); changed(); d.close();
    },"primary")); d.show();
  }
  function editWord(w) {
    const d = dialog(w.surface);
    const phrase = view.lines.find(p=>p.id === w.parentPhraseID);
    const old = w.syllableIDs.map(id=>view.syllables.get(id));
    const rows = [], groups = element("div");
    d.body.append(element("p","",phrase.originalText),groups);
    const add = (text="",ipa="",kana="") => {
      const r = element("div","segment-row");
      const fields = [formInput(r,"つづり",text),formInput(r,"単語の発音記号",ipa),formInput(r,"単語の読み",kana)];
      rows.push(fields); groups.append(r);
    };
    old.forEach(s=>add(s.text.value,s.ipa.value,s.reading.value));
    if (!old.length) add(w.surface);
    d.body.append(button("音節を追加",()=>add(),"link"),button("最後の音節を外す",()=>{
      if (rows.length > 1) {rows.pop(); groups.lastChild.remove();}
    },"link"));
    if ((phrase.language || song.metadata.sourceLanguage) === "en" &&
        (song.metadata.englishPronunciation || "american") === "american") {
      const entry = SingingEngine.analyze(w.surface).lines[0]?.words[0];
      if (entry?.alternatives.length) {
        d.body.append(element("p","","辞書にある読みを選ぶ"));
        const choices = element("div","alt-list");
        entry.alternatives.forEach(a=>choices.append(button(a.kana.join("")+" /"+a.ipa.join("")+"/",()=>{
          rows.length=0; groups.replaceChildren();
          entry.segments.forEach((s,i)=>add(s,a.ipa[i] || "",a.kana[i] || ""));
        }))); d.body.append(choices);
      }
    }
    const meaning = formInput(d.body,"この単語の意味",w.contextualMeaning.value);
    const err = element("p","dialog-error"); err.setAttribute("role","alert"); d.body.append(err);
    d.foot.append(button("戻る",d.close),button("反映",()=>{
      const parts = rows.map(([s,i,k])=>({text:s.value,ipa:i.value.trim(),kana:k.value.trim()}));
      const spelling = parts.map(s=>s.text).join("");
      if (parts.some(s=>!s.text) || (spelling !== w.surface && spelling !== old.map(s=>s.text.value).join(""))) {
        err.textContent = "音節のつづりをつなぐと元の単語になるように入力してください。"; return;
      }
      try { Worksheet.applyWord(song,view,w,parts,meaning.value.trim(),"manual"); changed(); d.close(); }
      catch (e) {err.textContent = e.message;}
    },"primary")); d.show();
  }
  function buildSheet(interactive) {
    const frag = document.createDocumentFragment();
    frag.append(element("h1","sheet-title",song.metadata.title));
    for (const p of view.lines) {
      if (!p.originalText.trim()) {frag.append(element("div","stanza"));continue;}
      const line = element("section","line");
      line.append(element("p","original",p.originalText));
      if ($("meaning").checked) {
        if (interactive) {
          const b = button(p.translation.value || "＋ 行の訳を入力",()=>editPhrase(p),"translation edit"+(p.translation.value?"":" ui-only"));
          b.disabled = !!job; line.append(b);
        } else if (p.translation.value) line.append(element("p","translation",p.translation.value));
      }
      const group = element("div","word-list");
      for (const id of p.wordIDs) {
        const w = view.words.get(id), segments = w.syllableIDs.map(s=>view.syllables.get(s));
        const token = interactive ? button("",()=>editWord(w),"token") : element("div","token");
        if (interactive) {token.disabled = !!job; token.setAttribute("aria-label",w.surface+"を編集");}
        const spelling = element("span","spelling");
        for (const s of segments) spelling.append(element("span","",s.text.value));
        if (!segments.length) spelling.textContent = w.surface;
        token.append(spelling);
        const {kana,ipa} = Worksheet.displayReading(song,p,w,segments);
        if ($("kana").checked && kana) token.append(element("span","pron",kana));
        if ($("ipa").checked && ipa) token.append(element("span","ipa","/"+ipa+"/"));
        if ($("meaning").checked && w.contextualMeaning.value) token.append(element("span","gloss",w.contextualMeaning.value));
        if (interactive && !ipa && !kana) token.append(element("span","todo","読みを確認"));
        group.append(token);
      }
      line.append(group); frag.append(line);
    }
    return frag;
  }
  function render() {
    $("paper").replaceChildren(buildSheet(true));
    $("count").textContent = view.lines.filter(p=>p.originalText.trim()).length+"行　·　"+song.words.length+"語";
    $("ai").disabled = !!job || song.metadata.sourceLanguage !== "en" ||
      (song.metadata.englishPronunciation || "american") !== "american" || !song.words.length;
    for (const id of ["title","lyrics","generate","open","sample"]) $(id).disabled=!!job;
  }
  const printHTML = () => {
    const clean = document.implementation.createHTMLDocument(song.metadata.title);
    clean.documentElement.lang="ja"; clean.head.append(element("style","",nativeCSS+printCSS));
    clean.body.append(buildSheet(false)); return "<!doctype html>"+clean.documentElement.outerHTML;
  };
  function fresh() {
    if (!stale()) return true;
    say("入力欄に未反映の変更があります。先に「教材を作成」を選んでください。"); $("generate").focus(); return false;
  }
  function doPrint(action) {
    if (!fresh()) return;
    if (bridge) bridge.postMessage({action,html:printHTML(),filename:song.metadata.title});
    else window.print();
  }
  $("print").onclick = ()=>doPrint("print"); $("sharePDF").hidden = !bridge; $("sharePDF").onclick=()=>doPrint("sharePDF");
  $("save").onclick=()=>{
    if (!fresh()) return;
    const text = JSON.stringify(song,null,2), filename = song.metadata.title.replace(/[/\\:\x00-\x1f]/g,"_")+".json";
    if (bridge) bridge.postMessage({action:"shareText",text,filename});
    else {
      const url = URL.createObjectURL(new Blob([text],{type:"application/json"}));
      const a = element("a"); a.href=url; a.download=filename; document.body.append(a); a.click(); a.remove();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
    }
  };
  $("open").onclick=()=>$("file").click();
  $("file").onchange=async e=>{
    const file=e.target.files[0]; e.target.value=""; if (!file || job) return;
    try {
      if (file.size > 20000000) throw Error("教材データは20MBまで開けます。");
      const next=JSON.parse(await file.text()); Worksheet.index(next);
      if ((edited || stale()) && !await confirmAction("今の教材を、選んだ教材に入れ替えます。必要な変更は先に保存してください。","入れ替える")) return;
      edited=true; install(next); persist(); say("教材データを開きました。");
    } catch(e) {say(e instanceof SyntaxError ? "教材データのJSONを読み取れませんでした。" : e.message);}
  };
  $("generate").onclick=async()=>{
    const input=inputs();
    if (!input.lyrics.trim()) {say("歌詞を1行以上入力してください。"); $("lyrics").focus(); return;}
    if (input.lyrics.length>16000 || input.lyrics.split("\n").length>250) {say("1回に作成できる歌詞は250行・16,000文字までです。");return;}
    if (input.lyrics === sourceLyrics) {
      song.metadata.title=input.title; sourceTitle=input.title; $("title").value=input.title;
      changed(); say("教材に反映しました。"); return;
    }
    if (edited && !await confirmAction("教材を作り直すと、今の教材で編集した読みや訳を置き換えます。必要に応じて先に教材データを保存してください。","作り直す")) return;
    edited=false; install(Worksheet.make(input.title,input.lyrics)); persist(); say("教材を作成しました。単語を選ぶと読みと意味を編集できます。");
    if (matchMedia("(max-width:660px)").matches) $("paper").scrollIntoView({block:"start"});
  };
  $("sample").onclick=async()=>{
    if ((edited || stale() || sourceLyrics !== example.lyrics) && !await confirmAction("曲名と歌詞の入力欄を例文に入れ替えます。","例文を使う")) return;
    $("title").value=example.title; $("lyrics").value=example.lyrics; pending();
  };
  $("help").onclick=showHelp;
  ["lyrics","title"].forEach(k=>$(k).oninput=pending);
  toggles.forEach(k=>$(k).onchange=()=>{render();persist();});
  $("ai").onclick=()=>{
    if (!fresh()) return;
    if (!bridge && !globalThis.isSecureContext && location.protocol !== "file:") {
      say("APIキーを使うときはHTTPSのWeb版、Macで展開したWeb版、またはアプリ版を開いてください。会場のHTTP接続では端末内の辞書と手動編集を使えます。");
      return;
    }
    const d = dialog("OpenAIで読みと意味を補完");
    d.body.append(element("p","","教材の英語の歌詞を行ごとにOpenAIに送り、音節・読み・日本語訳を補います。ご自身のAPI利用料がかかります。手で編集した項目は保持します。"));
    const input=formInput(d.body,"ご自身のOpenAI APIキー","","password"); input.autocomplete="off"; input.spellcheck=false;
    d.body.append(element("p","hint","キーは今回の補完の間だけ使います。教材や端末には保存しません。"));
    const err=element("p","dialog-error"); d.body.append(err);
    d.foot.append(button("戻る",()=>{input.value="";d.close();}),button("歌詞を送信して補完",()=>{
      const key=input.value.trim(); if (!key) {err.textContent="APIキーを入力してください。";return;}
      input.value=""; d.close(); runAI(key);
    },"primary")); d.show();
  };
  async function runAI(key) {
    if (job) return;
    const controller = new AbortController(); job=controller; render();
    const target=view.lines.filter(p=>p.wordIDs.length && (p.language || song.metadata.sourceLanguage)==="en");
    let done=0;
    try {
      for (const p of target) {
        say("OpenAIで補完中　"+(done+1)+" / "+target.length+"行　");
        $("status").append(button("中止",()=>controller.abort(),"link"));
        const words=p.wordIDs.map(id=>view.words.get(id));
        const response=await WorksheetAI.completeLine(p.originalText,words.map(w=>w.surface),key,controller.signal);
        if (controller.signal.aborted) break;
        words.forEach((w,i)=>Worksheet.applyWord(song,view,w,response.words[i].segments,response.words[i].meaning,"ai"));
        Worksheet.setField(p,"translation",response.translation,"ai"); done++; changed();
      }
      say(done+"行の補完が完了しました。読みと訳を確認してください。");
    } catch(e) {
      say((controller.signal.aborted ? "補完を中止しました。" : "補完を停止しました。"+e.message)+" 完了した行は"+done+"行です。");
    } finally { job=null; render(); }
  }
  try {
    if (!globalThis.SingingEngine) throw Error("発音辞書が見つかりません。配布フォルダをすべて展開してから開いてください。");
    let draft;
    try {draft=JSON.parse(localStorage.getItem(keyName));} catch {}
    let restored=false;
    if (draft) {
      try {
        install(draft.song);
        if (typeof draft.title==="string") $("title").value=draft.title;
        if (typeof draft.lyrics==="string") $("lyrics").value=draft.lyrics;
        if (Array.isArray(draft.options)) toggles.forEach((k,i)=>$(k).checked=draft.options[i]!==false);
        edited=!!draft.edited; render(); restored=true;
        say(stale() ? "未反映の入力も復元しました。「教材を作成」で反映します。" : "この端末の前回の教材を開きました。");
      } catch {}
    }
    if (!restored) {install(Worksheet.make(example.title,example.lyrics));say("入力例を表示しています。ご自分の歌詞に入れ替えてください。");}
  } catch(e) {say(e.message);}
})();
