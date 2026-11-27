// node --experimental-strip-types --test supabase/functions/delete-account/
import assert from "node:assert/strict";
import { generateKeyPairSync, createPublicKey, verify } from "node:crypto";
import { test } from "node:test";

import {
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  appleCodeFrom,
  appleConfigFrom,
  createClientSecret,
  hasAppleProvider,
  revokeAppleAuthorization,
} from "./apple.ts";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" });
const config = { teamId: "TEAM123", keyId: "KEY456", privateKey: pem, clientId: "com.sercinyous.kisiselasistan" };

const decode = (part) => JSON.parse(Buffer.from(part, "base64url").toString("utf8"));

test("yapılandırma dört gizli anahtarın hepsini ister", () => {
  const env = { APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_PRIVATE_KEY: "P", APPLE_CLIENT_ID: "C" };
  assert.deepEqual(appleConfigFrom((n) => env[n]), { teamId: "T", keyId: "K", privateKey: "P", clientId: "C" });
  for (const missing of Object.keys(env)) {
    const partial = { ...env, [missing]: " " };
    assert.equal(appleConfigFrom((n) => partial[n]), null);
  }
});

test("gövdeden yetki kodu", () => {
  assert.equal(appleCodeFrom({ confirm: "SİL", apple_authorization_code: " c1 " }), "c1");
  assert.equal(appleCodeFrom({ confirm: "SİL" }), null);
  assert.equal(appleCodeFrom({ apple_authorization_code: 5 }), null);
  assert.equal(appleCodeFrom({ apple_authorization_code: "x".repeat(3000) }), null);
  assert.equal(appleCodeFrom(null), null);
  assert.equal(hasAppleProvider(["email", "apple"]), true);
  assert.equal(hasAppleProvider(["google"]), false);
  assert.equal(hasAppleProvider(undefined), false);
});

test("client_secret ES256 ile imzalanır ve Apple alanlarını taşır", async () => {
  const jwt = await createClientSecret(config, 1000);
  const [h, c, s] = jwt.split(".");
  assert.deepEqual(decode(h), { alg: "ES256", kid: "KEY456", typ: "JWT" });
  assert.deepEqual(decode(c), {
    iss: "TEAM123",
    iat: 1000,
    exp: 1300,
    aud: "https://appleid.apple.com",
    sub: "com.sercinyous.kisiselasistan",
  });
  const sig = Buffer.from(s, "base64url");
  assert.equal(sig.length, 64);
  const ok = verify(
    "sha256",
    Buffer.from(`${h}.${c}`),
    { key: createPublicKey(privateKey), dsaEncoding: "ieee-p1363" },
    sig,
  );
  assert.equal(ok, true);
});

test("kaçışlı (\\n) PEM de kabul edilir", async () => {
  const escaped = { ...config, privateKey: pem.replace(/\n/g, "\\n") };
  const jwt = await createClientSecret(escaped, 1);
  assert.equal(jwt.split(".").length, 3);
});

test("kod belirtece çevrilir ve refresh_token iptal edilir", async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push([url, new URLSearchParams(init.body)]);
    if (url === APPLE_TOKEN_URL) {
      return new Response(JSON.stringify({ refresh_token: "r1", access_token: "a1" }), { status: 200 });
    }
    return new Response("", { status: 200 });
  };
  await revokeAppleAuthorization(config, "kod", fetchImpl, 10);
  assert.equal(calls.length, 2);
  assert.equal(calls[0][0], APPLE_TOKEN_URL);
  assert.equal(calls[0][1].get("code"), "kod");
  assert.equal(calls[0][1].get("grant_type"), "authorization_code");
  assert.equal(calls[0][1].get("client_id"), "com.sercinyous.kisiselasistan");
  assert.equal(calls[1][0], APPLE_REVOKE_URL);
  assert.equal(calls[1][1].get("token"), "r1");
  assert.equal(calls[1][1].get("token_type_hint"), "refresh_token");
  assert.equal(calls[1][1].get("client_secret"), calls[0][1].get("client_secret"));
});

test("token hatası iptali durdurur ve kodu sızdırmaz", async () => {
  let n = 0;
  const fetchImpl = async () => {
    n++;
    return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
  };
  await assert.rejects(revokeAppleAuthorization(config, "gizli-kod", fetchImpl), (e) => {
    assert.match(e.message, /invalid_grant/);
    assert.ok(!e.message.includes("gizli-kod"));
    return true;
  });
  assert.equal(n, 1);
});

test("revoke hatası fırlatılır", async () => {
  const fetchImpl = async (url) =>
    url === APPLE_TOKEN_URL
      ? new Response(JSON.stringify({ access_token: "a1" }), { status: 200 })
      : new Response("", { status: 503 });
  await assert.rejects(revokeAppleAuthorization(config, "kod", fetchImpl), /apple revoke 503/);
});
