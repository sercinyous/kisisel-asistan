-- Faz 4B şema değişiklikleri: yeni sütunlar, nötr varsayılanlar ve nötr seed,
-- 'Pusholder' → 'İş' (kısıtlar + eski uygulama sürümü için tetikleyici),
-- rapor kullanıcı listesi (yalnızca onboarded_at dolu), yetkiler.
-- Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

alter table auth.users disable trigger signup_invite_gate;
select tf.mkuser('b1000000-0000-0000-0000-000000000001', 'sema-a@example.com');
select tf.mkuser('b2000000-0000-0000-0000-000000000002', 'sema-b@example.com');
\set A '''b1000000-0000-0000-0000-000000000001'''
\set B '''b2000000-0000-0000-0000-000000000002'''

-- 1) Sütunlar ------------------------------------------------------------
do $$
declare
  v_col text;
  v_type text;
  v_expected text;
  v_count integer;
begin
  foreach v_col in array array['display_name', 'work_description', 'onboarded_at'] loop
    select data_type into v_type from information_schema.columns
    where table_schema = 'public' and table_name = 'user_settings'
      and column_name = v_col and is_nullable = 'YES' and column_default is null;
    if v_type is null then
      raise exception 'BAŞARISIZ: user_settings.% yok, NOT NULL ya da varsayılanlı', v_col;
    end if;
    v_expected := case v_col when 'onboarded_at' then 'timestamp with time zone' else 'text' end;
    if v_type <> v_expected then
      raise exception 'BAŞARISIZ: user_settings.% türü % (beklenen %)', v_col, v_type, v_expected;
    end if;
  end loop;
  -- Betik iki kez çalıştı: metin sütunlarında tam olarak bir check kalmalı.
  foreach v_col in array array['display_name', 'work_description'] loop
    select count(*) into v_count from pg_constraint
    where conrelid = 'public.user_settings'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ~ ('\m' || v_col || '\M');
    if v_count <> 1 then
      raise exception 'BAŞARISIZ: % için % check var (1 olmalı)', v_col, v_count;
    end if;
  end loop;
  raise notice 'tamam: yeni sütunlar (tür, boş olabilir, tek check)';
end;
$$;

-- 2) Yeni hesap: nötr varsayılanlar, nötr seed ---------------------------
select tf.eq('yeni hesabın ayar satırı nötr varsayılanlarla açılır',
  (select to_jsonb(s) - 'user_id' - 'updated_at' - 'timezone' - 'quiet_start' - 'quiet_end'
          - 'monthly_remind_time' from public.user_settings s where s.user_id = :A),
  '{"start_weight_kg": 70, "target_weight_kg": 70, "daily_calories": 2000, "daily_protein_g": 120,
    "daily_carbs_g": 220, "daily_fat_g": 65, "daily_steps": 8000, "sleep_minutes": 450,
    "notifications_enabled": true, "routine_notifications": true, "monthly_lead_days": 3,
    "event_remind_minutes": 30, "quiet_hours_enabled": true, "team_members": [],
    "height_cm": null, "birth_year": null, "sex": null,
    "display_name": null, "work_description": null, "onboarded_at": null,
    "task_categories": null, "health_source": null, "daily_water_ml": 2000,
    "activity_level": null}'::jsonb);
select tf.eq('yeni hesaba rutin/görev/not/tartı/öğün/ekip yüklenmez',
  (select to_jsonb(
     (select count(*) from public.routines where user_id = :A)
   + (select count(*) from public.tasks where user_id = :A)
   + (select count(*) from public.notes where user_id = :A)
   + (select count(*) from public.fitness_logs where user_id = :A)
   + (select count(*) from public.nutrition_logs where user_id = :A))),
  '0'::jsonb);

