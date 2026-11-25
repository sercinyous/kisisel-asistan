// generate-reports isteğinin akışı. Veritabanı ve ağ dışarıdan verilir
// (index.ts gerçeklerini bağlar), böylece bu dosya Deno/npm içe aktarımı
// olmadan Node ile sınanabilir (handler.test.mjs).
import {
  type ConsumeQuota,
  DEFAULT_REPORT_REGEN_DAILY_LIMIT,
  REPORT_REGEN_QUOTA_KIND,
} from "../_shared/quota.ts";
import {
  buildGeminiRequest,
  buildPrompt,
  extractBearer,
  filterHealthAdvice,
  healthSafetyOf,
  parseGeminiText,
  parseRequest,
  type ReportKind,
  resolveTarget,
  timingSafeEqual,
} from "./logic.ts";

export interface ReportUser {
  id: string;
  timeZone: string;
  /** user_settings.onboarded_at dolu mu; ilk kurulumunu bitirmeyen için rapor üretilmez. */
  onboarded: boolean;
  /**
   * user_settings.ai_consent_at dolu mu. false ise Gemini çağrılmaz, rapor
   * yalnızca sayılarla kaydedilir. Belirtilmezse (eski testler) onaylı sayılır.
   */
  aiConsent?: boolean;
}

/** Veritabanı işlemleri (service_role istemcisiyle; yalnızca sunucuda). */
export interface ReportStore {
  /** Kullanıcı JWT'sini doğrular; geçersizse null. */
  userIdFromJwt(token: string): Promise<string | null>;
  /** Tüm kullanıcılar (zamanlanmış çalıştırma); onboarded olmayanı işleyici eler. */
  listUsers(): Promise<ReportUser[]>;
  /** Tek kullanıcının ayarı; ayar satırı yoksa null. */
  userOf(userId: string): Promise<ReportUser | null>;
  /** consume_ai_quota: kota içindeyse sayacı atomik artırıp true. */
  consumeQuota: ConsumeQuota;
  metrics(kind: ReportKind, userId: string, date: string): Promise<unknown>;
  save(
    kind: ReportKind,
    userId: string,
    date: string,
    metrics: unknown,
    summary: string | null,
    status: "ok" | "failed",
  ): Promise<void>;
  /** claim_dirty_reports: işaretli raporları kiralar (dirty iş bitene dek kalır). */
  claimDirty(limit: number): Promise<DirtyReport[]>;
  /** release_report_claim: hata sonrası kirayı bırakır; rapor sonraki geçişte yeniden alınır. */
  releaseClaim(report: DirtyReport): Promise<void>;
  /** complete_report_claim: sayılar değişmediyse; sürüm aynıysa dirty temizlenir. */
  completeClaim(report: DirtyReport): Promise<void>;
  /** refresh_report_metrics: sayıları yeniden hesaplar; changed=false ise yorum güncel. */
  refreshMetrics(kind: ReportKind, userId: string, date: string): Promise<RefreshedMetrics>;
  /**
   * save_refreshed_report (jetonlu): summary null → sayılar yazılır, eski yorum kalır,
   * dirty kalır; doluysa sürüm değişmediyse dirty temizlenir. Her durumda kira bırakılır.
   */
  saveRefreshed(report: DirtyReport, metrics: unknown, summary: string | null): Promise<void>;
}

export interface DirtyReport {
  kind: ReportKind;
  userId: string;
  date: string;
  /** Kira jetonu (claim_token). */
  token: string;
  /** Alındığı andaki dirty_version; yalnızca değişmediyse dirty temizlenir. */
  version: number;
}

export interface RefreshedMetrics {
  metrics: unknown;
  /** Yorumun dayandığı sayılardan farklı mı (AI yorumu yenilenmeli mi). */
  changed: boolean;
}

/** Geç veriyle yorum yenilemenin sayaç türü (ai_usage.kind). */
export const REPORT_REFRESH_QUOTA_KIND = "report_refresh";

