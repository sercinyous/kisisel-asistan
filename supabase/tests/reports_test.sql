-- Rapor fonksiyonlarının ve rapor tablosu yetkilerinin testi.
-- Elle hesaplanmış beklenen değerlerle karşılaştırır; ilk farkta durur.
-- Çalıştırma: supabase/tests/run_local.sh (auth_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- Kayıt kapısı (signup_invite_gate) bu testin fikstür kullanıcılarını
-- engellemesin; kapının kendisi signup_gate_test.sql'de sınanır.
alter table auth.users disable trigger signup_invite_gate;

create schema t;

create function t.eq(p_label text, p_actual jsonb, p_expected jsonb) returns void
language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception E'BAŞARISIZ: %\n  beklenen: %\n  gelen:    %', p_label, p_expected, p_actual;
  end if;
  raise notice 'tamam: %', p_label;
end;
$$;

-- [p_sql] verilen rol + kullanıcı ile çalışınca "yetki yok" (42501) vermelidir.
create function t.denied(p_label text, p_role text, p_uid uuid, p_sql text) returns void
language plpgsql as $$
declare
  v_denied boolean := false;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
  exception when insufficient_privilege then
    v_denied := true;
  end;
  reset role;
  if not v_denied then
    raise exception 'BAŞARISIZ: % — % için reddedilmeliydi', p_label, p_role;
  end if;
  raise notice 'tamam: %', p_label;
end;
$$;

-- [p_sql] (tek bigint döndüren sorgu) verilen rol + kullanıcı ile çalıştırılır.
create function t.as_role(p_role text, p_uid uuid, p_sql text) returns bigint
language plpgsql as $$
declare
  v bigint;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  execute p_sql into v;
  reset role;
  return v;
end;
$$;

grant usage on schema t to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Kullanıcılar. Seed (trigger) verisi silinir ki sayılar yalnızca
-- aşağıdaki fikstürden gelsin.
--   A: dolu hafta (Europe/Istanbul)   B: hiç veri yok
--   C: A'nın sınır kayıtları, saat dilimi UTC   D: bugünü içeren hafta
-- ---------------------------------------------------------------------
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@test'),
  ('cccccccc-0000-0000-0000-000000000003', 'c@test'),
  ('dddddddd-0000-0000-0000-000000000004', 'd@test');

delete from public.routines;
delete from public.tasks;
delete from public.notes;
delete from public.fitness_logs;
-- B'nin ayar satırı da yok: hedefler tablo varsayılanlarından gelmeli.
delete from public.user_settings where user_id = 'bbbbbbbb-0000-0000-0000-000000000002';
update public.user_settings set timezone = 'UTC'
  where user_id = 'cccccccc-0000-0000-0000-000000000003';
-- Beklenen değerler 170 g protein / 10000 adım hedefiyle elle hesaplandı;
-- tablo varsayılanları (Faz 4B: nötr) değişse de bu fikstür sabit kalır.
update public.user_settings set daily_protein_g = 170, daily_steps = 10000
  where user_id in ('aaaaaaaa-0000-0000-0000-000000000001',
                    'cccccccc-0000-0000-0000-000000000003',
                    'dddddddd-0000-0000-0000-000000000004');

\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
\set D '''dddddddd-0000-0000-0000-000000000004'''

-- ---------------------------------------------------------------------
-- A'nın fikstürü. Hafta: 28 Eylül 2026 Pazartesi – 4 Ekim 2026 Pazar.
-- Hedefler: 2000 kcal (aralık 1700–2200), 170 g protein (eşik 153), 10000 adım, 450 dk
-- (A, C, D için açıkça yazılır; B'nin ayar satırı yok: tablo varsayılanları 120 g / 8000).
-- ---------------------------------------------------------------------
insert into public.routines
  (id, user_id, title, category, frequency, days_of_week, day_of_month, is_active, created_at)
values
  -- R1: her gün → 7 planlı
  ('00000000-0000-0000-0000-0000000000a1', :A, 'R1 günlük', 'operasyon', 'weekly', '{1,2,3,4,5,6,7}', null, true, '2026-09-01 09:00+03'),
  -- R2: spor, Pzt/Çar/Cum → 3 planlı
  ('00000000-0000-0000-0000-0000000000a2', :A, 'R2 spor', 'spor', 'weekly', '{1,3,5}', null, true, '2026-09-01 09:00+03'),
  -- R3: hafta ortasında (1 Ekim 00:30 İstanbul = 30 Eylül 21:30 UTC) oluştu → Per..Paz = 4 planlı
  ('00000000-0000-0000-0000-0000000000a3', :A, 'R3 yeni', 'kisisel', 'weekly', '{1,2,3,4,5,6,7}', null, true, '2026-10-01 00:30+03'),
  -- M1: ayın 31'i; Eylül 30 gün → 30 Eylül Çarşamba planlı
  ('00000000-0000-0000-0000-0000000000b1', :A, 'M1 ay sonu', 'finans', 'monthly', '{1,2,3,4,5,6,7}', 31, true, '2026-08-01 09:00+03'),
  -- M2: ayın 2'si → 2 Ekim Cuma planlı
  ('00000000-0000-0000-0000-0000000000b2', :A, 'M2 ayın ikisi', 'operasyon', 'monthly', '{1,2,3,4,5,6,7}', 2, true, '2026-08-01 09:00+03'),
  -- M3: ayın 15'i → bu haftaya düşmez
  ('00000000-0000-0000-0000-0000000000b3', :A, 'M3 ortası', 'finans', 'monthly', '{1,2,3,4,5,6,7}', 15, true, '2026-08-01 09:00+03'),
  -- R4: pasif → sayılmaz
  ('00000000-0000-0000-0000-0000000000a4', :A, 'R4 pasif', 'spor', 'weekly', '{1,2,3,4,5,6,7}', null, false, '2026-09-01 09:00+03');

insert into public.routine_completions (user_id, routine_id, completed_on) values
  (:A, '00000000-0000-0000-0000-0000000000a1', '2026-09-28'),
  (:A, '00000000-0000-0000-0000-0000000000a1', '2026-09-29'),
  (:A, '00000000-0000-0000-0000-0000000000a1', '2026-09-30'),
  (:A, '00000000-0000-0000-0000-0000000000a1', '2026-10-01'),
  (:A, '00000000-0000-0000-0000-0000000000a1', '2026-10-02'),
  (:A, '00000000-0000-0000-0000-0000000000a2', '2026-09-28'),
  -- R2 Salı planlı değil: sayılmamalı
  (:A, '00000000-0000-0000-0000-0000000000a2', '2026-09-29'),
  (:A, '00000000-0000-0000-0000-0000000000a3', '2026-10-01'),
  -- R3 o gün henüz yoktu: sayılmamalı
  (:A, '00000000-0000-0000-0000-0000000000a3', '2026-09-30'),
  -- M1 Eylül dönemi tamam
  (:A, '00000000-0000-0000-0000-0000000000b1', '2026-09-01'),
  -- M2'nin Eylül dönemi tamam ama haftaya düşen Ekim dönemi değil
  (:A, '00000000-0000-0000-0000-0000000000b2', '2026-09-01'),
  (:A, '00000000-0000-0000-0000-0000000000a4', '2026-09-28');

insert into public.tasks (user_id, title, status, due_at) values
  (:A, 'T1', 'done', '2026-09-28 10:00+03'),
  (:A, 'T2', 'todo', '2026-09-28 23:30+03'),          -- Pazartesi
  (:A, 'T3', 'done', '2026-09-29 00:30+03'),          -- Salı (UTC'de hâlâ Pazartesi)
  (:A, 'T4', 'done', '2026-10-04 23:59:59+03'),       -- Pazar
  (:A, 'T5', 'done', '2026-10-05 00:00+03'),          -- sonraki hafta
  (:A, 'T6', 'done', null),                           -- tarihsiz
  (:A, 'T7', 'done', '2026-09-27 23:59+03');          -- önceki hafta

insert into public.fitness_logs (user_id, log_type, workout_type, logged_at) values
  (:A, 'workout', 'weights',    '2026-09-28 19:00+03'),
  (:A, 'workout', 'running',    '2026-09-28 23:30+03'),   -- Pazartesi
  (:A, 'workout', 'kickboxing', '2026-09-29 00:30+03'),   -- Salı
  (:A, 'workout', 'running',    '2026-10-03 10:00+03');

insert into public.fitness_logs (user_id, log_type, weight_kg, logged_at) values
  (:A, 'weight', 84.0, '2026-09-20 08:00+03'),
  (:A, 'weight', 83.8, '2026-09-27 23:30+03'),   -- haftadan önceki son ölçüm = başlangıç
  (:A, 'weight', 83.6, '2026-09-28 08:00+03'),
  (:A, 'weight', 83.1, '2026-10-04 23:30+03'),   -- haftanın son ölçümü
  (:A, 'weight', 82.0, '2026-10-05 00:30+03');   -- sonraki hafta

insert into public.nutrition_logs (user_id, food_name, calories, protein_g, carbs_g, fat_g, eaten_at) values
  -- Pazartesi: 1700 kcal (alt sınır, dahil) · 153 g protein (tam eşik, tutar)
  (:A, 'p1', 500, 40, 50, 10, '2026-09-28 08:00+03'),
  (:A, 'p2', 700, 60, 60, 20, '2026-09-28 13:00+03'),
  (:A, 'p3', 500, 53, 40, 15, '2026-09-28 23:30+03'),
  -- Salı: 2200.5 kcal (üst sınırın üstü) · 140.5 g (tutmaz)
  (:A, 's1', 300, 20, 30, 5, '2026-09-29 00:30+03'),
  (:A, 's2', 1900.5, 120.5, 200, 60, '2026-09-29 12:00+03'),
  -- Çarşamba: 2200 kcal (üst sınır, dahil) · 180 g
  (:A, 'c1', 2200, 180, 200, 70, '2026-09-30 12:00+03'),
  -- Perşembe: 1699.9 kcal (alt sınırın altı) · 152.9 g (eşiğin altı)
  (:A, 'e1', 1699.9, 152.9, 100, 50, '2026-10-01 12:00+03');

insert into public.daily_health_metrics (user_id, metric_date, steps, sleep_minutes, active_kcal) values
  (:A, '2026-09-28', 8000, 420, 400),
  (:A, '2026-09-29', 12000, 0, 500),
  (:A, '2026-09-30', 0, 480, 0);

-- ---------------------------------------------------------------------
-- Haftalık rapor (A).
--   rutin: Pzt 2/2, Sal 1/1, Çar 3/2, Per 2/2, Cum 4/1, Cmt 2/0, Paz 2/0 → 16 planlı, 8 yapıldı
--   görev: Pzt 2/1, Sal 1/1, Paz 1/1 → 4 toplam, 3 yapıldı
--   iş oranı (3+8)/(4+16) = %55
--   spor planlı 3 (Pzt, Çar, Cum), antrenman 4 (Pzt 2, Sal 1, Cmt 1)
--   protein tutan gün 2 (Pzt, Çar), kalori aralığında 2 (Pzt, Çar)
--   form oranı (min(4,3)+2)/(3+7) = %50
--   ort. kalori (1700+2200.5+2200+1699.9)/4 = 1950.1 · protein 626.4/4 = 156.6
--   ort. karbonhidrat 680/4 = 170 · yağ 230/4 = 57.5
--   adım (8000+12000)/2 · uyku (420+480)/2 · aktif (400+500)/2
-- ---------------------------------------------------------------------
select t.eq('haftalık: dolu hafta',
  public.report_weekly_metrics(:A, '2026-09-28'),
  '{
    "period": {"start": "2026-09-28", "end": "2026-10-04"},
    "work": {"tasks_total": 4, "tasks_done": 3, "routines_planned": 16, "routines_done": 8, "rate": 55},
    "form": {"workouts_planned": 3, "workouts_done": 4, "protein_days_hit": 2, "calorie_days_in_range": 2, "rate": 50},
    "nutrition": {"calories": 1950.1, "protein_g": 156.6, "carbs_g": 170, "fat_g": 57.5, "days_logged": 4},
    "health": {"steps": 10000, "sleep_minutes": 450, "active_kcal": 450, "days_with_data": 3},
    "weight": {"start_kg": 83.8, "end_kg": 83.1, "change_kg": -0.7},
    "targets": {"calories": 2000, "protein_g": 170, "steps": 10000, "sleep_minutes": 450},
    "days": [
      {"date": "2026-09-28", "work_rate": 75,  "form_rate": 100, "calories": 1700,   "protein_g": 153,   "steps": 8000,  "sleep_minutes": 420, "workouts": 2},
      {"date": "2026-09-29", "work_rate": 100, "form_rate": 0,   "calories": 2200.5, "protein_g": 140.5, "steps": 12000, "sleep_minutes": 0,   "workouts": 1},
      {"date": "2026-09-30", "work_rate": 67,  "form_rate": 50,  "calories": 2200,   "protein_g": 180,   "steps": 0,     "sleep_minutes": 480, "workouts": 0},
      {"date": "2026-10-01", "work_rate": 100, "form_rate": 0,   "calories": 1699.9, "protein_g": 152.9, "steps": 0,     "sleep_minutes": 0,   "workouts": 0},
      {"date": "2026-10-02", "work_rate": 25,  "form_rate": 0,   "calories": 0,      "protein_g": 0,     "steps": 0,     "sleep_minutes": 0,   "workouts": 0},
      {"date": "2026-10-03", "work_rate": 0,   "form_rate": 0,   "calories": 0,      "protein_g": 0,     "steps": 0,     "sleep_minutes": 0,   "workouts": 1},
      {"date": "2026-10-04", "work_rate": 33,  "form_rate": 0,   "calories": 0,      "protein_g": 0,     "steps": 0,     "sleep_minutes": 0,   "workouts": 0}
    ]
  }'::jsonb);

-- Günlük: Pazartesi. 23:30'daki görev, antrenman ve öğün bu güne aittir.
select t.eq('günlük: Pazartesi (23:30 kayıtları dahil)',
  public.report_daily_metrics(:A, '2026-09-28'),
  '{
    "period": {"start": "2026-09-28", "end": "2026-09-28"},
    "work": {"tasks_total": 2, "tasks_done": 1, "routines_planned": 2, "routines_done": 2, "rate": 75},
    "form": {"workouts_planned": 1, "workouts_done": 2, "protein_days_hit": 1, "calorie_days_in_range": 1, "rate": 100},
    "nutrition": {"calories": 1700, "protein_g": 153, "carbs_g": 150, "fat_g": 45, "days_logged": 1},
    "health": {"steps": 8000, "sleep_minutes": 420, "active_kcal": 400, "days_with_data": 1},
    "weight": {"start_kg": 83.8, "end_kg": 83.6, "change_kg": -0.2},
    "targets": {"calories": 2000, "protein_g": 170, "steps": 10000, "sleep_minutes": 450}
  }'::jsonb);

-- Günlük: Salı. 00:30'daki kayıtlar bu güne aittir; o gün ölçüm yok.
select t.eq('günlük: Salı (00:30 kayıtları dahil)',
  public.report_daily_metrics(:A, '2026-09-29'),
  '{
    "period": {"start": "2026-09-29", "end": "2026-09-29"},
    "work": {"tasks_total": 1, "tasks_done": 1, "routines_planned": 1, "routines_done": 1, "rate": 100},
    "form": {"workouts_planned": 0, "workouts_done": 1, "protein_days_hit": 0, "calorie_days_in_range": 0, "rate": 0},
    "nutrition": {"calories": 2200.5, "protein_g": 140.5, "carbs_g": 230, "fat_g": 65, "days_logged": 1},
    "health": {"steps": 12000, "sleep_minutes": 0, "active_kcal": 500, "days_with_data": 1},
    "weight": {"start_kg": 83.6, "end_kg": null, "change_kg": null},
    "targets": {"calories": 2000, "protein_g": 170, "steps": 10000, "sleep_minutes": 450}
  }'::jsonb);

-- Aylık rutinler tek tek: 30 Eylül'de M1 (31 → 30) planlı ve tamam,
-- 2 Ekim'de M2 planlı ama Ekim dönemi işaretsiz.
select t.eq('günlük: 31. gün 30 günlük ayda son güne düşer',
  public.report_daily_metrics(:A, '2026-09-30') -> 'work',
  '{"tasks_total": 0, "tasks_done": 0, "routines_planned": 3, "routines_done": 2, "rate": 67}'::jsonb);
select t.eq('günlük: aylık rutin gününde planlı, dönemi işaretsiz',
  public.report_daily_metrics(:A, '2026-10-02') -> 'work',
  '{"tasks_total": 0, "tasks_done": 0, "routines_planned": 4, "routines_done": 1, "rate": 25}'::jsonb);
-- R3 30 Eylül'de yoktu (İstanbul'a göre 1 Ekim 00:30'da oluştu).
select t.eq('günlük: rutin oluşturulmadan önce sayılmaz',
  public.report_daily_metrics(:A, '2026-10-01') -> 'work',
  '{"tasks_total": 0, "tasks_done": 0, "routines_planned": 2, "routines_done": 2, "rate": 100}'::jsonb);

-- ---------------------------------------------------------------------
-- Hiç veri yok (B; ayar satırı da yok). İş oranının paydası 0 → null.
-- Form paydası gün sayısını içerdiği için 0 olmaz: oran %0.
-- ---------------------------------------------------------------------
select t.eq('günlük: hiç veri yok',
  public.report_daily_metrics(:B, '2026-09-28'),
  '{
    "period": {"start": "2026-09-28", "end": "2026-09-28"},
    "work": {"tasks_total": 0, "tasks_done": 0, "routines_planned": 0, "routines_done": 0, "rate": null},
    "form": {"workouts_planned": 0, "workouts_done": 0, "protein_days_hit": 0, "calorie_days_in_range": 0, "rate": 0},
    "nutrition": {"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0, "days_logged": 0},
    "health": {"steps": 0, "sleep_minutes": 0, "active_kcal": 0, "days_with_data": 0},
    "weight": {"start_kg": null, "end_kg": null, "change_kg": null},
    "targets": {"calories": 2000, "protein_g": 120, "steps": 8000, "sleep_minutes": 450}
  }'::jsonb);

select t.eq('haftalık: hiç veri yok',
  public.report_weekly_metrics(:B, '2026-09-28'),
  '{
    "period": {"start": "2026-09-28", "end": "2026-10-04"},
    "work": {"tasks_total": 0, "tasks_done": 0, "routines_planned": 0, "routines_done": 0, "rate": null},
    "form": {"workouts_planned": 0, "workouts_done": 0, "protein_days_hit": 0, "calorie_days_in_range": 0, "rate": 0},
    "nutrition": {"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0, "days_logged": 0},
    "health": {"steps": 0, "sleep_minutes": 0, "active_kcal": 0, "days_with_data": 0},
    "weight": {"start_kg": null, "end_kg": null, "change_kg": null},
    "targets": {"calories": 2000, "protein_g": 120, "steps": 8000, "sleep_minutes": 450},
    "days": [
      {"date": "2026-09-28", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0},
      {"date": "2026-09-29", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0},
      {"date": "2026-09-30", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0},
      {"date": "2026-10-01", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0},
      {"date": "2026-10-02", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0},
      {"date": "2026-10-03", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0},
      {"date": "2026-10-04", "work_rate": null, "form_rate": 0, "calories": 0, "protein_g": 0, "steps": 0, "sleep_minutes": 0, "workouts": 0}
    ]
  }'::jsonb);

-- ---------------------------------------------------------------------
-- Saat dilimi sınırı (C, UTC). Aynı iki an: 23:30 ve 00:30 İstanbul
-- = 20:30 ve 21:30 UTC → UTC kullanıcısı için İKİSİ DE 28 Eylül'dür.
-- A için (İstanbul) yukarıda farklı günlere düştüler.
-- ---------------------------------------------------------------------
insert into public.nutrition_logs (user_id, food_name, calories, protein_g, eaten_at) values
  (:C, 'gece1', 500, 53, '2026-09-28 23:30+03'),
  (:C, 'gece2', 300, 20, '2026-09-29 00:30+03');
insert into public.tasks (user_id, title, status, due_at) values
  (:C, 'gece görevi 1', 'todo', '2026-09-28 23:30+03'),
  (:C, 'gece görevi 2', 'done', '2026-09-29 00:30+03');

select t.eq('saat dilimi UTC: iki kayıt aynı günde (beslenme)',
  public.report_daily_metrics(:C, '2026-09-28') -> 'nutrition',
  '{"calories": 800, "protein_g": 73, "carbs_g": 0, "fat_g": 0, "days_logged": 1}'::jsonb);
select t.eq('saat dilimi UTC: iki kayıt aynı günde (görev)',
  public.report_daily_metrics(:C, '2026-09-28') -> 'work',
  '{"tasks_total": 2, "tasks_done": 1, "routines_planned": 0, "routines_done": 0, "rate": 50}'::jsonb);
select t.eq('saat dilimi UTC: ertesi gün boş',
  public.report_daily_metrics(:C, '2026-09-29') -> 'nutrition',
  '{"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0, "days_logged": 0}'::jsonb);

-- Aynı kullanıcı İstanbul'a alınınca kayıtlar iki güne ayrılır.
update public.user_settings set timezone = 'Europe/Istanbul' where user_id = :C;
select t.eq('saat dilimi İstanbul: 23:30 kaydı ilk günde',
  public.report_daily_metrics(:C, '2026-09-28') -> 'nutrition',
  '{"calories": 500, "protein_g": 53, "carbs_g": 0, "fat_g": 0, "days_logged": 1}'::jsonb);
select t.eq('saat dilimi İstanbul: 00:30 kaydı ertesi günde',
  public.report_daily_metrics(:C, '2026-09-29') -> 'nutrition',
  '{"calories": 300, "protein_g": 20, "carbs_g": 0, "fat_g": 0, "days_logged": 1}'::jsonb);

-- Bozuk saat dilimi adı raporu düşürmez; İstanbul'a döner.
update public.user_settings set timezone = 'Boyle/BirYerYok' where user_id = :C;
select t.eq('bozuk saat dilimi İstanbul sayılır',
  public.report_daily_metrics(:C, '2026-09-29') -> 'nutrition',
  '{"calories": 300, "protein_g": 20, "carbs_g": 0, "fat_g": 0, "days_logged": 1}'::jsonb);

-- ---------------------------------------------------------------------
-- Henüz gelmemiş günler planlı sayılmaz (D: her gün bir rutin, eski tarihli).
-- ---------------------------------------------------------------------
insert into public.routines (user_id, title, category, days_of_week, created_at)
values (:D, 'D günlük', 'spor', '{1,2,3,4,5,6,7}', '2020-01-01 09:00+03');

select t.eq('bu hafta: yalnızca geçen günler planlı',
  (public.report_weekly_metrics(:D, date_trunc('week', now() at time zone 'Europe/Istanbul')::date)
     #> '{work,routines_planned}'),
  to_jsonb(extract(isodow from now() at time zone 'Europe/Istanbul')::integer));
select t.eq('bu hafta: form paydası geçen gün sayısıyla',
  (public.report_weekly_metrics(:D, date_trunc('week', now() at time zone 'Europe/Istanbul')::date)
     #> '{form,rate}'),
  '0'::jsonb);
select t.eq('gelecek hafta: iş',
  (public.report_weekly_metrics(:D, date_trunc('week', now() at time zone 'Europe/Istanbul')::date + 7)
     -> 'work'),
  '{"tasks_total": 0, "tasks_done": 0, "routines_planned": 0, "routines_done": 0, "rate": null}'::jsonb);
select t.eq('gelecek hafta: form oranı null (payda 0)',
  (public.report_weekly_metrics(:D, date_trunc('week', now() at time zone 'Europe/Istanbul')::date + 7)
     #> '{form,rate}'),
  'null'::jsonb);

-- p_week_start Pazartesi değilse reddedilir.
do $$
begin
  begin
    perform public.report_weekly_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-29');
  exception when invalid_parameter_value then
    raise notice 'tamam: Pazartesi olmayan hafta başı reddedildi';
    return;
  end;
  raise exception 'BAŞARISIZ: Pazartesi olmayan hafta başı kabul edildi';
end;
$$;

-- ---------------------------------------------------------------------
-- Kaydetme (upsert) ve sayısal sütunlar.
-- ---------------------------------------------------------------------
select public.save_weekly_report(:A, '2026-09-28',
  public.report_weekly_metrics(:A, '2026-09-28'), null, 'failed');
select public.save_weekly_report(:A, '2026-09-28',
  public.report_weekly_metrics(:A, '2026-09-28'), 'Özet metni', 'ok');

select t.eq('save_weekly_report: tek satır, sütunlar metrics''ten',
  (select jsonb_agg(to_jsonb(w) - 'id' - 'metrics' - 'generated_at' - 'created_at' - 'dirty' - 'dirty_at' - 'ai_basis')
   from public.weekly_reports w where user_id = :A),
  '[{
    "user_id": "aaaaaaaa-0000-0000-0000-000000000001", "week_start": "2026-09-28",
    "tasks_total": 4, "tasks_done": 3, "task_completion_rate": 75.00,
    "routines_planned": 16, "routines_done": 8, "workouts_done": 4,
    "avg_calories": 1950.1, "avg_protein_g": 156.6, "avg_steps": 10000, "avg_sleep_minutes": 450,
    "weight_start_kg": 83.80, "weight_end_kg": 83.10,
    "ai_summary": "Özet metni", "ai_status": "ok"
  }]'::jsonb);
select t.eq('save_weekly_report: metrics aynen saklanır',
  (select metrics from public.weekly_reports where user_id = :A),
  public.report_weekly_metrics(:A, '2026-09-28'));

-- Verisi olmayan haftada ortalama sütunları null kalır (0 değil).
select public.save_weekly_report(:B, '2026-09-28',
  public.report_weekly_metrics(:B, '2026-09-28'), null, 'failed');
select t.eq('save_weekly_report: veri yoksa ortalamalar null',
  (select to_jsonb(w) - 'id' - 'metrics' - 'generated_at' - 'created_at' - 'dirty' - 'dirty_at' - 'ai_basis' - 'user_id'
   from public.weekly_reports w where user_id = :B),
  '{
    "week_start": "2026-09-28", "tasks_total": 0, "tasks_done": 0, "task_completion_rate": 0,
    "routines_planned": 0, "routines_done": 0, "workouts_done": 0,
    "avg_calories": null, "avg_protein_g": null, "avg_steps": null, "avg_sleep_minutes": null,
    "weight_start_kg": null, "weight_end_kg": null, "ai_summary": null, "ai_status": "failed"
  }'::jsonb);

select public.save_daily_report(:A, '2026-09-28',
  public.report_daily_metrics(:A, '2026-09-28'), 'ilk', 'ok');
select public.save_daily_report(:A, '2026-09-28',
  public.report_daily_metrics(:A, '2026-09-28'), null, 'failed');
select public.save_daily_report(:B, '2026-09-28',
  public.report_daily_metrics(:B, '2026-09-28'), 'B özeti', 'ok');
select t.eq('save_daily_report: upsert son değeri tutar',
  (select jsonb_agg(jsonb_build_object('d', report_date, 's', ai_summary, 'st', ai_status,
                                       'rate', metrics #> '{work,rate}'))
   from public.daily_reports where user_id = :A),
  '[{"d": "2026-09-28", "s": null, "st": "failed", "rate": 75}]'::jsonb);

do $$
begin
  begin
    perform public.save_daily_report('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28',
                                     '{}'::jsonb, null, 'bitti');
  exception when check_violation then
    raise notice 'tamam: geçersiz ai_status reddedildi';
    return;
  end;
  raise exception 'BAŞARISIZ: geçersiz ai_status kabul edildi';
end;
$$;

-- ---------------------------------------------------------------------
-- Yetkiler. Bu noktada: weekly_reports A + B, daily_reports A + B.
-- ---------------------------------------------------------------------
select t.eq('authenticated: yalnızca kendi haftalık raporu',
  to_jsonb(t.as_role('authenticated', :A, 'select count(*) from public.weekly_reports')), '1'::jsonb);
select t.eq('authenticated: yalnızca kendi günlük raporu',
  to_jsonb(t.as_role('authenticated', :A, 'select count(*) from public.daily_reports')), '1'::jsonb);
select t.eq('authenticated: başkasının satırı görünmez',
  to_jsonb(t.as_role('authenticated', :A,
    $q$select count(*) from public.daily_reports where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'$q$)),
  '0'::jsonb);
select t.eq('authenticated: raporu olmayan kullanıcı boş görür',
  to_jsonb(t.as_role('authenticated', :D, 'select count(*) from public.weekly_reports')), '0'::jsonb);

select t.denied('authenticated günlük rapor ekleyemez', 'authenticated', :A,
  $q$insert into public.daily_reports (user_id, report_date) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-01-01')$q$);
select t.denied('authenticated günlük rapor güncelleyemez', 'authenticated', :A,
  $q$update public.daily_reports set ai_summary = 'x'$q$);
select t.denied('authenticated günlük rapor silemez', 'authenticated', :A,
  $q$delete from public.daily_reports$q$);
select t.denied('authenticated haftalık rapor ekleyemez', 'authenticated', :A,
  $q$insert into public.weekly_reports (user_id, week_start) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-01-05')$q$);
select t.denied('authenticated haftalık rapor güncelleyemez', 'authenticated', :A,
  $q$update public.weekly_reports set ai_summary = 'x'$q$);
select t.denied('authenticated haftalık rapor silemez', 'authenticated', :A,
  $q$delete from public.weekly_reports$q$);

select t.denied('anon haftalık rapor okuyamaz', 'anon', null,
  $q$select count(*) from public.weekly_reports$q$);
select t.denied('anon günlük rapor okuyamaz', 'anon', null,
  $q$select count(*) from public.daily_reports$q$);

select t.denied('authenticated report_daily_metrics çalıştıramaz', 'authenticated', :A,
  $q$select public.report_daily_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28')$q$);
select t.denied('authenticated report_weekly_metrics çalıştıramaz', 'authenticated', :A,
  $q$select public.report_weekly_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28')$q$);
select t.denied('authenticated report_period_metrics çalıştıramaz', 'authenticated', :A,
  $q$select public.report_period_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', '2026-09-28', false)$q$);
select t.denied('authenticated save_daily_report çalıştıramaz', 'authenticated', :A,
  $q$select public.save_daily_report('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', '{}'::jsonb, 'x', 'ok')$q$);
select t.denied('authenticated save_weekly_report çalıştıramaz', 'authenticated', :A,
  $q$select public.save_weekly_report('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', '{}'::jsonb, 'x', 'ok')$q$);
select t.denied('anon report_daily_metrics çalıştıramaz', 'anon', null,
  $q$select public.report_daily_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28')$q$);
select t.denied('anon report_weekly_metrics çalıştıramaz', 'anon', null,
  $q$select public.report_weekly_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28')$q$);
select t.denied('anon save_daily_report çalıştıramaz', 'anon', null,
  $q$select public.save_daily_report('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', '{}'::jsonb, 'x', 'ok')$q$);
select t.denied('anon save_weekly_report çalıştıramaz', 'anon', null,
  $q$select public.save_weekly_report('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', '{}'::jsonb, 'x', 'ok')$q$);

-- service_role: Edge Function'ın yaptığı her şey (kullanıcı listesi, sayılar, kayıt).
select t.eq('service_role kullanıcı listesini okur',
  to_jsonb(t.as_role('service_role', null, 'select count(*) from public.user_settings')), '3'::jsonb);
select t.eq('service_role sayıları hesaplar',
  to_jsonb(t.as_role('service_role', null,
    $q$select (public.report_weekly_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28') #>> '{work,rate}')::bigint$q$)),
  '55'::jsonb);
select t.eq('service_role günlük sayıları hesaplar',
  to_jsonb(t.as_role('service_role', null,
    $q$select (public.report_daily_metrics('aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28') #>> '{work,rate}')::bigint$q$)),
  '75'::jsonb);
select t.eq('service_role günlük raporu kaydeder',
  to_jsonb(t.as_role('service_role', null,
    $q$with s as (select public.save_daily_report('dddddddd-0000-0000-0000-000000000004', '2026-09-28', '{}'::jsonb, 'x', 'ok'))
       select count(*) from s$q$)),
  '1'::jsonb);
select t.eq('service_role haftalık raporu kaydeder',
  to_jsonb(t.as_role('service_role', null,
    $q$with s as (select public.save_weekly_report('dddddddd-0000-0000-0000-000000000004', '2026-09-28', '{}'::jsonb, 'x', 'ok'))
       select count(*) from s$q$)),
  '1'::jsonb);
select t.eq('service_role tüm raporları görür',
  to_jsonb(t.as_role('service_role', null, 'select count(*) from public.daily_reports')), '3'::jsonb);

-- Uygulamanın diğer tablolardaki yetkisi bozulmadı.
select t.eq('authenticated kendi görevlerini hâlâ okur',
  to_jsonb(t.as_role('authenticated', :A, 'select count(*) from public.tasks')), '7'::jsonb);

-- ---------------------------------------------------------------------
-- Sıklık değişimi (B). completed_on günlükte "o gün", aylıkta "ayın 1'i"dir;
-- sıklık değişince eski işaretler yeni sıklıkta yanlış dönemi yapılmış
-- göstermesin diye silinir (routines_frequency_changed). Güncellemeler
-- uygulamanın yaptığı gibi authenticated rolüyle (RLS altında) çalıştırılır.
-- ---------------------------------------------------------------------
insert into public.routines (id, user_id, title, category, frequency, days_of_week, day_of_month, created_at)
values
  ('00000000-0000-0000-0000-0000000000f1', :B, 'F1 fatura kontrolü', 'finans', 'weekly', '{1,2,3,4,5,6,7}', null, '2026-08-01 09:00+03'),
  ('00000000-0000-0000-0000-0000000000f2', :B, 'F2 dokunulmayan', 'kisisel', 'weekly', '{1,2,3,4,5,6,7}', null, '2026-08-01 09:00+03'),
  ('00000000-0000-0000-0000-0000000000f3', :B, 'F3 aylık', 'finans', 'monthly', '{1,2,3,4,5,6,7}', 20, '2026-08-01 09:00+03');
insert into public.routine_completions (user_id, routine_id, completed_on) values
  (:B, '00000000-0000-0000-0000-0000000000f1', '2026-09-01'),   -- günlük işaret, ayın 1'i
  (:B, '00000000-0000-0000-0000-0000000000f1', '2026-09-02'),
  (:B, '00000000-0000-0000-0000-0000000000f2', '2026-09-01'),
  (:B, '00000000-0000-0000-0000-0000000000f3', '2026-09-01');   -- aylık işaret, Eylül dönemi

-- Uygulama her düzenlemede frequency sütununu da gönderir; değer aynıysa işaretler durur.
select t.eq('sıklık aynı: düzenleme (authenticated) bir satırı günceller',
  to_jsonb(t.as_role('authenticated', :B,
    $q$with u as (update public.routines set title = 'F1 fatura', frequency = 'weekly'
                  where id = '00000000-0000-0000-0000-0000000000f1' returning 1)
       select count(*) from u$q$)),
  '1'::jsonb);
select t.eq('sıklık aynı: işaretler durur',
  to_jsonb((select count(*) from public.routine_completions where user_id = :B)), '4'::jsonb);

-- Günlük → aylık (ayın 12'si): 1 Eylül'deki günlük işaret Eylül dönemi sayılmamalı.
select t.eq('günlük → aylık: düzenleme (authenticated) bir satırı günceller',
  to_jsonb(t.as_role('authenticated', :B,
    $q$with u as (update public.routines set frequency = 'monthly', day_of_month = 12
                  where id = '00000000-0000-0000-0000-0000000000f1' returning 1)
       select count(*) from u$q$)),
  '1'::jsonb);
select t.eq('günlük → aylık: yalnızca o rutinin işaretleri silinir',
  (select jsonb_agg(routine_id order by routine_id) from public.routine_completions where user_id = :B),
  '["00000000-0000-0000-0000-0000000000f2", "00000000-0000-0000-0000-0000000000f3"]'::jsonb);
-- 12 Eylül: F1 (aylık, günü bugün) + F2 (günlük) planlı; hiçbiri yapılmadı.
select t.eq('günlük → aylık: aylık dönem yapılmış sayılmaz',
  public.report_daily_metrics(:B, '2026-09-12') -> 'work',
  '{"tasks_total": 0, "tasks_done": 0, "routines_planned": 2, "routines_done": 0, "rate": 0}'::jsonb);

-- Aylık → günlük: Eylül dönem işareti 1 Eylül gününü yapılmış göstermemeli.
select t.eq('aylık → günlük: düzenleme (authenticated) bir satırı günceller',
  to_jsonb(t.as_role('authenticated', :B,
    $q$with u as (update public.routines set frequency = 'weekly', day_of_month = null
                  where id = '00000000-0000-0000-0000-0000000000f3' returning 1)
       select count(*) from u$q$)),
  '1'::jsonb);
-- 1 Eylül: F2 + F3 (artık günlük) planlı; yalnızca F2 işaretli. F1 aylık, günü 12.
select t.eq('aylık → günlük: aylık işaret ayın 1''ini yapılmış göstermez',
  public.report_daily_metrics(:B, '2026-09-01') -> 'work',
  '{"tasks_total": 0, "tasks_done": 0, "routines_planned": 2, "routines_done": 1, "rate": 50}'::jsonb);

-- Başka kullanıcının rutini RLS yüzünden güncellenemez; işaretleri de durur.
select t.eq('başkasının rutini güncellenmez',
  to_jsonb(t.as_role('authenticated', :A,
    $q$with u as (update public.routines set frequency = 'monthly', day_of_month = 5
                  where id = '00000000-0000-0000-0000-0000000000f2' returning 1)
       select count(*) from u$q$)),
  '0'::jsonb);
select t.eq('başkasının rutini: işaret durur',
  to_jsonb((select count(*) from public.routine_completions
            where routine_id = '00000000-0000-0000-0000-0000000000f2')), '1'::jsonb);

drop schema t cascade;
\echo RAPOR TESTLERI GECTI