-- seed işlevi yinelenince ve veri varken hiçbir şey eklemez/silmez/değiştirmez.
select tf.run('authenticated', :A, $q$select to_jsonb(count(*)) from (
  select public.quick_add_entries('{"tasks":[{"title":"kendi görevim"}],"notes":[{"title":"n"}]}'::jsonb)) z$q$);
select public.seed_personal_assistant(:A::uuid);
select public.seed_personal_assistant(:A::uuid);
select tf.eq('seed tekrar çalışınca kullanıcının verisine dokunmaz',
  (select to_jsonb((select count(*) from public.tasks where user_id = :A)
                 + (select count(*) from public.notes where user_id = :A)
                 + (select count(*) from public.routines where user_id = :A)
                 + (select count(*) from public.user_settings where user_id = :A))),
  '3'::jsonb);
update public.user_settings set daily_steps = 12345 where user_id = :A;
select public.seed_personal_assistant(:A::uuid);
select tf.eq('seed mevcut ayar satırını ezmez',
  (select to_jsonb(daily_steps) from public.user_settings where user_id = :A), '12345'::jsonb);
update public.user_settings set daily_steps = 8000 where user_id = :A;
select tf.ok('seed işlevini istemci çalıştıramaz',
  not has_function_privilege('authenticated', 'public.seed_personal_assistant(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.seed_personal_assistant(uuid)', 'execute'));

-- 3) Metin sütunu sınırları ----------------------------------------------
select tf.eq('görünen ad 60 karakter kabul',
  tf.run('authenticated', :A, $q$with u as (update public.user_settings
    set display_name = repeat('a', 60) where user_id = auth.uid() returning 1)
    select to_jsonb(count(*)) from u$q$), '1'::jsonb);
select tf.fails('görünen ad 61 karakter reddedilir', 'authenticated', :A,
  $q$with u as (update public.user_settings set display_name = repeat('a', 61)
     where user_id = auth.uid() returning 1) select to_jsonb(count(*)) from u$q$, '23514');
select tf.eq('iş tanımı 500 karakter kabul',
  tf.run('authenticated', :A, $q$with u as (update public.user_settings
    set work_description = repeat('b', 500) where user_id = auth.uid() returning 1)
    select to_jsonb(count(*)) from u$q$), '1'::jsonb);
select tf.fails('iş tanımı 501 karakter reddedilir', 'authenticated', :A,
  $q$with u as (update public.user_settings set work_description = repeat('b', 501)
     where user_id = auth.uid() returning 1) select to_jsonb(count(*)) from u$q$, '23514');
select tf.eq('kullanıcı kendi onboarded_at değerini yazar',
  tf.run('authenticated', :A, $q$with u as (update public.user_settings
    set onboarded_at = now(), display_name = null, work_description = null
    where user_id = auth.uid() returning 1) select to_jsonb(count(*)) from u$q$), '1'::jsonb);
select tf.eq('başkasının ayar satırı güncellenmez (0 satır)',
  tf.run('authenticated', :A, $q$with u as (update public.user_settings
    set display_name = 'x' where user_id = 'b2000000-0000-0000-0000-000000000002' returning 1)
    select to_jsonb(count(*)) from u$q$), '0'::jsonb);

-- 4) 'Pusholder' → 'İş' ---------------------------------------------------
select tf.ok('kısıtlarda Pusholder kalmadı, İş var; her sütunda tek check',
  -- tasks.category sürüm 7'den beri serbesttir (görev kategorileri); yalnızca
  -- notlarda sabit liste kalır.
  (select bool_and(pg_get_constraintdef(c.oid) not like '%Pusholder%' and pg_get_constraintdef(c.oid) like '%İş%')
   from pg_constraint c
   where c.conrelid = 'public.notes'::regclass
     and c.contype = 'c' and pg_get_constraintdef(c.oid) ~ '\mcategory\M')
  and (select bool_and(pg_get_constraintdef(c.oid) not like '%Pusholder%')
       from pg_constraint c
       where c.conrelid = 'public.tasks'::regclass
         and c.contype = 'c' and pg_get_constraintdef(c.oid) ~ '\mcategory\M')
  and (select bool_and(pg_get_constraintdef(c.oid) not like '%Pusholder%' and pg_get_constraintdef(c.oid) like '%İş%')
       from pg_constraint c
       where c.conrelid = 'public.routines'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) ~ '\mscope\M')
  and (select count(*) from pg_constraint c
       where c.conrelid = 'public.tasks'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) ~ '\mcategory\M') = 1
  and (select count(*) from pg_constraint c
       where c.conrelid = 'public.notes'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) ~ '\mcategory\M') = 1
  and (select count(*) from pg_constraint c
       where c.conrelid = 'public.routines'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) ~ '\mscope\M') = 1);

