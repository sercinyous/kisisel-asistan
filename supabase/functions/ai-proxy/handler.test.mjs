// ai-proxy istek akışının testleri (sahte oturum doğrulama, kota ve Gemini ile):
//   node --experimental-strip-types --test supabase/functions/
import assert from "node:assert/strict";
import { test } from "node:test";

import { createHandler } from "./handler.ts";

const GEMINI_KEY = "gemini-gizli-anahtar";
const USER_TEXT = "kullanıcının-özel-metni-12345";

const GEMINI_OK = {
  candidates: [{ content: { role: "model", parts: [{ text: '{"tasks":[]}' }] }, finishReason: "STOP" }],
  usageMetadata: { totalTokenCount: 12 },
};

function geminiOk(body = GEMINI_OK) {
  return async () => new Response(JSON.stringify(body), { status: 200 });
}

function geminiBody(extra = {}) {
  return {
    systemInstruction: { parts: [{ text: "talimat" }] },
    contents: [{ role: "user", parts: [{ text: USER_TEXT }] }],
    generationConfig: { maxOutputTokens: 8192, responseMimeType: "application/json" },
    ...extra,
  };
}

/** consume_ai_quota gibi: kota içindeyse atomik artırır; kullanıcı ve tür ayrı sayılır. */
function memoryQuota() {
  const used = new Map();
  return {
    used,
    consume: async (userId, kind, limit) => {
      const key = `${userId}/${kind}`;
      const count = used.get(key) ?? 0;
      if (count >= limit) return false;
      used.set(key, count + 1);
      return true;
    },
  };
}

function setup(overrides = {}) {
  const calls = { jwt: [], consent: [], quota: [], fetch: [], log: [] };
  const quota = memoryQuota();
  const store = {
    userIdFromJwt: async (token) => {
      calls.jwt.push(token);
      if (token === "jwt-ali") return "user-ali";
      if (token === "jwt-veli") return "user-veli";
      return null;
    },
    hasAiConsent: async (userId) => {
      calls.consent.push(userId);
      return true;
    },
    consumeQuota: async (userId, kind, limit) => {
      calls.quota.push({ userId, kind, limit });
      return quota.consume(userId, kind, limit);
    },
    ...overrides.store,
  };
  const fetchImpl = overrides.fetch ?? geminiOk();
  const handler = createHandler({
    store,
    geminiApiKey: GEMINI_KEY,
    geminiModel: "gemini-3.8-flash",
    dailyLimit: 100,
    fetch: async (url, init) => {
      calls.fetch.push({ url, init });
      return fetchImpl(url, init);
    },
    log: (message) => calls.log.push(message),
    ...overrides.deps,
  });
  return { handler, calls, quota };
}

