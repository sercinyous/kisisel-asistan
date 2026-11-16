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
-- Sürüm 3 (Faz 3): user_settings.timezone, daily_reports tablosu,
-- weekly_reports.ai_status / generated_at, rapor tablolarında salt okuma,
-- rapor fonksiyonları (report_daily_metrics, report_weekly_metrics,
-- save_daily_report, save_weekly_report — yalnızca service_role).
-- Eski bir sürümle kurulmuş veritabanında çalıştırıldığında yerinde yükseltir.
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
-- 6) weekly_reports / daily_reports — otomatik raporlar (AI özetli)
--    Satırları yalnızca Edge Function (service_role) yazar; uygulama okur.
--    Sayıların tamamı metrics içindedir; weekly_reports'taki sayısal
--    sütunlar aynı değerlerin sorgulanabilir kopyasıdır.
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
  ai_status             text not null default 'pending'
                        check (ai_status in ('pending', 'ok', 'failed')),
  generated_at          timestamptz not null default now(),
  created_at            timestamptz not null default now(),
  unique (user_id, week_start)
);

-- Sürüm 2 → 3 yükseltmesi.
alter table public.weekly_reports
  add column if not exists ai_status text not null default 'pending'
    check (ai_status in ('pending', 'ok', 'failed'));
alter table public.weekly_reports
  add column if not exists generated_at timestamptz not null default now();

create table if not exists public.daily_reports (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  report_date   date not null,
  metrics       jsonb not null default '{}'::jsonb,
  ai_summary    text,
  ai_status     text not null default 'pending'
                check (ai_status in ('pending', 'ok', 'failed')),
  generated_at  timestamptz not null default now(),
  unique (user_id, report_date)
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
  -- Rapor günü ve haftası bu saat dilimine göre kesilir (IANA adı).
  timezone               text not null default 'Europe/Istanbul',
  updated_at             timestamptz not null default now()
);

