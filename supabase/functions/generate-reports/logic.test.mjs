// generate-reports Edge Function'ının saf mantığının testleri (Node ile):
//   node --experimental-strip-types --test supabase/functions/generate-reports/logic.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  aiSafeSentence,
  buildGeminiRequest,
  filterHealthAdvice,
  healthSafetyOf,
  buildPrompt,
  extractBearer,
  lastFinishedWeekStart,
  parseGeminiText,
  parseRequest,
  resolveTarget,
  timingSafeEqual,
  todayInTimeZone,
  weekStartOf,
} from "./logic.ts";

test("parseRequest: geçerli gövdeler", () => {
  assert.deepEqual(parseRequest({ kind: "daily" }), { ok: true, kind: "daily", date: null, previous: false });
  assert.deepEqual(parseRequest({ kind: "weekly", date: "2026-11-09" }), {
    ok: true,
    kind: "weekly",
    date: "2026-11-09",
    previous: false,
  });
  assert.deepEqual(parseRequest({ kind: "daily", date: null }), {
    ok: true,
    kind: "daily",
    date: null,
    previous: false,
  });
  assert.deepEqual(parseRequest({ kind: "daily", previous: true }), {
    ok: true,
    kind: "daily",
    date: null,
    previous: true,
  });
  assert.deepEqual(parseRequest({ kind: "refresh" }), { ok: true, kind: "refresh", date: null, previous: false });
});

test("parseRequest: previous yalnızca tarihsiz günlükte, boolean", () => {
  for (const body of [
    { kind: "weekly", previous: true },
    { kind: "daily", previous: true, date: "2026-11-15" },
    { kind: "daily", previous: "evet" },
  ]) {
    assert.equal(parseRequest(body).ok, false, JSON.stringify(body));
  }
});

test("resolveTarget: previous → kullanıcının dünü (biten gün)", () => {
  // 16 Kasım 21:15 UTC = 17 Kasım 00:15 İstanbul.
  const now = new Date("2026-11-16T21:15:00Z");
  assert.deepEqual(resolveTarget("daily", null, "Europe/Istanbul", now, true), { ok: true, date: "2026-11-16" });
  assert.deepEqual(resolveTarget("daily", null, "Europe/Istanbul", now), { ok: true, date: "2026-11-17" });
});

test("parseRequest: kind eksik ya da geçersiz", () => {
  for (const body of [null, undefined, "daily", 5, [], {}, { kind: "monthly" }, { kind: 1 }]) {
    const result = parseRequest(body);
    assert.equal(result.ok, false, JSON.stringify(body));
    assert.match(result.error, /kind/);
  }
});

test("parseRequest: tarih biçimi ve gerçek tarih kontrolü", () => {
  for (const date of ["2026-1-5", "16.11.2026", "2026-11-16T10:00:00Z", "2026-02-30", "2026-13-01", "", 20261116, {}]) {
    const result = parseRequest({ kind: "daily", date });
    assert.equal(result.ok, false, JSON.stringify(date));
    assert.match(result.error, /date/);
  }
  assert.equal(parseRequest({ kind: "daily", date: "2028-02-29" }).ok, true);
});

test("todayInTimeZone: gün sınırı saat dilimine göre", () => {
  // 20:45 UTC = 23:45 İstanbul (aynı gün); 21:30 UTC = 00:30 İstanbul (ertesi gün)
  assert.equal(todayInTimeZone(new Date("2026-11-16T20:45:00Z"), "Europe/Istanbul"), "2026-11-16");
  assert.equal(todayInTimeZone(new Date("2026-11-16T21:30:00Z"), "Europe/Istanbul"), "2026-11-17");
  assert.equal(todayInTimeZone(new Date("2026-11-16T21:30:00Z"), "UTC"), "2026-11-16");
  assert.equal(todayInTimeZone(new Date("2026-11-16T03:00:00Z"), "America/Los_Angeles"), "2026-11-15");
  // Yıl sonu
  assert.equal(todayInTimeZone(new Date("2026-12-31T21:00:00Z"), "Europe/Istanbul"), "2027-01-01");
});

