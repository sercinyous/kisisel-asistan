// node --experimental-strip-types --test supabase/functions/delete-account/
import assert from "node:assert/strict";
import { test } from "node:test";

import { createHandler } from "./handler.ts";

function setup(overrides = {}) {
  const calls = [];
  const log = [];
  const store = {
    userFromJwt: async (t) => (t === "gecerli" ? { id: "u1", email: "Ali@Example.com" } : null),
    deleteFriendships: async (id) => calls.push(["friendships", id]),
    deleteFriendRequests: async (id, email) => calls.push(["requests", id, email]),
    deleteAvatars: async (id) => calls.push(["avatars", id]),
    deleteAuthUser: async (id) => calls.push(["auth", id]),
    ...overrides,
  };
  return { calls, log, handler: createHandler({ store, log: (m) => log.push(m) }) };
}

const req = (body, token = "gecerli", method = "POST") =>
  new Request("http://x/delete-account", {
    method,
    headers: token === null ? {} : { Authorization: `Bearer ${token}` },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });

test("geçerli istek sırayla siler", async () => {
  const { calls, handler } = setup();
  const res = await handler(req({ confirm: "SİL" }));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.deepEqual(calls, [
    ["friendships", "u1"],
    ["requests", "u1", "ali@example.com"],
    ["avatars", "u1"],
    ["auth", "u1"],
  ]);
});

test("JWT yoksa ya da geçersizse 401, hiçbir şey silinmez", async () => {
  for (const token of [null, "sahte"]) {
    const { calls, handler } = setup();
    const res = await handler(req({ confirm: "SİL" }, token));
    assert.equal(res.status, 401);
    assert.equal(calls.length, 0);
  }
});

test("onay yoksa 400", async () => {
  const { calls, handler } = setup();
  assert.equal((await handler(req({ confirm: "hayır" }))).status, 400);
  assert.equal((await handler(req("bozuk"))).status, 400);
  assert.equal(calls.length, 0);
});

test("GET 405, OPTIONS 204", async () => {
  const { handler } = setup();
  assert.equal((await handler(req(null, "gecerli", "GET"))).status, 405);
  assert.equal((await handler(req(null, "gecerli", "OPTIONS"))).status, 204);
});

test("bir adım başarısızsa auth kullanıcısı silinmez ve 500", async () => {
  const { calls, log, handler } = setup({
    deleteFriendRequests: async () => {
      throw new Error("db");
    },
  });
  const res = await handler(req({ confirm: "SİL" }));
  assert.equal(res.status, 500);
  assert.deepEqual(calls, [["friendships", "u1"]]);
  assert.equal(log.length, 1);
  assert.ok(!log[0].includes("u1"));
});

test("avatar silme başarısızsa auth kullanıcısı silinmez", async () => {
  const { calls, handler } = setup({
    deleteAvatars: async () => {
      throw new Error("storage");
    },
  });
  const res = await handler(req({ confirm: "SİL" }));
  assert.equal(res.status, 500);
  assert.deepEqual(calls, [
    ["friendships", "u1"],
    ["requests", "u1", "ali@example.com"],
  ]);
});
