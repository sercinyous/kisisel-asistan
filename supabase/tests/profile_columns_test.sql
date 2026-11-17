-- Profil sütunları (Faz 4A): user_settings.height_cm, birth_year, sex.
--   * sütun türleri ve adlandırılmış check'ler (betik iki kez çalışsa da tek tane)
--   * sınır değerleri: boy 100..250, doğum yılı 1900..2100, cinsiyet 3 değer ya da null
--   * RLS: kullanıcı yalnızca kendi profilini yazar; anon erişemez; service_role okur
--   * uygulamanın yaptığı PostgREST upsert'i (boş profil null yazılır)
--   * yükseltmede mevcut ayar satırı korunur, profil alanları null başlar
-- Çalıştırma: supabase/tests/run_local.sh (temiz ve yükseltilmiş veritabanlarında).
-- Yükseltilmiş veritabanında ayrıca
--   -v fixture_user=<uuid> -v fixture_calories=<n>
-- verilir: o kullanıcının satırı ve daily_calories değeri yükseltmeden sonra aranır.
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- Kayıt kapısı (signup_invite_gate) bu testin fikstür kullanıcılarını
-- engellemesin; kapının kendisi signup_gate_test.sql'de sınanır.
alter table auth.users disable trigger signup_invite_gate;

insert into auth.users (id, email) values
  ('c1c1c1c1-0000-0000-0000-000000000001', 'profil-a@test'),
  ('c2c2c2c2-0000-0000-0000-000000000002', 'profil-b@test')
on conflict (id) do nothing;

-- 1) Şema -------------------------------------------------------------
do $$
declare
  v_col text;
  v_type text;
  v_expected text;
  v_count integer;
begin
  foreach v_col in array array['height_cm', 'birth_year', 'sex'] loop
    select data_type into v_type from information_schema.columns
    where table_schema = 'public' and table_name = 'user_settings'
      and column_name = v_col and is_nullable = 'YES' and column_default is null;
    if v_type is null then
      raise exception 'BAŞARISIZ: user_settings.% yok, NOT NULL ya da varsayılanlı', v_col;
    end if;
    v_expected := case v_col when 'sex' then 'text' else 'smallint' end;
    if v_type <> v_expected then
      raise exception 'BAŞARISIZ: user_settings.% türü % (beklenen %)',
        v_col, v_type, v_expected;
    end if;

    -- Betik iki kez çalıştı: her sütunda tam olarak bir check kalmalı.
    select count(*) into v_count from pg_constraint
    where conrelid = 'public.user_settings'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ~ ('\m' || v_col || '\M');
    if v_count <> 1 then
      raise exception 'BAŞARISIZ: % için % check var (1 olmalı)', v_col, v_count;
    end if;
    if not exists (
      select 1 from pg_constraint
      where conrelid = 'public.user_settings'::regclass
        and conname = 'user_settings_' || v_col || '_check'
    ) then
      raise exception 'BAŞARISIZ: user_settings_%_check adlı kısıt yok', v_col;
    end if;
  end loop;
  raise notice 'tamam: şema (tür, boş olabilir, tek ve adlandırılmış check)';
end;
$$;

-- 2) Yetkiler (sütun düzeyinde) ----------------------------------------
do $$
declare
  v_col text;
begin
  foreach v_col in array array['height_cm', 'birth_year', 'sex'] loop
    if not has_column_privilege('authenticated', 'public.user_settings', v_col, 'select')
       or not has_column_privilege('authenticated', 'public.user_settings', v_col, 'insert')
       or not has_column_privilege('authenticated', 'public.user_settings', v_col, 'update') then
      raise exception 'BAŞARISIZ: authenticated % sütununu okuyup yazamıyor', v_col;
    end if;
    if not has_column_privilege('service_role', 'public.user_settings', v_col, 'select') then
      raise exception 'BAŞARISIZ: service_role % sütununu okuyamıyor', v_col;
    end if;
    if has_column_privilege('anon', 'public.user_settings', v_col, 'select')
       or has_column_privilege('anon', 'public.user_settings', v_col, 'update') then
      raise exception 'BAŞARISIZ: anon % sütununa erişebiliyor', v_col;
    end if;
  end loop;
  raise notice 'tamam: yetkiler (authenticated yazar, service_role okur, anon yok)';