function post(body, headers = { Authorization: "Bearer jwt-ali" }) {
  return new Request("https://proje.supabase.co/functions/v1/ai-proxy", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function errorOf(response) {
  const body = await response.json();
  assert.deepEqual(Object.keys(body), ["error"], "hata gövdesi yalnızca {error}");
  assert.equal(typeof body.error, "string");
  return body.error;
}

// ------------------------------------------------------------- yöntem / CORS

test("OPTIONS: CORS ön uçuşu 204 ve başlıklarla döner; oturum/Gemini/kota gerekmez", async () => {
  const { handler, calls } = setup();
  const response = await handler(new Request("https://x/functions/v1/ai-proxy", { method: "OPTIONS" }));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.match(response.headers.get("Access-Control-Allow-Headers"), /authorization/);
  assert.match(response.headers.get("Access-Control-Allow-Methods"), /POST/);
  assert.equal(calls.jwt.length + calls.quota.length + calls.fetch.length, 0);
});

test("POST dışı yöntem 405 ve Türkçe hata", async () => {
  const { handler } = setup();
  const response = await handler(new Request("https://x/functions/v1/ai-proxy", { method: "GET" }));
  assert.equal(response.status, 405);
  assert.match(await errorOf(response), /POST/);
});

test("her yanıtta CORS başlığı vardır (başarı ve hata)", async () => {
  const { handler } = setup();
  const ok = await handler(post(geminiBody()));
  const unauthorized = await handler(post(geminiBody(), {}));
  const bad = await handler(post("{bozuk"));
  for (const response of [ok, unauthorized, bad]) {
    assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
    assert.match(response.headers.get("Content-Type"), /application\/json/);
  }
});

// ------------------------------------------------------------------- oturum

test("Authorization yoksa 401; oturum, kota ve Gemini'ye dokunulmaz", async () => {
  const { handler, calls } = setup();
  const response = await handler(post(geminiBody(), {}));
  assert.equal(response.status, 401);
  assert.match(await errorOf(response), /Oturum/);
  assert.equal(calls.jwt.length, 0);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("geçersiz/sahte/anon JWT 401; kota ve Gemini'ye dokunulmaz", async () => {
  const { handler, calls } = setup();
  for (const header of ["Bearer sahte-jwt", "Bearer anon-anahtari", "Basic abc", "Bearer"]) {
    const response = await handler(post(geminiBody(), { Authorization: header }));
    assert.equal(response.status, 401, header);
  }
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("oturum doğrulaması hata verirse 500 (401 değil), kota ve Gemini'ye dokunulmaz", async () => {
  const { handler, calls } = setup({
    store: { userIdFromJwt: async () => { throw new Error("auth servisi kapalı"); } },
  });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 500);
  assert.match(await errorOf(response), /doğrulanamadı/);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

// ------------------------------------------------------------ yapılandırma

test("GEMINI_API_KEY yoksa 500, kota harcanmaz, Gemini çağrılmaz", async () => {
  const { handler, calls } = setup({ deps: { geminiApiKey: "" } });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 500);
  assert.match(await errorOf(response), /yapılandırması eksik/);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("bozuk GEMINI_MODEL adı 500; URL'ye girmez", async () => {
  const { handler, calls } = setup({ deps: { geminiModel: "x/../y?key=1" } });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 500);
  assert.equal(calls.fetch.length, 0);
});

// ----------------------------------------------------------- gövde sınırları

test("gövde sınırı aşılınca 413; kota harcanmaz, Gemini çağrılmaz", async () => {
  const { handler, calls } = setup({ deps: { maxBodyBytes: 200 } });
  const big = geminiBody({ contents: [{ role: "user", parts: [{ text: "a".repeat(500) }] }] });
  const response = await handler(post(big));
  assert.equal(response.status, 413);
  assert.match(await errorOf(response), /büyük/);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("varsayılan sınır 64 KB: 64 KB altı geçer, üstü 413", async () => {
  const { handler } = setup();
  // Metin sınırı (8000) ayrı denetlenir; gövde boyutu talimatla sınanır.
  const pad = (n) => geminiBody({ systemInstruction: { parts: [{ text: "a".repeat(n) }] } });
  assert.equal((await handler(post(pad(20 * 1024)))).status, 200);
  assert.equal((await handler(post(pad(70 * 1024)))).status, 413);
});

test("Content-Length başlığı olmayan akışlı büyük gövde de 413", async () => {
  const { handler, calls } = setup({ deps: { maxBodyBytes: 100 } });
  const stream = new ReadableStream({
    pull(controller) {
      controller.enqueue(new Uint8Array(50));
    },
  });
  const request = new Request("https://x/functions/v1/ai-proxy", {
    method: "POST",
    headers: { Authorization: "Bearer jwt-ali" },
    body: stream,
    duplex: "half",
  });
  assert.equal((await handler(request)).status, 413);
  assert.equal(calls.quota.length, 0);
});

test("geçersiz istekler 400 döner ve kotayı yemez", async () => {
  const { handler, calls, quota } = setup();
  const cases = [
    "{bozuk",
    "",
    "[]",
    "null",
    JSON.stringify({}),
    JSON.stringify({ contents: [] }),
    JSON.stringify({ contents: [{ parts: [{ inlineData: { mimeType: "image/png", data: "AAAA" } }] }] }),
  ];
  for (const body of cases) {
    const response = await handler(post(body));
    assert.equal(response.status, 400, body);
    await errorOf(response);
  }
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
  assert.equal(quota.used.size, 0);
});

// ------------------------------------------------------------------ başarı

test("başarı: Gemini yanıtı olduğu gibi 200 ile döner", async () => {
  const { handler } = setup();
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), GEMINI_OK);
});

test("başarı: yanıt gövdesi bayt bayt aynıdır (yeniden serileştirilmez)", async () => {
  const raw = '{ "candidates":[ {"content":{"parts":[{"text":"çalışıyor"}]}} ] }';
  const { handler } = setup({ fetch: async () => new Response(raw, { status: 200 }) });
  const response = await handler(post(geminiBody()));
  assert.equal(await response.text(), raw);
});

test("Gemini isteği: uç nokta, model secret'tan, anahtar yalnızca başlıkta, zaman aşımı sinyali", async () => {
  const { handler, calls } = setup({ deps: { geminiModel: "gemini-ozel-model" } });
  await handler(post(geminiBody()));
  assert.equal(calls.fetch.length, 1);
  const { url, init } = calls.fetch[0];
  assert.equal(url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-ozel-model:generateContent");
  assert.equal(init.method, "POST");
  assert.equal(init.headers["x-goog-api-key"], GEMINI_KEY);
  assert.ok(!url.includes(GEMINI_KEY));
  assert.ok(init.signal instanceof AbortSignal);
  assert.ok(!("Authorization" in init.headers), "kullanıcı JWT'si Gemini'ye iletilmez");
});

test("model seçimi istemcide değil sunucudadır: gövdedeki model alanı yok sayılır", async () => {
  const { handler, calls } = setup();
  await handler(post(geminiBody({ model: "gemini-pahali-model" })));
  assert.ok(calls.fetch[0].url.includes("gemini-3.8-flash"));
  assert.equal("model" in JSON.parse(calls.fetch[0].init.body), false);
});

test("Gemini'ye giden gövde sınırlanır: araçlar atılır, maxOutputTokens tavana kırpılır, tek aday", async () => {
  const { handler, calls } = setup();
  await handler(post(geminiBody({
    tools: [{ googleSearch: {} }],
    cachedContent: "cachedContents/abc",
    generationConfig: { maxOutputTokens: 1_000_000, candidateCount: 8, responseMimeType: "application/json" },
  })));
  const sent = JSON.parse(calls.fetch[0].init.body);
  assert.deepEqual(Object.keys(sent).sort(), ["contents", "generationConfig", "systemInstruction"]);
  assert.equal(sent.generationConfig.maxOutputTokens, 4096);
  assert.deepEqual(sent.generationConfig.thinkingConfig, { thinkingLevel: "low" });
  assert.equal(sent.generationConfig.candidateCount, 1);
  assert.equal(sent.generationConfig.responseMimeType, "application/json");
  assert.equal(sent.contents[0].parts[0].text, USER_TEXT);
});

test("maxOutputTokens verilmezse varsayılan sınır eklenir", async () => {
  const { handler, calls } = setup();
  await handler(post({ contents: [{ role: "user", parts: [{ text: "merhaba" }] }] }));
  assert.equal(JSON.parse(calls.fetch[0].init.body).generationConfig.maxOutputTokens, 2048);
});

// -------------------------------------------------------------------- kota

test("kota: oturumdaki kullanıcı, 'ai' türü ve yapılandırılan sınırla bir kez düşülür", async () => {
  const { handler, calls } = setup({ deps: { dailyLimit: 42 } });
  await handler(post(geminiBody()));
  assert.deepEqual(calls.quota, [{ userId: "user-ali", kind: "ai", limit: 42 }]);
});

test("kota: kullanıcı kimliği istemci gövdesinden değil JWT'den gelir", async () => {
  const { handler, calls } = setup();
  await handler(post(geminiBody({ user_id: "user-veli", userId: "user-veli", p_user: "user-veli" })));
  assert.equal(calls.quota[0].userId, "user-ali");
});

test("kota: sınır dolunca 429 ve Türkçe mesaj; Gemini çağrılmaz", async () => {
  const { handler, calls } = setup({ deps: { dailyLimit: 3 } });
  for (let i = 1; i <= 3; i++) {
    assert.equal((await handler(post(geminiBody()))).status, 200, `${i}. istek`);
  }
  assert.equal(calls.fetch.length, 3);

  const blocked = await handler(post(geminiBody()));
  assert.equal(blocked.status, 429);
  const message = await errorOf(blocked);
  assert.match(message, /Günlük AI kullanım sınırına \(3 istek\) ulaştın/);
  assert.match(message, /Yarın/);
  assert.equal(calls.fetch.length, 3, "kota aşılınca Gemini çağrılmaz");
});

test("kota: varsayılan senaryoda 100/gün; 101. istek 429", async () => {
  const { handler, calls } = setup({ deps: { dailyLimit: 100 } });
  for (let i = 0; i < 100; i++) await handler(post(geminiBody()));
  assert.equal(calls.fetch.length, 100);
  const blocked = await handler(post(geminiBody()));
  assert.equal(blocked.status, 429);
  assert.equal(calls.fetch.length, 100);
});

test("kota: kullanıcılar birbirinden bağımsızdır", async () => {
  const { handler, calls } = setup({ deps: { dailyLimit: 1 } });
  assert.equal((await handler(post(geminiBody(), { Authorization: "Bearer jwt-ali" }))).status, 200);
  assert.equal((await handler(post(geminiBody(), { Authorization: "Bearer jwt-ali" }))).status, 429);
  assert.equal((await handler(post(geminiBody(), { Authorization: "Bearer jwt-veli" }))).status, 200);
  assert.deepEqual(calls.quota.map((q) => q.userId), ["user-ali", "user-ali", "user-veli"]);
});

test("kota: eşzamanlı istekler sınırı aşamaz", async () => {
  const { handler, calls } = setup({ deps: { dailyLimit: 5 } });
  const responses = await Promise.all(Array.from({ length: 20 }, () => handler(post(geminiBody()))));
  const statuses = responses.map((r) => r.status);
  assert.equal(statuses.filter((s) => s === 200).length, 5);
  assert.equal(statuses.filter((s) => s === 429).length, 15);
  assert.equal(calls.fetch.length, 5);
});

test("kota 'report_regen' sayacından ayrıdır: yeniden üretim hakkı AI kotasını yemez", async () => {
  const { handler, quota } = setup({ deps: { dailyLimit: 1 } });
  quota.used.set("user-ali/report_regen", 10);
  assert.equal((await handler(post(geminiBody()))).status, 200);
});

test("kota düşülemezse (RPC hatası) 500 ve Gemini çağrılmaz", async () => {
  const { handler, calls } = setup({
    store: { consumeQuota: async () => { throw new Error("rpc hatası"); } },
  });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 500);
  assert.match(await errorOf(response), /kota/i);
  assert.equal(calls.fetch.length, 0);
});

// --------------------------------------------------------------- Gemini hata

for (const [upstream, expected, pattern] of [
  [402, 402, /faturalandırma/],
  [400, 400, /geçersiz/],
  [429, 503, /yoğun/], // Gemini'nin kendi hız sınırı, kota 429'u ile karışmaz
  [500, 503, /yoğun/],
  [503, 503, /yoğun/],
  [401, 502, /yapılandırma/], // istemci "oturum yok" sanmasın
  [403, 502, /yapılandırma/],
  [404, 502, /yapılandırma/], // istemci "fonksiyon kurulmamış" sanmasın
]) {
  test(`Gemini ${upstream} -> istemciye ${expected}, Türkçe ileti`, async () => {
    const { handler } = setup({
      fetch: async () => new Response(JSON.stringify({ error: { message: `ham hata ${GEMINI_KEY}` } }), { status: upstream }),
    });
    const response = await handler(post(geminiBody()));
    assert.equal(response.status, expected);
    const message = await errorOf(response);
    assert.match(message, pattern);
    assert.ok(!message.includes(GEMINI_KEY) && !message.includes("ham hata"), "Gemini ayrıntısı iletilmez");
  });
}

test("Gemini zaman aşımı 504", async () => {
  const { handler } = setup({ fetch: async () => { throw new DOMException("süre doldu", "TimeoutError"); } });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 504);
  assert.match(await errorOf(response), /zamanında/);
});

test("Gemini ağ hatası 503", async () => {
  const { handler } = setup({ fetch: async () => { throw new TypeError("fetch failed"); } });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 503);
  assert.match(await errorOf(response), /ulaşılamadı/);
});

test("Gemini yanıt gövdesi okunurken kesilirse 503", async () => {
  const broken = new Response(
    new ReadableStream({ pull(controller) { controller.error(new TypeError("terminated")); } }),
    { status: 200 },
  );
  const { handler } = setup({ fetch: async () => broken });
  assert.equal((await handler(post(geminiBody()))).status, 503);
});

test("gerçek zaman aşımı: yavaş Gemini upstreamTimeoutMs sonunda 504 olur", async () => {
  // AbortSignal.timeout zamanlayıcısı Node'da olay döngüsünü tutmaz; test beklerken döngü canlı kalsın.
  const keepAlive = setTimeout(() => {}, 5_000);
  try {
    const { handler } = setup({
      deps: { upstreamTimeoutMs: 30 },
      fetch: (_url, init) =>
        new Promise((_resolve, reject) => {
          init.signal.addEventListener("abort", () => reject(init.signal.reason));
        }),
    });
    const response = await handler(post(geminiBody()));
    assert.equal(response.status, 504);
  } finally {
    clearTimeout(keepAlive);
  }
});

// ------------------------------------------------------------ gizlilik / günlük

test("günlüğe anahtar, kullanıcı metni ya da Gemini yanıt gövdesi yazılmaz", async () => {
  const failing = [
    async () => new Response(`sızıntı ${GEMINI_KEY} ${USER_TEXT}`, { status: 403 }),
    async () => new Response(`sızıntı ${GEMINI_KEY}`, { status: 500 }),
    async () => { throw new TypeError(`fetch failed ${GEMINI_KEY} ${USER_TEXT}`); },
  ];
  for (const fetchImpl of failing) {
    const { handler, calls } = setup({ fetch: fetchImpl });
    await handler(post(geminiBody()));
    assert.ok(calls.log.length > 0);
    for (const line of calls.log) {
      assert.ok(!line.includes(GEMINI_KEY), line);
      assert.ok(!line.includes(USER_TEXT), line);
      assert.ok(!line.includes("jwt-ali"), line);
    }
  }
});

test("hata yanıtlarında anahtar ya da istek metni yoktur", async () => {
  const { handler } = setup({
    fetch: async () => new Response(`ham ${GEMINI_KEY} ${USER_TEXT}`, { status: 400 }),
  });
  const response = await handler(post(geminiBody()));
  const text = await response.text();
  assert.ok(!text.includes(GEMINI_KEY) && !text.includes(USER_TEXT));
});

test("Gemini 5xx ya da ağ hatasında düşülen kota iade edilir; 4xx'te edilmez", async () => {
  for (const [fetchImpl, refunds] of [
    [async () => new Response("{}", { status: 503 }), 1],
    [async () => { throw new Error("ağ"); }, 1],
    [async () => new Response("{}", { status: 400 }), 0],
  ]) {
    const refunded = [];
    const { handler } = setup({
      fetch: fetchImpl,
      store: { refundQuota: async (u, k) => { refunded.push([u, k]); } },
    });
    await handler(new Request("https://x/functions/v1/ai-proxy", {
      method: "POST",
      headers: { Authorization: "Bearer jwt-ali", "Content-Type": "application/json" },
      body: JSON.stringify(geminiBody()),
    }));
    assert.equal(refunded.length, refunds);
  }
});

// ---------------------------------------------------------------- AI onayı

test("AI onayı yoksa 403; Gemini çağrılmaz, kota harcanmaz", async () => {
  const { handler, calls } = setup({ store: { hasAiConsent: async () => false } });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 403);
  assert.match(await errorOf(response), /onay/);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("AI onayı okunamazsa 500; Gemini çağrılmaz, kota harcanmaz", async () => {
  const { handler, calls } = setup({
    store: { hasAiConsent: async () => { throw new Error("db"); } },
  });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 500);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("AI onayı varsa istek Gemini'ye gider ve onay kullanıcı kimliğiyle sorulur", async () => {
  const { handler, calls } = setup();
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 200);
  assert.deepEqual(calls.consent, ["user-ali"]);
  assert.equal(calls.fetch.length, 1);
});

for (const [status, refunded] of [[400, false], [401, true], [402, true], [403, true], [404, true], [429, true], [500, true]]) {
  test(`Gemini ${status}: kota ${refunded ? "iade edilir" : "iade edilmez"}`, async () => {
    const refunds = [];
    const { handler } = setup({
      fetch: async () => new Response("{}", { status }),
      store: { refundQuota: async (userId, kind) => { refunds.push({ userId, kind }); } },
    });
    await handler(post(geminiBody()));
    assert.equal(refunds.length, refunded ? 1 : 0);
  });
}

// ------------------------------------------------------- maliyet emniyeti (ICG2-02)

test("genel günlük sınır dolunca 503 döner, Gemini çağrılmaz, kişisel birim iade edilir", async () => {
  const refunds = [];
  const { handler, calls } = setup({
    store: {
      consumeGlobalQuota: async (limit) => {
        assert.equal(limit, 7);
        return false;
      },
      refundQuota: async (userId, kind) => refunds.push({ userId, kind }),
    },
    deps: { globalDailyLimit: 7 },
  });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 503);
  assert.match(await errorOf(response), /genel kullanım sınırına/);
  assert.equal(calls.fetch.length, 0);
  assert.deepEqual(refunds, [{ userId: "user-ali", kind: "ai" }]);
});

test("genel sınır içindeyse istek geçer", async () => {
  let used = 0;
  const { handler, calls } = setup({
    store: { consumeGlobalQuota: async () => ++used <= 1 },
  });
  assert.equal((await handler(post(geminiBody()))).status, 200);
  assert.equal(calls.fetch.length, 1);
});

test("onay yoksa 403; kota düşülmez, Gemini çağrılmaz", async () => {
  const { handler, calls } = setup({ store: { hasAiConsent: async () => false } });
  const response = await handler(post(geminiBody()));
  assert.equal(response.status, 403);
  assert.equal(calls.quota.length, 0);
  assert.equal(calls.fetch.length, 0);
});

test("istemcinin düşünme düzeyi yok sayılır; her zaman low", async () => {
  const { handler, calls } = setup();
  await handler(post(geminiBody({
    generationConfig: { thinkingConfig: { thinkingLevel: "high", thinkingBudget: 99999 } },
  })));
  const sent = JSON.parse(calls.fetch[0].init.body);
  assert.deepEqual(sent.generationConfig.thinkingConfig, { thinkingLevel: "low" });
});

test("8000 karakteri aşan kullanıcı metni 400; kota düşülmez", async () => {
  const { handler, calls } = setup();
  const response = await handler(post(geminiBody({
    contents: [{ role: "user", parts: [{ text: "a".repeat(8001) }] }],
  })));
  assert.equal(response.status, 400);
  assert.match(await errorOf(response), /çok uzun/);
  assert.equal(calls.quota.length, 0);
});
