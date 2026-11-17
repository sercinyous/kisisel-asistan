-- =====================================================================
-- Kişisel Asistan & Operasyon Merkezi — Supabase (PostgreSQL) şeması
-- Supabase Dashboard > SQL Editor içinde TEK SEFERDE çalıştırılabilir.
-- Tekrar çalıştırılabilir (idempotent): mevcut veriyi silmez.
--
-- Güvenlik modeli: anon key uygulamanın içinde taşındığı için tüm tablolarda
-- RLS açık ve satırlar auth.uid() ile sahibine kilitli. Uygulamaya Supabase
-- Auth (Google ya da e-posta + şifre) ile girilir. Kullanıcılar birbirinin ham
-- tablolarını okuyamaz; arkadaşlar yalnızca security definer işlevlerinden,
-- kişinin açtığı anahtar kadar hedef özeti görür (Faz 4B bölümü).
--
-- Yeni hesap: auth.users trigger'ı yalnızca user_settings satırı açar (nötr
-- başlangıç; rutin/görev/not yüklenmez). Hesap açmak için en az bir
-- kullanıcıdan bekleyen arkadaş isteği almış e-posta gerekir (kayıt kapısı).
--
-- Sürüm 2 (Faz 2): routines.frequency / day_of_month / scope, 'finans'
-- kategorisi, user_settings tablosu, quick_add_entries içinde routines[].
-- Sürüm 3 (Faz 3): user_settings.timezone, daily_reports tablosu,
-- weekly_reports.ai_status / generated_at, rapor tablolarında salt okuma,
-- rapor fonksiyonları (report_daily_metrics, report_weekly_metrics,
-- save_daily_report, save_weekly_report — yalnızca service_role).
-- Sürüm 4 (Google Health): fitness_logs.source 'google' değerini kabul eder,
-- fitness_logs.external_id + (user_id, source, external_id) tekil dizini
-- içe aktarılan antrenmanın yeniden eşitlemede kopyalanmasını önler.
-- Sürüm 5 (Faz 4A): user_settings.height_cm / birth_year / sex profil
-- sütunları (enerji dengesi için; cevaplanmamışsa null).
-- Sürüm 6 (Faz 4B): çok kullanıcılı. user_settings.display_name /
-- work_description / onboarded_at, nötr varsayılanlar, 'Pusholder' → 'İş'
-- (eski uygulama sürümü için geçiş tetikleyicisi), friend_requests /
-- friendships / friend_sharing / ai_usage + arkadaş işlevleri, kayıt kapısı,
-- consume_ai_quota. Rapor zamanlayıcısı yalnızca onboarded_at dolu kullanıcılar
-- için çalışır: Edge Function (service_role) user_settings'ten okur.
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
--    scope: iş / kişisel ayrımı.
-- ---------------------------------------------------------------------
create table if not exists public.routines (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 200),
  scope         text not null default 'Kişisel'
                check (scope in ('İş', 'Kişisel')),
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
        check (scope in ('İş', 'Kişisel'));

    update public.routines set scope = 'İş' where category = 'operasyon';

    -- Sürüm 2 seed'indeki iki aylık örnek, verisi olan kullanıcılara da eklenir.
    insert into public.routines
      (user_id, title, scope, category, frequency, day_of_month, time_of_day, sort_order)
    select u.user_id, v.title, 'İş', v.category, 'monthly', v.day_of_month,
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
                check (category in ('İş', 'Ekip', 'Finans', 'Kişisel')),
  priority      text not null default 'medium'
                check (priority in ('low', 'medium', 'high')),
  status        text not null default 'todo'
                check (status in ('todo', 'in_progress', 'done')),
  assignee      text,
  due_at        timestamptz,
  remind_at     timestamptz,
  -- false: "Hatırlat" kapalı; termini olsa da bildirim planlanmaz.
  notify        boolean not null default true,
  completed_at  timestamptz,
  source        text not null default 'manual' check (source in ('manual', 'ai')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

do $$
begin
  -- notify sütunu sürüm 3'te eklendi. Eski formda "Hatırlat" kapalı kaydedilen
  -- görev (termin var, hatırlatma saati yok) yalnızca sütun eklenirken, bir kez
  -- kapalıya çevrilir; AI girişleri hatırlatma saati olmadan da bildirimlidir.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks'
      and column_name = 'notify'
  ) then
    alter table public.tasks add column notify boolean not null default true;

    update public.tasks set notify = false
    where source = 'manual' and due_at is not null and remind_at is null;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) notes — toplantı / fikir / kategori bazlı hızlı notlar
-- ---------------------------------------------------------------------
create table if not exists public.notes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null check (char_length(title) between 1 and 200),
  content       text not null default '',
  category      text not null default 'Kişisel'
                check (category in ('Toplantı', 'Fikir', 'İş', 'Ekip', 'Finans', 'Kişisel')),
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
  source           text not null default 'manual'
                   check (source in ('manual', 'ai', 'healthkit', 'google')),
  -- Dış kaynaktaki kimlik (Google Health veri noktası); elle/AI kayıtta boş.
  external_id      text,
  created_at       timestamptz not null default now(),
  constraint fitness_logs_shape check (
    (log_type = 'workout' and workout_type is not null)
    or (log_type = 'weight' and weight_kg is not null)
  ),
  constraint fitness_logs_external_id_check check (
    external_id is null
    or (char_length(external_id) between 1 and 300 and source in ('healthkit', 'google'))
  )
);

-- Sürüm 3 → 4 yükseltmesi. Kaynak listesi sütun check'inde durduğu için
-- source'u denetleyen eski check (adı ne olursa olsun) kaldırılır ve her
-- çalıştırmada aynı adla yeniden kurulur (veri değişmez).
alter table public.fitness_logs add column if not exists external_id text;
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.fitness_logs'::regclass
      and contype = 'c'
      and conname <> 'fitness_logs_external_id_check'
      and pg_get_constraintdef(oid) ~ '\msource\M'
  loop
    execute format('alter table public.fitness_logs drop constraint %I', c.conname);
  end loop;
end;
$$;
alter table public.fitness_logs add constraint fitness_logs_source_check
  check (source in ('manual', 'ai', 'healthkit', 'google'));
