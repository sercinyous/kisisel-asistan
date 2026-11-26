// ai-proxy saf mantığının testleri (istek doğrulama/sınırlama, hata eşleme):
//   node --experimental-strip-types --test supabase/functions/
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  buildUpstreamUrl,
  clampMaxOutputTokens,
  CORS_HEADERS,
  DEFAULT_MAX_OUTPUT_TOKENS,
  extractBearer,
  isValidModel,
  mapUpstreamError,
  MAX_CONTENT_ENTRIES,
  MAX_OUTPUT_TOKENS_LIMIT,
  MAX_PARTS_PER_CONTENT,
  quotaExceededMessage,
  readTextLimited,
  sanitizeRequest,
} from "./logic.ts";

const userContent = (text = "merhaba") => ({ role: "user", parts: [{ text }] });

test("sanitizeRequest: geçerli istek olduğu gibi (izinli alanlarla) geçer", () => {
  const result = sanitizeRequest({
    systemInstruction: { parts: [{ text: "talimat" }] },
    contents: [userContent("öğlen 200 gr tavuk")],
    generationConfig: {
      maxOutputTokens: 8192,
      responseMimeType: "application/json",
      responseSchema: { type: "OBJECT", properties: {} },
      thinkingConfig: { thinkingLevel: "low" },
    },
  });
  assert.ok(result.ok);
  assert.deepEqual(result.body.contents, [userContent("öğlen 200 gr tavuk")]);
  assert.deepEqual(result.body.systemInstruction, { parts: [{ text: "talimat" }] });
  const config = result.body.generationConfig;
  assert.equal(config.maxOutputTokens, 4096);
  assert.equal(config.responseMimeType, "application/json");
  assert.deepEqual(config.responseSchema, { type: "OBJECT", properties: {} });
  assert.deepEqual(config.thinkingConfig, { thinkingLevel: "low" });
  assert.equal(config.candidateCount, 1);
});

test("sanitizeRequest: systemInstruction ve generationConfig yoksa da geçer; varsayılan token sınırı eklenir", () => {
  const result = sanitizeRequest({ contents: [userContent()] });
  assert.ok(result.ok);
  assert.equal("systemInstruction" in result.body, false);
  assert.deepEqual(result.body.generationConfig, {
    maxOutputTokens: DEFAULT_MAX_OUTPUT_TOKENS,
    candidateCount: 1,
    thinkingConfig: { thinkingLevel: "low" },
  });
});

