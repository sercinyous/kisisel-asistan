#!/usr/bin/env bash
# schema.sql'i yerel bir PostgreSQL 16 kümesinde sınar (Supabase gerekmez):
#   1) temiz kurulum, iki kez (idempotent mi?)
#   1c) Faz 4B (ayrı veritabanında): kayıt kapısı (varsayılan açık kurulum),
#      şema/nötr seed/Pusholder→İş, arkadaşlar ve yetki sınırları, AI kotası
#      (paralel oturumlarla atomiklik), SQL-Dart hedef eşliği (SQL tarafı;
#      Dart tarafı test/friend_goal_parity_test.dart, aynı goal_vectors.json)
#   2) rapor fonksiyonları + yetkiler (reports_test.sql), Google antrenman
#      içe aktarımı (fitness_import_test.sql), profil sütunları
#      (profile_columns_test.sql)
#   3) sürüm 2 şemasıyla kurulmuş, verisi olan veritabanını yükseltme
#   4) sürüm 3 şemasıyla kurulmuş, verisi olan veritabanını yükseltme
# Kullanım (postgres işletim sistemi kullanıcısıyla):
#   PG_BIN=/usr/lib/postgresql/16/bin bash supabase/tests/run_local.sh [v2_schema.sql [v3_schema.sql]]
# Şema verilmezse `git show a220efc:supabase/schema.sql` (sürüm 2) ve
# `git show e0cee16:supabase/schema.sql` (sürüm 3) denenir. 3 numaralı (sürüm 2)
# adım şema bulunamazsa hata verir; 4 numaralı (sürüm 3) adım bulunamazsa uyarı
# yazıp atlanır (betik git deposu olmayan bir kopyadan da çalıştırılabilsin).
set -euo pipefail

PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
PORT="${PGPORT_TEST:-54329}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$HERE/../schema.sql"
WORK="$(mktemp -d /tmp/kasist-pg.XXXXXX)"
OLD_SCHEMA="${1:-}"
V3_SCHEMA="${2:-}"

