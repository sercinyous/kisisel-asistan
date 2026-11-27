// Supabase Edge Function: delete-account
// Kullanıcı kendi hesabını ve tüm verisini kalıcı olarak siler (App Store şartı).
// Uygulama kullanıcı JWT'siyle {"confirm":"SİL"} gönderir. Akış:
//   1) friendships (iki yön) ve friend_requests (gönderdiği + ona gelen) açıkça silinir,
//   2) Storage `avatars` kovasındaki <uid>/avatar.jpg ve klasörde kalanlar silinir,
//      ardından `body_photos` kovasındaki <uid>/<tarih>/<poz>.jpg nesneleri,
//   3) auth.admin.deleteUser; diğer tüm public satırları ON DELETE CASCADE ile gider.
// Apple kullanıcısında gövdede `apple_authorization_code` (istemcinin silmeden hemen
// önce Apple'dan aldığı taze kod) varsa önce Apple belirteci iptal edilir
// (/auth/token + /auth/revoke, ES256 client_secret). İptal hatası silmeyi engellemez.
// Kimlik doğrulama burada yapılır; fonksiyon `--no-verify-jwt` ile dağıtılır.
// Ortam: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (Supabase kendisi verir; anahtar
// uygulamaya ya da depoya hiç girmez); isteğe bağlı APPLE_TEAM_ID, APPLE_KEY_ID,
// APPLE_PRIVATE_KEY (.p8 içeriği), APPLE_CLIENT_ID (paket kimliği). Biri eksikse
// Apple iptali atlanır ve günlüğe yazılır.
import { createClient } from "npm:@supabase/supabase-js@2";

import { appleConfigFrom, revokeAppleAuthorization } from "./apple.ts";
import { type AccountStore, createHandler } from "./handler.ts";
import {
  AVATAR_BUCKET,
  type AvatarBucket,
  BODY_PHOTO_BUCKET,
  jsonResponse,
  MESSAGES,
  purgeAvatars,
  purgeBodyPhotos,
} from "./logic.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function storageBucket(name: string): AvatarBucket {
  const bucket = admin.storage.from(name);
  return {
    async list(prefix) {
      const { data, error } = await bucket.list(prefix, { limit: 1000 });
      if (error !== null) throw new Error(error.message);
      return (data ?? []).map((o) => ({ name: o.name, id: o.id ?? null }));
    },
    async remove(paths) {
      const { data, error } = await bucket.remove(paths);
      if (error !== null) throw new Error(error.message);
      return (data ?? []).length;
    },
  };
}

const store: AccountStore = {
  async userFromJwt(token) {
    const { data, error } = await admin.auth.getUser(token);
    if (error !== null || data.user === null) return null;
    const meta = data.user.app_metadata ?? {};
    const providers = new Set<string>();
    if (Array.isArray(meta.providers)) {
      for (const p of meta.providers) if (typeof p === "string") providers.add(p);
    }
    if (typeof meta.provider === "string") providers.add(meta.provider);
    for (const identity of data.user.identities ?? []) providers.add(identity.provider);
    return { id: data.user.id, email: data.user.email ?? null, providers: [...providers] };
  },

  async deleteFriendships(userId) {
    const { error } = await admin
      .from("friendships")
      .delete()
      .or(`user_a.eq.${userId},user_b.eq.${userId}`);
    if (error !== null) throw new Error(error.message);
  },

  async deleteFriendRequests(userId, email) {
    const filters = [`from_user.eq.${userId}`, `target_user.eq.${userId}`];
    const byIds = await admin.from("friend_requests").delete().or(filters.join(","));
    if (byIds.error !== null) throw new Error(byIds.error.message);
    if (email !== null) {
      const byEmail = await admin.from("friend_requests").delete().eq("target_email", email);
      if (byEmail.error !== null) throw new Error(byEmail.error.message);
    }
  },

  async deleteAvatars(userId) {
    await purgeAvatars(storageBucket(AVATAR_BUCKET), userId);
  },

  async deleteBodyPhotos(userId) {
    await purgeBodyPhotos(storageBucket(BODY_PHOTO_BUCKET), userId);
  },

  async deleteAuthUser(userId) {
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error !== null) throw new Error(error.message);
  },
};

const appleConfig = appleConfigFrom((name) => Deno.env.get(name));

const handler = createHandler({
  store,
  log: (message) => console.error(message),
  revokeApple: appleConfig === null
    ? null
    : (code) => revokeAppleAuthorization(appleConfig, code),
});

Deno.serve((req) => {
  if (supabaseUrl === "" || serviceRoleKey === "") {
    return jsonResponse(500, { ok: false, error: MESSAGES.failed });
  }
  return handler(req);
});
