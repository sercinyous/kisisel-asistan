// Ortak kota yardımcılarının testleri:
//   node --experimental-strip-types --test supabase/functions/
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  AI_QUOTA_KIND,
  DEFAULT_AI_DAILY_LIMIT,
  DEFAULT_REPORT_REGEN_DAILY_LIMIT,
  parseLimit,
  REPORT_REGEN_QUOTA_KIND,
} from "./quota.ts";

test("sözleşme sabitleri: tür adları ve varsayılan sınırlar", () => {
  assert.equal(AI_QUOTA_KIND, "ai");
  assert.equal(REPORT_REGEN_QUOTA_KIND, "report_regen");
  assert.equal(DEFAULT_AI_DAILY_LIMIT, 100);
  assert.equal(DEFAULT_REPORT_REGEN_DAILY_LIMIT, 10);
});

test("parseLimit: geçerli pozitif tam sayı kabul edilir, boşluk kırpılır", () => {
  assert.equal(parseLimit("50", 100), 50);
  assert.equal(parseLimit("  250 \n", 100), 250);
  assert.equal(parseLimit("1", 100), 1);
  assert.equal(parseLimit("999999999", 100), 999999999);
});

test("parseLimit: boş, bozuk, sıfır, negatif, ondalık ya da çok büyük değer varsayılana döner", () => {
  for (const raw of [undefined, null, "", "  ", "abc", "0", "000", "-5", "12.5", "1e3", "1000000000", "10 20"]) {
    assert.equal(parseLimit(raw, 100), 100, String(raw));
  }
});