/** Kişi başına günde en çok otomatik yorum yenilemesi (REPORT_REFRESH_DAILY_LIMIT). */
export const DEFAULT_REPORT_REFRESH_DAILY_LIMIT = 6;

/** Bir yenileme geçişinde en çok işlenen rapor sayısı. */
export const REFRESH_BATCH_LIMIT = 40;

export interface HandlerDeps {
  store: ReportStore;
  cronSecret: string;
  geminiApiKey: string;
  geminiModel: string;
  /** Kişi başına günde en çok "Raporu yeniden oluştur" sayısı (varsayılan 10). */
  regenDailyLimit?: number;
  /** Kişi başına günde en çok otomatik yorum yenilemesi (varsayılan 6). */
  refreshDailyLimit?: number;
  fetch: typeof fetch;
  now: () => Date;
  log: (message: string) => void;
}

/** Gemini çağrısının üst süresi. */
export const GEMINI_TIMEOUT_MS = 30_000;

/** Aynı anda işlenen kullanıcı sayısı (Gemini kotasını ve süreyi dengeler). */
const USER_CONCURRENCY = 4;

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

/** Yorum metni; üretilemezse null (rapor sayılarla yine kaydedilir). */
async function generateSummary(
  deps: HandlerDeps,
  kind: ReportKind,
  date: string,
  metrics: unknown,
): Promise<string | null> {
  if (deps.geminiApiKey === "") {
    deps.log("GEMINI_API_KEY tanımlı değil; yorum üretilmedi.");
    return null;
  }
  try {
    const url = "https://generativelanguage.googleapis.com/v1beta/models/" +
      `${encodeURIComponent(deps.geminiModel)}:generateContent`;
    const response = await deps.fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": deps.geminiApiKey,
      },
      body: JSON.stringify(buildGeminiRequest(buildPrompt(kind, date, metrics))),
      signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
    });
    if (!response.ok) {
      // Yanıt gövdesi anahtar ya da istek ayrıntısı içerebilir; yalnızca durum kodu yazılır.
      deps.log(`Gemini HTTP ${response.status}`);
      return null;
    }
    const text = parseGeminiText(await response.json());
    if (text === null) {
      deps.log("Gemini yanıtında metin yok.");
      return null;
    }
    // Sağlık sınırını aşan cümle (taban altı kalori, hızlı kayıp, oruç, öğün
    // atlama) kaydedilmeden önce güvenli cümleyle değiştirilir.
    return filterHealthAdvice(text, healthSafetyOf(metrics));
  } catch (error) {
    deps.log(`Gemini çağrısı başarısız: ${error instanceof Error ? error.name : "hata"}`);
    return null;
  }
}

type UserOutcome =
  | { status: "saved"; date: string; aiOk: boolean }
  | { status: "rejected"; error: string }
  | { status: "failed" };

async function generateForUser(
  deps: HandlerDeps,
  kind: ReportKind,
  requestedDate: string | null,
  previous: boolean,
  user: ReportUser,
): Promise<UserOutcome> {
  const target = resolveTarget(kind, requestedDate, user.timeZone, deps.now(), previous);
  if (!target.ok) return { status: "rejected", error: target.error };
  try {
    const metrics = await deps.store.metrics(kind, user.id, target.date);
    const summary = user.aiConsent === false
      ? null
      : await generateSummary(deps, kind, target.date, metrics);
    await deps.store.save(
      kind,
      user.id,
      target.date,
      metrics,
      summary,
      summary === null ? "failed" : "ok",
    );
    return { status: "saved", date: target.date, aiOk: summary !== null };
  } catch (error) {
    // Bir kullanıcının hatası diğerlerini durdurmaz.
    deps.log(
      `Rapor üretilemedi (${kind}, ${user.id}): ` +
        (error instanceof Error ? error.message : String(error)),
    );
    return { status: "failed" };
  }
}

type RefreshOutcome = "unchanged" | "ai" | "deferred" | "failed";

