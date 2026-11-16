// generate-reports isteğinin akışı. Veritabanı ve ağ dışarıdan verilir
// (index.ts gerçeklerini bağlar), böylece bu dosya Deno/npm içe aktarımı
// olmadan Node ile sınanabilir (handler.test.mjs).
import {
  buildGeminiRequest,
  buildPrompt,
  DEFAULT_TIME_ZONE,
  extractBearer,
  parseGeminiText,
  parseRequest,
  type ReportKind,
  resolveTarget,
  timingSafeEqual,
} from "./logic.ts";

export interface ReportUser {
  id: string;
  timeZone: string;
}

/** Veritabanı işlemleri (service_role istemcisiyle; yalnızca sunucuda). */
export interface ReportStore {
  /** Kullanıcı JWT'sini doğrular; geçersizse null. */
  userIdFromJwt(token: string): Promise<string | null>;
  /** Rapor üretilecek tüm kullanıcılar (zamanlanmış çalıştırma). */
  listUsers(): Promise<ReportUser[]>;
  /** Kullanıcının saat dilimi; ayar satırı yoksa null. */
  timeZoneOf(userId: string): Promise<string | null>;
  metrics(kind: ReportKind, userId: string, date: string): Promise<unknown>;
  save(
    kind: ReportKind,
    userId: string,
    date: string,
    metrics: unknown,
    summary: string | null,
    status: "ok" | "failed",
  ): Promise<void>;
}

export interface HandlerDeps {
  store: ReportStore;
  cronSecret: string;
  geminiApiKey: string;
  geminiModel: string;
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
    if (text === null) deps.log("Gemini yanıtında metin yok.");
    return text;
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
  user: ReportUser,
): Promise<UserOutcome> {
  const target = resolveTarget(kind, requestedDate, user.timeZone, deps.now());
  if (!target.ok) return { status: "rejected", error: target.error };
  try {
    const metrics = await deps.store.metrics(kind, user.id, target.date);
    const summary = await generateSummary(deps, kind, target.date, metrics);
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

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
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

    let users: ReportUser[];
    try {
      users = jwtUserId === null ? await deps.store.listUsers() : [{
        id: jwtUserId,
        timeZone: (await deps.store.timeZoneOf(jwtUserId)) ?? DEFAULT_TIME_ZONE,
      }];
    } catch (error) {
      deps.log(`Kullanıcılar okunamadı: ${error instanceof Error ? error.message : String(error)}`);
      return json(500, { ok: false, error: "Kullanıcılar okunamadı." });
    }

    const outcomes: UserOutcome[] = new Array(users.length);
    let next = 0;
    const worker = async () => {
      while (next < users.length) {
        const index = next++;
        outcomes[index] = await generateForUser(deps, parsed.kind, parsed.date, users[index]);
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
      kind: parsed.kind,
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
