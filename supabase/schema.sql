-- =====================================================================
-- Kişisel Asistan & Operasyon Merkezi — Supabase (PostgreSQL) şeması
-- Supabase Dashboard > SQL Editor içinde TEK SEFERDE çalıştırılabilir.
-- Tekrar çalıştırılabilir (idempotent): mevcut veriyi silmez.
--
-- Güvenlik modeli: Tek kullanıcı da olsa anon key uygulamanın içinde
-- taşındığı için tüm tablolarda RLS açık ve satırlar auth.uid() ile
-- sahibine kilitli. Uygulamaya Supabase Auth (e-posta + şifre) ile girilir.
--
-- Seed: Başlangıç verisi, kullanıcı oluştuğu anda (auth.users trigger'ı)
-- ve bu script çalıştığında zaten var olan kullanıcılar için yüklenir.
--
-- Sürüm 2 (Faz 2): routines.frequency / day_of_month / scope, 'finans'
-- kategorisi, user_settings tablosu, quick_add_entries içinde routines[].
-- Sürüm 1 ile kurulmuş bir veritabanında çalıştırıldığında yerinde yükseltir.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Ortak: updated_at trigger fonksiyonu
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 1) routines — tekrarlayan işler (günlük / haftalık / aylık)
--    frequency = 'weekly' : days_of_week kullanılır (7 gün = günlük).
--                           ISO gün numaraları (1 = Pazartesi ... 7 = Pazar)
--    frequency = 'monthly': day_of_month kullanılır; ayın o günü yoksa
--                           ayın son günü geçerlidir (31 → Şubat'ta 28/29).
--                           days_of_week bu durumda yok sayılır.
--    scope: iş (Pusholder) / kişisel ayrımı.
-- ---------------------------------------------------------------------
create table if not exists public.routines (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 200),
  scope         text not null default 'Kişisel'
                check (scope in ('Pusholder', 'Kişisel')),
  category      text not null default 'operasyon'
                check (category in ('operasyon', 'spor', 'beslenme', 'kisisel', 'finans')),
  frequency     text not null default 'weekly'
                check (frequency in ('weekly', 'monthly')),
  time_of_day   time,
  days_of_week  smallint[] not null default '{1,2,3,4,5,6,7}'
                check (days_of_week <@ array[1,2,3,4,5,6,7]::smallint[]
                       and cardinality(days_of_week) > 0),
  day_of_month  smallint check (day_of_month between 1 and 31),
  notify        boolean not null default true,
  sort_order    integer not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint routines_monthly_day
    check (frequency <> 'monthly' or day_of_month is not null)
);

-- Sürüm 1 → 2 yükseltmesi. Yeni kurulumda sütunlar zaten vardır; bu blok
-- yalnızca eski tabloyu tamamlar.
alter table public.routines
  add column if not exists frequency text not null default 'weekly'
    check (frequency in ('weekly', 'monthly'));
alter table public.routines
  add column if not exists day_of_month smallint
    check (day_of_month between 1 and 31);

-- Kategori listesine 'finans' eklendi: kısıt her çalıştırmada yeniden kurulur
-- (aşağıdaki aylık örnekler 'finans' kullandığı için veri düzeltmesinden önce).
alter table public.routines drop constraint if exists routines_category_check;
alter table public.routines add constraint routines_category_check
  check (category in ('operasyon', 'spor', 'beslenme', 'kisisel', 'finans'));

do $$
begin
  -- scope sütununun yokluğu "sürüm 1 veritabanı" demektir. Aşağıdaki veri
  -- düzeltmeleri yalnızca o anda, bir kez yapılır; sonraki çalıştırmalarda
  -- kullanıcının kendi düzenlemeleri ezilmez.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'routines'
      and column_name = 'scope'
  ) then
    alter table public.routines
      add column scope text not null default 'Kişisel'
        check (scope in ('Pusholder', 'Kişisel'));

    update public.routines set scope = 'Pusholder' where category = 'operasyon';

    -- Sürüm 2 seed'indeki iki aylık örnek, verisi olan kullanıcılara da eklenir.
    insert into public.routines
      (user_id, title, scope, category, frequency, day_of_month, time_of_day, sort_order)
    select u.user_id, v.title, 'Pusholder', v.category, 'monthly', v.day_of_month,
           '10:00', v.sort_order
    from (select distinct user_id from public.routines) as u
    cross join (values
      ('Maaş ödemeleri', 'finans', 15, 120),
      ('Aylık push performans raporu', 'operasyon', 1, 130)
    ) as v(title, category, day_of_month, sort_order);
  end if;