/**
 * Tek bir işaretli raporu yeniler. Sayılar her zaman yeniden hesaplanır; AI
 * yalnızca sayılar yorumun dayanağından farklıysa ve kota izin verirse çağrılır.
 * Kota dolar ya da AI başarısız olursa eski yorum kalır, rapor dirty kalır.
 * Hata olursa kira bırakılır; böylece rapor sonraki geçişte yeniden alınır.
 */
async function refreshOne(
  deps: HandlerDeps,
  report: DirtyReport,
  refreshLimit: number,
): Promise<RefreshOutcome> {
  try {
    const fresh = await deps.store.refreshMetrics(report.kind, report.userId, report.date);
    if (!fresh.changed) {
      await deps.store.completeClaim(report);
      return "unchanged";
    }
    const owner = await deps.store.userOf(report.userId);
    const allowed = owner !== null && owner.aiConsent !== false &&
      await deps.store.consumeQuota(
        report.userId,
        REPORT_REFRESH_QUOTA_KIND,
        refreshLimit,
      );
    const summary = allowed
      ? await generateSummary(deps, report.kind, report.date, fresh.metrics)
      : null;
    await deps.store.saveRefreshed(report, fresh.metrics, summary);
    return summary === null ? "deferred" : "ai";
  } catch (error) {
    deps.log(
      `Rapor yenilenemedi (${report.kind}, ${report.userId}, ${report.date}): ` +
        (error instanceof Error ? error.message : String(error)),
    );
    // Kira bırakılır; bırakılamazsa süresi dolunca rapor yeniden alınır.
    try {
      await deps.store.releaseClaim(report);
    } catch (releaseError) {
      deps.log(
        `Kira bırakılamadı (${report.kind}, ${report.userId}, ${report.date}): ` +
          (releaseError instanceof Error ? releaseError.message : String(releaseError)),
      );
    }
    return "failed";
  }
}

async function runRefresh(deps: HandlerDeps, refreshLimit: number): Promise<Response> {
  let reports: DirtyReport[];
  try {
    reports = await deps.store.claimDirty(REFRESH_BATCH_LIMIT);
  } catch (error) {
    deps.log(`İşaretli raporlar alınamadı: ${error instanceof Error ? error.message : String(error)}`);
    return json(500, { ok: false, error: "İşaretli raporlar alınamadı." });
  }
  const outcomes: RefreshOutcome[] = new Array(reports.length);
  let next = 0;
  const worker = async () => {
    while (next < reports.length) {
      const index = next++;
      outcomes[index] = await refreshOne(deps, reports[index], refreshLimit);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(USER_CONCURRENCY, reports.length) }, worker),
  );
  const count = (o: RefreshOutcome) => outcomes.filter((x) => x === o).length;
  const failed = count("failed");
  return json(reports.length > 0 && failed === reports.length ? 500 : 200, {
    ok: failed === 0,
    kind: "refresh",
    reports: reports.length,
    unchanged: count("unchanged"),
    ai: count("ai"),
    deferred: count("deferred"),
    failed,
  });
}

