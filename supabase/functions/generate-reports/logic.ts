// generate-reports Edge Function'ının saf mantığı.
// Deno ya da npm içe aktarımı YOKTUR: aynı dosya Node ile de sınanır
// (logic.test.mjs). Ağ ve veritabanı işleri index.ts'tedir.

export type ReportKind = "daily" | "weekly";

export type ParsedRequest =
  | { ok: true; kind: ReportKind; date: string | null; previous: boolean }
  | { ok: true; kind: "refresh"; date: null; previous: false }
  | { ok: false; error: string };

export type ResolvedTarget =
  | { ok: true; date: string }
  | { ok: false; error: string };

export interface Prompt {
  system: string;
  user: string;
}

/** user_settings.timezone boş ya da bozuksa kullanılan saat dilimi. */
export const DEFAULT_TIME_ZONE = "Europe/Istanbul";

/** Kaydedilen özetin üst sınırı (karakter); model sözü dinlemezse taşmasın. */
export const MAX_SUMMARY_LENGTH = 2000;

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

/** "YYYY-MM-DD" gerçek bir takvim günü mü? (2026-02-30 değildir.) */
function isRealDate(value: string): boolean {
  const match = DATE_PATTERN.exec(value);
  if (match === null) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
}

/**
 * İstek gövdesini doğrular:
 * `{ kind: "daily"|"weekly", date?: "YYYY-MM-DD", previous?: true }` ya da
 * `{ kind: "refresh" }` (dirty işaretli raporları yenile; yalnızca zamanlayıcı).
 * `previous: true` (yalnızca günlük, tarihsiz): kullanıcının dünü, yani biten gün.
 */
export function parseRequest(body: unknown): ParsedRequest {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, error: 'kind "daily" ya da "weekly" olmalı.' };
  }
  const record = body as Record<string, unknown>;
  const kind = record.kind;
  if (kind === "refresh") {
    return { ok: true, kind, date: null, previous: false };
  }
  if (kind !== "daily" && kind !== "weekly") {
    return { ok: false, error: 'kind "daily" ya da "weekly" olmalı.' };
  }
  const previous = record.previous;
  if (previous !== undefined && previous !== null && typeof previous !== "boolean") {
    return { ok: false, error: "previous true ya da false olmalı." };
  }
  const date = record.date;
  if (previous === true && (kind !== "daily" || (date !== undefined && date !== null))) {
    return { ok: false, error: "previous yalnızca tarihsiz günlük raporda kullanılır." };
  }
  if (date === undefined || date === null) {
    return { ok: true, kind, date: null, previous: previous === true };
  }
  if (typeof date !== "string" || !isRealDate(date)) {
    return { ok: false, error: "date YYYY-MM-DD biçiminde geçerli bir gün olmalı." };
  }
  return { ok: true, kind, date, previous: false };
}

