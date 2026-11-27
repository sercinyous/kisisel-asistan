// Sign in with Apple belirteç iptali (App Store 5.1.1(v)). Deno/npm içe
// aktarımı yok: yalnızca WebCrypto ve fetch; Node ile sınanır.
//
// Akış: istemci Apple kullanıcısı silmeye dokununca Apple'dan taze bir
// authorizationCode alır ve gövdeye koyar. Burada kod, ES256 imzalı
// client_secret ile /auth/token'da refresh_token'a çevrilir ve
// /auth/revoke ile iptal edilir. Hata silmeyi engellemez; çağıran günlüğe yazar.

export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
export const APPLE_AUDIENCE = "https://appleid.apple.com";

/** Gövdede kabul edilen en uzun yetki kodu. */
export const MAX_APPLE_CODE_LENGTH = 2048;

export interface AppleConfig {
  teamId: string;
  keyId: string;
  /** .p8 dosyasının içeriği (PEM, PKCS#8). `\n` kaçışları da kabul edilir. */
  privateKey: string;
  /** Paket kimliği (com.sercinyous.kisiselasistan). */
  clientId: string;
}

/** Dört gizli anahtarın hepsi doluysa yapılandırma; biri eksikse null. */
export function appleConfigFrom(env: (name: string) => string | undefined): AppleConfig | null {
  const teamId = env("APPLE_TEAM_ID")?.trim() ?? "";
  const keyId = env("APPLE_KEY_ID")?.trim() ?? "";
  const privateKey = env("APPLE_PRIVATE_KEY")?.trim() ?? "";
  const clientId = env("APPLE_CLIENT_ID")?.trim() ?? "";
  if (teamId === "" || keyId === "" || privateKey === "" || clientId === "") return null;
  return { teamId, keyId, privateKey, clientId };
}

/** Gövdeden `apple_authorization_code`; yoksa ya da geçersizse null. */
export function appleCodeFrom(body: unknown): string | null {
  if (body === null || typeof body !== "object" || Array.isArray(body)) return null;
  const value = (body as Record<string, unknown>).apple_authorization_code;
  if (typeof value !== "string") return null;
  const code = value.trim();
  if (code.length === 0 || code.length > MAX_APPLE_CODE_LENGTH) return null;
  return code;
}

/** Kullanıcının sağlayıcıları arasında Apple var mı? */
export function hasAppleProvider(providers: readonly string[] | undefined): boolean {
  return (providers ?? []).includes("apple");
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

/** PEM (PKCS#8) metnini DER baytlarına çevirir. */
export function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/**
 * Apple'ın istediği client_secret: ES256 imzalı JWT (iss=Team ID,
 * sub=paket kimliği, aud=appleid.apple.com, en çok 6 ay; burada 5 dakika).
 */
export async function createClientSecret(
  config: AppleConfig,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  const header = { alg: "ES256", kid: config.keyId, typ: "JWT" };
  const claims = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + 300,
    aud: APPLE_AUDIENCE,
    sub: config.clientId,
  };
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto ECDSA imzası JWS'in istediği r||s (64 bayt) biçimindedir.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

function form(values: Record<string, string>): RequestInit {
  return {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(values).toString(),
  };
}

/**
 * Yetki kodunu belirtece çevirir ve iptal eder. Başarısızlıkta Error fırlatır
 * (mesajda belirteç ya da kod yer almaz).
 */
export async function revokeAppleAuthorization(
  config: AppleConfig,
  authorizationCode: string,
  fetchImpl: FetchLike = fetch,
  nowSeconds?: number,
): Promise<void> {
  const clientSecret = await createClientSecret(config, nowSeconds);
  const tokenRes = await fetchImpl(
    APPLE_TOKEN_URL,
    form({
      client_id: config.clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  );
  if (!tokenRes.ok) {
    let reason = "";
    try {
      const data = (await tokenRes.json()) as Record<string, unknown>;
      if (typeof data.error === "string") reason = ` (${data.error})`;
    } catch {
      // Gövde JSON değil.
    }
    throw new Error(`apple token ${tokenRes.status}${reason}`);
  }
  const tokens = (await tokenRes.json()) as Record<string, unknown>;
  const refresh = typeof tokens.refresh_token === "string" ? tokens.refresh_token : "";
  const access = typeof tokens.access_token === "string" ? tokens.access_token : "";
  const token = refresh !== "" ? refresh : access;
  if (token === "") throw new Error("apple token yanıtında belirteç yok");
  const revokeRes = await fetchImpl(
    APPLE_REVOKE_URL,
    form({
      client_id: config.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: refresh !== "" ? "refresh_token" : "access_token",
    }),
  );
  if (!revokeRes.ok) throw new Error(`apple revoke ${revokeRes.status}`);
}
