// node --experimental-strip-types --test supabase/functions/delete-account/
import assert from "node:assert/strict";
import { test } from "node:test";

import { avatarObjectPath, avatarPaths, BODY_PHOTO_BUCKET, DELETION_STEPS, purgeAvatars, purgeBodyPhotos, extractBearer, isConfirmed, normalizeEmail } from "./logic.ts";

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

test("purgeBodyPhotos tarih klasörlerindeki tüm fotoğrafları siler", async () => {
  const objects = new Set([
    "u1/2026-11-02/front.jpg",
    "u1/2026-11-02/side.jpg",
    "u1/2026-11-09/back.jpg",
    "u2/2026-11-02/front.jpg",
  ]);
  const bucket = {
    async list(prefix) {
      const out = new Map();
      for (const p of objects) {
        if (!p.startsWith(`${prefix}/`)) continue;
        const rest = p.slice(prefix.length + 1);
        const [head, ...tail] = rest.split("/");
        out.set(head, tail.length > 0 ? { name: head, id: null } : { name: head, id: "x" });
      }
      return [...out.values()];
    },
    async remove(paths) {
      let n = 0;
      for (const p of paths) if (objects.delete(p)) n++;
      return n;
    },
  };
  await purgeBodyPhotos(bucket, "u1");
  assert.equal(BODY_PHOTO_BUCKET, "body_photos");
  assert.deepEqual([...objects], ["u2/2026-11-02/front.jpg"]);
});

test("purgeBodyPhotos hiçbir şey silinmezse durur", async () => {
  let lists = 0;
  await purgeBodyPhotos(
    {
      async list(prefix) {
        lists++;
        return prefix === "u1" ? [{ name: "2026-11-02", id: null }] : [{ name: "a.jpg", id: "1" }];
      },
      async remove() {
        return 0;
      },
    },
    "u1",
  );
  assert.equal(lists, 2);
});

test("purgeBodyPhotos 1000'den fazla klasörü birden çok turda siler", async () => {
  const objects = new Set();
  for (let i = 0; i < 1500; i++) objects.add(`u1/d${String(i).padStart(4, "0")}/front.jpg`);
  const LIMIT = 1000; // Storage list üst sınırı
  const bucket = {
    async list(prefix) {
      const out = new Map();
      for (const p of objects) {
        if (!p.startsWith(`${prefix}/`)) continue;
        const rest = p.slice(prefix.length + 1);
        const [head, ...tail] = rest.split("/");
        out.set(head, tail.length > 0 ? { name: head, id: null } : { name: head, id: "x" });
      }
      return [...out.values()].slice(0, LIMIT);
    },
    async remove(paths) {
      let n = 0;
      for (const p of paths) if (objects.delete(p)) n++;
      return n;
    },
  };
  await purgeBodyPhotos(bucket, "u1");
  assert.equal(objects.size, 0);
});