alter table public.fitness_logs drop constraint if exists fitness_logs_external_id_check;
alter table public.fitness_logs add constraint fitness_logs_external_id_check
  check (
    external_id is null
    or (char_length(external_id) between 1 and 300 and source in ('healthkit', 'google'))
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
  -- Varsayılanlar nötr/genel değerlerdir (Faz 4B); ilk kurulum gerçek
  -- değerleri yazar. Mevcut satırlar değişmez.
  start_weight_kg        numeric(5,2) not null default 70
                         check (start_weight_kg between 30 and 250),
  target_weight_kg       numeric(5,2) not null default 70
                         check (target_weight_kg between 30 and 250),
  daily_calories         integer not null default 2000
                         check (daily_calories between 800 and 6000),
  daily_protein_g        integer not null default 120
                         check (daily_protein_g between 0 and 500),
  daily_carbs_g          integer not null default 220
                         check (daily_carbs_g between 0 and 800),
  daily_fat_g            integer not null default 65
                         check (daily_fat_g between 0 and 400),
  daily_steps            integer not null default 8000
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
  team_members           text[] not null default '{}',
  -- Rapor günü ve haftası bu saat dilimine göre kesilir (IANA adı).
  timezone               text not null default 'Europe/Istanbul',
  -- Profil (Faz 4A, enerji dengesi). Cevaplanmamışsa null; sex 'unspecified'
  -- "belirtmek istemiyorum" demektir, null ise henüz cevaplanmadığını.
  height_cm              smallint check (height_cm between 100 and 250),
  birth_year             smallint check (birth_year between 1900 and 2100),
  sex                    text check (sex in ('female', 'male', 'unspecified')),
  -- Faz 4B: görünen ad (arkadaşlara), iş tanımı (yalnızca AI komutuna),
  -- ilk kurulumun bittiği an (null = kılavuz ve sorular gösterilir).
  display_name           text check (char_length(display_name) <= 60),
  work_description       text check (char_length(work_description) <= 500),
  onboarded_at           timestamptz,
  updated_at             timestamptz not null default now()
);

-- Sürüm 2 → 3 yükseltmesi.
alter table public.user_settings
  add column if not exists timezone text not null default 'Europe/Istanbul';

-- Sürüm 4 → 5 yükseltmesi (profil sütunları). Satır düzeyi RLS politikası ve
-- tablo düzeyi yetkiler yeni sütunları kendiliğinden kapsar. Sütun zaten
-- varsa ifade atlanır, yani betik tekrar çalışınca check'ler çoğalmaz.
alter table public.user_settings
  add column if not exists height_cm smallint check (height_cm between 100 and 250),
  add column if not exists birth_year smallint check (birth_year between 1900 and 2100),
  add column if not exists sex text check (sex in ('female', 'male', 'unspecified'));

-- Sürüm 5 → 6 yükseltmesi (Faz 4B). onboarded_at'in yokluğu "bu veritabanı
-- henüz Faz 4B'yi görmedi" demektir. Mevcut hesaplar kılavuza ZORLANMAZ:
-- yalnızca sütun eklenirken, bir kez, hepsine o an yazılır (ayar satırı hiç
-- açılmamış eski hesaplara da bir satır açılır). updated_at tetikleyicisi bu
-- toplu yazıda çalışmaz; sonraki çalıştırmalarda yeni hesaplara dokunulmaz.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_settings'
      and column_name = 'onboarded_at'
  ) then
    alter table public.user_settings add column onboarded_at timestamptz;
    alter table public.user_settings disable trigger user;
    update public.user_settings set onboarded_at = now();
    alter table public.user_settings enable trigger user;
    insert into public.user_settings (user_id, onboarded_at)
    select u.id, now() from auth.users u
    on conflict (user_id) do nothing;
  end if;
end;
$$;

alter table public.user_settings
  add column if not exists display_name text check (char_length(display_name) <= 60),
  add column if not exists work_description text check (char_length(work_description) <= 500);

-- Nötr varsayılanlar: yalnızca YENİ satırlar etkilenir, mevcut satırlar durur.
alter table public.user_settings
  alter column start_weight_kg set default 70,
  alter column target_weight_kg set default 70,
  alter column daily_protein_g set default 120,
  alter column daily_carbs_g set default 220,
  alter column daily_steps set default 8000,
  alter column team_members set default '{}';

-- ---------------------------------------------------------------------
-- 'Pusholder' → 'İş' (Faz 4B: sahibe özel ad ürün kodundan kalkar).
--   * tasks.category, notes.category, routines.scope kısıtları yeniden kurulur;
--   * mevcut satırlar taşınır (updated_at değişmesin diye tetikleyiciler
--     toplu yazıda kapatılır; kısıt önce kalktığı için sıra güvenlidir);
--   * eski TestFlight yapısı 'Pusholder' yazarsa BEFORE tetikleyicisi 'İş'e
--     çevirir (aşağıda, tetikleyici bölümünde).
-- ---------------------------------------------------------------------
do $$
declare
  v record;
  c record;
begin
  for v in
    select * from (values ('tasks', 'category'), ('notes', 'category'), ('routines', 'scope'))
      as x(tbl, col)
  loop
    for c in
      select conname from pg_constraint
      where conrelid = format('public.%I', v.tbl)::regclass
        and contype = 'c'
        and pg_get_constraintdef(oid) ~ ('\m' || v.col || '\M')
    loop
      execute format('alter table public.%I drop constraint %I', v.tbl, c.conname);
    end loop;
  end loop;

  alter table public.tasks disable trigger user;
  alter table public.notes disable trigger user;
  alter table public.routines disable trigger user;
  update public.tasks set category = 'İş' where category = 'Pusholder';
  update public.notes set category = 'İş' where category = 'Pusholder';
  update public.routines set scope = 'İş' where scope = 'Pusholder';
  alter table public.tasks enable trigger user;
  alter table public.notes enable trigger user;
  alter table public.routines enable trigger user;

  -- Görev kategorileri kullanıcı tarafından yönetilir (sürüm 7); ad sınırı
  -- dosya sonundaki "Görev kategorileri" bölümüyle aynıdır.
  alter table public.tasks add constraint tasks_category_check
    check (char_length(btrim(category)) between 1 and 40);
  alter table public.notes add constraint notes_category_check
    check (category in ('Toplantı', 'Fikir', 'İş', 'Ekip', 'Finans', 'Kişisel'));
  alter table public.routines add constraint routines_scope_check
    check (scope in ('İş', 'Kişisel'));
