// node --experimental-strip-types --test supabase/functions/delete-account/
import assert from "node:assert/strict";
import { test } from "node:test";

import { avatarPaths, DELETION_STEPS, extractBearer, isConfirmed, normalizeEmail } from "./logic.ts";

test("onay sözcüğü Türkçe büyük harfle eşleşir", () => {
  assert.equal(isConfirmed({ confirm: "SİL" }), true);
  assert.equal(isConfirmed({ confirm: " sil " }), true);
  assert.equal(isConfirmed({ confirm: "SIL" }), false);
  assert.equal(isConfirmed({ confirm: "evet" }), false);
  assert.equal(isConfirmed({}), false);
  assert.equal(isConfirmed(null), false);
  assert.equal(isConfirmed(["SİL"]), false);
});

test("bearer ayrıştırma", () => {
  assert.equal(extractBearer("Bearer abc"), "abc");
  assert.equal(extractBearer("bearer abc "), "abc");
  assert.equal(extractBearer("Basic abc"), null);
  assert.equal(extractBearer(null), null);
});

test("e-posta normalleşir", () => {
  assert.equal(normalizeEmail(" Ali@Example.COM "), "ali@example.com");
  assert.equal(normalizeEmail(""), null);
  assert.equal(normalizeEmail(null), null);
});

test("auth kullanıcısı en son silinir", () => {
  assert.equal(DELETION_STEPS.at(-1), "auth_user");
});

test("avatar yolları kullanıcının klasörüyle sınırlı", () => {
  assert.deepEqual(avatarPaths("u1", ["avatar.jpg", "", "x/y.jpg"]), ["u1/avatar.jpg"]);
  assert.ok(DELETION_STEPS.indexOf("avatars") < DELETION_STEPS.indexOf("auth_user"));
});