cleanup() {
  "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"$PG_BIN/initdb" -D "$WORK/data" -U postgres --locale=C.UTF-8 -E UTF8 >/dev/null
"$PG_BIN/pg_ctl" -D "$WORK/data" -w -l "$WORK/log" \
  -o "-p $PORT -k $WORK -c listen_addresses=''" start >/dev/null

# Şema dosyasının "zaten var, atlandı" bildirimleri çıktıyı boğmasın.
export PGOPTIONS="-c client_min_messages=warning"
run() { "$PG_BIN/psql" -X -q -v ON_ERROR_STOP=1 -h "$WORK" -p "$PORT" -U postgres "$@"; }

echo "== 1) temiz kurulum (iki kez) =="
run -d postgres -c "create database fresh"
run -d fresh -f "$HERE/auth_stub.sql"
run -d fresh -f "$SCHEMA"
run -d fresh -f "$SCHEMA"
echo "tamam"

echo "== 1b) profil sütunları (user_settings: boy, doğum yılı, cinsiyet) =="
run -d fresh -f "$HERE/profile_columns_test.sql"

echo "== 1b2) görev kategorileri (user_settings.task_categories, tasks.category) =="
run -d fresh -f "$HERE/task_categories_test.sql"

echo "== 1b3) ilk kurulum RPC'si (complete_onboarding: tek transaction, idempotent) =="
run -d fresh -f "$HERE/complete_onboarding_test.sql"

echo "== 1c) Faz 4B: kayıt kapısı, arkadaşlar, kota, eşlik =="
export GOAL_VECTORS="$HERE/goal_vectors.json"
run -d postgres -c "create database faz4b"
run -d faz4b -f "$HERE/auth_stub.sql"
run -d faz4b -f "$SCHEMA"
run -d faz4b -f "$SCHEMA"
# Kapı testi şema yeni kurulmuşken İLK çalışır (varsayılan: kapı açık).
run -d faz4b -f "$HERE/signup_gate_test.sql" >/dev/null
echo "tamam: kayıt kapısı"
run -d faz4b -f "$HERE/faz4b_schema_test.sql" >/dev/null
echo "tamam: şema, nötr seed, Pusholder → İş, rapor zamanlayıcısı yetkisi"
run -d faz4b -f "$HERE/friends_test.sql" >/dev/null
echo "tamam: arkadaşlar ve yetki sınırları"
run -d faz4b -f "$HERE/ai_quota_test.sql" >/dev/null
echo "tamam: AI kotası"
run -d faz4b -f "$HERE/goal_parity_test.sql" >/dev/null
echo "tamam: SQL-Dart eşlik (SQL tarafı)"
run -d faz4b -f "$HERE/friend_leaderboard_test.sql" >/dev/null
echo "tamam: arkadaş sıralaması (friend_leaderboard)"
run -d faz4b -f "$HERE/friend_scope_test.sql" >/dev/null
echo "tamam: arkadaş paylaşım kapsamı ve sağlık kaynağı (friend_scope_test)"

# Atomiklik: 8 paralel oturum aynı kullanıcı için 5'er çağrı yapar, limit 10.
# Tam 10 çağrı true almalı, sayaç tam 10 olmalı (aşım ve kayıp artış yok).
run -d faz4b -c "alter table auth.users disable trigger signup_invite_gate" \
  -c "insert into auth.users (id, email) values ('e1000000-0000-0000-0000-000000000001', 'paralel@example.com') on conflict do nothing" \
  -c "alter table auth.users enable trigger signup_invite_gate"
for i in 1 2 3 4 5 6 7 8; do
  run -d faz4b -At -c "select count(*) from generate_series(1, 5) where public.consume_ai_quota('e1000000-0000-0000-0000-000000000001', 'paralel', 10)" \
    > "$WORK/quota_$i.out" &
done
wait
TRUES=$(cat "$WORK"/quota_*.out | awk '{ s += $1 } END { print s + 0 }')
COUNT=$(run -d faz4b -At -c "select count from public.ai_usage where user_id = 'e1000000-0000-0000-0000-000000000001' and kind = 'paralel'")
if [ "$TRUES" != "10" ] || [ "$COUNT" != "10" ]; then
  echo "BAŞARISIZ: paralel kota: true=$TRUES sayaç=$COUNT (ikisi de 10 olmalı)" >&2
  exit 1
fi
echo "tamam: paralel kota atomik (true=$TRUES, sayaç=$COUNT)"

echo "== 2) rapor fonksiyonları ve yetkiler =="
run -d fresh -f "$HERE/reports_test.sql"
echo "== 2b) Google antrenman içe aktarımı (fitness_logs) =="
run -d fresh -f "$HERE/fitness_import_test.sql"
echo "== 2c) rutin tamamlaması sahiplik FK'sı (routine_owner_test.sql) =="
run -d fresh -f "$HERE/routine_owner_test.sql"
echo "== 2d) geç gelen veriyle rapor yenileme (report_dirty_test.sql) =="
run -d fresh -f "$HERE/report_dirty_test.sql" >/dev/null
echo "tamam: report_dirty"
echo "== 2e) kiralamalı rapor yenileme (report_claim_test.sql) =="
run -d fresh -f "$HERE/report_claim_test.sql" >/dev/null
echo "tamam: report_claim_lease"

echo "== 3) sürüm 2 → 3 yükseltme =="
if [ -z "$OLD_SCHEMA" ]; then
  OLD_SCHEMA="$WORK/schema_v2.sql"
  git -C "$HERE" show a220efc:supabase/schema.sql > "$OLD_SCHEMA"
fi
run -d postgres -c "create database upgrade"
run -d upgrade -f "$HERE/auth_stub.sql"
run -d upgrade -f "$OLD_SCHEMA"
run -d upgrade -f "$HERE/upgrade_fixture.sql"
run -d upgrade -f "$SCHEMA"
run -d upgrade -f "$SCHEMA"
run -d upgrade -f "$HERE/upgrade_test.sql"
run -d upgrade -v fixture_user=eeeeeeee-0000-0000-0000-000000000005 \
  -f "$HERE/upgrade_faz4b_test.sql"
run -d upgrade -v fixture_user=eeeeeeee-0000-0000-0000-000000000005 \
  -v fixture_calories=2400 -f "$HERE/profile_columns_test.sql"
# Yükseltilmiş veritabanında fonksiyon ve yetki testleri de geçmeli.
run -d upgrade -c "delete from auth.users"
run -d upgrade -f "$HERE/reports_test.sql" >/dev/null 2>"$WORK/upgrade_reports.log" || {
  cat "$WORK/upgrade_reports.log"
  exit 1
}
echo "tamam: rapor testleri yükseltilmiş veritabanında da geçti"
run -d upgrade -f "$HERE/complete_onboarding_test.sql"
run -d upgrade -f "$HERE/fitness_import_test.sql"
run -d upgrade -f "$HERE/routine_owner_test.sql"
# Yükseltilmiş veritabanında Faz 4B işlevleri de aynı davranır.
run -d upgrade -f "$HERE/friends_test.sql" >/dev/null
run -d upgrade -f "$HERE/ai_quota_test.sql" >/dev/null
run -d upgrade -f "$HERE/goal_parity_test.sql" >/dev/null
run -d upgrade -f "$HERE/report_dirty_test.sql" >/dev/null
run -d upgrade -f "$HERE/friend_scope_test.sql" >/dev/null
run -d upgrade -f "$HERE/report_claim_test.sql" >/dev/null
echo "tamam: Faz 4B testleri sürüm 2'den yükseltilmiş veritabanında da geçti"

echo "== 4) sürüm 3 → güncel yükseltme =="
if [ -z "$V3_SCHEMA" ]; then
  V3_SCHEMA="$WORK/schema_v3.sql"
  git -C "$HERE" show e0cee16:supabase/schema.sql > "$V3_SCHEMA" 2>/dev/null \
    || { rm -f "$V3_SCHEMA"; V3_SCHEMA=""; }
fi
if [ -z "$V3_SCHEMA" ]; then
  echo "UYARI: sürüm 3 şeması bulunamadı, 4. adım ATLANDI" \
       "(2. argüman olarak schema_v3.sql verin)" >&2
else
  run -d postgres -c "create database upgrade3"
  run -d upgrade3 -f "$HERE/auth_stub.sql"
  run -d upgrade3 -f "$V3_SCHEMA"
  run -d upgrade3 -f "$HERE/upgrade_fixture_v3.sql"
  run -d upgrade3 -f "$SCHEMA"
  run -d upgrade3 -f "$SCHEMA"
  # Yükseltme testi, fikstür satırına başka test dokunmadan ÖNCE çalışır.
  run -d upgrade3 -v fixture_user=eeeeeeee-0000-0000-0000-000000000006 \
    -f "$HERE/upgrade_faz4b_test.sql"
  run -d upgrade3 -v fixture_user=eeeeeeee-0000-0000-0000-000000000006 \
    -v fixture_calories=2300 -f "$HERE/profile_columns_test.sql"
  # Yükseltilmiş veritabanında Faz 4B işlevleri de aynı davranır.
  run -d upgrade3 -f "$HERE/friends_test.sql" >/dev/null
  run -d upgrade3 -f "$HERE/ai_quota_test.sql" >/dev/null
  run -d upgrade3 -f "$HERE/goal_parity_test.sql" >/dev/null
  run -d upgrade3 -f "$HERE/report_dirty_test.sql" >/dev/null
  run -d upgrade3 -f "$HERE/report_claim_test.sql" >/dev/null
  run -d upgrade3 -f "$HERE/routine_owner_test.sql" >/dev/null
  run -d upgrade3 -f "$HERE/friend_scope_test.sql" >/dev/null
  echo "tamam: Faz 4B testleri sürüm 3'ten yükseltilmiş veritabanında da geçti"
  echo "tamam: sürüm 3 yükseltmesi"
fi

echo "TÜM ŞEMA TESTLERİ GEÇTİ"
