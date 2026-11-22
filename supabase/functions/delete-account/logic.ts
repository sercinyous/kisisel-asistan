// delete-account saf yardımcıları (Deno/npm içe aktarımı yok; Node ile sınanır).

/** Kullanıcının yazması gereken onay sözcüğü (istemci de aynısını ister). */
export const CONFIRM_WORD = "SİL";

export const MAX_BODY_BYTES = 4 * 1024;

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const MESSAGES = {
  method: "Yalnızca POST desteklenir.",
  unauthorized: "Oturum doğrulanamadı. Yeniden giriş yap.",
  badRequest: "Onay için SİL yazılmalı.",
  failed: "Hesap silinemedi. Biraz sonra tekrar dene.",
} as const;

export function extractBearer(header: string | null): string | null {
  if (header === null) return null;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return match === null ? null : match[1];
}

/** Gövde {"confirm":"SİL"} mi? Büyük/küçük harf ve boşluk Türkçe kurallarıyla yok sayılır. */
export function isConfirmed(body: unknown): boolean {
  if (body === null || typeof body !== "object" || Array.isArray(body)) return false;
  const value = (body as Record<string, unknown>).confirm;
  if (typeof value !== "string") return false;
  return value.trim().toLocaleUpperCase("tr-TR") === CONFIRM_WORD;
}

/** Arkadaş isteklerinde e-posta küçük harf ve boşluksuz saklanır. */
export function normalizeEmail(email: string | null | undefined): string | null {
  if (email === null || email === undefined) return null;
  const value = email.trim().toLowerCase();
  return value.length === 0 ? null : value;
}

/** Silme adımları sırası: önce açık silmeler, en son auth kullanıcısı. */
export type DeletionStep = "friendships" | "friend_requests" | "avatars" | "auth_user";

export const DELETION_STEPS: readonly DeletionStep[] = [
  "friendships",
  "friend_requests",
  "avatars",
  "auth_user",
];

/** Profil fotoğrafının Storage kovası; dosyalar `<uid>/` klasöründedir. */
export const AVATAR_BUCKET = "avatars";

/** Kullanıcının avatar klasöründeki nesne adlarından silinecek tam yollar. */
export function avatarPaths(userId: string, names: readonly string[]): string[] {
  return names
    .filter((n) => n.length > 0 && !n.includes("/"))
    .map((n) => `${userId}/${n}`);
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" },
  });
}
