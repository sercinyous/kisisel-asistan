// ai-proxy Edge Function'ının saf mantığı: istek doğrulama ve sınırlama,
// Gemini hatalarının eşlenmesi, başlıklar. Deno ya da npm içe aktarımı YOKTUR:
// aynı dosya Node ile de sınanır (logic.test.mjs). Ağ ve veritabanı işleri
// handler.ts / index.ts'tedir.

/** Gövde üst sınırı (bayt). İstemci talimatı ve şema ~15 KB'tır; pay bırakılmıştır. */
export const MAX_BODY_BYTES = 64 * 1024;

/** İstemci `maxOutputTokens` vermezse kullanılan değer. */
export const DEFAULT_MAX_OUTPUT_TOKENS = 2048;

/** `maxOutputTokens` için sunucu tavanı (Gemini 3'te düşünme belirteçleri de sayılır). */
export const MAX_OUTPUT_TOKENS_LIMIT = 8192;

/** İçerik girdisi ve parça sayısı üst sınırları (gövde sınırının yanında ek önlem). */
export const MAX_CONTENT_ENTRIES = 20;
export const MAX_PARTS_PER_CONTENT = 20;

/** Secret yoksa kullanılan model. */
export const DEFAULT_MODEL = "gemini-3.8-flash";

/** Gemini çağrısının üst süresi; istemci zaman aşımından (30 sn) kısa tutulur. */
export const UPSTREAM_TIMEOUT_MS = 25_000;

/** Tarayıcı tabanlı çağıranlar (web demo) için CORS; kimlik çerezle değil Bearer ile. */
export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

/** Kullanıcıya gösterilen (Türkçe) hata iletileri. */
export const MESSAGES = {
  method: "Yalnızca POST desteklenir.",
  unauthorized: "Oturum bulunamadı ya da süresi doldu. Çıkış yapıp yeniden giriş yap.",
  authCheckFailed: "Oturum doğrulanamadı. Biraz sonra yeniden dene.",
  misconfigured: "AI sunucusu yapılandırması eksik. Sunucu sahibine haber ver.",
  tooLarge: "İstek çok büyük. Metni kısaltıp yeniden dene.",
  badJson: "Gövde geçerli bir JSON nesnesi olmalı.",
  badContents: "contents en az bir metin içerikli girdi içermeli.",
  badParts: "İçerikte yalnızca metin parçaları desteklenir.",
  quotaCheckFailed: "Kullanım kotası denetlenemedi. Biraz sonra yeniden dene.",
  upstreamBadRequest: "AI isteği geçersiz bulundu.",
  upstreamBilling: "AI servisinin faturalandırması tükendi. Sunucu sahibi krediyi yenilemeli.",
  upstreamConfig: "AI servisi yapılandırması geçersiz. Sunucu sahibine haber ver.",
  upstreamBusy: "AI servisi şu anda yoğun. Biraz sonra yeniden dene.",
  upstreamUnreachable: "AI servisine ulaşılamadı. Biraz sonra yeniden dene.",
  upstreamTimeout: "AI servisi zamanında yanıt vermedi. Yeniden dene.",
  upstreamUnexpected: "AI servisi beklenmeyen bir yanıt verdi.",
} as const;

/** Günlük kota aşıldığında dönen ileti. */
export function quotaExceededMessage(limit: number): string {
  return `Günlük AI kullanım sınırına (${limit} istek) ulaştın. Yarın yeniden dene.`;
}

/** Gemini'ye iletilecek, doğrulanmış ve sınırlanmış istek gövdesi. */
export interface GeminiBody {
  contents: unknown[];
  systemInstruction?: unknown;
  generationConfig: Record<string, unknown>;
}

export type Sanitized =
  | { ok: true; body: GeminiBody }
  | { ok: false; error: string };

/** İstemcinin gönderebildiği generationConfig anahtarları; gerisi atılır. */
const ALLOWED_CONFIG_KEYS = [
  "temperature",
  "topP",
  "topK",
  "stopSequences",
  "responseMimeType",
  "responseSchema",
  "responseJsonSchema",
  "thinkingConfig",
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Bir içerik (rol + yalnızca metin parçaları); geçersizse null. */
function cleanContent(value: unknown): Record<string, unknown> | null {
  if (!isRecord(value)) return null;
  const parts = value.parts;
  if (!Array.isArray(parts) || parts.length === 0 || parts.length > MAX_PARTS_PER_CONTENT) {
    return null;
  }
  const cleanParts: { text: string }[] = [];
  for (const part of parts) {
    if (!isRecord(part) || typeof part.text !== "string") return null;
    cleanParts.push({ text: part.text });
  }
  const role = value.role;
  return role === "user" || role === "model"
    ? { role, parts: cleanParts }
    : { parts: cleanParts };
}

/** `maxOutputTokens`: geçerli pozitif tam sayı tavana kırpılır; yoksa/bozuksa varsayılan. */
export function clampMaxOutputTokens(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 1) {
    return DEFAULT_MAX_OUTPUT_TOKENS;
  }
  return Math.min(Math.floor(value), MAX_OUTPUT_TOKENS_LIMIT);
}

