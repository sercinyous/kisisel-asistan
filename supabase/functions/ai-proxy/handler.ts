// ai-proxy isteğinin akışı. Veritabanı ve ağ dışarıdan verilir (index.ts
// gerçeklerini bağlar), böylece bu dosya Deno/npm içe aktarımı olmadan Node ile
// sınanabilir (handler.test.mjs).
//
// Sıra: yöntem → oturum (JWT) → yapılandırma → gövde boyutu → doğrulama →
// günlük kota → Gemini. Kota yalnızca geçerli bir istek Gemini'ye gitmeden
// hemen önce düşer; geçersiz istekler kotayı yemez.
import { AI_QUOTA_KIND, type ConsumeQuota } from "../_shared/quota.ts";
import {
  buildUpstreamUrl,
  CORS_HEADERS,
  extractBearer,
  isValidModel,
  mapUpstreamError,
  MAX_BODY_BYTES,
  MESSAGES,
  quotaExceededMessage,
  readTextLimited,
  sanitizeRequest,
  UPSTREAM_TIMEOUT_MS,
} from "./logic.ts";

/** Veritabanı işlemleri (service_role istemcisiyle; yalnızca sunucuda). */
export interface ProxyStore {
  /** Kullanıcı JWT'sini doğrular; geçersizse null. Ağ/sunucu hatasında fırlatır. */
  userIdFromJwt(token: string): Promise<string | null>;
  /** user_settings.ai_consent_at dolu mu. Ağ/sunucu hatasında fırlatır. */
  hasAiConsent(userId: string): Promise<boolean>;
  /** consume_ai_quota: kota içindeyse sayacı atomik artırıp true. */
  consumeQuota: ConsumeQuota;
  /** Upstream geçici hatasında düşülen birimi geri verir (en iyi çaba). */
  refundQuota?: (userId: string, kind: string) => Promise<void>;
}

export interface ProxyDeps {
  store: ProxyStore;
  /** Yalnızca fonksiyon secret'ında durur; istemciye ya da günlüğe girmez. */
  geminiApiKey: string;
  geminiModel: string;
  /** Kişi başına günlük çağrı sınırı. */
  dailyLimit: number;
  fetch: typeof fetch;
  log: (message: string) => void;
  maxBodyBytes?: number;
  upstreamTimeoutMs?: number;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

/** Tüm hatalar tek biçimde döner: `{"error": "<Türkçe ileti>"}`. */
function fail(status: number, error: string): Response {
  return json(status, { error });
}

export function createHandler(deps: ProxyDeps): (req: Request) => Promise<Response> {
  const maxBodyBytes = deps.maxBodyBytes ?? MAX_BODY_BYTES;
  const upstreamTimeoutMs = deps.upstreamTimeoutMs ?? UPSTREAM_TIMEOUT_MS;

  const refund = async (userId: string) => {
    try {
      await deps.store.refundQuota?.(userId, AI_QUOTA_KIND);
    } catch (error) {
      deps.log(`Kota iade edilemedi: ${error instanceof Error ? error.message : String(error)}`);
    }
  };

  return async (req) => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    if (req.method !== "POST") return fail(405, MESSAGES.method);

    // 1) Oturum: yalnızca geçerli bir kullanıcı JWT'si.
    const token = extractBearer(req.headers.get("Authorization"));
    if (token === null) return fail(401, MESSAGES.unauthorized);
    let userId: string | null;
    try {
      userId = await deps.store.userIdFromJwt(token);
    } catch (error) {
      deps.log(`JWT doğrulanamadı: ${error instanceof Error ? error.message : String(error)}`);
      return fail(500, MESSAGES.authCheckFailed);
    }
    if (userId === null) return fail(401, MESSAGES.unauthorized);

    // 1b) AI onayı: onayı olmayanın metni Gemini'ye gitmez, kota harcanmaz.
    let consent: boolean;
    try {
      consent = await deps.store.hasAiConsent(userId);
    } catch (error) {
      deps.log(`AI onayı okunamadı: ${error instanceof Error ? error.message : String(error)}`);
      return fail(500, MESSAGES.consentCheckFailed);
    }
    if (!consent) return fail(403, MESSAGES.consentRequired);

    // 2) Sunucu yapılandırması (secret'lar). Kota harcanmadan reddedilir.
    if (deps.geminiApiKey === "" || !isValidModel(deps.geminiModel)) {
      deps.log("GEMINI_API_KEY ya da GEMINI_MODEL geçersiz; istek reddedildi.");
      return fail(500, MESSAGES.misconfigured);
    }

    // 3) Gövde: boyut sınırı, JSON, izinli alanlar.
    const read = await readTextLimited(req, maxBodyBytes);
    if (!read.ok) return fail(413, MESSAGES.tooLarge);
    let parsed: unknown;
    try {
      parsed = JSON.parse(read.text);
    } catch (_) {
      return fail(400, MESSAGES.badJson);
    }
    const sanitized = sanitizeRequest(parsed);
    if (!sanitized.ok) return fail(400, sanitized.error);

    // 4) Günlük kota (atomik; hata olursa maliyeti korumak için reddedilir).
    let allowed: boolean;
    try {
      allowed = await deps.store.consumeQuota(userId, AI_QUOTA_KIND, deps.dailyLimit);
    } catch (error) {
      deps.log(`Kota düşülemedi: ${error instanceof Error ? error.message : String(error)}`);
      return fail(500, MESSAGES.quotaCheckFailed);
    }
    if (!allowed) return fail(429, quotaExceededMessage(deps.dailyLimit));

    // 5) Gemini. Anahtar başlıkta gider; günlüğe yalnızca durum kodu yazılır
    // (yanıt ve istek gövdesi kullanıcı metni ya da anahtar ayrıntısı içerebilir).
    let upstream: Response;
    try {
      upstream = await deps.fetch(buildUpstreamUrl(deps.geminiModel), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": deps.geminiApiKey,
        },
        body: JSON.stringify(sanitized.body),
        signal: AbortSignal.timeout(upstreamTimeoutMs),
      });
    } catch (error) {
      const name = error instanceof Error ? error.name : "hata";
      deps.log(`Gemini çağrısı başarısız: ${name}`);
      await refund(userId);
      return name === "TimeoutError" || name === "AbortError"
        ? fail(504, MESSAGES.upstreamTimeout)
        : fail(503, MESSAGES.upstreamUnreachable);
    }

    if (!upstream.ok) {
      deps.log(`Gemini HTTP ${upstream.status}`);
      // 400 isteğin kendisinden gelir; diğer hatalar (429, 402, 401/403/404,
      // 5xx) kullanıcının suçu değildir, birim iade edilir.
      if (upstream.status !== 400) await refund(userId);
      const mapped = mapUpstreamError(upstream.status);
      return fail(mapped.status, mapped.error);
    }

    // Başarı: Gemini yanıtı olduğu gibi iletilir (istemci ayrıştırması aynı kalır).
    let text: string;
    try {
      text = await upstream.text();
    } catch (error) {
      const name = error instanceof Error ? error.name : "hata";
      deps.log(`Gemini yanıtı okunamadı: ${name}`);
      await refund(userId);
      return name === "TimeoutError" || name === "AbortError"
        ? fail(504, MESSAGES.upstreamTimeout)
        : fail(503, MESSAGES.upstreamUnreachable);
    }
    return new Response(text, {
      status: 200,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  };
}