test("todayInTimeZone: bozuk saat dilimi İstanbul sayılır", () => {
  assert.equal(todayInTimeZone(new Date("2026-11-16T21:30:00Z"), "Boyle/BirYerYok"), "2026-11-17");
  assert.equal(todayInTimeZone(new Date("2026-11-16T21:30:00Z"), ""), "2026-11-17");
});

test("weekStartOf: haftanın Pazartesi'si", () => {
  assert.equal(weekStartOf("2026-11-16"), "2026-11-16"); // Pazartesi
  assert.equal(weekStartOf("2026-11-18"), "2026-11-16"); // Çarşamba
  assert.equal(weekStartOf("2026-11-22"), "2026-11-16"); // Pazar
  assert.equal(weekStartOf("2026-11-01"), "2026-10-26"); // ay sınırı
  assert.equal(weekStartOf("2027-01-01"), "2026-12-28"); // yıl sınırı
});

test("lastFinishedWeekStart: biten son haftanın Pazartesi'si", () => {
  assert.equal(lastFinishedWeekStart("2026-11-16"), "2026-11-09"); // Pazartesi sabahı: dün biten hafta
  assert.equal(lastFinishedWeekStart("2026-11-22"), "2026-11-09"); // Pazar: içinde bulunulan hafta bitmedi
  assert.equal(lastFinishedWeekStart("2026-11-23"), "2026-11-16");
  assert.equal(lastFinishedWeekStart("2027-01-04"), "2026-12-28");
});

test("resolveTarget: tarih verilmezse günlük = bugün, haftalık = biten hafta", () => {
  const now = new Date("2026-11-16T04:00:00Z"); // Pazartesi 07:00 İstanbul
  assert.deepEqual(resolveTarget("daily", null, "Europe/Istanbul", now), { ok: true, date: "2026-11-16" });
  assert.deepEqual(resolveTarget("weekly", null, "Europe/Istanbul", now), { ok: true, date: "2026-11-09" });
});

test("resolveTarget: haftalıkta verilen tarih haftanın Pazartesi'sine çekilir", () => {
  const now = new Date("2026-11-16T04:00:00Z");
  assert.deepEqual(resolveTarget("weekly", "2026-11-05", "Europe/Istanbul", now), { ok: true, date: "2026-11-02" });
  // İçinde bulunulan hafta üretilebilir (kısmi rapor).
  assert.deepEqual(resolveTarget("weekly", "2026-11-16", "Europe/Istanbul", now), { ok: true, date: "2026-11-16" });
});

test("resolveTarget: gelecekteki tarih reddedilir", () => {
  const now = new Date("2026-11-16T20:45:00Z"); // 23:45 İstanbul, 16 Kasım
  assert.equal(resolveTarget("daily", "2026-11-16", "Europe/Istanbul", now).ok, true);
  const daily = resolveTarget("daily", "2026-11-17", "Europe/Istanbul", now);
  assert.equal(daily.ok, false);
  assert.match(daily.error, /gelecek/i);
  // Gelecek haftanın bir günü → hafta başı bugünden sonra
  assert.equal(resolveTarget("weekly", "2026-11-23", "Europe/Istanbul", now).ok, false);
  // Aynı an, saat dilimi ilerideyse 17 Kasım artık "bugün"dür.
  assert.equal(resolveTarget("daily", "2026-11-17", "Pacific/Auckland", now).ok, true);
});

test("timingSafeEqual", () => {
  assert.equal(timingSafeEqual("gizli-anahtar", "gizli-anahtar"), true);
  assert.equal(timingSafeEqual("gizli-anahtar", "gizli-anahtaR"), false);
  assert.equal(timingSafeEqual("gizli", "gizli-anahtar"), false);
  assert.equal(timingSafeEqual("gizli-anahtar", "gizli"), false);
  assert.equal(timingSafeEqual("şifre", "şifre"), true);
  // Boş değer hiçbir şeyle eşleşmez: tanımsız CRON_SECRET herkese kapı açmasın.
  assert.equal(timingSafeEqual("", ""), false);
  assert.equal(timingSafeEqual("", "x"), false);
});