-- Sürüm 2 → 3 yükseltmesi.
alter table public.user_settings
  add column if not exists timezone text not null default 'Europe/Istanbul';

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
    'fitness_logs', 'nutrition_logs', 'daily_health_metrics', 'user_settings'
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

  -- Rapor tabloları: kullanıcı yalnızca kendi satırını OKUR. Yazma politikası
  -- yoktur; satırları service_role (RLS'i aşar) ile Edge Function yazar.
  -- Sürüm 2'nin weekly_reports_owner_all politikası burada kaldırılır.
  foreach t in array array['daily_reports', 'weekly_reports']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_owner_all', t);
    execute format('drop policy if exists %I on public.%I', t || '_owner_select', t);
    execute format(
      'create policy %I on public.%I for select to authenticated
         using (auth.uid() = user_id)',
      t || '_owner_select', t
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
  public.user_settings
  to authenticated;
revoke all on table
  public.routines, public.routine_completions, public.tasks, public.notes,
  public.fitness_logs, public.nutrition_logs, public.daily_health_metrics,
  public.weekly_reports, public.daily_reports, public.user_settings
  from anon;

-- Rapor tabloları uygulama için salt okunurdur. Önce tümü geri alınır ki
-- sürüm 2'de verilmiş yazma yetkisi de kalksın.
revoke all on table public.weekly_reports, public.daily_reports from authenticated;
grant select on table public.weekly_reports, public.daily_reports to authenticated;

-- Edge Function (service_role): kullanıcı listesini ve saat dilimini
-- user_settings'ten okur, raporları yazar. Diğer tablolara rapor
-- fonksiyonları (security definer) üzerinden erişir.
grant usage on schema public to service_role;
grant select on table public.user_settings to service_role;
grant select, insert, update, delete on table
  public.weekly_reports, public.daily_reports to service_role;

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
-- RAPORLAR — sayılar burada hesaplanır; Gemini yalnızca yorum yazar.
-- Dört fonksiyonu yalnızca service_role (Edge Function generate-reports)
-- çalıştırır. security definer: service_role'ün veri tablolarında yetkisi
-- olması gerekmez; kullanıcı p_user ile açıkça verilir (auth.uid() yok).
--
-- Kurallar (docs/SPEC_FAZ3.md §2):
--   * Gün sınırı user_settings.timezone'a göredir.
--   * Görev o güne aittir: due_at o günde. done: status = 'done'.
--   * Günlük/haftalık rutin: days_of_week o günü içeriyorsa planlıdır.
--     Aylık rutin: günü = min(day_of_month, ayın son günü) ise planlıdır;
--     tamamlanması ayın 1'i anahtarıyla okunur.
--     Rutin, oluşturulduğu günden önce ve pasifken planlı sayılmaz.
--   * Henüz gelmemiş günler planlı sayılmaz (hafta ortasında üretilen rapor
--     kalan günler yüzünden düşük çıkmasın).
--   * Protein tutturma: günlük protein >= hedefin %90'ı.
--     Kalori aralığı: hedefin %85–%110'u (uçlar dahil). Kayıtsız gün tutmaz.
--   * Ortalamalar yalnızca verisi olan günler üzerinden alınır.
--   * Kilo: end = aralıktaki son ölçüm; start = aralıktan önceki son ölçüm,
--     yoksa aralıktaki ilk ölçüm.
-- ---------------------------------------------------------------------
create or replace function public.report_period_metrics(
  p_user uuid,
  p_from date,
  p_to date,
  p_with_days boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz        text;
  v_cal       integer;
  v_pro       integer;
  v_steps     integer;
  v_sleep     integer;
  v_today     date;
  v_t0        timestamptz;
  v_t1        timestamptz;
  v_t1_tasks  timestamptz;
  v_w_start   numeric;
  v_w_end     numeric;
  v_result    jsonb;
begin
  if p_user is null or p_from is null or p_to is null or p_to < p_from then
    raise exception 'Geçersiz rapor aralığı' using errcode = '22023';
  end if;

  select s.timezone, s.daily_calories, s.daily_protein_g, s.daily_steps, s.sleep_minutes
    into v_tz, v_cal, v_pro, v_steps, v_sleep
  from user_settings s
  where s.user_id = p_user;

  -- Ayar satırı yoksa tablo varsayılanları geçerlidir.
  v_tz    := coalesce(nullif(btrim(v_tz), ''), 'Europe/Istanbul');
  v_cal   := coalesce(v_cal, 2000);
  v_pro   := coalesce(v_pro, 170);
  v_steps := coalesce(v_steps, 10000);
  v_sleep := coalesce(v_sleep, 450);

  -- Bozuk bir saat dilimi adı raporu düşürmesin.
  begin
    perform now() at time zone v_tz;
  exception when others then
    v_tz := 'Europe/Istanbul';
  end;

  v_today    := (now() at time zone v_tz)::date;
  v_t0       := p_from::timestamp at time zone v_tz;
  v_t1       := (p_to + 1)::timestamp at time zone v_tz;
  v_t1_tasks := least(v_t1, (v_today + 1)::timestamp at time zone v_tz);

  select f.weight_kg into v_w_end
  from fitness_logs f
  where f.user_id = p_user and f.log_type = 'weight'
    and f.logged_at >= v_t0 and f.logged_at < v_t1
  order by f.logged_at desc
  limit 1;

  select f.weight_kg into v_w_start
  from fitness_logs f
  where f.user_id = p_user and f.log_type = 'weight' and f.logged_at < v_t0
  order by f.logged_at desc
  limit 1;

  if v_w_start is null then
    select f.weight_kg into v_w_start
    from fitness_logs f
    where f.user_id = p_user and f.log_type = 'weight'
      and f.logged_at >= v_t0 and f.logged_at < v_t1
    order by f.logged_at asc
    limit 1;
  end if;

  with days as (
    select g::date as day, g::date <= v_today as elapsed
    from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') as g
  ),
  planned as (
    select d.day,
           r.id as routine_id,
           r.category,
           case when r.frequency = 'monthly'
                then date_trunc('month', d.day)::date
                else d.day end as period_key
    from days d
    join routines r
      on r.user_id = p_user
     and r.is_active
     and (r.created_at at time zone v_tz)::date <= d.day
     and (
       (r.frequency = 'weekly'
        and extract(isodow from d.day)::smallint = any (r.days_of_week))
       or
       (r.frequency = 'monthly'
        and extract(day from d.day)::integer = least(
              r.day_of_month::integer,
              extract(day from date_trunc('month', d.day)
                               + interval '1 month' - interval '1 day')::integer))
     )
    where d.elapsed
  ),
  routine_day as (
    select p.day,
           count(*)                                        as planned,
           count(c.id)                                     as done,
           count(*) filter (where p.category = 'spor')     as workouts_planned
    from planned p
    left join routine_completions c
      on c.routine_id = p.routine_id and c.completed_on = p.period_key
    group by p.day
  ),
  task_day as (
    select (t.due_at at time zone v_tz)::date              as day,
           count(*)                                        as total,
           count(*) filter (where t.status = 'done')       as done
    from tasks t
    where t.user_id = p_user and t.due_at >= v_t0 and t.due_at < v_t1_tasks
    group by 1
  ),
  nutrition_day as (
    select (n.eaten_at at time zone v_tz)::date            as day,
           sum(n.calories)  as calories,
           sum(n.protein_g) as protein_g,
           sum(n.carbs_g)   as carbs_g,
           sum(n.fat_g)     as fat_g,
           count(*)         as entries
    from nutrition_logs n
    where n.user_id = p_user and n.eaten_at >= v_t0 and n.eaten_at < v_t1
    group by 1
  ),
  workout_day as (
    select (f.logged_at at time zone v_tz)::date as day, count(*) as done
    from fitness_logs f
    where f.user_id = p_user and f.log_type = 'workout'
      and f.logged_at >= v_t0 and f.logged_at < v_t1
    group by 1
  ),
  per_day as (
    select d.day,
           d.elapsed,
           coalesce(t.total, 0)             as tasks_total,
           coalesce(t.done, 0)              as tasks_done,
           coalesce(r.planned, 0)           as routines_planned,
           coalesce(r.done, 0)              as routines_done,
           coalesce(r.workouts_planned, 0)  as workouts_planned,
           coalesce(w.done, 0)              as workouts_done,
           coalesce(n.calories, 0)          as calories,
           coalesce(n.protein_g, 0)         as protein_g,
           coalesce(n.carbs_g, 0)           as carbs_g,
           coalesce(n.fat_g, 0)             as fat_g,
           coalesce(n.entries, 0)           as entries,
           coalesce(h.steps, 0)             as steps,
           coalesce(h.sleep_minutes, 0)     as sleep_minutes,
           coalesce(h.active_kcal, 0)       as active_kcal,
           (coalesce(n.entries, 0) > 0
             and n.protein_g >= v_pro * 0.9)::integer as protein_hit,
           (coalesce(n.entries, 0) > 0
             and n.calories between v_cal * 0.85 and v_cal * 1.10)::integer as calorie_ok
    from days d
    left join task_day t      on t.day = d.day
    left join routine_day r   on r.day = d.day
    left join workout_day w   on w.day = d.day
    left join nutrition_day n on n.day = d.day
    left join daily_health_metrics h
      on h.user_id = p_user and h.metric_date = d.day
  ),
  agg as (
    select
      sum(tasks_total)       as tasks_total,
      sum(tasks_done)        as tasks_done,
      sum(routines_planned)  as routines_planned,
      sum(routines_done)     as routines_done,
      sum(workouts_planned)  as workouts_planned,
      sum(workouts_done)     as workouts_done,
      sum(protein_hit)       as protein_days_hit,
      sum(calorie_ok)        as calorie_days_in_range,
      count(*) filter (where elapsed)       as elapsed_days,
      count(*) filter (where entries > 0)   as days_logged,
      avg(calories)  filter (where entries > 0) as calories,
      avg(protein_g) filter (where entries > 0) as protein_g,
      avg(carbs_g)   filter (where entries > 0) as carbs_g,
      avg(fat_g)     filter (where entries > 0) as fat_g,
      avg(steps)         filter (where steps > 0)         as steps,
      avg(sleep_minutes) filter (where sleep_minutes > 0) as sleep_minutes,
      avg(active_kcal)   filter (where active_kcal > 0)   as active_kcal,
      count(*) filter (where steps > 0 or sleep_minutes > 0 or active_kcal > 0)
        as days_with_data,
      jsonb_agg(
        jsonb_build_object(
          'date', to_char(day, 'YYYY-MM-DD'),
          'work_rate', round(100.0 * (tasks_done + routines_done)
                             / nullif(tasks_total + routines_planned, 0))::integer,
          'form_rate', case when elapsed then
                         round(100.0 * (least(workouts_done, workouts_planned) + protein_hit)
                               / (workouts_planned + 1))::integer
                       end,
          'calories', round(calories, 1),
          'protein_g', round(protein_g, 1),
          'steps', steps,
          'sleep_minutes', sleep_minutes,
          'workouts', workouts_done
        ) order by day
      ) as days
    from per_day
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'start', to_char(p_from, 'YYYY-MM-DD'),
      'end', to_char(p_to, 'YYYY-MM-DD')),
    'work', jsonb_build_object(
      'tasks_total', a.tasks_total,
      'tasks_done', a.tasks_done,
      'routines_planned', a.routines_planned,
      'routines_done', a.routines_done,
      'rate', round(100.0 * (a.tasks_done + a.routines_done)
                    / nullif(a.tasks_total + a.routines_planned, 0))::integer),
    'form', jsonb_build_object(
      'workouts_planned', a.workouts_planned,
      'workouts_done', a.workouts_done,
      'protein_days_hit', a.protein_days_hit,
      'calorie_days_in_range', a.calorie_days_in_range,
      'rate', round(100.0 * (least(a.workouts_done, a.workouts_planned) + a.protein_days_hit)
                    / nullif(a.workouts_planned + a.elapsed_days, 0))::integer),
    'nutrition', jsonb_build_object(
      'calories', coalesce(round(a.calories, 1), 0),
      'protein_g', coalesce(round(a.protein_g, 1), 0),
      'carbs_g', coalesce(round(a.carbs_g, 1), 0),
      'fat_g', coalesce(round(a.fat_g, 1), 0),
      'days_logged', a.days_logged),
    'health', jsonb_build_object(
      'steps', coalesce(round(a.steps), 0)::integer,
      'sleep_minutes', coalesce(round(a.sleep_minutes), 0)::integer,
      'active_kcal', coalesce(round(a.active_kcal), 0)::integer,
      'days_with_data', a.days_with_data),
    'weight', jsonb_build_object(
      'start_kg', v_w_start,
      'end_kg', v_w_end,
      'change_kg', v_w_end - v_w_start),
    'targets', jsonb_build_object(
      'calories', v_cal,
      'protein_g', v_pro,
      'steps', v_steps,
      'sleep_minutes', v_sleep)
  ) || case when p_with_days
            then jsonb_build_object('days', a.days)
            else '{}'::jsonb end
  into v_result
  from agg a;

  return v_result;
end;
$$;

-- Bir günün raporu (p_day: kullanıcının saat dilimindeki gün).
create or replace function public.report_daily_metrics(p_user uuid, p_day date)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.report_period_metrics(p_user, p_day, p_day, false);
$$;

-- Bir haftanın raporu (p_week_start Pazartesi; Pzt–Paz). Toplam/ortalama
-- değerlere ek olarak gün gün dökümü `days` dizisinde verir.
create or replace function public.report_weekly_metrics(p_user uuid, p_week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if extract(isodow from p_week_start) <> 1 then
    raise exception 'p_week_start Pazartesi olmalı: %', p_week_start
      using errcode = '22023';
  end if;
  return public.report_period_metrics(p_user, p_week_start, p_week_start + 6, true);
end;
$$;

-- Günlük raporu yazar ya da günceller (kullanıcı + gün başına tek satır).
create or replace function public.save_daily_report(
  p_user uuid,
  p_day date,
  p_metrics jsonb,
  p_summary text,
  p_status text
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into daily_reports (user_id, report_date, metrics, ai_summary, ai_status, generated_at)
  values (p_user, p_day, coalesce(p_metrics, '{}'::jsonb), p_summary, p_status, now())
  on conflict (user_id, report_date) do update
    set metrics      = excluded.metrics,
        ai_summary   = excluded.ai_summary,
        ai_status    = excluded.ai_status,
        generated_at = excluded.generated_at;
$$;

-- Haftalık raporu yazar ya da günceller; sayısal sütunları metrics'ten doldurur.
create or replace function public.save_weekly_report(
  p_user uuid,
  p_week_start date,
  p_metrics jsonb,
  p_summary text,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m            jsonb := coalesce(p_metrics, '{}'::jsonb);
  v_total      integer := coalesce((m #>> '{work,tasks_total}')::numeric, 0)::integer;
  v_done       integer := coalesce((m #>> '{work,tasks_done}')::numeric, 0)::integer;
  v_logged     integer := coalesce((m #>> '{nutrition,days_logged}')::numeric, 0)::integer;
  v_steps      integer := coalesce((m #>> '{health,steps}')::numeric, 0)::integer;
  v_sleep      integer := coalesce((m #>> '{health,sleep_minutes}')::numeric, 0)::integer;
begin
  if extract(isodow from p_week_start) <> 1 then
    raise exception 'p_week_start Pazartesi olmalı: %', p_week_start
      using errcode = '22023';
  end if;

  insert into weekly_reports (
    user_id, week_start, tasks_total, tasks_done, task_completion_rate,
    routines_planned, routines_done, workouts_done,
    avg_calories, avg_protein_g, avg_steps, avg_sleep_minutes,
    weight_start_kg, weight_end_kg, ai_summary, metrics, ai_status, generated_at
  )
  values (
    p_user, p_week_start, v_total, v_done,
    case when v_total > 0 then round(100.0 * v_done / v_total, 2) else 0 end,
    coalesce((m #>> '{work,routines_planned}')::numeric, 0)::integer,
    coalesce((m #>> '{work,routines_done}')::numeric, 0)::integer,
    coalesce((m #>> '{form,workouts_done}')::numeric, 0)::integer,
    -- Verisi olmayan ortalama 0 değil "yok"tur.
    case when v_logged > 0 then (m #>> '{nutrition,calories}')::numeric end,
    case when v_logged > 0 then (m #>> '{nutrition,protein_g}')::numeric end,
    nullif(v_steps, 0),
    nullif(v_sleep, 0),
    (m #>> '{weight,start_kg}')::numeric,
    (m #>> '{weight,end_kg}')::numeric,
    p_summary, m, p_status, now()
  )
  on conflict (user_id, week_start) do update
    set tasks_total          = excluded.tasks_total,
        tasks_done           = excluded.tasks_done,
        task_completion_rate = excluded.task_completion_rate,
        routines_planned     = excluded.routines_planned,
        routines_done        = excluded.routines_done,
        workouts_done        = excluded.workouts_done,
        avg_calories         = excluded.avg_calories,
        avg_protein_g        = excluded.avg_protein_g,
        avg_steps            = excluded.avg_steps,
        avg_sleep_minutes    = excluded.avg_sleep_minutes,
        weight_start_kg      = excluded.weight_start_kg,
        weight_end_kg        = excluded.weight_end_kg,
        ai_summary           = excluded.ai_summary,
        metrics              = excluded.metrics,
        ai_status            = excluded.ai_status,
        generated_at         = excluded.generated_at;
end;
$$;

-- Fonksiyonlar herkese (PUBLIC) açık doğar; yalnızca service_role çalıştırır.
revoke all on function public.report_period_metrics(uuid, date, date, boolean)
  from public, anon, authenticated;
revoke all on function public.report_daily_metrics(uuid, date)
  from public, anon, authenticated;
revoke all on function public.report_weekly_metrics(uuid, date)
  from public, anon, authenticated;
revoke all on function public.save_daily_report(uuid, date, jsonb, text, text)
  from public, anon, authenticated;
revoke all on function public.save_weekly_report(uuid, date, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function public.report_period_metrics(uuid, date, date, boolean)
  to service_role;
grant execute on function public.report_daily_metrics(uuid, date) to service_role;
grant execute on function public.report_weekly_metrics(uuid, date) to service_role;
grant execute on function public.save_daily_report(uuid, date, jsonb, text, text)
  to service_role;
grant execute on function public.save_weekly_report(uuid, date, jsonb, text, text)
  to service_role;

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
