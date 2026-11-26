// Supabase Edge Function: ai-proxy
// Uygulamanın Gemini çağrısını sunucudan geçirir: GEMINI_API_KEY yalnızca bu
// fonksiyonun secret'ında durur, uygulamada olmaz. İstemci Gemini
// `generateContent` gövdesini üretmeye devam eder; burada oturum doğrulanır,
// gövde ve çıktı sınırlanır, kişi başına günlük kota uygulanır.
//
//   POST {SUPABASE_URL}/functions/v1/ai-proxy
//   Authorization: Bearer <oturum JWT'si>
//   gövde = Gemini generateContent gövdesi, yanıt = Gemini yanıt JSON'u
//   hatalar: {"error": "<Türkçe ileti>"} — 401 oturum, 403 AI onayı yok, 402 fatura,
//            413 büyük gövde, 429 günlük kota, 5xx geçici/yapılandırma.
//
// Oturum burada doğrulandığı için fonksiyon `--no-verify-jwt` ile dağıtılır:
//   supabase functions deploy ai-proxy --no-verify-jwt
//
// Ortam (Supabase kendisi verir): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
// Secret'lar: GEMINI_API_KEY (zorunlu), isteğe bağlı GEMINI_MODEL (varsayılan
// gemini-3.8-flash) ve AI_DAILY_LIMIT (kişi başına günlük çağrı, varsayılan 30) ve
// AI_GLOBAL_DAILY_LIMIT (tüm kullanıcılar toplamı, varsayılan 500; dolunca 503):
//   supabase secrets set GEMINI_API_KEY=... AI_DAILY_LIMIT=30 AI_GLOBAL_DAILY_LIMIT=500
import { createClient } from "npm:@supabase/supabase-js@2";

import {
  DEFAULT_AI_DAILY_LIMIT,
  DEFAULT_AI_GLOBAL_DAILY_LIMIT,
  parseLimit,
} from "../_shared/quota.ts";
import { createHandler, type ProxyStore } from "./handler.ts";
import { DEFAULT_MODEL } from "./logic.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// service_role anahtarı RLS'i aşar; yalnızca bu sunucu sürecinde kullanılır.
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const store: ProxyStore = {
  async userIdFromJwt(token) {
    // Anon anahtarı ya da süresi dolmuş/sahte token burada reddedilir.
    const { data, error } = await admin.auth.getUser(token);
    if (error !== null || data.user === null) return null;
    return data.user.id;
  },

  async hasAiConsent(userId) {
    const { data, error } = await admin
      .from("user_settings")
      .select("ai_consent_at")
      .eq("user_id", userId)
      .maybeSingle();
    if (error !== null) throw new Error(error.message);
    return data?.ai_consent_at != null;
  },

  async consumeQuota(userId, kind, limit) {
    const { data, error } = await admin.rpc("consume_ai_quota", {
      p_user: userId,
      p_kind: kind,
      p_limit: limit,
    });
    if (error !== null) throw new Error(error.message);
    return data === true;
  },

  async consumeGlobalQuota(limit) {
    const { data, error } = await admin.rpc("consume_global_ai_quota", { p_limit: limit });
    if (error !== null) throw new Error(error.message);
    return data === true;
  },

  async refundQuota(userId, kind) {
    const { error } = await admin.rpc("refund_ai_quota", { p_user: userId, p_kind: kind });
    if (error !== null) throw new Error(error.message);
  },
};

const handler = createHandler({
  store,
  geminiApiKey: Deno.env.get("GEMINI_API_KEY") ?? "",
  geminiModel: (Deno.env.get("GEMINI_MODEL") ?? "").trim() || DEFAULT_MODEL,
  dailyLimit: parseLimit(Deno.env.get("AI_DAILY_LIMIT"), DEFAULT_AI_DAILY_LIMIT),
  globalDailyLimit: parseLimit(
    Deno.env.get("AI_GLOBAL_DAILY_LIMIT"),
    DEFAULT_AI_GLOBAL_DAILY_LIMIT,
  ),
  fetch,
  log: (message) => console.error(message),
});

Deno.serve((req) => {
  if (supabaseUrl === "" || serviceRoleKey === "") {
    return new Response(
      JSON.stringify({ error: "AI sunucusu yapılandırması eksik. Sunucu sahibine haber ver." }),
      { status: 500, headers: { "Content-Type": "application/json; charset=utf-8" } },
    );
  }
  return handler(req);
});