end;
$$;

alter table public.routines drop constraint if exists routines_monthly_day;
alter table public.routines add constraint routines_monthly_day
  check (frequency <> 'monthly' or day_of_month is not null);

-- Tamamlanma kaydı. completed_on bir DÖNEM ANAHTARIDIR:
--   günlük/haftalık rutinde → işin yapıldığı gün,
--   aylık rutinde           → o ayın 1'i (ay başına tek kayıt).
-- unique (routine_id, completed_on) böylece "dönem başına bir kez"i garanti eder.
create table if not exists public.routine_completions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  routine_id    uuid not null references public.routines (id) on delete cascade,
  completed_on  date not null,
  completed_at  timestamptz not null default now(),
  unique (routine_id, completed_on)
);

comment on column public.routine_completions.completed_on is
  'Dönem anahtarı: günlük/haftalık rutinde o gün, aylık rutinde o ayın 1''i.';

-- ---------------------------------------------------------------------
-- 2) tasks — iş görevleri ve saatli hatırlatmalar
-- ---------------------------------------------------------------------
create table if not exists public.tasks (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 300),
  description   text,
  category      text not null default 'Kişisel'
                check (category in ('Pusholder', 'Ekip', 'Finans', 'Kişisel')),
  priority      text not null default 'medium'
                check (priority in ('low', 'medium', 'high')),
  status        text not null default 'todo'
                check (status in ('todo', 'in_progress', 'done')),
  assignee      text,
  due_at        timestamptz,
  remind_at     timestamptz,
  completed_at  timestamptz,
  source        text not null default 'manual' check (source in ('manual', 'ai')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3) notes — toplantı / fikir / kategori bazlı hızlı notlar
-- ---------------------------------------------------------------------
create table if not exists public.notes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 200),
  content       text not null default '',
  category      text not null default 'Kişisel'
                check (category in ('Toplantı', 'Fikir', 'Pusholder', 'Ekip', 'Finans', 'Kişisel')),
  is_pinned     boolean not null default false,
  source        text not null default 'manual' check (source in ('manual', 'ai')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4) fitness_logs — antrenman günlüğü + kilo ölçümleri
-- ---------------------------------------------------------------------
create table if not exists public.fitness_logs (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  log_type         text not null check (log_type in ('workout', 'weight')),
  workout_type     text check (workout_type in ('weights', 'kickboxing', 'running', 'football', 'other')),
  title            text,
  duration_min     integer check (duration_min is null or duration_min between 1 and 600),
  distance_km      numeric(6,2) check (distance_km is null or distance_km >= 0),
  calories_burned  integer check (calories_burned is null or calories_burned >= 0),
  weight_kg        numeric(5,2) check (weight_kg is null or weight_kg between 30 and 250),
  notes            text,
  logged_at        timestamptz not null default now(),
  source           text not null default 'manual' check (source in ('manual', 'ai', 'healthkit')),
  created_at       timestamptz not null default now(),
  constraint fitness_logs_shape check (
    (log_type = 'workout' and workout_type is not null)
    or (log_type = 'weight' and weight_kg is not null)
  )
);

-- ---------------------------------------------------------------------
-- 5) nutrition_logs — öğün ve makro kayıtları
-- ---------------------------------------------------------------------
create table if not exists public.nutrition_logs (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  meal_type      text not null default 'snack'
                 check (meal_type in ('breakfast', 'lunch', 'dinner', 'snack')),
  food_name      text not null check (char_length(food_name) between 1 and 200),
  quantity_text  text,
  calories       numeric(7,1) not null default 0 check (calories >= 0),
  protein_g      numeric(6,1) not null default 0 check (protein_g >= 0),
  carbs_g        numeric(6,1) not null default 0 check (carbs_g >= 0),
  fat_g          numeric(6,1) not null default 0 check (fat_g >= 0),
  eaten_at       timestamptz not null default now(),
  source         text not null default 'manual' check (source in ('manual', 'ai')),
  created_at     timestamptz not null default now()
);

-- HealthKit'ten okunan günlük özet (adım, aktif kalori, uyku)
create table if not exists public.daily_health_metrics (
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  metric_date    date not null,
  steps          integer not null default 0 check (steps >= 0),
  active_kcal    integer not null default 0 check (active_kcal >= 0),
  sleep_minutes  integer not null default 0 check (sleep_minutes >= 0),
  synced_at      timestamptz not null default now(),
  primary key (user_id, metric_date)
);