-- Yeni yapı 'İş' yazar; eski TestFlight yapısı 'Pusholder' yazarsa 'İş'e çevrilir.
select tf.run('authenticated', :A, $q$with i as (
  insert into public.tasks (title, category) values ('yeni-is', 'İş'), ('eski-yapi', 'Pusholder') returning 1)
  select to_jsonb(count(*)) from i$q$);
select tf.run('authenticated', :A, $q$with i as (
  insert into public.notes (title, category) values ('eski-not', 'Pusholder'), ('yeni-not', 'İş') returning 1)
  select to_jsonb(count(*)) from i$q$);
select tf.run('authenticated', :A, $q$with i as (
  insert into public.routines (title, scope) values ('eski-rutin', 'Pusholder'), ('yeni-rutin', 'İş') returning 1)
  select to_jsonb(count(*)) from i$q$);
select tf.eq('eski yapının Pusholder yazdığı görev/not/rutin İş olarak saklanır',
  (select to_jsonb(array[
     (select category from public.tasks where user_id = :A and title = 'eski-yapi'),
     (select category from public.notes where user_id = :A and title = 'eski-not'),
     (select scope from public.routines where user_id = :A and title = 'eski-rutin')])),
  '["İş", "İş", "İş"]'::jsonb);

-- Güncelleme yolu: önce başka değere, sonra 'Pusholder'a çevrilmeye çalışılır.
select tf.run('authenticated', :A, $q$with u as (update public.tasks set category = 'Kişisel' where title = 'eski-yapi' returning 1)
  select to_jsonb(count(*)) from u$q$);
select tf.run('authenticated', :A, $q$with u as (update public.tasks set category = 'Pusholder' where title = 'eski-yapi' returning 1)
  select to_jsonb(count(*)) from u$q$);
select tf.run('authenticated', :A, $q$with u as (update public.notes set category = 'Fikir' where title = 'eski-not' returning 1)
  select to_jsonb(count(*)) from u$q$);
select tf.run('authenticated', :A, $q$with u as (update public.notes set category = 'Pusholder' where title = 'eski-not' returning 1)
  select to_jsonb(count(*)) from u$q$);
select tf.run('authenticated', :A, $q$with u as (update public.routines set scope = 'Kişisel' where title = 'eski-rutin' returning 1)
  select to_jsonb(count(*)) from u$q$);
select tf.run('authenticated', :A, $q$with u as (update public.routines set scope = 'Pusholder' where title = 'eski-rutin' returning 1)
  select to_jsonb(count(*)) from u$q$);
select tf.eq('güncellemede de Pusholder İş olur',
  (select to_jsonb(array[
     (select category from public.tasks where user_id = :A and title = 'eski-yapi'),
     (select category from public.notes where user_id = :A and title = 'eski-not'),
     (select scope from public.routines where user_id = :A and title = 'eski-rutin')])),
  '["İş", "İş", "İş"]'::jsonb);

