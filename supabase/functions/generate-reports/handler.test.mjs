// generate-reports istek akışının testleri (sahte veritabanı ve sahte Gemini ile):
//   node --experimental-strip-types --test supabase/functions/generate-reports/
import assert from "node:assert/strict";
import { test } from "node:test";

import { createHandler } from "./handler.ts";

const NOW = new Date("2026-11-16T20:45:00Z"); // Pazartesi 23:45 İstanbul
const METRICS = { work: { rate: 75 } };

function geminiOk(text = "Güzel bir gün.") {
  return async () =>
    new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }), { status: 200 });
}

function setup(overrides = {}) {
  const calls = { metrics: [], save: [], fetch: [], log: [] };
  const store = {
    userIdFromJwt: async (token) => (token === "gecerli-jwt" ? "user-1" : null),
    listUsers: async () => [
      { id: "user-1", timeZone: "Europe/Istanbul" },
      { id: "user-2", timeZone: "Europe/Istanbul" },
    ],
    timeZoneOf: async () => "Europe/Istanbul",
    metrics: async (kind, userId, date) => {
      calls.metrics.push({ kind, userId, date });
      return METRICS;
    },
    save: async (kind, userId, date, metrics, summary, status) => {
      calls.save.push({ kind, userId, date, metrics, summary, status });
    },
    ...overrides.store,
  };
  const fetchImpl = overrides.fetch ?? geminiOk();
  const handler = createHandler({
    store,
    cronSecret: "cron-gizli",
    geminiApiKey: "gemini-anahtar",
    geminiModel: "gemini-3.8-flash",
    fetch: async (url, init) => {
      calls.fetch.push({ url, init });
      return fetchImpl(url, init);
    },
    now: () => NOW,
    log: (message) => calls.log.push(message),
    ...overrides.deps,
  });
  return { handler, calls };
}

function post(body, headers = {}) {
  return new Request("https://proje.supabase.co/functions/v1/generate-reports", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

test("yetki yoksa 401 ve hiçbir şey üretilmez", async () => {
  const { handler, calls } = setup();
  const response = await handler(post({ kind: "daily" }));
  assert.equal(response.status, 401);
  assert.equal(calls.metrics.length, 0);
  assert.equal(calls.save.length, 0);
});

test("yanlış cron anahtarı ve geçersiz JWT 401", async () => {
  const { handler, calls } = setup();
  assert.equal((await handler(post({ kind: "daily" }, { "x-cron-secret": "yanlis" }))).status, 401);
  assert.equal((await handler(post({ kind: "daily" }, { Authorization: "Bearer sahte" }))).status, 401);
  assert.equal(calls.save.length, 0);
});

test("CRON_SECRET tanımsızken boş başlık kabul edilmez", async () => {
  const { handler } = setup({ deps: { cronSecret: "" } });
  assert.equal((await handler(post({ kind: "daily" }, { "x-cron-secret": "" }))).status, 401);
});

test("POST dışı yöntem 405", async () => {
  const { handler } = setup();
  const response = await handler(new Request("https://x/functions/v1/generate-reports", { method: "GET" }));
  assert.equal(response.status, 405);
});

test("cron: tüm kullanıcılar için günlük rapor (kullanıcının bugünü)", async () => {
  const { handler, calls } = setup();
  const response = await handler(post({ kind: "daily" }, { "x-cron-secret": "cron-gizli" }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true, kind: "daily", date: "2026-11-16", users: 2, failed: 0, ai_failed: 0,
  });
  assert.deepEqual(calls.save.map((s) => s.userId).sort(), ["user-1", "user-2"]);
  for (const saved of calls.save) {
    assert.equal(saved.kind, "daily");
    assert.equal(saved.date, "2026-11-16");
    assert.equal(saved.status, "ok");
    assert.equal(saved.summary, "Güzel bir gün.");
    assert.deepEqual(saved.metrics, METRICS);
  }
});

test("cron: haftalık rapor biten son hafta için", async () => {
  const { handler, calls } = setup({ deps: { now: () => new Date("2026-11-16T04:00:00Z") } });
  const response = await handler(post({ kind: "weekly" }, { "x-cron-secret": "cron-gizli" }));
  assert.equal((await response.json()).date, "2026-11-09");
  assert.deepEqual(calls.metrics[0], { kind: "weekly", userId: "user-1", date: "2026-11-09" });
});

test("JWT: yalnızca o kullanıcı için üretir", async () => {
  const { handler, calls } = setup();
  const response = await handler(
    post({ kind: "weekly", date: "2026-11-05" }, { Authorization: "Bearer gecerli-jwt" }),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true, kind: "weekly", date: "2026-11-02", users: 1, failed: 0, ai_failed: 0,
  });
  assert.deepEqual(calls.save.map((s) => s.userId), ["user-1"]);
});

test("JWT: ayar satırı yoksa İstanbul günü kullanılır", async () => {
  const { handler, calls } = setup({
    store: { timeZoneOf: async () => null },
    deps: { now: () => new Date("2026-11-16T21:30:00Z") }, // 00:30 İstanbul, 17 Kasım
  });
  await handler(post({ kind: "daily" }, { Authorization: "Bearer gecerli-jwt" }));
  assert.equal(calls.save[0].date, "2026-11-17");
});

test("Gemini isteği: uç nokta, anahtar başlıkta, zaman aşımı sinyali", async () => {
  const { handler, calls } = setup();
  await handler(post({ kind: "daily" }, { Authorization: "Bearer gecerli-jwt" }));
  assert.equal(calls.fetch.length, 1);
  const { url, init } = calls.fetch[0];
  assert.equal(url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent");
  assert.equal(init.method, "POST");
  assert.equal(init.headers["x-goog-api-key"], "gemini-anahtar");
  assert.ok(!url.includes("gemini-anahtar"));
  assert.ok(init.signal instanceof AbortSignal);
  assert.ok(JSON.parse(init.body).contents[0].parts[0].text.includes(JSON.stringify(METRICS)));
});

for (const [name, fetchImpl] of [
  ["HTTP 500", async () => new Response("hata", { status: 500 })],
  ["ağ hatası", async () => { throw new TypeError("fetch failed"); }],
  ["zaman aşımı", async () => { throw new DOMException("süre doldu", "TimeoutError"); }],
  ["boş yanıt", async () => new Response(JSON.stringify({ candidates: [] }), { status: 200 })],
  ["JSON olmayan yanıt", async () => new Response("<html>", { status: 200 })],
]) {
  test(`Gemini başarısız (${name}): rapor sayılarla ve 'failed' olarak kaydedilir`, async () => {
    const { handler, calls } = setup({ fetch: fetchImpl });
    const response = await handler(post({ kind: "daily" }, { Authorization: "Bearer gecerli-jwt" }));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      ok: true, kind: "daily", date: "2026-11-16", users: 1, failed: 0, ai_failed: 1,
    });
    assert.equal(calls.save.length, 1);
    assert.equal(calls.save[0].status, "failed");
    assert.equal(calls.save[0].summary, null);
    assert.deepEqual(calls.save[0].metrics, METRICS);
  });
}