end;
$$;

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
-- İçe aktarma tekilleştirmesi. Kısmi değil, tam dizin: uygulama PostgREST
-- upsert'inde on_conflict=user_id,source,external_id verir ve PostgREST kısmi
-- dizinin koşulunu ON CONFLICT'e yazamaz. NULL'lar birbirine eşit sayılmadığı
-- için external_id'si boş elle/AI kayıtları bu dizine takılmaz.
create unique index if not exists fitness_logs_external_uidx
  on public.fitness_logs (user_id, source, external_id);
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

-- Eski TestFlight yapısı kategori/kapsam olarak 'Pusholder' göndermeye devam
-- eder; kısıttan ÖNCE çalışan BEFORE tetikleyicisi bunu 'İş'e çevirir. Yeni
-- yapı zaten 'İş' yazar. (Geçiş uyumu: eski yapılar kalmayınca kaldırılabilir.)
create or replace function public.normalize_legacy_pusholder()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'routines' then
    if new.scope = 'Pusholder' then
      new.scope := 'İş';
    end if;
  elsif new.category = 'Pusholder' then
    new.category := 'İş';
  end if;
  return new;
end;
$$;
revoke all on function public.normalize_legacy_pusholder() from public, anon, authenticated;

drop trigger if exists tasks_legacy_pusholder on public.tasks;
create trigger tasks_legacy_pusholder
  before insert or update of category on public.tasks
  for each row execute function public.normalize_legacy_pusholder();

drop trigger if exists notes_legacy_pusholder on public.notes;
create trigger notes_legacy_pusholder
  before insert or update of category on public.notes
  for each row execute function public.normalize_legacy_pusholder();

drop trigger if exists routines_legacy_pusholder on public.routines;
create trigger routines_legacy_pusholder
  before insert or update of scope on public.routines
  for each row execute function public.normalize_legacy_pusholder();