-- ---------------------------------------------------------------------
-- 6) weekly_reports — haftalık verimlilik + form raporu (AI özetli)
-- ---------------------------------------------------------------------
create table if not exists public.weekly_reports (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
  week_start            date not null,
  tasks_total           integer not null default 0,
  tasks_done            integer not null default 0,
  task_completion_rate  numeric(5,2) not null default 0,
  routines_planned      integer not null default 0,
  routines_done         integer not null default 0,
  workouts_done         integer not null default 0,
  avg_calories          numeric(7,1),
  avg_protein_g         numeric(6,1),
  avg_steps             integer,
  avg_sleep_minutes     integer,
  weight_start_kg       numeric(5,2),
  weight_end_kg         numeric(5,2),
  ai_summary            text,
  metrics               jsonb not null default '{}'::jsonb,
  created_at            timestamptz not null default now(),
  unique (user_id, week_start)
);

-- ---------------------------------------------------------------------
-- 7) user_settings — hedefler, bildirim tercihleri, ekip (kullanıcı başına
--    tek satır). Sınırlar Ayarlar ekranındaki doğrulamayla aynıdır.
-- ---------------------------------------------------------------------
create table if not exists public.user_settings (
  user_id                uuid primary key default auth.uid()
                         references auth.users (id) on delete cascade,
  start_weight_kg        numeric(5,2) not null default 84.5
                         check (start_weight_kg between 30 and 250),
  target_weight_kg       numeric(5,2) not null default 78
                         check (target_weight_kg between 30 and 250),
  daily_calories         integer not null default 2000
                         check (daily_calories between 800 and 6000),
  daily_protein_g        integer not null default 170
                         check (daily_protein_g between 0 and 500),
  daily_carbs_g          integer not null default 180
                         check (daily_carbs_g between 0 and 800),
  daily_fat_g            integer not null default 65
                         check (daily_fat_g between 0 and 400),
  daily_steps            integer not null default 10000
                         check (daily_steps between 1000 and 60000),
  sleep_minutes          integer not null default 450
                         check (sleep_minutes between 180 and 900),
  notifications_enabled  boolean not null default true,
  routine_notifications  boolean not null default true,
  monthly_lead_days      smallint not null default 3
                         check (monthly_lead_days between 0 and 14),
  monthly_remind_time    time not null default '09:00',
  event_remind_minutes   smallint not null default 30
                         check (event_remind_minutes between 0 and 1440),
  quiet_hours_enabled    boolean not null default true,
  quiet_start            time not null default '23:00',
  quiet_end              time not null default '07:30',
  team_members           text[] not null default '{Duhan,İlhan,Mehmet,Sedat}',
  updated_at             timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- İndeksler
-- ---------------------------------------------------------------------
create index if not exists routines_user_active_idx
  on public.routines (user_id, sort_order) where is_active;
create index if not exists routines_days_gin_idx
  on public.routines using gin (days_of_week);
create index if not exists routine_completions_user_day_idx
  on public.routine_completions (user_id, completed_on);
create index if not exists tasks_user_status_due_idx
  on public.tasks (user_id, status, due_at);
create index if not exists tasks_user_remind_idx
  on public.tasks (user_id, remind_at) where status <> 'done' and remind_at is not null;
create index if not exists tasks_user_category_idx
  on public.tasks (user_id, category);
create index if not exists notes_user_category_idx
  on public.notes (user_id, category, created_at desc);
create index if not exists fitness_logs_user_type_time_idx
  on public.fitness_logs (user_id, log_type, logged_at desc);
create index if not exists nutrition_logs_user_time_idx
  on public.nutrition_logs (user_id, eaten_at desc);
create index if not exists weekly_reports_user_week_idx
  on public.weekly_reports (user_id, week_start desc);

-- ---------------------------------------------------------------------
-- updated_at trigger'ları
-- ---------------------------------------------------------------------
drop trigger if exists routines_set_updated_at on public.routines;
create trigger routines_set_updated_at before update on public.routines
  for each row execute function public.set_updated_at();

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at before update on public.tasks
  for each row execute function public.set_updated_at();

drop trigger if exists notes_set_updated_at on public.notes;
create trigger notes_set_updated_at before update on public.notes
  for each row execute function public.set_updated_at();

drop trigger if exists user_settings_set_updated_at on public.user_settings;
create trigger user_settings_set_updated_at before update on public.user_settings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Row Level Security — her satır yalnızca sahibine açık
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'routines', 'routine_completions', 'tasks', 'notes',
    'fitness_logs', 'nutrition_logs', 'daily_health_metrics', 'weekly_reports',
    'user_settings'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_owner_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      t || '_owner_all', t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Tablo yetkileri. Yeni Supabase projelerinde public şemasındaki tablolara
-- varsayılan yetki verilmez; açıkça verilmezse her sorgu 42501 ile reddedilir.
-- Erişimi satır bazında yukarıdaki RLS politikaları sınırlar.
-- ---------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, insert, update, delete on table
  public.routines, public.routine_completions, public.tasks, public.notes,
  public.fitness_logs, public.nutrition_logs, public.daily_health_metrics,
  public.weekly_reports, public.user_settings
  to authenticated;
revoke all on table
  public.routines, public.routine_completions, public.tasks, public.notes,
  public.fitness_logs, public.nutrition_logs, public.daily_health_metrics,
  public.weekly_reports, public.user_settings
  from anon;

-- ---------------------------------------------------------------------
-- Görünüm: günlük makro toplamları (İstanbul gününe göre)
-- ---------------------------------------------------------------------
create or replace view public.daily_nutrition_totals
with (security_invoker = true) as
select
  user_id,
  (eaten_at at time zone 'Europe/Istanbul')::date as log_date,
  round(sum(calories), 1)  as calories,
  round(sum(protein_g), 1) as protein_g,
  round(sum(carbs_g), 1)   as carbs_g,
  round(sum(fat_g), 1)     as fat_g,
  count(*)                 as entry_count
from public.nutrition_logs
group by user_id, (eaten_at at time zone 'Europe/Istanbul')::date;

grant select on public.daily_nutrition_totals to authenticated;
revoke all on public.daily_nutrition_totals from anon;

-- ---------------------------------------------------------------------
-- RPC: quick_add_entries — AI Hızlı Giriş çıktısını TEK TRANSACTION'da
-- ilgili tablolara dağıtır. Bir parça hata verirse hiçbiri yazılmaz.
-- payload: { tasks: [], nutrition: [], workouts: [], weights: [], notes: [],
--            routines: [] }
-- routines kalemi: { title, scope, category, frequency, days_of_week int[],
--                    day_of_month int, time_of_day "HH:MM" | null }
-- ---------------------------------------------------------------------
create or replace function public.quick_add_entries(payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_tasks      jsonb := '[]'::jsonb;
  v_nutrition  integer := 0;
  v_workouts   integer := 0;
  v_weights    integer := 0;
  v_notes      integer := 0;
  v_routines   integer := 0;
  v_sort       integer;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;

  with ins as (
    insert into tasks (user_id, title, description, category, priority, assignee, due_at, remind_at, source)
    select v_uid, x.title, x.description,
           coalesce(x.category, 'Kişisel'), coalesce(x.priority, 'medium'),
           x.assignee, x.due_at, x.remind_at, 'ai'
    from jsonb_to_recordset(coalesce(payload -> 'tasks', '[]'::jsonb))
      as x(title text, description text, category text, priority text,
           assignee text, due_at timestamptz, remind_at timestamptz)
    returning id, title, due_at, remind_at
  )
  select coalesce(jsonb_agg(to_jsonb(ins)), '[]'::jsonb) into v_tasks from ins;

  insert into nutrition_logs (user_id, meal_type, food_name, quantity_text,
                              calories, protein_g, carbs_g, fat_g, eaten_at, source)
  select v_uid, coalesce(x.meal_type, 'snack'), x.food_name, x.quantity_text,
         coalesce(x.calories, 0), coalesce(x.protein_g, 0),
         coalesce(x.carbs_g, 0), coalesce(x.fat_g, 0),
         coalesce(x.eaten_at, now()), 'ai'
  from jsonb_to_recordset(coalesce(payload -> 'nutrition', '[]'::jsonb))
    as x(meal_type text, food_name text, quantity_text text, calories numeric,
         protein_g numeric, carbs_g numeric, fat_g numeric, eaten_at timestamptz);
  get diagnostics v_nutrition = row_count;

  insert into fitness_logs (user_id, log_type, workout_type, title, duration_min,
                            distance_km, calories_burned, notes, logged_at, source)
  select v_uid, 'workout', coalesce(x.workout_type, 'other'), x.title, x.duration_min,
         x.distance_km, x.calories_burned, x.notes, coalesce(x.performed_at, now()), 'ai'
  from jsonb_to_recordset(coalesce(payload -> 'workouts', '[]'::jsonb))
    as x(workout_type text, title text, duration_min integer, distance_km numeric,
         calories_burned integer, notes text, performed_at timestamptz);
  get diagnostics v_workouts = row_count;

  insert into fitness_logs (user_id, log_type, weight_kg, logged_at, source)
  select v_uid, 'weight', x.weight_kg, coalesce(x.measured_at, now()), 'ai'
  from jsonb_to_recordset(coalesce(payload -> 'weights', '[]'::jsonb))
    as x(weight_kg numeric, measured_at timestamptz);
  get diagnostics v_weights = row_count;

  insert into notes (user_id, title, content, category, source)
  select v_uid, x.title, coalesce(x.content, ''), coalesce(x.category, 'Kişisel'), 'ai'
  from jsonb_to_recordset(coalesce(payload -> 'notes', '[]'::jsonb))
    as x(title text, content text, category text);
  get diagnostics v_notes = row_count;

  -- Yeni rutinler mevcut sıralamanın sonuna eklenir.
  select coalesce(max(sort_order), 0) + 10 into v_sort
  from routines where user_id = v_uid;

  -- Aylık işte days_of_week, haftalıkta day_of_month anlamsızdır; modelden
  -- ne gelirse gelsin tablo kısıtlarına uyan değerlere indirgenir.
  insert into routines (user_id, title, scope, category, frequency, days_of_week,
                        day_of_month, time_of_day, notify, sort_order)
  select v_uid, x.title, coalesce(x.scope, 'Kişisel'), coalesce(x.category, 'kisisel'),
         coalesce(x.frequency, 'weekly'),
         case when coalesce(x.frequency, 'weekly') = 'monthly'
                   or x.days_of_week is null or cardinality(x.days_of_week) = 0
              then '{1,2,3,4,5,6,7}'::smallint[]
              else x.days_of_week end,
         case when x.frequency = 'monthly' then x.day_of_month end,
         x.time_of_day, true, v_sort
  from jsonb_to_recordset(coalesce(payload -> 'routines', '[]'::jsonb))
    as x(title text, scope text, category text, frequency text,
         days_of_week smallint[], day_of_month smallint, time_of_day time);
  get diagnostics v_routines = row_count;

  return jsonb_build_object(
    'tasks', v_tasks,
    'nutrition_count', v_nutrition,
    'workout_count', v_workouts,
    'weight_count', v_weights,
    'note_count', v_notes,
    'routine_count', v_routines
  );
end;
$$;

revoke all on function public.quick_add_entries(jsonb) from public, anon;
grant execute on function public.quick_add_entries(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- SEED — başlangıç verisi (kullanıcı başına bir kez)
-- Gün ataması varsayımdır, uygulamadan/SQL'den değiştirilebilir:
--   Ağırlık: Pzt, Sal, Per, Cum · Kickboks: Çar · Koşu: Cmt · Halı saha: Paz
-- ---------------------------------------------------------------------
create or replace function public.seed_personal_assistant(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today timestamp := date_trunc('day', now() at time zone 'Europe/Istanbul');
begin
  -- Ayarlar satırı, verisi olan (sürüm 1'den gelen) kullanıcılar için de açılır.
  insert into user_settings (user_id) values (p_user)
  on conflict (user_id) do nothing;

  if exists (select 1 from routines where user_id = p_user)
     or exists (select 1 from tasks where user_id = p_user)
     or exists (select 1 from notes where user_id = p_user)
     or exists (select 1 from fitness_logs where user_id = p_user) then
    return; -- zaten yüklenmiş ya da kullanıcının verisi var
  end if;

  insert into routines (user_id, title, scope, category, time_of_day, days_of_week, sort_order) values
    (p_user, 'Sabah push performans kontrolü (CTR, teslim oranı)', 'Pusholder', 'operasyon', '09:00', '{1,2,3,4,5,6,7}', 10),
    (p_user, 'Editör vardiya kontrolü (Duhan, İlhan, Mehmet, Sedat)', 'Pusholder', 'operasyon', '09:30', '{1,2,3,4,5,6,7}', 20),
    (p_user, 'Öğlen gündem ve push takvimi kontrolü', 'Pusholder', 'operasyon', '13:00', '{1,2,3,4,5,6,7}', 30),
    (p_user, 'Akşam operasyon kapanış kontrolü', 'Pusholder', 'operasyon', '22:00', '{1,2,3,4,5,6,7}', 40),
    (p_user, 'Haftalık ekip toplantısı ve vardiya planı', 'Pusholder', 'operasyon', '11:00', '{1}', 50),
    (p_user, 'Sabah tartı ve kilo kaydı', 'Kişisel', 'beslenme', '08:00', '{1,2,3,4,5,6,7}', 60),
    (p_user, 'Günlük makro kontrolü (protein hedefi)', 'Kişisel', 'beslenme', '21:30', '{1,2,3,4,5,6,7}', 70),
    (p_user, 'Ağırlık antrenmanı', 'Kişisel', 'spor', '19:00', '{1,2,4,5}', 80),
    (p_user, 'Kickboks', 'Kişisel', 'spor', '19:30', '{3}', 90),
    (p_user, 'Koşu', 'Kişisel', 'spor', '10:00', '{6}', 100),
    (p_user, 'Halı saha', 'Kişisel', 'spor', '20:00', '{7}', 110);

  insert into routines (user_id, title, scope, category, frequency, day_of_month, time_of_day, sort_order) values
    (p_user, 'Maaş ödemeleri', 'Pusholder', 'finans', 'monthly', 15, '10:00', 120),
    (p_user, 'Aylık push performans raporu', 'Pusholder', 'operasyon', 'monthly', 1, '10:00', 130);

  insert into tasks (user_id, title, description, category, priority, assignee, due_at, remind_at) values
    (p_user, 'Haftalık vardiya çizelgesini yayınla', 'Duhan, İlhan, Mehmet ve Sedat için gelecek haftanın vardiyaları.',
       'Ekip', 'high', null,
       (v_today + interval '1 day 15 hours') at time zone 'Europe/Istanbul',
       (v_today + interval '1 day 14 hours 30 minutes') at time zone 'Europe/Istanbul'),
    (p_user, 'Push bildirim performans raporunu hazırla', 'Son 7 günün gönderim, teslim ve tıklama oranları.',
       'Pusholder', 'high', null,
       (v_today + interval '2 days 12 hours') at time zone 'Europe/Istanbul',
       (v_today + interval '2 days 10 hours') at time zone 'Europe/Istanbul'),
    (p_user, 'Aylık gelir-gider tablosunu güncelle', null,
       'Finans', 'medium', null,
       (v_today + interval '5 days 18 hours') at time zone 'Europe/Istanbul', null),
    (p_user, 'Haftalık öğün hazırlığı alışverişi', 'Tavuk göğsü, yumurta, yulaf, çavdar ekmeği, yoğurt.',
       'Kişisel', 'low', null,
       (v_today + interval '3 days 17 hours') at time zone 'Europe/Istanbul', null);

  insert into notes (user_id, title, content, category, is_pinned) values
    (p_user, 'Form hedefi', '84.5 kg → 78 kg. Kas kütlesini koru: yüksek protein, haftada 4 ağırlık + kickboks + koşu + halı saha.', 'Kişisel', true),
    (p_user, 'Toplantı şablonu', 'Gündem · Kararlar · Sorumlu · Termin', 'Toplantı', false),
    (p_user, 'Fikir: son dakika push şablonları', 'Sık kullanılan başlık kalıpları için hazır şablon seti.', 'Fikir', false);

  insert into fitness_logs (user_id, log_type, weight_kg, logged_at, source)
  values (p_user, 'weight', 84.5, now(), 'manual');
end;
$$;

revoke all on function public.seed_personal_assistant(uuid) from public, anon, authenticated;

-- Yeni kullanıcı oluştuğunda seed'i çalıştır (hata kaydı engellemez)
create or replace function public.handle_new_user_seed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.seed_personal_assistant(new.id);
  exception when others then
    raise warning 'seed_personal_assistant başarısız: %', sqlerrm;
  end;
  return new;
end;
$$;

revoke all on function public.handle_new_user_seed() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_seed on auth.users;
create trigger on_auth_user_created_seed
  after insert on auth.users
  for each row execute function public.handle_new_user_seed();

-- Script çalıştığında zaten var olan kullanıcılar için seed
do $$
declare
  u record;
begin
  for u in select id from auth.users loop
    perform public.seed_personal_assistant(u.id);
  end loop;
end;
$$;
