// Supabase Edge Function: delete-account
// Kullanıcı kendi hesabını ve tüm verisini kalıcı olarak siler (App Store şartı).
// Uygulama kullanıcı JWT'siyle {"confirm":"SİL"} gönderir. Akış:
//   1) friendships (iki yön) ve friend_requests (gönderdiği + ona gelen) açıkça silinir,
//   2) Storage `avatars` kovasındaki <uid>/ klasörü (profil fotoğrafı) silinir,
//   3) auth.admin.deleteUser; diğer tüm public satırları ON DELETE CASCADE ile gider.
// Kimlik doğrulama burada yapılır; fonksiyon `--no-verify-jwt` ile dağıtılır.
// Ortam: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (Supabase kendisi verir; anahtar
// uygulamaya ya da depoya hiç girmez).
import { createClient } from "npm:@supabase/supabase-js@2";

import { type AccountStore, createHandler } from "./handler.ts";
import { AVATAR_BUCKET, avatarPaths, jsonResponse, MESSAGES } from "./logic.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const store: AccountStore = {
  async userFromJwt(token) {
    const { data, error } = await admin.auth.getUser(token);
    if (error !== null || data.user === null) return null;
    return { id: data.user.id, email: data.user.email ?? null };
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
    const bucket = admin.storage.from(AVATAR_BUCKET);
    for (;;) {
      const { data, error } = await bucket.list(userId, { limit: 100 });
      if (error !== null) throw new Error(error.message);
      const paths = avatarPaths(userId, (data ?? []).map((o) => o.name));
      if (paths.length === 0) return;
      const removed = await bucket.remove(paths);
      if (removed.error !== null) throw new Error(removed.error.message);
    }
  },

  async deleteAuthUser(userId) {
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error !== null) throw new Error(error.message);
  },
};

const handler = createHandler({ store, log: (message) => console.error(message) });

Deno.serve((req) => {
  if (supabaseUrl === "" || serviceRoleKey === "") {
    return jsonResponse(500, { ok: false, error: MESSAGES.failed });
  }
  return handler(req);
});