test("extractBearer", () => {
  assert.equal(extractBearer("Bearer abc.def.ghi"), "abc.def.ghi");
  assert.equal(extractBearer("bearer   abc"), "abc");
  assert.equal(extractBearer("Basic abc"), null);
  assert.equal(extractBearer("Bearer "), null);
  assert.equal(extractBearer(null), null);
});

const metrics = {
  period: { start: "2026-11-09", end: "2026-11-15" },
  work: { tasks_total: 12, tasks_done: 9, routines_planned: 50, routines_done: 41, rate: 81 },
  form: { workouts_planned: 7, workouts_done: 5, protein_days_hit: 5, calorie_days_in_range: 4, rate: 71 },
};

test("buildPrompt: haftalık kurallar ve sayılar", () => {
  const prompt = buildPrompt("weekly", "2026-11-09", metrics);
  assert.match(prompt.system, /Türkçe/);
  assert.match(prompt.system, /120 kelime/);
  assert.match(prompt.system, /en fazla 3 öneri/);
  assert.match(prompt.system, /tıbbi/i);
  assert.match(prompt.system, /düz metin/i);
  assert.match(prompt.user, /2026-11-09/);
  assert.ok(prompt.user.includes(JSON.stringify(metrics)));
});

test("buildPrompt: günlük sınır 70 kelime, öneri listesi yok", () => {
  const prompt = buildPrompt("daily", "2026-11-16", metrics);
  assert.match(prompt.system, /70 kelime/);
  assert.doesNotMatch(prompt.system, /120 kelime/);
  assert.match(prompt.user, /2026-11-16/);
});

test("buildGeminiRequest: gövde biçimi", () => {
  const body = buildGeminiRequest({ system: "S", user: "U" });
  assert.equal(body.systemInstruction.parts[0].text, "S");
  assert.deepEqual(body.contents, [{ role: "user", parts: [{ text: "U" }] }]);
  assert.equal(typeof body.generationConfig.maxOutputTokens, "number");
});

test("parseGeminiText: parçaları birleştirir ve kırpar", () => {
  const response = {
    candidates: [{ content: { parts: [{ text: "  İyi bir hafta. " }, { text: "Devam et.\n" }] } }],
  };
  assert.equal(parseGeminiText(response), "İyi bir hafta. Devam et.");
});

test("parseGeminiText: markdown işaretlerini temizler", () => {
  const response = {
    candidates: [{ content: { parts: [{ text: "**İş** güçlü.\n- Öneri bir\n* Öneri iki\n# Başlık" }] } }],
  };
  assert.equal(parseGeminiText(response), "İş güçlü.\nÖneri bir\nÖneri iki\nBaşlık");
});

test("parseGeminiText: metin yoksa null", () => {
  for (const response of [
    null,
    {},
    { candidates: [] },
    { candidates: [{}] },
    { candidates: [{ content: { parts: [] } }] },
    { candidates: [{ content: { parts: [{ text: "   " }] } }] },
    { candidates: [{ content: { parts: [{ inlineData: {} }] } }] },
    { promptFeedback: { blockReason: "SAFETY" } },
    "metin",
  ]) {
    assert.equal(parseGeminiText(response), null, JSON.stringify(response));
  }
});

test("parseGeminiText: aşırı uzun yanıt kısaltılır", () => {
  const response = { candidates: [{ content: { parts: [{ text: "a".repeat(5000) }] } }] };
  assert.equal(parseGeminiText(response).length, 2000);
});

const healthMetrics = {
  nutrition: { calories: 1900, days_logged: 5 },
  safety: { floor_kcal: 1605, expenditure_kcal: 2500 },
  days: [
    { date: "2026-11-13", calories: 2000 },
    { date: "2026-11-14", calories: 1950 },
    { date: "2026-11-15", calories: 1900 },
  ],
};

test("healthSafetyOf: taban, sınır, dönem açığı ve seri", () => {
  const s = healthSafetyOf(healthMetrics);
  assert.equal(s.floorKcal, 1605);
  assert.equal(s.deficitCapKcal, 625);
  assert.equal(s.periodDeficitKcal, 3000);
  assert.equal(s.deficitStreakDays, 3);
  const empty = healthSafetyOf({});
  assert.equal(empty.floorKcal, 1200);
  assert.equal(empty.deficitCapKcal, null);
  assert.equal(empty.deficitStreakDays, null);
});

