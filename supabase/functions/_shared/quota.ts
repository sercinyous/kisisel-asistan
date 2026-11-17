// Edge Function'ların ortak kota sabitleri ve yardımcıları.
// Deno ya da npm içe aktarımı YOKTUR: Node ile de sınanır (quota.test.mjs).
// Sayaç veritabanındadır: `consume_ai_quota(p_user, p_kind, p_limit)` kota
// içindeyse sayacı atomik artırıp true döner (yalnızca service_role çağırır).

/** ai-proxy çağrılarının sayaç türü (ai_usage.kind). */
export const AI_QUOTA_KIND = "ai";

/** "Raporu yeniden oluştur" çağrılarının sayaç türü (ai_usage.kind). */
export const REPORT_REGEN_QUOTA_KIND = "report_regen";

/** Kişi başına günlük AI çağrısı üst sınırı (AI_DAILY_LIMIT secret'ı ile ayarlanır). */
export const DEFAULT_AI_DAILY_LIMIT = 100;

/** Kişi başına günde en çok rapor yeniden üretimi (REPORT_REGEN_DAILY_LIMIT ile ayarlanır). */
export const DEFAULT_REPORT_REGEN_DAILY_LIMIT = 10;

/** Kotayı sayaçtan düşer; kota içindeyse true, aşıldıysa false. Hata fırlatabilir. */
export type ConsumeQuota = (
  userId: string,
  kind: string,
  limit: number,
) => Promise<boolean>;

/**
 * Secret'tan okunan günlük sınırı çözer. Yalnızca 1 ile 999.999.999 arası
 * pozitif tam sayı kabul edilir; boş, bozuk ya da sıfır değer [fallback]'e döner
 * (yanlış yazılmış bir secret kotayı sessizce kaldırmasın).
 */
export function parseLimit(raw: string | null | undefined, fallback: number): number {
  if (raw === null || raw === undefined) return fallback;
  const text = raw.trim();
  if (!/^\d{1,9}$/.test(text)) return fallback;
  const value = Number(text);
  return value > 0 ? value : fallback;
}