test("sanitizeRequest: izin verilmeyen üst düzey alanlar atılır (tools, cachedContent, safetySettings, model)", () => {
  const result = sanitizeRequest({
    contents: [userContent()],
    tools: [{ googleSearch: {} }, { codeExecution: {} }],
    toolConfig: { functionCallingConfig: { mode: "ANY" } },
    cachedContent: "cachedContents/abc",
    safetySettings: [{ category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" }],
    model: "gemini-pahali-model",
  });
  assert.ok(result.ok);
  assert.deepEqual(Object.keys(result.body).sort(), ["contents", "generationConfig"]);
});

test("sanitizeRequest: izin verilmeyen generationConfig alanları atılır, candidateCount 1'e sabitlenir", () => {
  const result = sanitizeRequest({
    contents: [userContent()],
    generationConfig: {
      candidateCount: 8,
      responseModalities: ["IMAGE"],
      speechConfig: {},
      temperature: 1,
      topP: 0.9,
      topK: 40,
      stopSequences: ["X"],
    },
  });
  assert.ok(result.ok);
  const config = result.body.generationConfig;
  assert.equal(config.candidateCount, 1);
  assert.equal("responseModalities" in config, false);
  assert.equal("speechConfig" in config, false);
  assert.equal(config.temperature, 1);
  assert.equal(config.topP, 0.9);
  assert.equal(config.topK, 40);
  assert.deepEqual(config.stopSequences, ["X"]);
});

test("clampMaxOutputTokens: tavana kırpar; eksik/bozuk değer varsayılana döner", () => {
  assert.equal(clampMaxOutputTokens(100), 100);
  assert.equal(clampMaxOutputTokens(2048), 2048);
  assert.equal(clampMaxOutputTokens(4096), 4096);
  assert.equal(clampMaxOutputTokens(8192), MAX_OUTPUT_TOKENS_LIMIT);
  assert.equal(clampMaxOutputTokens(1_000_000), MAX_OUTPUT_TOKENS_LIMIT);
  assert.equal(clampMaxOutputTokens(Number.MAX_SAFE_INTEGER), MAX_OUTPUT_TOKENS_LIMIT);
  assert.equal(clampMaxOutputTokens(99.9), 99);
  for (const bad of [undefined, null, "8192", 0, -1, NaN, Infinity, {}, []]) {
    assert.equal(clampMaxOutputTokens(bad), DEFAULT_MAX_OUTPUT_TOKENS, String(bad));
  }
});

test("sanitizeRequest: maxOutputTokens tavanı aşan değer kırpılır, sınırsız istenemez", () => {
  const huge = sanitizeRequest({ contents: [userContent()], generationConfig: { maxOutputTokens: 999999 } });
  assert.ok(huge.ok);
  assert.equal(huge.body.generationConfig.maxOutputTokens, MAX_OUTPUT_TOKENS_LIMIT);
  const missing = sanitizeRequest({ contents: [userContent()], generationConfig: {} });
  assert.ok(missing.ok);
  assert.equal(missing.body.generationConfig.maxOutputTokens, DEFAULT_MAX_OUTPUT_TOKENS);
});

test("sanitizeRequest: nesne olmayan gövde reddedilir", () => {
  for (const body of [null, undefined, "metin", 5, [], true]) {
    const result = sanitizeRequest(body);
    assert.equal(result.ok, false, String(body));
    assert.match(result.error, /JSON/);
  }
});

test("sanitizeRequest: contents eksik, boş, dizi değil ya da çok uzun -> reddedilir", () => {
  for (const contents of [undefined, null, [], {}, "x", new Array(MAX_CONTENT_ENTRIES + 1).fill(userContent())]) {
    const result = sanitizeRequest({ contents });
    assert.equal(result.ok, false);
    assert.match(result.error, /contents/);
  }
  assert.ok(sanitizeRequest({ contents: new Array(MAX_CONTENT_ENTRIES).fill(userContent()) }).ok);
});

test("sanitizeRequest: metin dışı parça (resim, dosya, işlev) reddedilir", () => {
  const bad = [
    { parts: [{ inlineData: { mimeType: "image/png", data: "AAAA" } }] },
    { parts: [{ fileData: { fileUri: "gs://x/y" } }] },
    { parts: [{ functionCall: { name: "x" } }] },
    { parts: [{ text: 5 }] },
    { parts: [] },
    { parts: "metin" },
    { parts: new Array(MAX_PARTS_PER_CONTENT + 1).fill({ text: "a" }) },
    "düz metin",
    null,
  ];
  for (const content of bad) {
    const result = sanitizeRequest({ contents: [content] });
    assert.equal(result.ok, false, JSON.stringify(content));
    assert.match(result.error, /metin/i);
  }
  const system = sanitizeRequest({
    contents: [userContent()],
    systemInstruction: { parts: [{ inlineData: { mimeType: "image/png", data: "AAAA" } }] },
  });
  assert.equal(system.ok, false);
});

test("sanitizeRequest: parçadan yalnızca text taşınır, bilinmeyen rol atılır", () => {
  const result = sanitizeRequest({
    contents: [{ role: "system", parts: [{ text: "a", thought: true, extra: 1 }] }],
  });
  assert.ok(result.ok);
  assert.deepEqual(result.body.contents, [{ parts: [{ text: "a" }] }]);
});

test("isValidModel / buildUpstreamUrl: model adı URL'ye güvenle girer, anahtar adreste yoktur", () => {
  assert.ok(isValidModel("gemini-3.8-flash"));
  assert.ok(isValidModel("gemini_2.5-pro"));
  for (const bad of ["", "a b", "a/b", "../x", "m?key=1", "m:generateContent", "x".repeat(101)]) {
    assert.equal(isValidModel(bad), false, bad);
  }
  assert.equal(
    buildUpstreamUrl("gemini-3.8-flash"),
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent",
  );
});

test("extractBearer", () => {
  assert.equal(extractBearer("Bearer abc.def.ghi"), "abc.def.ghi");
  assert.equal(extractBearer("bearer  tok  "), "tok");
  assert.equal(extractBearer(null), null);
  assert.equal(extractBearer(""), null);
  assert.equal(extractBearer("Basic abc"), null);
  assert.equal(extractBearer("Bearer"), null);
  assert.equal(extractBearer("Bearer a b"), null);
});

test("mapUpstreamError: 402 olduğu gibi; kota 429'undan ayrı olarak Gemini 429/5xx geçici (503)", () => {
  assert.equal(mapUpstreamError(402).status, 402);
  assert.equal(mapUpstreamError(400).status, 400);
  assert.equal(mapUpstreamError(429).status, 503);
  for (const status of [500, 502, 503, 504, 599]) assert.equal(mapUpstreamError(status).status, 503, String(status));
});

test("mapUpstreamError: Gemini 401/403/404 istemciye 401/404 olarak sızmaz (502)", () => {
  for (const status of [401, 403, 404]) {
    const mapped = mapUpstreamError(status);
    assert.equal(mapped.status, 502, String(status));
    assert.match(mapped.error, /yapılandırma/);
  }
  assert.equal(mapUpstreamError(418).status, 502);
  assert.equal(mapUpstreamError(302).status, 502);
});

test("mapUpstreamError: iletiler Türkçe, boş değil ve ayrıntı sızdırmaz", () => {
  for (const status of [400, 401, 402, 403, 404, 418, 429, 500, 503]) {
    const { error } = mapUpstreamError(status);
    assert.equal(typeof error, "string");
    assert.ok(error.length > 10);
    assert.ok(!/gemini api key|api[_ ]key/i.test(error), error);
  }
});

test("quotaExceededMessage: sınırı Türkçe iletiyle söyler", () => {
  assert.equal(quotaExceededMessage(100), "Günlük AI kullanım sınırına (100 istek) ulaştın. Yarın yeniden dene.");
});

test("CORS: tüm yöntem ve başlıklar tanımlı", () => {
  assert.equal(CORS_HEADERS["Access-Control-Allow-Origin"], "*");
  assert.match(CORS_HEADERS["Access-Control-Allow-Headers"], /authorization/);
  assert.match(CORS_HEADERS["Access-Control-Allow-Methods"], /POST/);
  assert.match(CORS_HEADERS["Access-Control-Allow-Methods"], /OPTIONS/);
});

function postWith(body, headers = {}) {
  return new Request("https://proje.supabase.co/functions/v1/ai-proxy", {
    method: "POST",
    headers,
    body,
  });
}

test("readTextLimited: sınır içindeki gövde (UTF-8 dahil) okunur", async () => {
  const text = JSON.stringify({ metin: "çalışıyor şğüöı" });
  const result = await readTextLimited(postWith(text), 1024);
  assert.deepEqual(result, { ok: true, text });
});

test("readTextLimited: tam sınırdaki gövde kabul edilir, bir bayt fazlası reddedilir", async () => {
  assert.equal((await readTextLimited(postWith("a".repeat(100)), 100)).ok, true);
  assert.equal((await readTextLimited(postWith("a".repeat(101)), 100)).ok, false);
});

test("readTextLimited: Content-Length sınırı aşıyorsa gövde hiç okunmaz", async () => {
  let pulled = false;
  const stream = new ReadableStream({
    pull(controller) {
      pulled = true;
      controller.enqueue(new TextEncoder().encode("a"));
      controller.close();
    },
  }, { highWaterMark: 0 });
  // Sunucu çalışma zamanındaki gerçek Request başlığı simüle edilir (yalnızca headers ve body kullanılır).
  const request = { headers: new Headers({ "content-length": "5000" }), body: stream };
  assert.equal((await readTextLimited(request, 100)).ok, false);
  assert.equal(pulled, false);
});

test("readTextLimited: Content-Length yoksa/yalansa akış sınırı aşınca kesilir", async () => {
  let chunks = 0;
  const stream = new ReadableStream({
    pull(controller) {
      chunks++;
      controller.enqueue(new Uint8Array(40));
      if (chunks > 1000) controller.close();
    },
  });
  const request = new Request("https://x/functions/v1/ai-proxy", {
    method: "POST",
    headers: { "content-length": "10" },
    body: stream,
    duplex: "half",
  });
  assert.equal((await readTextLimited(request, 100)).ok, false);
  assert.ok(chunks < 20, `sınırdan sonra okumaya devam edildi (${chunks})`);
});

test("readTextLimited: gövdesiz istek boş metin döner", async () => {
  const result = await readTextLimited(new Request("https://x/", { method: "POST" }), 100);
  assert.deepEqual(result, { ok: true, text: "" });
});