test("GEMINI_API_KEY yoksa çağrı yapılmaz, rapor 'failed' kaydedilir", async () => {
  const { handler, calls } = setup({ deps: { geminiApiKey: "" } });
  await handler(post({ kind: "daily" }, { Authorization: "Bearer gecerli-jwt" }));
  assert.equal(calls.fetch.length, 0);
  assert.equal(calls.save[0].status, "failed");
});

test("bir kullanıcının hatası diğerini durdurmaz", async () => {
  const { handler, calls } = setup({
    store: {
      metrics: async (_kind, userId) => {
        if (userId === "user-1") throw new Error("veritabanı hatası");
        return METRICS;
      },
    },
  });
  const response = await handler(post({ kind: "daily" }, { "x-cron-secret": "cron-gizli" }));
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.ok, false);
  assert.equal(result.users, 2);
  assert.equal(result.failed, 1);
  assert.deepEqual(calls.save.map((s) => s.userId), ["user-2"]);
});

test("hiçbir rapor yazılamazsa 500", async () => {
  const { handler } = setup({
    store: { save: async () => { throw new Error("yazılamadı"); } },
  });
  const response = await handler(post({ kind: "daily" }, { Authorization: "Bearer gecerli-jwt" }));
  assert.equal(response.status, 500);
  assert.equal((await response.json()).ok, false);
});

test("girdi doğrulama: bozuk JSON, kind, tarih biçimi, gelecek tarih → 400", async () => {
  const { handler, calls } = setup();
  const auth = { Authorization: "Bearer gecerli-jwt" };
  assert.equal((await handler(post("{bozuk", auth))).status, 400);
  assert.equal((await handler(post({ kind: "aylik" }, auth))).status, 400);
  assert.equal((await handler(post({ kind: "daily", date: "16.11.2026" }, auth))).status, 400);
  const future = await handler(post({ kind: "daily", date: "2026-11-17" }, auth));
  assert.equal(future.status, 400);
  assert.match((await future.json()).error, /gelecek/i);
  assert.equal(calls.metrics.length, 0);
  assert.equal(calls.save.length, 0);
});

test("hata günlüğüne Gemini anahtarı ya da yanıt gövdesi yazılmaz", async () => {
  const { handler, calls } = setup({
    fetch: async () => new Response("gemini-anahtar sızıntısı", { status: 403 }),
  });
  await handler(post({ kind: "daily" }, { Authorization: "Bearer gecerli-jwt" }));
  assert.ok(calls.log.length > 0);
  for (const line of calls.log) assert.ok(!line.includes("gemini-anahtar"), line);
});

test("kullanıcı yoksa 200 ve users 0", async () => {
  const { handler } = setup({ store: { listUsers: async () => [] } });
  const response = await handler(post({ kind: "daily" }, { "x-cron-secret": "cron-gizli" }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true, kind: "daily", date: null, users: 0, failed: 0, ai_failed: 0,
  });
});
