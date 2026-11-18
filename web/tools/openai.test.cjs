const assert = require("node:assert/strict");
const { test } = require("node:test");
require("../openai.js");

const original = "Think, think!";
const surfaces = ["Think", "think"];
const key = "mock-private-project-token";
function answer() {
  return { translation: "考えて、考えて！", words: surfaces.map(surface => ({
    surface, meaning: "考える", segments: [{ text: surface, ipa: "θɪŋk", kana: "シンク" }]
  })) };
}
function wrapped(result) {
  return { status: "completed", output: [{ type: "reasoning" }, { role: "assistant", type: "message",
    content: [{ type: "output_text", text: JSON.stringify(result) }] }] };
}
function response(payload, status = 200) {
  return new Response(JSON.stringify(payload), { status });
}

test("sends only the selected line to official Responses with a project key and strict format", async t => {
  const stub = t.mock.method(globalThis, "fetch", async (url, options) => {
    assert.equal(url, "https://api.openai.com/v1/responses");
    assert.equal(options.headers.Authorization, "Bearer " + key);
    assert.equal(options.redirect, "error");
    assert.equal(options.credentials, "omit");
    assert.equal(options.referrerPolicy, "no-referrer");
    const body = JSON.parse(options.body);
    assert.deepEqual(JSON.parse(body.input), { original, surfaces });
    assert.equal(body.model, "gpt-6.2-sol");
    assert.equal(body.store, false);
    assert.equal(body.text.format.strict, true);
    assert.equal(body.text.format.schema.additionalProperties, false);
    assert.equal(options.body.includes(key), false);
    return response(wrapped(answer()));
  });
  assert.deepEqual(await WorksheetAI.completeLine(original, surfaces, key), answer());
  assert.equal(stub.mock.callCount(), 1);
});

test("rejects changed spelling, count, order, invalid reading and extra output fields", async t => {
  const stub = t.mock.method(globalThis, "fetch");
  const invalidResults = [
    form => { form.words[0].segments[0].text = "think"; },
    form => { form.words.pop(); },
    form => { form.words.reverse(); },
    form => { form.words[1].segments[0].kana = "think"; },
    form => { form.words[1].segments[0].ipa = "ˈ"; },
    form => { form.extra = true; }
  ];
  for (const change of invalidResults) {
    const result = answer();
    change(result);
    stub.mock.mockImplementation(async () => response(wrapped(result)));
    await assert.rejects(WorksheetAI.completeLine(original, surfaces, key), /照合/);
  }
});

test("sanitizes provider/network errors, recognises exhausted grant and aborts before dispatch", async t => {
  const stub = t.mock.method(globalThis, "fetch", async () => {
    throw new Error("sensitive provider body " + key);
  });
  await assert.rejects(WorksheetAI.completeLine(original, surfaces, key), error => !error.message.includes(key) && /接続/.test(error.message));
  stub.mock.mockImplementation(async () => response({ error: { message: key, code: "credit_balance_exhausted" } }, 429));
  await assert.rejects(WorksheetAI.completeLine(original, surfaces, key), /クレジット残高/);
  stub.mock.mockImplementation(async () => response({ status: "incomplete", output: [] }));
  await assert.rejects(WorksheetAI.completeLine(original, surfaces, key), /完了できません/);
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(WorksheetAI.completeLine(original, surfaces, key, controller.signal), { name: "AbortError" });
  await assert.rejects(WorksheetAI.completeLine(original, ["missing"], key), /照合/);
  await assert.rejects(WorksheetAI.completeLine(original, surfaces, ""), /APIキー/);
  assert.equal(stub.mock.callCount(), 3);
});