-- quick_add_entries (eski yapının AI girişi) de aynı yoldan geçer.
select tf.run('authenticated', :A, $q$select to_jsonb(count(*)) from (select public.quick_add_entries(
  '{"tasks":[{"title":"ai-eski","category":"Pusholder"}],
    "notes":[{"title":"ai-eski-not","category":"Pusholder"}],
    "routines":[{"title":"ai-eski-rutin","scope":"Pusholder","category":"operasyon","frequency":"weekly"}]}'::jsonb)) z$q$);
select tf.eq('quick_add_entries Pusholder yollarını İş''e çevirir',
  (select to_jsonb(array[
     (select category from public.tasks where user_id = :A and title = 'ai-eski'),
     (select category from public.notes where user_id = :A and title = 'ai-eski-not'),
     (select scope from public.routines where user_id = :A and title = 'ai-eski-rutin')])),
  '["İş", "İş", "İş"]'::jsonb);
select tf.ok('veritabanında hiç Pusholder değeri yok',
  not exists (select 1 from public.tasks where category = 'Pusholder')
  and not exists (select 1 from public.notes where category = 'Pusholder')
  and not exists (select 1 from public.routines where scope = 'Pusholder'));

-- Bilinmeyen değer yine reddedilir.
-- Görev kategorisi sürüm 7'den beri kullanıcı tanımlıdır: boş ad reddedilir.
select tf.fails('boş görev kategorisi reddedilir', 'authenticated', :A,
  $q$insert into public.tasks (title, category) values ('x', ' ') returning to_jsonb(id)$q$, '23514');
select tf.fails('bilinmeyen not kategorisi reddedilir', 'authenticated', :A,
  $q$insert into public.notes (title, category) values ('x', 'Bilinmeyen') returning to_jsonb(id)$q$, '23514');
select tf.fails('bilinmeyen rutin kapsamı reddedilir', 'authenticated', :A,
  $q$insert into public.routines (title, scope) values ('x', 'Bilinmeyen') returning to_jsonb(id)$q$, '23514');
select tf.ok('geçiş tetikleyici işlevini istemci çalıştıramaz',
  not has_function_privilege('authenticated', 'public.normalize_legacy_pusholder()', 'execute')
  and not has_function_privilege('anon', 'public.normalize_legacy_pusholder()', 'execute'));

-- 5) Rapor zamanlayıcısı: service_role yalnızca onboarded_at dolu kullanıcıları seçer -
-- (Edge Function generate-reports user_settings'i service_role ile okur ve
-- onboarded_at boş olanları atlar; sütunun service_role'e okunur olması şarttır.)
select tf.ok('service_role onboarded_at sütununu okur, anon okuyamaz',
  has_column_privilege('service_role', 'public.user_settings', 'onboarded_at', 'select')
  and not has_column_privilege('anon', 'public.user_settings', 'onboarded_at', 'select'));
update public.user_settings set onboarded_at = now() where user_id = :A;
update public.user_settings set onboarded_at = null where user_id = :B;
select tf.eq('service_role: yalnızca ilk kurulumunu bitirmiş kullanıcılar seçilir',
  tf.run('service_role', null,
    $q$select jsonb_agg(s.user_id order by s.user_id) from public.user_settings s
       where s.onboarded_at is not null
         and s.user_id in ('b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002')$q$),
  '["b1000000-0000-0000-0000-000000000001"]'::jsonb);
update public.user_settings set onboarded_at = now() where user_id = :B;

-- 6) Politikalar ----------------------------------------------------------
select tf.eq('yeni tablolardaki politikalar',
  (select jsonb_agg(tablename || '.' || policyname || '.' || cmd order by tablename, policyname)
   from pg_policies
   where schemaname = 'public' and tablename in ('friend_requests', 'friendships', 'friend_sharing', 'ai_usage')),
  '["ai_usage.ai_usage_owner_select.SELECT", "friend_requests.friend_requests_sender_select.SELECT",
    "friend_sharing.friend_sharing_owner_all.ALL", "friendships.friendships_member_select.SELECT"]'::jsonb);

\echo tamam: Faz 4B şema testleri geçti