/**
 * İstemci gövdesini doğrular ve Gemini'ye yalnızca izin verilen alanları verir:
 * `contents`, `systemInstruction` (yalnızca metin), `generationConfig` (izinli
 * anahtarlar). Araç (tools), önbellek, güvenlik ayarı gibi alanlar atılır;
 * `maxOutputTokens` her zaman tavana bağlıdır, `candidateCount` 1'dir.
 */
export function sanitizeRequest(body: unknown): Sanitized {
  if (!isRecord(body)) return { ok: false, error: MESSAGES.badJson };

  const contents = body.contents;
  if (!Array.isArray(contents) || contents.length === 0 || contents.length > MAX_CONTENT_ENTRIES) {
    return { ok: false, error: MESSAGES.badContents };
  }
  const cleanContents: Record<string, unknown>[] = [];
  for (const entry of contents) {
    const clean = cleanContent(entry);
    if (clean === null) return { ok: false, error: MESSAGES.badParts };
    cleanContents.push(clean);
  }

  const result: GeminiBody = { contents: cleanContents, generationConfig: {} };

  if (body.systemInstruction !== undefined && body.systemInstruction !== null) {
    const clean = cleanContent(body.systemInstruction);
    if (clean === null) return { ok: false, error: MESSAGES.badParts };
    result.systemInstruction = clean;
  }

  const config = isRecord(body.generationConfig) ? body.generationConfig : {};
  const cleanConfig: Record<string, unknown> = {};
  for (const key of ALLOWED_CONFIG_KEYS) {
    if (config[key] !== undefined) cleanConfig[key] = config[key];
  }
  cleanConfig.maxOutputTokens = clampMaxOutputTokens(config.maxOutputTokens);
  cleanConfig.candidateCount = 1;
  result.generationConfig = cleanConfig;

  return { ok: true, body: result };
}

/** Model adı yalnızca harf, rakam, nokta, tire, alt çizgi içerebilir (URL'ye girer). */
export function isValidModel(model: string): boolean {
  return /^[A-Za-z0-9._-]{1,100}$/.test(model);
}

/** Gemini `generateContent` adresi; anahtar adreste değil başlıkta gider. */
export function buildUpstreamUrl(model: string): string {
  return "https://generativelanguage.googleapis.com/v1beta/models/" +
    `${encodeURIComponent(model)}:generateContent`;
}

/** `Authorization: Bearer <token>` başlığından token; yoksa null. */
export function extractBearer(header: string | null): string | null {
  if (header === null) return null;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return match === null ? null : match[1];
}

export interface MappedError {
  status: number;
  error: string;
}

/**
 * Gemini'nin hata durum kodunu istemciye dönecek duruma çevirir. İstemci
 * 401/404'ü kendi oturumu / "fonksiyon kurulmamış" diye okuduğu için Gemini'nin
 * 401, 403, 404'ü buradan geçmez (502); Gemini'nin 429 ve 5xx'i geçici sayılır
 * (503) ve kota 429'undan ayrılır. 402 olduğu gibi iletilir.
 */
export function mapUpstreamError(status: number): MappedError {
  if (status === 400) return { status: 400, error: MESSAGES.upstreamBadRequest };
  if (status === 402) return { status: 402, error: MESSAGES.upstreamBilling };
  if (status === 401 || status === 403 || status === 404) {
    return { status: 502, error: MESSAGES.upstreamConfig };
  }
  if (status === 429 || status >= 500) return { status: 503, error: MESSAGES.upstreamBusy };
  return { status: 502, error: MESSAGES.upstreamUnexpected };
}

export type BodyRead = { ok: true; text: string } | { ok: false };

/**
 * İstek gövdesini [maxBytes] ile sınırlı okur. Content-Length büyükse hiç
 * okunmaz; başlık yoksa ya da yalan söylüyorsa akış sınırı aşınca kesilir.
 */
export async function readTextLimited(req: Request, maxBytes: number): Promise<BodyRead> {
  const declared = req.headers.get("content-length");
  if (declared !== null) {
    const size = Number(declared);
    if (Number.isFinite(size) && size > maxBytes) return { ok: false };
  }
  if (req.body === null) return { ok: true, text: "" };

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return { ok: false };
    }
    chunks.push(value);
  }
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, text: new TextDecoder().decode(merged) };
}
