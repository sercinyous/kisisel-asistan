#!/usr/bin/env bash
# schema.sql'i yerel bir PostgreSQL 16 kümesinde sınar (Supabase gerekmez):
#   1) temiz kurulum, iki kez (idempotent mi?)
#   2) rapor fonksiyonları + yetkiler (reports_test.sql), Google antrenman
#      içe aktarımı (fitness_import_test.sql)
#   3) sürüm 2 şemasıyla kurulmuş, verisi olan veritabanını yükseltme
# Kullanım (postgres işletim sistemi kullanıcısıyla):
#   PG_BIN=/usr/lib/postgresql/16/bin bash supabase/tests/run_local.sh [v2_schema.sql]
# İkinci adım için eski şema verilmezse `git show a220efc:supabase/schema.sql` denenir.
set -euo pipefail

PG_BIN="${PG_BIN:-/usr/lib/postgresql/16/bin}"
PORT="${PGPORT_TEST:-54329}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$HERE/../schema.sql"
WORK="$(mktemp -d /tmp/kasist-pg.XXXXXX)"
OLD_SCHEMA="${1:-}"

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

echo "== 2) rapor fonksiyonları ve yetkiler =="
run -d fresh -f "$HERE/reports_test.sql"
echo "== 2b) Google antrenman içe aktarımı (fitness_logs) =="
run -d fresh -f "$HERE/fitness_import_test.sql"

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
# Yükseltilmiş veritabanında fonksiyon ve yetki testleri de geçmeli.
run -d upgrade -c "delete from auth.users"
run -d upgrade -f "$HERE/reports_test.sql" >/dev/null 2>"$WORK/upgrade_reports.log" || {
  cat "$WORK/upgrade_reports.log"
  exit 1
}
echo "tamam: rapor testleri yükseltilmiş veritabanında da geçti"
run -d upgrade -f "$HERE/fitness_import_test.sql"

echo "TÜM ŞEMA TESTLERİ GEÇTİ"
