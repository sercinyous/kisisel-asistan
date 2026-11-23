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
export type DeletionStep =
  | "friendships"
  | "friend_requests"
  | "avatars"
  | "body_photos"
  | "auth_user";

export const DELETION_STEPS: readonly DeletionStep[] = [
  "friendships",
  "friend_requests",
  "avatars",
  "body_photos",
  "auth_user",
];

/** Profil fotoğrafının Storage kovası; dosyalar `<uid>/` klasöründedir. */
export const AVATAR_BUCKET = "avatars";

/** Profil fotoğrafının sabit yolu (Storage politikası yalnızca bunu kabul eder). */
export function avatarObjectPath(userId: string): string {
  return `${userId}/avatar.jpg`;
}

/** Storage list() girdisi: klasörlerin `id`'si null'dır. */
export interface StorageEntry {
  name: string;
  id?: string | null;
}

/** Klasördeki dosya girdilerinden silinecek tam yollar; klasör girdileri atlanır. */
export function avatarPaths(userId: string, entries: readonly StorageEntry[]): string[] {
  return entries
    .filter((e) => e.name.length > 0 && !e.name.includes("/") && e.id !== null)
    .map((e) => `${userId}/${e.name}`);
}

export interface AvatarBucket {
  list(prefix: string): Promise<StorageEntry[]>;
  remove(paths: string[]): Promise<number>;
}

/**
 * Önce sabit yolu siler, sonra klasörde kalan dosyaları temizler. Bir tur hiçbir
 * şey silmezse durur (sonsuz döngü olmaz); en fazla [maxPasses] tur.
 */
export async function purgeAvatars(
  bucket: AvatarBucket,
  userId: string,
  maxPasses = 10,
): Promise<void> {
  await bucket.remove([avatarObjectPath(userId)]);
  for (let pass = 0; pass < maxPasses; pass++) {
    const paths = avatarPaths(userId, await bucket.list(userId));
    if (paths.length === 0) return;
    const removed = await bucket.remove(paths);
    if (removed === 0) return;
  }
}

/** İlerleme fotoğraflarının özel kovası; yol `<uid>/<YYYY-MM-DD>/<poz>.jpg`. */
export const BODY_PHOTO_BUCKET = "body_photos";

/**
 * `body_photos` kovasında `<uid>/` altındaki her şeyi siler: önce tarih
 * klasörleri listelenir, her klasörün dosyaları silinir; kökte dosya kalırsa o
 * da silinir. Bir tur hiçbir şey silmezse durur; en fazla [maxPasses] tur.
 */
export async function purgeBodyPhotos(
  bucket: AvatarBucket,
  userId: string,
  maxPasses = 20,
): Promise<void> {
  for (let pass = 0; pass < maxPasses; pass++) {
    const top = await bucket.list(userId);
    const folders = top.filter(
      (e) => e.id === null && e.name.length > 0 && !e.name.includes("/"),
    );
    const paths = avatarPaths(userId, top);
    for (const folder of folders) {
      const prefix = `${userId}/${folder.name}`;
      paths.push(...avatarPaths(prefix, await bucket.list(prefix)));
    }
    if (paths.length === 0) return;
    const removed = await bucket.remove(paths);
    if (removed === 0) return;
  }
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" },
  });
}
