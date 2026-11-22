// node --experimental-strip-types --test supabase/functions/delete-account/
import assert from "node:assert/strict";
import { test } from "node:test";

import { avatarObjectPath, avatarPaths, DELETION_STEPS, purgeAvatars, extractBearer, isConfirmed, normalizeEmail } from "./logic.ts";

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
  assert.deepEqual(avatarPaths("u1", [{ name: "avatar.jpg", id: "1" }, { name: "" }, { name: "x/y.jpg" }]), ["u1/avatar.jpg"]);
  assert.ok(DELETION_STEPS.indexOf("avatars") < DELETION_STEPS.indexOf("auth_user"));
});

test("avatarPaths klasör girdilerini (id null) atlar", () => {
  assert.deepEqual(
    avatarPaths("u1", [{ name: "eski", id: null }, { name: "a.jpg", id: "2" }]),
    ["u1/a.jpg"],
  );
});

test("purgeAvatars sabit yolu siler ve klasör girdisinde sonsuz döngüye girmez", async () => {
  const removed = [];
  let lists = 0;
  await purgeAvatars(
    {
      async list() {
        lists++;
        return [{ name: "alt", id: null }];
      },
      async remove(paths) {
        removed.push(paths);
        return paths.length;
      },
    },
    "u1",
  );
  assert.equal(avatarObjectPath("u1"), "u1/avatar.jpg");
  assert.deepEqual(removed, [["u1/avatar.jpg"]]);
  assert.equal(lists, 1);
});

test("purgeAvatars bir tur hiçbir şey silmezse durur", async () => {
  let lists = 0;
  await purgeAvatars(
    {
      async list() {
        lists++;
        return [{ name: "takili.jpg", id: "x" }];
      },
      async remove() {
        return 0;
      },
    },
    "u1",
  );
  assert.equal(lists, 1);
});