function formatYmd(date: Date): string {
  const y = String(date.getUTCFullYear()).padStart(4, "0");
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Takvim günü hesabı UTC gece yarısı üzerinden yapılır (yaz saati etkilemez). */
function addDays(ymd: string, days: number): string {
  const date = new Date(`${ymd}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return formatYmd(date);
}

function ymdIn(now: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const pick = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${pick("year")}-${pick("month")}-${pick("day")}`;
}

/** [now] anının [timeZone] saat dilimindeki günü ("YYYY-MM-DD"). */
export function todayInTimeZone(now: Date, timeZone: string): string {
  try {
    return ymdIn(now, timeZone.trim() === "" ? DEFAULT_TIME_ZONE : timeZone);
  } catch (_) {
    // Bozuk saat dilimi adı (RangeError) raporu düşürmesin; SQL tarafı da
    // aynı durumda İstanbul'a döner.
    return ymdIn(now, DEFAULT_TIME_ZONE);
  }
}

/** [ymd] gününün haftasının Pazartesi'si. */
export function weekStartOf(ymd: string): string {
  const weekday = new Date(`${ymd}T00:00:00Z`).getUTCDay(); // 0 = Pazar
  return addDays(ymd, -((weekday + 6) % 7));
}

/** [today]'e göre tamamen bitmiş son haftanın (Pzt–Paz) Pazartesi'si. */
export function lastFinishedWeekStart(today: string): string {
  return addDays(weekStartOf(today), -7);
}

/**
 * Raporun hedef gününü (günlük) ya da hafta başını (haftalık) belirler.
 * Tarih verilmezse: günlük = kullanıcının bugünü ([previous] ise dünü, yani
 * tamamen bitmiş gün), haftalık = biten son hafta.
 * Gelecek reddedilir; içinde bulunulan hafta üretilebilir (kısmi rapor).
 */
export function resolveTarget(
  kind: ReportKind,
  date: string | null,
  timeZone: string,
  now: Date,
  previous = false,
): ResolvedTarget {
  const today = todayInTimeZone(now, timeZone);
  const target = kind === "daily"
    ? (date ?? (previous ? addDays(today, -1) : today))
    : (date === null ? lastFinishedWeekStart(today) : weekStartOf(date));
  // "YYYY-MM-DD" sözlük sırası takvim sırasıyla aynıdır.
  if (target > today) {
    return { ok: false, error: "Gelecekteki bir tarih için rapor üretilemez." };
  }
  return { ok: true, date: target };
}

/**
 * Sabit zamanlı metin karşılaştırması: süre, ilk farkın yerine göre değişmez.
 * Boş değer hiçbir şeyle eşleşmez (tanımsız gizli anahtar kapıyı açmasın).
 */
export function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0 && left.length > 0;
}

/** `Authorization: Bearer <token>` başlığından token; yoksa null. */
export function extractBearer(header: string | null): string | null {
  if (header === null) return null;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return match === null ? null : match[1];
}

/** Gemini'ye verilecek talimat ve veri. Sayılar SQL'de hesaplanmıştır. */
export function buildPrompt(kind: ReportKind, date: string, metrics: unknown): Prompt {
  const common = [
    "Kişisel bir asistan uygulaması için rapor yorumu yazıyorsun.",
    "Türkçe yaz. Düz metin kullan: başlık, madde işareti, yıldız ya da markdown yok.",
    "Yalnızca sana verilen sayılara dayan; veride olmayan bir şeyi uydurma ve sayı tahmin etme.",
    "Değeri null ya da 0 olan ve veri girilmemiş görünen alanları başarısızlık gibi yorumlama; " +
    "o alanda veri olmadığını kısaca söyle.",
    "Tıbbi tavsiye verme; teşhis, ilaç, takviye ya da tedavi önerme.",
    "Sayıları tek tek tekrar etme; öne çıkanı söyle. Samimi ama abartısız bir dil kullan.",
    "work = iş (görev ve rutinler), form = antrenman ve beslenme düzeni; rate değerleri yüzdedir.",
    "targets günlük hedeflerdir.",
  ];
  const specific = kind === "daily"
    ? [
      "Bu bir GÜNLÜK değerlendirmedir: o günün iş ve form durumunu özetle.",
      "En fazla 70 kelime yaz. Tek paragraf; öneri listesi verme.",
    ]
    : [
      "Bu bir HAFTALIK değerlendirmedir (Pazartesi–Pazar): iş ve form tarafını ayrı ayrı özetle; " +
      "days dizisinden öne çıkan günleri belirt.",
      "Değerlendirme en fazla 120 kelime olsun. Ardından en fazla 3 öneri yaz: " +
      "her öneri ayrı satırda, tek kısa cümle, somut ve verilen sayılara dayalı.",
    ];
  const label = kind === "daily" ? `Gün: ${date}` : `Hafta başı (Pazartesi): ${date}`;
  const safety = healthSafetyOf(metrics);
  return {
    system: [...common, ...specific, ...healthSafetyLines(safety)].join("\n"),
    user: `${label}\nSayılar (JSON):\n${JSON.stringify(metrics)}`,
  };
}

/** Gemini `generateContent` istek gövdesi. */
export function buildGeminiRequest(prompt: Prompt) {
  return {
    systemInstruction: { parts: [{ text: prompt.system }] },
    contents: [{ role: "user", parts: [{ text: prompt.user }] }],
    generationConfig: {
      // Sıcaklık verilmez: Gemini 3 serisinde 1.0'ın altı döngüye sokabiliyor.
      // Gemini 3 serisinde düşünme belirteçleri de bu sınıra sayılır.
      maxOutputTokens: 2048,
      // Kısa yorum için düşünme adımı gereksiz gecikme ve maliyettir.
      // Gemini 3 serisi bütçe yerine düzey alır; en düşük desteklenen "low".
      thinkingConfig: { thinkingLevel: "low" },
    },
  };
}

/**
 * Gemini yanıtından yorum metnini çıkarır; kullanılabilir metin yoksa null.
 * Model talimata rağmen markdown işareti koyarsa temizlenir (uygulama düz
 * metin gösterir).
 */
export function parseGeminiText(response: unknown): string | null {
  if (typeof response !== "object" || response === null) return null;
  const candidates = (response as { candidates?: unknown }).candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const content = (candidates[0] as { content?: { parts?: unknown } } | null)?.content;
  const parts = content?.parts;
  if (!Array.isArray(parts)) return null;

  const raw = parts
    .map((part) => (part as { text?: unknown } | null)?.text)
    .filter((text): text is string => typeof text === "string")
    .join("");

  const text = raw
    .split("\n")
    .map((line) =>
      line
        .replace(/^\s*(?:[-*•]|#{1,6})\s+/, "")
        .replace(/\*\*|__|`/g, "")
        .trim()
    )
    .filter((line) => line !== "")
    .join("\n")
    .replace(/[ \t]{2,}/g, " ");

  if (text === "") return null;
  return text.length > MAX_SUMMARY_LENGTH ? text.slice(0, MAX_SUMMARY_LENGTH) : text;
}

// ------------------------------------------------------------ sağlık güvenliği

/** AI asla bundan hızlı kayıp önermez (kg/hafta). */
export const AI_MAX_KG_PER_WEEK = 0.75;
/** Kalori tabanı bilinmiyorsa kullanılan alt sınır. */
export const DEFAULT_FLOOR_KCAL = 1200;

/** SQL `safety` bloğu (report_health_safety) ve ondan türetilen hafta özeti. */
export interface HealthSafety {
  floorKcal: number;
  expenditureKcal: number | null;
  deficitCapKcal: number | null;
  /** Kayıtlı günlerde harcama − alım toplamı (kcal); veri yoksa null. */
  periodDeficitKcal: number | null;
  /** Son günden geriye, açığı (0, sınır] ve alımı tabanın üstünde olan ardışık gün. */
  deficitStreakDays: number | null;
  /** Kullanıcının hedef türü (user_settings.goal_mode); bilinmiyorsa yağ yakma. */
  goalMode: GoalMode;
}

export type GoalMode = "fat_loss" | "recomp" | "lean_gain" | "maintain";

const GOAL_MODES: readonly GoalMode[] = ["fat_loss", "recomp", "lean_gain", "maintain"];

function goalModeOf(value: unknown): GoalMode {
  return GOAL_MODES.includes(value as GoalMode) ? value as GoalMode : "fat_loss";
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** Rapor sayılarından güvenlik sınırlarını çıkarır. */
export function healthSafetyOf(metrics: unknown): HealthSafety {
  const m = (typeof metrics === "object" && metrics !== null ? metrics : {}) as Record<string, unknown>;
  const s = (typeof m.safety === "object" && m.safety !== null ? m.safety : {}) as Record<string, unknown>;
  const floorKcal = Math.max(DEFAULT_FLOOR_KCAL, Math.round(num(s.floor_kcal) ?? 0));
  const expenditureKcal = num(s.expenditure_kcal);
  const deficitCapKcal = expenditureKcal === null
    ? null
    : Math.min(Math.round(expenditureKcal * 0.25), 1000);
  const nutrition = (typeof m.nutrition === "object" && m.nutrition !== null ? m.nutrition : {}) as Record<string, unknown>;
  const avg = num(nutrition.calories);
  const logged = num(nutrition.days_logged) ?? 0;
  const periodDeficitKcal = expenditureKcal === null || avg === null || logged <= 0
    ? null
    : Math.round((expenditureKcal - avg) * logged);
  let deficitStreakDays: number | null = null;
  if (expenditureKcal !== null && deficitCapKcal !== null && Array.isArray(m.days)) {
    deficitStreakDays = 0;
    for (let i = m.days.length - 1; i >= 0; i--) {
      const cal = num((m.days[i] as Record<string, unknown> | null)?.calories);
      if (cal === null || cal <= 0) {
        // Kayıtsız son gün (ör. henüz bitmemiş bugün) seriyi bozmaz.
        if (deficitStreakDays === 0 && i === m.days.length - 1) continue;
        break;
      }
      const gap = expenditureKcal - cal;
      if (gap <= 0 || gap > deficitCapKcal || cal < floorKcal) break;
      deficitStreakDays++;
    }
  }
  return {
    floorKcal,
    expenditureKcal,
    deficitCapKcal,
    periodDeficitKcal,
    deficitStreakDays,
    goalMode: goalModeOf(s.goal_mode),
  };
}

/** Talimata eklenen sağlık sınırı satırları (hedef türüne göre açık ya da fazla dili). */
export function healthSafetyLines(safety: HealthSafety): string[] {
  const deficitGoal = safety.goalMode === "fat_loss" || safety.goalMode === "recomp";
  const lines: string[] = [];
  switch (safety.goalMode) {
    case "recomp":
      lines.push("Kullanıcının hedefi: kas yaparken yağ yakma (hafif kalori açığı, yüksek protein, " +
        "düzenli kuvvet antrenmanı).");
      break;
    case "lean_gain":
      lines.push("Kullanıcının hedefi: kas yapma (kontrollü kalori fazlası ve kuvvet antrenmanı). " +
        "Kalori açığı ya da kilo vermeyi önerme; harcamanın üstünde yemek hedefin parçasıdır.");
      break;
    case "maintain":
      lines.push("Kullanıcının hedefi: kiloyu korumak. Kalori açığı ya da fazlası önerme; " +
        "alımı harcamaya yakın tutmayı öner.");
      break;
    default:
      lines.push("Kullanıcının hedefi: yağ yakma (güvenli kalori açığı).");
  }
  lines.push(
    `Sağlık sınırları: günde en az ${safety.floorKcal} kcal; haftada en çok 0,75 kg kayıp` +
      (!deficitGoal || safety.deficitCapKcal === null
        ? "."
        : `; günlük kalori açığı en çok ${safety.deficitCapKcal} kcal.`),
  );
  if (safety.periodDeficitKcal !== null) {
    lines.push(deficitGoal
      ? `Bu dönemde kayıtlı günlerin toplam kalori açığı ${safety.periodDeficitKcal} kcal ` +
        "(negatifse fazla yenmiş)."
      : `Bu dönemde kayıtlı günlerin toplam kalori dengesi (alım − harcama) ` +
        `${-safety.periodDeficitKcal} kcal (pozitifse fazla, negatifse açık).`);
  }
  if (deficitGoal && safety.deficitStreakDays !== null) {
    lines.push(`Güvenli açık serisi: ${safety.deficitStreakDays} gün.`);
  }
  lines.push(
    `ASLA ${safety.floorKcal} kcal altında yemeyi, haftada 0,75 kg'dan hızlı kaybı, ` +
      "oruç ya da aralıklı açlığı (ör. 16:8), öğün atlamayı ya da öğünü pas geçmeyi önerme.",
  );
  return lines;
}

/** Sınır aşan cümlenin yerine konan güvenli cümle. */
export function aiSafeSentence(floorKcal: number): string {
  const s = String(floorKcal).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `Günde en az ${s} kcal al, öğün atlama ve haftada 0,75 kg'dan hızlı kaybı hedefleme.`;
}

const FASTING = new RegExp(
  "oruç|aralıklı açlık|(?<!\\d)(?:1[2-9]|2[0-3])\\s*[:/]\\s*[1-8](?!\\d)|" +
    "(?:öğün|kahvaltı|yemeğ|yemek)\\p{L}*\\s+atla|" +
    "pas\\s+geç|hiç\\s+yeme|aç\\s+kal(?!ma)",
  "iu",
);
const KCAL = /(\d{1,2}(?:[.\s]\d{3})|\d{3,4})\s*(?:kcal|kalori)/giu;
const KG_WEEK =
  /(\d+(?:[,.]\d+)?)\s*kg\s*(?:\/\s*|(?:her\s+)?)hafta|hafta\p{L}*\s+(\d+(?:[,.]\d+)?)\s*kg/giu;
/** Yeme/hedef fiilleri; tam kelime (ör. "kcal" içindeki "al" sayılmaz). */
const INTAKE_VERB = new RegExp(
  `(?<!\\p{L})(?:ye|yemeye|yemeyi|yiyerek|al|alın|almaya|almayı|alarak|yetin\\p{L}*|` +
    `tüket\\p{L}*|hedefle\\p{L}*|in|indir\\p{L}*|düşür\\p{L}*|sınırla\\p{L}*)(?!\\p{L})`,
  "iu",
);
const DEFICIT_WORD = /açık/iu;

function unsafeSentence(sentence: string, safety: HealthSafety): boolean {
  const lower = sentence.toLocaleLowerCase("tr");
  if (FASTING.test(lower)) return true;
  const intake = INTAKE_VERB.test(lower);
  for (const m of lower.matchAll(KCAL)) {
    const value = Number(m[1].replace(/[.\s]/g, ""));
    if (!Number.isFinite(value)) continue;
    if (DEFICIT_WORD.test(lower)) {
      if (safety.deficitCapKcal !== null && value > safety.deficitCapKcal && intake) return true;
      continue;
    }
    if (value < safety.floorKcal && intake) return true;
  }
  for (const m of lower.matchAll(KG_WEEK)) {
    const value = Number((m[1] ?? m[2]).replace(",", "."));
    if (Number.isFinite(value) && value > AI_MAX_KG_PER_WEEK + 1e-9) return true;
  }
  return false;
}

/**
 * Model cevabını cümle cümle denetler: tabanın altında yeme, sınırı aşan
 * açık, 0,75 kg/hafta üstü hız, oruç ya da öğün atlama içeren cümle
 * [aiSafeSentence] ile değiştirilir (güvenli cümle bir kez yazılır).
 */
export function filterHealthAdvice(text: string, safety: HealthSafety): string {
  const safe = aiSafeSentence(safety.floorKcal);
  let replaced = false;
  return text
    .split("\n")
    .map((line) => {
      const out: string[] = [];
      for (const sentence of line.split(/(?<=[.!?])\s+/)) {
        if (sentence.trim() === "") continue;
        if (unsafeSentence(sentence, safety)) {
          if (!replaced) out.push(safe);
          replaced = true;
        } else {
          out.push(sentence);
        }
      }
      return out.join(" ");
    })
    .filter((line) => line !== "")
    .join("\n");
}
