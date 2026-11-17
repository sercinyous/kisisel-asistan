// Supabase Edge Function: generate-reports
// Günlük ve haftalık raporu üretir: sayılar SQL'den (report_*_metrics),
// yorum Gemini'den; sonuç save_*_report ile yazılır.
//
// Çağıranlar:
//   - pg_cron (supabase/cron.sql): `x-cron-secret` başlığıyla, tüm kullanıcılar için.
//   - Uygulama ("Raporu yeniden oluştur"): kullanıcı JWT'siyle, yalnızca o kullanıcı için;
//     kişi başına günde en çok 10 kez (ai_usage kind 'report_regen').
// Yalnızca ilk kurulumunu bitirmiş (user_settings.onboarded_at dolu) kullanıcılar için üretilir.
// Kimlik doğrulama burada yapıldığı için fonksiyon `--no-verify-jwt` ile dağıtılır.
//
// Ortam: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (Supabase kendisi verir),
//        GEMINI_API_KEY, CRON_SECRET, isteğe bağlı GEMINI_MODEL ve
//        REPORT_REGEN_DAILY_LIMIT (varsayılan 10).
import { createClient } from "npm:@supabase/supabase-js@2";

import { DEFAULT_REPORT_REGEN_DAILY_LIMIT, parseLimit } from "../_shared/quota.ts";
import { createHandler, type ReportStore } from "./handler.ts";
import type { ReportKind } from "./logic.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// service_role anahtarı RLS'i aşar; yalnızca bu sunucu sürecinde kullanılır.
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const store: ReportStore = {
  async userIdFromJwt(token) {
    const { data, error } = await admin.auth.getUser(token);
    if (error !== null || data.user === null) return null;
    return data.user.id;
  },

  async listUsers() {
    const { data, error } = await admin
      .from("user_settings")
      .select("user_id, timezone, onboarded_at");
    if (error !== null) throw new Error(error.message);
    return (data ?? []).map((row) => ({
      id: row.user_id as string,
      timeZone: row.timezone as string,
      onboarded: row.onboarded_at !== null,
    }));
  },

  async userOf(userId) {
    const { data, error } = await admin
      .from("user_settings")
      .select("timezone, onboarded_at")
      .eq("user_id", userId)
      .maybeSingle();
    if (error !== null) throw new Error(error.message);
    if (data === null) return null;
    return {
      id: userId,
      timeZone: data.timezone as string,
      onboarded: data.onboarded_at !== null,
    };
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

  async metrics(kind: ReportKind, userId, date) {
    const { data, error } = kind === "daily"
      ? await admin.rpc("report_daily_metrics", { p_user: userId, p_day: date })
      : await admin.rpc("report_weekly_metrics", { p_user: userId, p_week_start: date });
    if (error !== null) throw new Error(error.message);
    return data;
  },

  async save(kind: ReportKind, userId, date, metrics, summary, status) {
    const { error } = kind === "daily"
      ? await admin.rpc("save_daily_report", {
        p_user: userId,
        p_day: date,
        p_metrics: metrics,
        p_summary: summary,
        p_status: status,
      })
      : await admin.rpc("save_weekly_report", {
        p_user: userId,
        p_week_start: date,
        p_metrics: metrics,
        p_summary: summary,
        p_status: status,
      });
    if (error !== null) throw new Error(error.message);
  },
};

const handler = createHandler({
  store,
  cronSecret: Deno.env.get("CRON_SECRET") ?? "",
  geminiApiKey: Deno.env.get("GEMINI_API_KEY") ?? "",
  geminiModel: Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash",
  regenDailyLimit: parseLimit(
    Deno.env.get("REPORT_REGEN_DAILY_LIMIT"),
    DEFAULT_REPORT_REGEN_DAILY_LIMIT,
  ),
  fetch,
  now: () => new Date(),
  log: (message) => console.error(message),
});

Deno.serve((req) => {
  if (supabaseUrl === "" || serviceRoleKey === "") {
    return new Response(
      JSON.stringify({ ok: false, error: "Sunucu yapılandırması eksik." }),
      { status: 500, headers: { "Content-Type": "application/json; charset=utf-8" } },
    );
  }
  return handler(req);
});