export function regenQuotaMessage(limit: number): string {
  return `Bugünlük rapor yenileme hakkın doldu (${limit}). Yarın yeniden dene.`;
}

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  const regenLimit = deps.regenDailyLimit ?? DEFAULT_REPORT_REGEN_DAILY_LIMIT;
  const refreshLimit = deps.refreshDailyLimit ?? DEFAULT_REPORT_REFRESH_DAILY_LIMIT;
  return async (req) => {
    if (req.method !== "POST") {
      return json(405, { ok: false, error: "Yalnızca POST desteklenir." });
    }

    // Yetki: (a) zamanlayıcının gizli anahtarı → tüm kullanıcılar,
    //        (b) kullanıcı JWT'si → yalnızca o kullanıcı.
    const cronHeader = req.headers.get("x-cron-secret");
    const isCron = cronHeader !== null && timingSafeEqual(cronHeader, deps.cronSecret);
    let jwtUserId: string | null = null;
    if (!isCron) {
      const token = extractBearer(req.headers.get("Authorization"));
      try {
        jwtUserId = token === null ? null : await deps.store.userIdFromJwt(token);
      } catch (error) {
        deps.log(`JWT doğrulanamadı: ${error instanceof Error ? error.message : String(error)}`);
        return json(500, { ok: false, error: "Oturum doğrulanamadı." });
      }
      if (jwtUserId === null) {
        return json(401, { ok: false, error: "Yetkisiz." });
      }
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch (_) {
      return json(400, { ok: false, error: "Gövde geçerli JSON olmalı." });
    }
    const parsed = parseRequest(body);
    if (!parsed.ok) return json(400, { ok: false, error: parsed.error });
    if (parsed.kind === "refresh") {
      // Toplu yenileme yalnızca zamanlayıcıya açıktır.
      if (!isCron) return json(403, { ok: false, error: "Yalnızca zamanlayıcı çağırabilir." });
      return runRefresh(deps, refreshLimit);
    }
    const kind = parsed.kind;

    let users: ReportUser[];
    try {
      if (jwtUserId === null) {
        // Zamanlanmış çalıştırma: yalnızca ilk kurulumunu bitirmiş kullanıcılar.
        users = (await deps.store.listUsers()).filter((user) => user.onboarded);
      } else {
        const user = await deps.store.userOf(jwtUserId);
        if (user === null || !user.onboarded) {
          return json(403, { ok: false, error: "Önce ilk kurulumu tamamla." });
        }
        users = [user];
      }
    } catch (error) {
      deps.log(`Kullanıcılar okunamadı: ${error instanceof Error ? error.message : String(error)}`);
      return json(500, { ok: false, error: "Kullanıcılar okunamadı." });
    }

    // "Raporu yeniden oluştur": kişi başına günlük sınır. Geçersiz tarih
    // (gelecek) kotayı yemez; kota düşülemezse maliyeti korumak için reddedilir.
    if (jwtUserId !== null) {
      const target = resolveTarget(kind, parsed.date, users[0].timeZone, deps.now(), parsed.previous);
      if (!target.ok) return json(400, { ok: false, error: target.error });
      let allowed: boolean;
      try {
        allowed = await deps.store.consumeQuota(jwtUserId, REPORT_REGEN_QUOTA_KIND, regenLimit);
      } catch (error) {
        deps.log(`Kota düşülemedi: ${error instanceof Error ? error.message : String(error)}`);
        return json(500, { ok: false, error: "Kullanım kotası denetlenemedi." });
      }
      if (!allowed) return json(429, { ok: false, error: regenQuotaMessage(regenLimit) });
    }

    const outcomes: UserOutcome[] = new Array(users.length);
    let next = 0;
    const worker = async () => {
      while (next < users.length) {
        const index = next++;
        outcomes[index] = await generateForUser(
          deps,
          kind,
          parsed.date,
          parsed.previous,
          users[index],
        );
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(USER_CONCURRENCY, users.length) }, worker),
    );

    // Tek kullanıcının isteği geçersiz tarihse bu bir istemci hatasıdır.
    if (jwtUserId !== null && outcomes[0].status === "rejected") {
      return json(400, { ok: false, error: outcomes[0].error });
    }

    const saved = outcomes.filter((o) => o.status === "saved");
    const failed = outcomes.length - saved.length;
    const result = {
      ok: failed === 0,
      kind,
      // Kullanıcılar farklı saat dilimlerindeyse gün farklı olabilir; ilk kaydedilen bildirilir.
      date: saved.length > 0 ? saved[0].date : parsed.date,
      users: users.length,
      failed,
      ai_failed: saved.filter((o) => !o.aiOk).length,
    };
    // Hiçbir rapor yazılamadıysa çağıran (uygulama, pg_net günlüğü) hata görmeli.
    return json(users.length > 0 && saved.length === 0 ? 500 : 200, result);
  };
}