end;
$$;

-- 3) Sınırlar ve RLS ----------------------------------------------------
do $$
declare
  v_a constant uuid := 'c1c1c1c1-0000-0000-0000-000000000001';
  v_b constant uuid := 'c2c2c2c2-0000-0000-0000-000000000002';
  v_rows integer;
  v_height smallint;
  v_birth smallint;
  v_sex text;
  v_rejected boolean;
  v_denied boolean;
  v_val text;
begin
  -- Yeni kullanıcıların ayar satırı açılmış ve profil boş olmalı.
  select height_cm, birth_year, sex into v_height, v_birth, v_sex
  from public.user_settings where user_id = v_a;
  if not found then
    raise exception 'BAŞARISIZ: yeni kullanıcının ayar satırı açılmadı';
  end if;
  if v_height is not null or v_birth is not null or v_sex is not null then
    raise exception 'BAŞARISIZ: yeni satırda profil boş olmalı (%, %, %)',
      v_height, v_birth, v_sex;
  end if;

  perform set_config('request.jwt.claim.sub', v_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  -- Boy: 100 ve 250 kabul, 99 / 251 / 0 / -1 ret.
  foreach v_val in array array['100', '250', '180', 'null'] loop
    execute format('update public.user_settings set height_cm = %s where user_id = %L',
                   v_val, v_a);
  end loop;
  foreach v_val in array array['99', '251', '0', '-1', '32767'] loop
    v_rejected := false;
    begin
      execute format('update public.user_settings set height_cm = %s where user_id = %L',
                     v_val, v_a);
    exception when check_violation then
      v_rejected := true;
    end;
    if not v_rejected then
      raise exception 'BAŞARISIZ: height_cm = % kabul edildi', v_val;
    end if;
  end loop;

  -- Doğum yılı: 1900 ve 2100 kabul, 1899 / 2101 / 0 ret.
  foreach v_val in array array['1900', '2100', '1990', 'null'] loop
    execute format('update public.user_settings set birth_year = %s where user_id = %L',
                   v_val, v_a);
  end loop;
  foreach v_val in array array['1899', '2101', '0', '-1990'] loop
    v_rejected := false;
    begin
      execute format('update public.user_settings set birth_year = %s where user_id = %L',
                     v_val, v_a);
    exception when check_violation then
      v_rejected := true;
    end;
    if not v_rejected then
      raise exception 'BAŞARISIZ: birth_year = % kabul edildi', v_val;
    end if;
  end loop;

  -- Cinsiyet: üç değer ve null kabul; büyük harf, boş, Türkçe karşılık ret.
  foreach v_val in array array['''female''', '''male''', '''unspecified''', 'null'] loop
    execute format('update public.user_settings set sex = %s where user_id = %L',
                   v_val, v_a);
  end loop;
  foreach v_val in array array['''x''', '''''', '''Male''', '''FEMALE''', '''erkek''', '''other'''] loop
    v_rejected := false;
    begin
      execute format('update public.user_settings set sex = %s where user_id = %L',
                     v_val, v_a);
    exception when check_violation then
      v_rejected := true;
    end;
    if not v_rejected then
      raise exception 'BAŞARISIZ: sex = % kabul edildi', v_val;
    end if;
  end loop;

  -- Tam profil yazılır ve geri okunur.
  update public.user_settings
  set height_cm = 180, birth_year = 1990, sex = 'male'
  where user_id = v_a;
  select height_cm, birth_year, sex into v_height, v_birth, v_sex
  from public.user_settings where user_id = v_a;
  if v_height <> 180 or v_birth <> 1990 or v_sex <> 'male' then
    raise exception 'BAŞARISIZ: profil geri okunamadı (%, %, %)', v_height, v_birth, v_sex;
  end if;

  -- Bir ret, aynı satırdaki başka alanların yazımını da geri alır (tek deyim).
  v_rejected := false;
  begin
    update public.user_settings set height_cm = 175, sex = 'x' where user_id = v_a;
  exception when check_violation then
    v_rejected := true;
  end;
  select height_cm into v_height from public.user_settings where user_id = v_a;
  if not v_rejected or v_height <> 180 then
    raise exception 'BAŞARISIZ: geçersiz güncelleme kısmen uygulandı (boy %)', v_height;
  end if;

  -- RLS: A, B'nin profilini göremez ve yazamaz.
  update public.user_settings set height_cm = 150, sex = 'female' where user_id = v_b;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'BAŞARISIZ: A, B''nin profilini güncelledi (% satır)', v_rows;
  end if;
  select count(*) into v_rows from public.user_settings where user_id = v_b;
  if v_rows <> 0 then
    raise exception 'BAŞARISIZ: A, B''nin ayar satırını görebiliyor';
  end if;

  -- Uygulamanın PostgREST upsert'i (UserSettings.toMap + user_id): önce dolu,
  -- sonra boş profil. Boş profil null olarak yazılıp önceki değerleri temizler.
  insert into public.user_settings
    (user_id, start_weight_kg, target_weight_kg, daily_calories, daily_protein_g,
     daily_carbs_g, daily_fat_g, daily_steps, sleep_minutes, notifications_enabled,
     routine_notifications, monthly_lead_days, monthly_remind_time,
     event_remind_minutes, quiet_hours_enabled, quiet_start, quiet_end,
     team_members, height_cm, birth_year, sex)
  values
    (v_a, 84.5, 78, 2000, 170, 180, 65, 10000, 450, true, true, 3, '09:00', 30,
     true, '23:00', '07:30', '{Duhan}', 172, 1988, 'unspecified')
  on conflict (user_id) do update set
    start_weight_kg = excluded.start_weight_kg, target_weight_kg = excluded.target_weight_kg,
    daily_calories = excluded.daily_calories, daily_protein_g = excluded.daily_protein_g,
    daily_carbs_g = excluded.daily_carbs_g, daily_fat_g = excluded.daily_fat_g,
    daily_steps = excluded.daily_steps, sleep_minutes = excluded.sleep_minutes,
    notifications_enabled = excluded.notifications_enabled,
    routine_notifications = excluded.routine_notifications,
    monthly_lead_days = excluded.monthly_lead_days,
    monthly_remind_time = excluded.monthly_remind_time,
    event_remind_minutes = excluded.event_remind_minutes,
    quiet_hours_enabled = excluded.quiet_hours_enabled,
    quiet_start = excluded.quiet_start, quiet_end = excluded.quiet_end,
    team_members = excluded.team_members, height_cm = excluded.height_cm,
    birth_year = excluded.birth_year, sex = excluded.sex;
  select height_cm, birth_year, sex into v_height, v_birth, v_sex
  from public.user_settings where user_id = v_a;
  if v_height <> 172 or v_birth <> 1988 or v_sex <> 'unspecified' then
    raise exception 'BAŞARISIZ: upsert profili yazmadı (%, %, %)', v_height, v_birth, v_sex;
  end if;

  insert into public.user_settings
    (user_id, daily_calories, height_cm, birth_year, sex)
  values (v_a, 2000, null, null, null)
  on conflict (user_id) do update set
    daily_calories = excluded.daily_calories, height_cm = excluded.height_cm,
    birth_year = excluded.birth_year, sex = excluded.sex;
  select height_cm, birth_year, sex into v_height, v_birth, v_sex
  from public.user_settings where user_id = v_a;
  if v_height is not null or v_birth is not null or v_sex is not null then
    raise exception 'BAŞARISIZ: null upsert profili temizlemedi (%, %, %)',
      v_height, v_birth, v_sex;
  end if;

  -- RLS with check: A kendi satırı olarak B adına yazamaz.
  v_denied := false;
  begin
    insert into public.user_settings (user_id, height_cm) values (v_b, 170)
    on conflict (user_id) do update set height_cm = excluded.height_cm;
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'BAŞARISIZ: A, B adına profil upsert''i yapabildi';
  end if;
  reset role;

  -- B'nin satırı dokunulmamış.
  select height_cm, sex into v_height, v_sex
  from public.user_settings where user_id = v_b;
  if v_height is not null or v_sex is not null then
    raise exception 'BAŞARISIZ: B''nin profili değişti (%, %)', v_height, v_sex;
  end if;
  raise notice 'tamam: sınırlar, RLS ve upsert';

  -- anon okuyamaz.
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  v_denied := false;
  begin
    perform height_cm from public.user_settings;
  exception when insufficient_privilege then
    v_denied := true;
  end;
  reset role;
  if not v_denied then
    raise exception 'BAŞARISIZ: anon profil sütununu okuyabildi';
  end if;

  -- service_role (RLS'i aşar) profil sütunlarını okur.
  update public.user_settings
  set height_cm = 165, birth_year = 1995, sex = 'female' where user_id = v_b;
  set local role service_role;
  select height_cm, birth_year, sex into v_height, v_birth, v_sex
  from public.user_settings where user_id = v_b;
  reset role;
  if v_height <> 165 or v_birth <> 1995 or v_sex <> 'female' then
    raise exception 'BAŞARISIZ: service_role profili okuyamadı (%, %, %)',
      v_height, v_birth, v_sex;
  end if;
  raise notice 'tamam: anon engelli, service_role okur';
end;
$$;

-- 4) Yükseltme: mevcut satır korunur, profil alanları boş başlar --------
\if :{?fixture_user}
select set_config('t.fixture_user', :'fixture_user', false) as _ \gset
select set_config('t.fixture_calories', :'fixture_calories', false) as _ \gset
do $$
declare
  v_user constant uuid := current_setting('t.fixture_user')::uuid;
  v_calories constant integer := current_setting('t.fixture_calories')::integer;
  r public.user_settings;
begin
  select * into strict r from public.user_settings where user_id = v_user;
  if r.daily_calories <> v_calories then
    raise exception 'BAŞARISIZ: yükseltmede daily_calories bozuldu (% yerine %)',
      v_calories, r.daily_calories;
  end if;
  if r.height_cm is not null or r.birth_year is not null or r.sex is not null then
    raise exception 'BAŞARISIZ: yükseltilen satırda profil boş olmalı: %', to_jsonb(r);
  end if;

  -- Yükseltilen kullanıcı kendi profilini yazıp temizleyebilir.
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  update public.user_settings
  set height_cm = 181, birth_year = 1991, sex = 'male' where user_id = v_user;
  select * into strict r from public.user_settings where user_id = v_user;
  if r.height_cm <> 181 or r.birth_year <> 1991 or r.sex <> 'male'
     or r.daily_calories <> v_calories then
    raise exception 'BAŞARISIZ: yükseltilen satıra profil yazılamadı: %', to_jsonb(r);
  end if;
  update public.user_settings
  set height_cm = null, birth_year = null, sex = null where user_id = v_user;
  reset role;
  select * into strict r from public.user_settings where user_id = v_user;
  if r.height_cm is not null or r.birth_year is not null or r.sex is not null then
    raise exception 'BAŞARISIZ: profil temizlenemedi: %', to_jsonb(r);
  end if;
  raise notice 'tamam: yükseltmede satır korundu, profil null başladı';
end;
$$;
\endif

-- Temizlik: yalnızca bu testin kullanıcıları (ayar satırları cascade ile gider).
delete from auth.users
where id in ('c1c1c1c1-0000-0000-0000-000000000001',
             'c2c2c2c2-0000-0000-0000-000000000002');
\echo tamam: profil sutunlari testi gecti