test("healthSafetyOf: fazla yenen gün seriyi bitirir", () => {
  const s = healthSafetyOf({ ...healthMetrics, days: [{ calories: 1900 }, { calories: 2700 }] });
  assert.equal(s.deficitStreakDays, 0);
});

test("buildPrompt: sağlık sınırları talimatta", () => {
  const prompt = buildPrompt("weekly", "2026-11-09", healthMetrics);
  assert.match(prompt.system, /en az 1605 kcal/);
  assert.match(prompt.system, /0,75 kg/);
  assert.match(prompt.system, /en çok 625 kcal/);
  assert.match(prompt.system, /3000 kcal/);
  assert.match(prompt.system, /oruç/);
  assert.match(prompt.system, /16:8/);
});

test("healthSafetyOf: hedef türü okunur, bilinmeyen yağ yakma", () => {
  assert.equal(healthSafetyOf(healthMetrics).goalMode, "fat_loss");
  const gain = { ...healthMetrics, safety: { ...healthMetrics.safety, goal_mode: "lean_gain" } };
  assert.equal(healthSafetyOf(gain).goalMode, "lean_gain");
  const bad = { ...healthMetrics, safety: { ...healthMetrics.safety, goal_mode: "bulk" } };
  assert.equal(healthSafetyOf(bad).goalMode, "fat_loss");
});

test("buildPrompt: kas yapmada açık dili yok, fazla dengesi var", () => {
  const metrics = {
    ...healthMetrics,
    nutrition: { calories: 2800, days_logged: 5 },
    safety: { ...healthMetrics.safety, goal_mode: "lean_gain" },
  };
  const prompt = buildPrompt("weekly", "2026-11-09", metrics);
  assert.match(prompt.system, /hedefi: kas yapma/);
  assert.match(prompt.system, /dengesi \(alım − harcama\) 1500 kcal/);
  assert.doesNotMatch(prompt.system, /Güvenli açık serisi/);
  assert.doesNotMatch(prompt.system, /kalori açığı en çok/);
  assert.match(prompt.system, /en az 1605 kcal/);
  assert.match(prompt.system, /oruç/);
});

test("buildPrompt: korumada açık/fazla önerilmez", () => {
  const metrics = { ...healthMetrics, safety: { ...healthMetrics.safety, goal_mode: "maintain" } };
  const prompt = buildPrompt("weekly", "2026-11-09", metrics);
  assert.match(prompt.system, /kiloyu korumak/);
  assert.doesNotMatch(prompt.system, /Güvenli açık serisi/);
});

test("filterHealthAdvice: güvenli metin ve geçmiş kalori cümlesi kalır", () => {
  const s = healthSafetyOf(healthMetrics);
  for (const text of [
    "Salı akşam yemeğin 600 kcal civarındaydı.",
    "Bu hafta 900 kcal açık verdin.",
    "Proteini artır.\nGünde 8.000 adım hedefle.",
    "Öğle yemeğinde 500 kalori aldın, dengeliydi.",
  ]) {
    assert.equal(filterHealthAdvice(text, s), text);
  }
});

test("filterHealthAdvice: taban altı, hızlı kayıp, oruç, 16:8, pas geç değiştirilir", () => {
  const s = healthSafetyOf(healthMetrics);
  const text = "Harika gidiyorsun. Günde 1.000 kcal ye.\n16:8 yap.\n" +
    "Akşam yemeğini pas geç.\nHaftada 1,5 kg ver.\nGünde 1200 kaloriye düşür.\n" +
    "Günde 900 kcal açık hedefle.";
  const out = filterHealthAdvice(text, s);
  assert.ok(out.startsWith("Harika gidiyorsun."));
  assert.equal(out.split(aiSafeSentence(1605)).length - 1, 1);
  for (const bad of ["1.000 kcal", "16:8", "pas geç", "1,5 kg", "1200", "900 kcal"]) {
    assert.ok(!out.includes(bad), bad);
  }
});