-- ---------------------------------------------------------------------
-- Rutinin sıklığı değişince tamamlanma kayıtları sıfırlanır.
-- Dönem anahtarının anlamı sıklığa bağlıdır (gün ↔ ayın 1'i); eski kayıtlar
-- yeni sıklıkta yanlış dönemi "yapıldı" gösterir, bu yüzden silinir.
-- security invoker: silme, güncellemeyi yapan kullanıcının RLS'i ile çalışır.
-- ---------------------------------------------------------------------
create or replace function public.routines_reset_completions()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  delete from public.routine_completions where routine_id = new.id;
  return null;
end;
$$;
revoke all on function public.routines_reset_completions() from public, anon, authenticated;

drop trigger if exists routines_frequency_changed on public.routines;
create trigger routines_frequency_changed
  after update of frequency on public.routines
  for each row when (old.frequency is distinct from new.frequency)
  execute function public.routines_reset_completions();

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
    -- AI ile eklenen görev her zaman bildirimlidir (notify = true).
    insert into tasks (user_id, title, description, category, priority, assignee, due_at, remind_at, notify, source)
    select v_uid, x.title, x.description,
           coalesce(x.category, 'Kişisel'), coalesce(x.priority, 'medium'),
           x.assignee, x.due_at, x.remind_at, true, 'ai'
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
  v_pro   := coalesce(v_pro, 120);
  v_steps := coalesce(v_steps, 8000);
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
-- SEED — yeni hesap (Faz 4B: nötr)
-- Yalnızca user_settings satırı açılır. Rutinler, görevler, notlar ve ilk
-- tartı yüklenmez: başlangıç rutinlerini kullanıcı ilk kurulumda seçer,
-- "kilo" cevabı ayrıca tartı kaydı olarak yazılır. Bu işlev hiçbir mevcut
-- veriye dokunmaz (sahibin eski seed verisi olduğu gibi durur).
-- ---------------------------------------------------------------------
create or replace function public.seed_personal_assistant(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into user_settings (user_id) values (p_user)
  on conflict (user_id) do nothing;
end;
$$;

revoke all on function public.seed_personal_assistant(uuid) from public, anon, authenticated;

-- Yeni kullanıcı oluştuğunda ayar satırını aç (hata kaydı engellemez)
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

-- Script çalıştığında zaten var olan kullanıcılar için ayar satırı
do $$
declare
  u record;
begin
  for u in select id from auth.users loop
    perform public.seed_personal_assistant(u.id);
  end loop;
end;
$$;

-- =====================================================================
-- FAZ 4B — çok kullanıcılı: arkadaşlar, kayıt kapısı, AI kotası
--
-- Güvenlik ilkeleri:
--   * Kullanıcılar birbirinin ham tablolarını OKUYAMAZ. Arkadaşlık verisi
--     yalnızca aşağıdaki security definer işlevlerinden akar; hepsi sabit
--     search_path ile çalışır, anon çağıramaz ve gövdede auth.uid() denetler.
--   * Bir e-postanın uygulamada hesabı olup olmadığı dışarıdan anlaşılamaz:
--     send_friend_request her durumda aynı cevabı verir; friend_requests'te
--     hedef kullanıcı sütunu istemciye açık değildir.
--   * Yardımcı işlevler hiçbir istemci rolüne açık değildir.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 8) friend_requests / friendships / friend_sharing / ai_usage
-- ---------------------------------------------------------------------
-- Arkadaş isteği. target_email küçük harf; target_user hedefin DOĞRULANMIŞ
-- hesabı varsa dolar (yoksa boş: hesap sonradan açılınca doğrulanmış e-posta
-- eşleşmesiyle görünür). Bekleyen istek (gönderen, hedef e-posta) başına tekil.
create table if not exists public.friend_requests (
  id            uuid primary key default gen_random_uuid(),
  from_user     uuid not null references auth.users (id) on delete cascade,
  target_email  text not null
                check (target_email = lower(btrim(target_email))
                       and char_length(target_email) between 3 and 254),
  target_user   uuid references auth.users (id) on delete set null,
  status        text not null default 'pending'
                check (status in ('pending', 'accepted', 'declined')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  constraint friend_requests_not_self check (target_user is distinct from from_user)
);

create unique index if not exists friend_requests_pending_uidx
  on public.friend_requests (from_user, target_email) where status = 'pending';
create index if not exists friend_requests_pending_email_idx
  on public.friend_requests (target_email) where status = 'pending';
create index if not exists friend_requests_from_user_idx
  on public.friend_requests (from_user);
create index if not exists friend_requests_target_user_idx
  on public.friend_requests (target_user) where target_user is not null;

-- Arkadaşlık: sıralı çift (user_a < user_b), çift başına tek satır.
create table if not exists public.friendships (
  user_a      uuid not null references auth.users (id) on delete cascade,
  user_b      uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_a, user_b),
  constraint friendships_ordered check (user_a < user_b)
);
create index if not exists friendships_user_b_idx on public.friendships (user_b);

-- Kişinin arkadaşlarına açtığı üç anahtar (hepsi varsayılan kapalı).
create table if not exists public.friend_sharing (
  user_id         uuid primary key default auth.uid()
                  references auth.users (id) on delete cascade,
  share_steps     boolean not null default false,
  share_sleep     boolean not null default false,
  share_calories  boolean not null default false,
  updated_at      timestamptz not null default now()
);

drop trigger if exists friend_sharing_set_updated_at on public.friend_sharing;
create trigger friend_sharing_set_updated_at before update on public.friend_sharing
  for each row execute function public.set_updated_at();

-- Günlük AI kullanımı (kişi + tür + gün). Satırları yalnızca consume_ai_quota
-- (service_role) yazar; kullanıcı kendi sayacını okuyabilir.
create table if not exists public.ai_usage (
  user_id  uuid not null references auth.users (id) on delete cascade,
  kind     text not null check (char_length(kind) between 1 and 40),
  day      date not null,
  count    integer not null default 0 check (count >= 0),
  primary key (user_id, kind, day)
);

-- RLS: her tabloda açık. İstemci erişimi aşağıdaki en dar yetkilerle sınırlı.
do $$
declare
  t text;
begin
  foreach t in array array['friend_requests', 'friendships', 'friend_sharing', 'ai_usage']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end;
$$;

drop policy if exists friend_requests_sender_select on public.friend_requests;
create policy friend_requests_sender_select on public.friend_requests
  for select to authenticated
  using ((select auth.uid()) = from_user);

drop policy if exists friendships_member_select on public.friendships;
create policy friendships_member_select on public.friendships
  for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

drop policy if exists friend_sharing_owner_all on public.friend_sharing;
create policy friend_sharing_owner_all on public.friend_sharing
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists ai_usage_owner_select on public.ai_usage;
create policy ai_usage_owner_select on public.ai_usage
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- Yetkiler. friend_requests'te target_user sütunu (hesap var mı sinyali) ve
-- tüm yazma yolları istemciye kapalıdır: istek yalnızca işlevlerle açılır.
revoke all on table
  public.friend_requests, public.friendships, public.friend_sharing, public.ai_usage
  from anon, authenticated;
grant select (id, from_user, target_email, status, created_at, responded_at)
  on table public.friend_requests to authenticated;
grant select on table public.friendships to authenticated;
grant select, insert, update, delete on table public.friend_sharing to authenticated;
grant select on table public.ai_usage to authenticated;

-- ---------------------------------------------------------------------
-- Yardımcı işlevler (hiçbir istemci rolüne açık değil; security definer
-- işlevlerin içinden sahibinin yetkisiyle çağrılır)
-- ---------------------------------------------------------------------
-- Kısmen maskelenmiş e-posta: sercan@gmail.com → s***@gmail.com
create or replace function public.friend_mask_email(p_email text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_email is null or position('@' in p_email) < 2 then 'Kullanıcı'
    else left(p_email, 1) || '***' || substr(p_email, position('@' in p_email))
  end;
$$;

-- Hesabın DOĞRULANMIŞ e-postası (küçük harf); doğrulanmamışsa null.
create or replace function public.verified_email_of(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select lower(btrim(u.email))
  from auth.users u
  where u.id = p_uid and u.email is not null and u.email_confirmed_at is not null;
$$;

-- Arkadaşa gösterilen ad: görünen ad, boşsa maskelenmiş e-posta.
create or replace function public.friend_display_name(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(nullif(btrim(s.display_name), ''), public.friend_mask_email(u.email))
  from auth.users u
  left join public.user_settings s on s.user_id = u.id
  where u.id = p_uid;
$$;

-- Geçerli IANA saat dilimi adı; boş ya da bozuksa Europe/Istanbul.
create or replace function public.safe_timezone(p_tz text)
returns text
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v text := coalesce(nullif(btrim(p_tz), ''), 'Europe/Istanbul');
begin
  perform now() at time zone v;
  return v;
exception when others then
  return 'Europe/Istanbul';
end;
$$;

-- Günlük hedef tutturma kuralları. Eşikler lib/features/health/domain/
-- goal_rules.dart (GoalRules) ile AYNIDIR; supabase/tests/goal_vectors.json
-- ortak vektörleriyle hem SQL'de hem Dart'ta sınanır (eşlik testi). Tam sayı
-- aritmetiği: kalori onda birlere yuvarlanır, sonra tam sayı karşılaştırılır.
-- Hedefi sıfır/negatif olan kural hiçbir zaman tutmaz.
create or replace function public.goal_steps_hit(p_steps bigint, p_target integer)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  -- adım: hedefin en az %100'ü
  select coalesce(p_target > 0 and p_steps * 100 >= p_target::bigint * 100, false);
$$;

create or replace function public.goal_sleep_hit(p_minutes bigint, p_target integer)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  -- uyku: hedefin en az %90'ı
  select coalesce(p_target > 0 and p_minutes * 100 >= p_target::bigint * 90, false);
$$;

create or replace function public.goal_calories_hit(p_kcal numeric, p_target integer)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  -- kalori: hedefin %85–%110'u (uçlar dahil); onda bir kalori tam sayıya çevrilir
  select coalesce(
    p_target > 0
    and round(p_kcal * 10) * 10 >= p_target::numeric * 85
    and round(p_kcal * 10) * 10 <= p_target::numeric * 110,
    false);
$$;

revoke all on function public.friend_mask_email(text) from public, anon, authenticated;
revoke all on function public.verified_email_of(uuid) from public, anon, authenticated;
revoke all on function public.friend_display_name(uuid) from public, anon, authenticated;
revoke all on function public.safe_timezone(text) from public, anon, authenticated;
revoke all on function public.goal_steps_hit(bigint, integer) from public, anon, authenticated;
revoke all on function public.goal_sleep_hit(bigint, integer) from public, anon, authenticated;
revoke all on function public.goal_calories_hit(numeric, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Arkadaş işlevleri (security definer, yalnızca authenticated)
-- ---------------------------------------------------------------------
-- Arkadaş isteği gönder. HER DURUMDA aynı cevap: kendine, zaten arkadaşa,
-- tekrar ya da hesabı olmayan e-postaya fark yok (e-posta sorgulanamaz).
-- Kullanıcı başına en çok 20 bekleyen istek: sınır yalnızca çağıranın kendi
-- durumuna bağlıdır, bu yüzden hedef hakkında bilgi sızdırmaz.
create or replace function public.send_friend_request(target_email text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  c_ok         constant text := 'İstek gönderildi';
  v_uid        uuid := auth.uid();
  v_email      text := lower(btrim(send_friend_request.target_email));
  v_my_email   text;
  v_my_verified text;
  v_target     uuid;
  v_pending    integer;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  if v_email is null or char_length(v_email) > 254
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Geçerli bir e-posta adresi gir' using errcode = '22023';
  end if;

  -- Aynı kullanıcının eşzamanlı istekleri sınırı aşmasın.
  perform pg_advisory_xact_lock(hashtextextended('friend_requests:' || v_uid::text, 0));

  select count(*) into v_pending
  from public.friend_requests r
  where r.from_user = v_uid and r.status = 'pending';
  if v_pending >= 20 then
    raise exception 'En fazla 20 bekleyen isteğin olabilir. Birini iptal et.'
      using errcode = '54000';
  end if;

  select lower(btrim(u.email)) into v_my_email from auth.users u where u.id = v_uid;
  if v_email = v_my_email then
    return c_ok;
  end if;

  v_my_verified := public.verified_email_of(v_uid);
  select u.id into v_target
  from auth.users u
  where lower(btrim(u.email)) = v_email and u.email_confirmed_at is not null
  order by u.created_at
  limit 1;

  if v_target is not null then
    if v_target = v_uid
       or exists (
         select 1 from public.friendships f
         where f.user_a = least(v_uid, v_target) and f.user_b = greatest(v_uid, v_target)
       )
       -- Karşı taraf zaten bana istek göndermiş: onunki gelen kutumda.
       or exists (
         select 1 from public.friend_requests r
         where r.from_user = v_target and r.status = 'pending'
           and (r.target_user = v_uid or r.target_email = v_my_verified)
       ) then
      return c_ok;
    end if;
  end if;

  begin
    insert into public.friend_requests (from_user, target_email, target_user)
    values (v_uid, v_email, v_target);
  exception when unique_violation then
    null; -- aynı hedefe bekleyen istek zaten var
  end;
  return c_ok;
end;
$$;

-- Bana gelen bekleyen istekler: hedef kullanıcı ben isem ya da doğrulanmış
-- e-postam hedef e-posta ise (hesabı sonradan açılan kişi de görür).
create or replace function public.my_incoming_requests()
returns table (id uuid, from_name text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  v_email := public.verified_email_of(v_uid);
  return query
  select r.id, public.friend_display_name(r.from_user), r.created_at
  from public.friend_requests r
  where r.status = 'pending'
    and r.from_user <> v_uid
    and (r.target_user = v_uid or r.target_email = v_email)
  order by r.created_at desc, r.id;
end;
$$;

-- Benim gönderdiğim bekleyen istekler.
create or replace function public.my_outgoing_requests()
returns table (id uuid, target_email text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  return query
  select r.id, r.target_email, r.created_at
  from public.friend_requests r
  where r.from_user = v_uid and r.status = 'pending'
  order by r.created_at desc, r.id;
end;
$$;

-- Gönderdiğim bekleyen isteği iptal eder (yoksa sessizce hiçbir şey yapmaz).
create or replace function public.cancel_friend_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  delete from public.friend_requests r
  where r.id = cancel_friend_request.request_id
    and r.from_user = v_uid and r.status = 'pending';
end;
$$;

-- Bana gelen isteği kabul eder ya da reddeder. Başkasına ait ya da bitmiş
-- istek "bulunamadı" verir (varlığı sızmaz).
create or replace function public.respond_friend_request(request_id uuid, accept boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_from  uuid;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  if respond_friend_request.request_id is null or respond_friend_request.accept is null then
    raise exception 'Geçersiz istek' using errcode = '22023';
  end if;
  v_email := public.verified_email_of(v_uid);

  select r.from_user into v_from
  from public.friend_requests r
  where r.id = respond_friend_request.request_id
    and r.status = 'pending'
    and r.from_user <> v_uid
    and (r.target_user = v_uid or r.target_email = v_email)
  for update;
  if not found then
    raise exception 'İstek bulunamadı' using errcode = 'P0002';
  end if;

  if respond_friend_request.accept then
    insert into public.friendships (user_a, user_b)
    values (least(v_uid, v_from), greatest(v_uid, v_from))
    on conflict do nothing;

    update public.friend_requests r
       set status = 'accepted', target_user = v_uid, responded_at = now()
     where r.id = respond_friend_request.request_id;

    -- Karşı yönde (benden ona) bekleyen istek artık gereksiz.
    delete from public.friend_requests r
    where r.from_user = v_uid and r.status = 'pending'
      and (r.target_user = v_from
           or r.target_email = (select lower(btrim(u.email)) from auth.users u where u.id = v_from));
  else
    update public.friend_requests r
       set status = 'declined', responded_at = now()
     where r.id = respond_friend_request.request_id;
  end if;
end;
$$;

-- Arkadaşlarım. share_* arkadaşın bana AÇTIĞI anahtarlardır (kapalıysa
-- arayüz "paylaşmıyor" der). display_name boşsa maskelenmiş e-posta.
create or replace function public.my_friends()
returns table (
  friend_id       uuid,
  display_name    text,
  share_steps     boolean,
  share_sleep     boolean,
  share_calories  boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  return query
  with f as (
    select case when fs.user_a = v_uid then fs.user_b else fs.user_a end as fid
    from public.friendships fs
    where fs.user_a = v_uid or fs.user_b = v_uid
  ),
  named as (
    select f.fid, public.friend_display_name(f.fid) as name from f
  )
  select n.fid, n.name,
         coalesce(sh.share_steps, false),
         coalesce(sh.share_sleep, false),
         coalesce(sh.share_calories, false)
  from named n
  left join public.friend_sharing sh on sh.user_id = n.fid
  order by lower(n.name), n.fid;
end;
$$;

-- Arkadaşın bu haftaki hedef günleri (Pazartesi–Pazar, ARKADAŞIN saat
-- diliminde). Yalnızca arkadaşlıkta VE ilgili anahtar açıkken sayı döner;
-- aksi halde shared = false ve 0/0 (tarih ya da başka alan yok). Kurallar
-- Dart TrendStats ile aynı: verisiz gün paydada yok; bitmemiş bugün yalnızca
-- hedef tutturulduysa sayılır; gelecek günler girmez.
create or replace function public.friend_goal_summary(friend uuid, week_start date)
returns table (metric text, shared boolean, goal_days integer, data_days integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid        uuid := auth.uid();
  v_friend     uuid := friend_goal_summary.friend;
  v_week       date := friend_goal_summary.week_start;
  v_is_friend  boolean := false;
  v_sh_steps   boolean := false;
  v_sh_sleep   boolean := false;
  v_sh_cal     boolean := false;
  v_tz         text;
  v_t_steps    integer;
  v_t_sleep    integer;
  v_t_cal      integer;
  v_today      date;
  v_t0         timestamptz;
  v_t1         timestamptz;
  v_s_goal     integer := 0;
  v_s_data     integer := 0;
  v_l_goal     integer := 0;
  v_l_data     integer := 0;
  v_c_goal     integer := 0;
  v_c_data     integer := 0;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  if v_week is null or extract(isodow from v_week) <> 1 then
    raise exception 'week_start Pazartesi olmalı: %', v_week using errcode = '22023';
  end if;

  if v_friend is not null and v_friend <> v_uid then
    v_is_friend := exists (
      select 1 from public.friendships f
      where f.user_a = least(v_uid, v_friend) and f.user_b = greatest(v_uid, v_friend)
    );
  end if;

  if v_is_friend then
    select coalesce(sh.share_steps, false), coalesce(sh.share_sleep, false),
           coalesce(sh.share_calories, false)
      into v_sh_steps, v_sh_sleep, v_sh_cal
    from public.friend_sharing sh
    where sh.user_id = v_friend;
    v_sh_steps := coalesce(v_sh_steps, false);
    v_sh_sleep := coalesce(v_sh_sleep, false);
    v_sh_cal   := coalesce(v_sh_cal, false);
  end if;

  if v_sh_steps or v_sh_sleep or v_sh_cal then
    select s.timezone, s.daily_steps, s.sleep_minutes, s.daily_calories
      into v_tz, v_t_steps, v_t_sleep, v_t_cal
    from public.user_settings s
    where s.user_id = v_friend;
    v_tz      := public.safe_timezone(v_tz);
    v_t_steps := coalesce(v_t_steps, 8000);
    v_t_sleep := coalesce(v_t_sleep, 450);
    v_t_cal   := coalesce(v_t_cal, 2000);
    v_today   := (now() at time zone v_tz)::date;
    v_t0      := v_week::timestamp at time zone v_tz;
    v_t1      := (v_week + 7)::timestamp at time zone v_tz;
  end if;

  if v_sh_steps then
    select (count(*) filter (where x.has_data and x.hit))::integer,
           (count(*) filter (where x.has_data and (x.day < v_today or x.hit)))::integer
      into v_s_goal, v_s_data
    from (
      select d.day,
             coalesce(h.steps, 0) > 0 as has_data,
             public.goal_steps_hit(coalesce(h.steps, 0), v_t_steps) as hit
      from (select g::date as day
            from generate_series(v_week::timestamp, (v_week + 6)::timestamp, interval '1 day') g) d
      left join public.daily_health_metrics h
        on h.user_id = v_friend and h.metric_date = d.day
      where d.day <= v_today
    ) x;
  end if;

  if v_sh_sleep then
    select (count(*) filter (where x.has_data and x.hit))::integer,
           (count(*) filter (where x.has_data and (x.day < v_today or x.hit)))::integer
      into v_l_goal, v_l_data
    from (
      select d.day,
             coalesce(h.sleep_minutes, 0) > 0 as has_data,
             public.goal_sleep_hit(coalesce(h.sleep_minutes, 0), v_t_sleep) as hit
      from (select g::date as day
            from generate_series(v_week::timestamp, (v_week + 6)::timestamp, interval '1 day') g) d
      left join public.daily_health_metrics h
        on h.user_id = v_friend and h.metric_date = d.day
      where d.day <= v_today
    ) x;
  end if;

  if v_sh_cal then
    select (count(*) filter (where x.has_data and x.hit))::integer,
           (count(*) filter (where x.has_data and (x.day < v_today or x.hit)))::integer
      into v_c_goal, v_c_data
    from (
      select d.day,
             n.kcal is not null as has_data,
             public.goal_calories_hit(n.kcal, v_t_cal) as hit
      from (select g::date as day
            from generate_series(v_week::timestamp, (v_week + 6)::timestamp, interval '1 day') g) d
      left join (
        select (nl.eaten_at at time zone v_tz)::date as day, sum(nl.calories) as kcal
        from public.nutrition_logs nl
        where nl.user_id = v_friend and nl.eaten_at >= v_t0 and nl.eaten_at < v_t1
        group by 1
      ) n on n.day = d.day
      where d.day <= v_today
    ) x;
  end if;

  return query values
    ('steps'::text,    v_sh_steps, v_s_goal, v_s_data),
    ('sleep'::text,    v_sh_sleep, v_l_goal, v_l_data),
    ('calories'::text, v_sh_cal,   v_c_goal, v_c_data);
end;
$$;

-- Arkadaşlıktan çık (iki yön de biter; aralarındaki bekleyen istekler silinir).
-- Arkadaş değilsek sessizce hiçbir şey yapmaz.
create or replace function public.leave_friendship(friend uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_friend uuid := leave_friendship.friend;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  if v_friend is null then
    return;
  end if;
  delete from public.friendships f
  where f.user_a = least(v_uid, v_friend) and f.user_b = greatest(v_uid, v_friend);
  delete from public.friend_requests r
  where r.status = 'pending'
    and ((r.from_user = v_uid and r.target_user = v_friend)
      or (r.from_user = v_friend and r.target_user = v_uid));
end;
$$;

revoke all on function public.send_friend_request(text) from public, anon;
revoke all on function public.my_incoming_requests() from public, anon;
revoke all on function public.my_outgoing_requests() from public, anon;
revoke all on function public.cancel_friend_request(uuid) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke all on function public.my_friends() from public, anon;
revoke all on function public.friend_goal_summary(uuid, date) from public, anon;
revoke all on function public.leave_friendship(uuid) from public, anon;
grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.my_incoming_requests() to authenticated;
grant execute on function public.my_outgoing_requests() to authenticated;
grant execute on function public.cancel_friend_request(uuid) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.my_friends() to authenticated;
grant execute on function public.friend_goal_summary(uuid, date) to authenticated;
grant execute on function public.leave_friendship(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Kayıt kapısı. Yalnızca en az bir kullanıcıdan BEKLEYEN arkadaş isteği
-- almış e-posta hesap açabilir; diğerleri "Bu e-posta için davet yok"
-- hatası alır. Mevcut hesaplar etkilenmez (yalnızca insert). Davet hem
-- arkadaşlık hem kayıt izni olur; ayrı izin listesi tutulmaz.
--
-- Not: GoTrue bir tetikleyici hatasını genel "Database error saving new
-- user" olarak gösterebilir. Daha okunur bir 403 mesajı için aşağıdaki
-- hook_before_user_created işlevi Dashboard > Authentication > Hooks >
-- "Before User Created" olarak seçilebilir (isteğe bağlı; tetikleyici her
-- durumda ikinci kapı olarak kalır).
-- Geçici olarak kapatmak (ör. Dashboard'dan elle hesap açmak) için:
--   alter table auth.users disable trigger signup_invite_gate;
-- ve işin sonunda:
--   alter table auth.users enable trigger signup_invite_gate;
-- ---------------------------------------------------------------------
create or replace function public.has_pending_invite(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.friend_requests r
    where r.status = 'pending' and r.target_email = lower(btrim(p_email))
  );
$$;

create or replace function public.enforce_signup_invite()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.has_pending_invite(new.email) then
    raise exception 'Bu e-posta için davet yok' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if public.has_pending_invite(event #>> '{user,email}') then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'message', 'Bu e-posta için davet yok', 'http_code', 403));
end;
$$;

revoke all on function public.has_pending_invite(text) from public, anon, authenticated;
revoke all on function public.enforce_signup_invite() from public, anon, authenticated;
revoke all on function public.hook_before_user_created(jsonb) from public, anon, authenticated;

-- Supabase'te hook'u çalıştıran rol; yerel sınama kümesinde yoktur.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant usage on schema public to supabase_auth_admin;
    grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
  end if;
end;
$$;

drop trigger if exists signup_invite_gate on auth.users;
create trigger signup_invite_gate
  before insert on auth.users
  for each row execute function public.enforce_signup_invite();

-- ---------------------------------------------------------------------
-- AI kotası (yalnızca service_role)
-- ---------------------------------------------------------------------
-- Kota içindeyse sayacı ATOMİK artırıp true döner, aşıldıysa false (sayaç
-- artmaz). Gün, kullanıcının saat dilimindeki gündür. p_kind örnekleri:
-- 'ai' (Gemini çağrıları), 'report_regen' (raporu yeniden oluştur; günde 10).
create or replace function public.consume_ai_quota(p_user uuid, p_kind text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz    text;
  v_day   date;
  v_count integer;
begin
  if p_user is null or p_kind is null or char_length(p_kind) not between 1 and 40 then
    raise exception 'Geçersiz kota isteği' using errcode = '22023';
  end if;
  if p_limit is null or p_limit <= 0 then
    return false;
  end if;

  select s.timezone into v_tz from public.user_settings s where s.user_id = p_user;
  v_day := (now() at time zone public.safe_timezone(v_tz))::date;

  insert into public.ai_usage as u (user_id, kind, day, count)
  values (p_user, p_kind, v_day, 1)
  on conflict (user_id, kind, day)
  do update set count = u.count + 1 where u.count < p_limit
  returning u.count into v_count;

  return v_count is not null;
end;
$$;

revoke all on function public.consume_ai_quota(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.consume_ai_quota(uuid, text, integer) to service_role;

-- Gemini geçici hata verdiğinde (5xx/zaman aşımı) düşülen birimi geri verir.
-- Sayaç 0'ın altına inmez; yalnızca service_role çağırır.
create or replace function public.refund_ai_quota(p_user uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz  text;
  v_day date;
begin
  if p_user is null or p_kind is null or char_length(p_kind) not between 1 and 40 then
    raise exception 'Geçersiz kota isteği' using errcode = '22023';
  end if;
  select s.timezone into v_tz from public.user_settings s where s.user_id = p_user;
  v_day := (now() at time zone public.safe_timezone(v_tz))::date;
  update public.ai_usage u set count = u.count - 1
   where u.user_id = p_user and u.kind = p_kind and u.day = v_day and u.count > 0;
end;
$$;

revoke all on function public.refund_ai_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.refund_ai_quota(uuid, text) to service_role;

-- =====================================================================
-- BEGIN friend_leaderboard (arkadaş sıralaması: ham sayılar + profil)
-- Tekrar çalıştırılabilir. Kabul edilmiş arkadaşlar + çağıranın kendisi için
-- bugün ve bu hafta (Pazartesi–Pazar, KİŞİNİN saat diliminde) yalnızca
-- TOPLANMIŞ sayılar döner; tarih ya da tekil kayıt yoktur. Arkadaşın değeri
-- yalnızca ilgili paylaşım anahtarı açıkken doludur, aksi halde null.
-- Ad: user_settings.display_name, yoksa Google meta verisi (full_name/name),
-- yoksa e-posta. Fotoğraf: avatar_url/picture. auth.users istemciye açılmaz.
-- =====================================================================
create or replace function public.friend_leaderboard(week_start date)
returns table (
  user_id         uuid,
  is_self         boolean,
  display_name    text,
  email           text,
  avatar_url      text,
  share_steps     boolean,
  share_sleep     boolean,
  share_calories  boolean,
  steps_today     bigint,
  steps_week      bigint,
  sleep_today     integer,
  sleep_week_avg  integer,
  kcal_today      numeric,
  kcal_week       numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_uid  uuid := auth.uid();
  v_week date := friend_leaderboard.week_start;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı' using errcode = '28000';
  end if;
  if v_week is null or extract(isodow from v_week) <> 1 then
    raise exception 'week_start Pazartesi olmalı: %', v_week using errcode = '22023';
  end if;

  return query
  with people as (
    select v_uid as pid, true as me
    union
    select case when f.user_a = v_uid then f.user_b else f.user_a end, false
    from public.friendships f
    where f.user_a = v_uid or f.user_b = v_uid
  ),
  base as (
    select p.pid, p.me,
           coalesce(to_jsonb(u) -> 'raw_user_meta_data', '{}'::jsonb) as meta,
           lower(btrim(u.email)) as mail,
           nullif(btrim(s.display_name), '') as dn,
           public.safe_timezone(s.timezone) as tz,
           p.me or coalesce(sh.share_steps, false) as sst,
           p.me or coalesce(sh.share_sleep, false) as ssl,
           p.me or coalesce(sh.share_calories, false) as sca
    from people p
    join auth.users u on u.id = p.pid
    left join public.user_settings s on s.user_id = p.pid
    left join public.friend_sharing sh on sh.user_id = p.pid
  ),
  b as (
    select x.*, (now() at time zone x.tz)::date as today
    from base x
  )
  select b.pid,
         b.me,
         coalesce(b.dn,
                  nullif(btrim(b.meta ->> 'full_name'), ''),
                  nullif(btrim(b.meta ->> 'name'), ''),
                  b.mail, '')::text,
         b.mail,
         coalesce(nullif(btrim(b.meta ->> 'avatar_url'), ''),
                  nullif(btrim(b.meta ->> 'picture'), ''))::text,
         b.sst, b.ssl, b.sca,
         case when b.sst then coalesce(h.st_today, 0) end,
         case when b.sst then coalesce(h.st_week, 0) end,
         case when b.ssl then coalesce(h.sl_today, 0) end,
         case when b.ssl then coalesce(h.sl_avg, 0) end,
         case when b.sca then coalesce(n.k_today, 0) end,
         case when b.sca then coalesce(n.k_week, 0) end
  from b
  left join lateral (
    select coalesce(sum(m.steps) filter (where m.metric_date = b.today), 0)::bigint as st_today,
           coalesce(sum(m.steps), 0)::bigint as st_week,
           coalesce(sum(m.sleep_minutes) filter (where m.metric_date = b.today), 0)::integer as sl_today,
           coalesce(round(avg(m.sleep_minutes) filter (where m.sleep_minutes > 0)), 0)::integer as sl_avg
    from public.daily_health_metrics m
    where (b.sst or b.ssl)
      and m.user_id = b.pid
      and m.metric_date between v_week and least(v_week + 6, b.today)
  ) h on true
  left join lateral (
    select coalesce(sum(nl.calories) filter (
             where (nl.eaten_at at time zone b.tz)::date = b.today), 0)::numeric as k_today,
           coalesce(sum(nl.calories), 0)::numeric as k_week
    from public.nutrition_logs nl
    where b.sca
      and nl.user_id = b.pid
      and nl.eaten_at >= v_week::timestamp at time zone b.tz
      and nl.eaten_at < (v_week + 7)::timestamp at time zone b.tz
  ) n on true
  order by b.me desc, b.pid;
end;
$$;

revoke all on function public.friend_leaderboard(date) from public, anon;
grant execute on function public.friend_leaderboard(date) to authenticated;
-- END friend_leaderboard
-- =====================================================================

-- =====================================================================
-- BEGIN Görev kategorileri (sürüm 7) — idempotent
--   * user_settings.task_categories: kullanıcının kategori listesi (jsonb
--     dizi: {name, icon, color, enabled, custom}); null = yerleşik liste
--     (İş, Ekip, Finans, Kişisel). RLS: mevcut owner-only user_settings
--     politikası sütunu kendiliğinden kapsar.
--   * tasks.category artık sabit listeyle sınırlı değil: 1..40 karakter
--     (kısıt yukarıdaki 'Pusholder' → 'İş' bölümünde kurulur; burada yalnızca
--     eski kısıt kaldıysa yeniden kurulur). 'Pusholder' tetikleyicisi aynen
--     çalışır.
-- =====================================================================
alter table public.user_settings
  add column if not exists task_categories jsonb;

alter table public.user_settings
  drop constraint if exists user_settings_task_categories_check;
alter table public.user_settings
  add constraint user_settings_task_categories_check
  check (
    task_categories is null
    or (jsonb_typeof(task_categories) = 'array'
        and jsonb_array_length(task_categories) <= 40)
  );

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.tasks'::regclass
      and conname = 'tasks_category_check'
      and pg_get_constraintdef(oid) like '%Ekip%'
  ) then
    alter table public.tasks drop constraint tasks_category_check;
    alter table public.tasks add constraint tasks_category_check
      check (char_length(btrim(category)) between 1 and 40);
  end if;
end;
$$;
-- END Görev kategorileri (sürüm 7)
