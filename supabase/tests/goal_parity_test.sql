-- SQL ↔ Dart eşlik testi (Faz 4B): hedef tutturma kuralları.
-- supabase/tests/goal_vectors.json dosyasını test/friend_goal_parity_test.dart
-- (GoalRules) da okur. Burada aynı vektörler iki yoldan sınanır:
--   1) goal_steps_hit / goal_sleep_hit / goal_calories_hit doğrudan,
--   2) uçtan uca: veri tabloya yazılır, friend_goal_summary sayar.
-- Ayrıca bitmemiş "bugün", gelecek günler ve arkadaşın saat dilimi sınanır.
-- Ortam: GOAL_VECTORS = goal_vectors.json yolu (run_local.sh verir).
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

\set vectors `cat "$GOAL_VECTORS"`
select set_config('tf.vectors', :'vectors', false) is not null as yuklendi \gset

alter table auth.users disable trigger signup_invite_gate;
select tf.mkuser('d1000000-0000-0000-0000-000000000001', 'esleme-izleyen@example.com');
select tf.mkuser('d2000000-0000-0000-0000-000000000002', 'esleme-arkadas@example.com');
insert into public.friendships (user_a, user_b)
values ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002');
insert into public.friend_sharing (user_id, share_steps, share_sleep, share_calories)
values ('d2000000-0000-0000-0000-000000000002', true, true, true);

-- 1) Doğrudan işlev vektörleri ----------------------------------------------
do $$
declare
  v jsonb := current_setting('tf.vectors')::jsonb;
  e jsonb;
  got boolean;
  n integer := 0;
begin
  for e in select * from jsonb_array_elements(v -> 'steps') loop
    got := public.goal_steps_hit((e ->> 'value')::bigint, (e ->> 'target')::integer);
    if got is distinct from (e ->> 'hit')::boolean then
      raise exception 'BAŞARISIZ: goal_steps_hit(%) = %, beklenen %', e, got, e -> 'hit';
    end if;
    n := n + 1;
  end loop;
  for e in select * from jsonb_array_elements(v -> 'sleep') loop
    got := public.goal_sleep_hit((e ->> 'value')::bigint, (e ->> 'target')::integer);
    if got is distinct from (e ->> 'hit')::boolean then
      raise exception 'BAŞARISIZ: goal_sleep_hit(%) = %, beklenen %', e, got, e -> 'hit';
    end if;
    n := n + 1;
  end loop;
  for e in select * from jsonb_array_elements(v -> 'calories') loop
    got := public.goal_calories_hit((e ->> 'value')::numeric, (e ->> 'target')::integer);
    if got is distinct from (e ->> 'hit')::boolean then
      raise exception 'BAŞARISIZ: goal_calories_hit(%) = %, beklenen %', e, got, e -> 'hit';
    end if;
    n := n + 1;
  end loop;
  -- null girdi hiçbir zaman tutmaz.
  if public.goal_steps_hit(null, 8000) or public.goal_sleep_hit(null, 450)
     or public.goal_calories_hit(null, 2000) or public.goal_steps_hit(9000, null) then
    raise exception 'BAŞARISIZ: null girdi tuttu';
  end if;
  raise notice 'tamam: % doğrudan vektör (SQL işlevleri)', n;
end;
$$;

-- 2) Uçtan uca: her vektör bir günlük veriye çevrilip özet işleviyle sayılır ----
do $$
declare
  c_viewer constant uuid := 'd1000000-0000-0000-0000-000000000001';
  c_friend constant uuid := 'd2000000-0000-0000-0000-000000000002';
  c_week   constant date := '2026-01-05'; -- Pazartesi, tamamen geçmiş hafta
  v jsonb := current_setting('tf.vectors')::jsonb;
  e jsonb;
  r jsonb;
  has_data boolean;
  exp_goal integer;
  exp_data integer;
  n integer := 0;
begin
  for e in select * from jsonb_array_elements(v -> 'steps') loop
    continue when coalesce((e ->> 'direct_only')::boolean, false);
    delete from public.daily_health_metrics where user_id = c_friend;
    update public.user_settings set daily_steps = (e ->> 'target')::integer where user_id = c_friend;
    insert into public.daily_health_metrics (user_id, metric_date, steps)
    values (c_friend, c_week, (e ->> 'value')::integer);
    has_data := (e ->> 'value')::integer > 0;
    exp_data := case when has_data then 1 else 0 end;
    exp_goal := case when has_data and (e ->> 'hit')::boolean then 1 else 0 end;
    r := tf.run('authenticated', c_viewer, format(
      $q$select to_jsonb(s) from public.friend_goal_summary(%L, %L) s where s.metric = 'steps'$q$,
      c_friend, c_week));
    if r is distinct from jsonb_build_object('metric', 'steps', 'shared', true,
         'goal_days', exp_goal, 'data_days', exp_data) then
      raise exception 'BAŞARISIZ: uçtan uca steps vektörü % → %', e, r;
    end if;
    n := n + 1;
  end loop;

  for e in select * from jsonb_array_elements(v -> 'sleep') loop
    continue when coalesce((e ->> 'direct_only')::boolean, false);
    delete from public.daily_health_metrics where user_id = c_friend;
    update public.user_settings set sleep_minutes = (e ->> 'target')::integer where user_id = c_friend;
    insert into public.daily_health_metrics (user_id, metric_date, sleep_minutes)
    values (c_friend, c_week, (e ->> 'value')::integer);
    has_data := (e ->> 'value')::integer > 0;
    exp_data := case when has_data then 1 else 0 end;
    exp_goal := case when has_data and (e ->> 'hit')::boolean then 1 else 0 end;
    r := tf.run('authenticated', c_viewer, format(
      $q$select to_jsonb(s) from public.friend_goal_summary(%L, %L) s where s.metric = 'sleep'$q$,
      c_friend, c_week));
    if r is distinct from jsonb_build_object('metric', 'sleep', 'shared', true,
         'goal_days', exp_goal, 'data_days', exp_data) then
      raise exception 'BAŞARISIZ: uçtan uca sleep vektörü % → %', e, r;
    end if;
    n := n + 1;
  end loop;

  for e in select * from jsonb_array_elements(v -> 'calories') loop
    continue when coalesce((e ->> 'direct_only')::boolean, false);
    delete from public.nutrition_logs where user_id = c_friend;
    update public.user_settings set daily_calories = (e ->> 'target')::integer where user_id = c_friend;
    -- Öğün kaydı varsa gün "veri var" sayılır (kalori 0 olsa bile).
    insert into public.nutrition_logs (user_id, food_name, calories, eaten_at)
    values (c_friend, 'vektör', (e ->> 'value')::numeric, '2026-01-05 12:00+03');
    exp_data := 1;
    exp_goal := case when (e ->> 'hit')::boolean then 1 else 0 end;
    r := tf.run('authenticated', c_viewer, format(
      $q$select to_jsonb(s) from public.friend_goal_summary(%L, %L) s where s.metric = 'calories'$q$,
      c_friend, c_week));
    if r is distinct from jsonb_build_object('metric', 'calories', 'shared', true,
         'goal_days', exp_goal, 'data_days', exp_data) then
      raise exception 'BAŞARISIZ: uçtan uca calories vektörü % → %', e, r;
    end if;
    n := n + 1;
  end loop;

  delete from public.daily_health_metrics where user_id = c_friend;
  delete from public.nutrition_logs where user_id = c_friend;
  update public.user_settings
     set daily_steps = 8000, sleep_minutes = 450, daily_calories = 2000
   where user_id = c_friend;
  raise notice 'tamam: % uçtan uca vektör (friend_goal_summary)', n;
end;
$$;

-- Kalori günü, 1 ondalıklı satırların toplamıdır (numeric toplam tam; kayan nokta yok).
do $$
declare
  c_viewer constant uuid := 'd1000000-0000-0000-0000-000000000001';
  c_friend constant uuid := 'd2000000-0000-0000-0000-000000000002';
  r jsonb;
begin
  -- 333.9 + 663.9 + 872.2 = 1870.0 tam (hedef 2200 → %85 = 1870 tutar).
  update public.user_settings set daily_calories = 2200 where user_id = c_friend;
  insert into public.nutrition_logs (user_id, food_name, calories, eaten_at) values
    (c_friend, 'a', 333.9, '2026-01-05 08:00+03'),
    (c_friend, 'b', 663.9, '2026-01-05 13:00+03'),
    (c_friend, 'c', 872.2, '2026-01-05 20:00+03');
  r := tf.run('authenticated', c_viewer, format(
    $q$select to_jsonb(s) from public.friend_goal_summary(%L, '2026-01-05') s where s.metric = 'calories'$q$, c_friend));
  if r is distinct from '{"metric":"calories","shared":true,"goal_days":1,"data_days":1}'::jsonb then
    raise exception 'BAŞARISIZ: 1 ondalıklı satırların toplamı yanlış tarafa düştü: %', r;
  end if;
  delete from public.nutrition_logs where user_id = c_friend;
  update public.user_settings set daily_calories = 2000 where user_id = c_friend;
  raise notice 'tamam: kalori toplamı tam numeric';
end;
$$;

-- 3) Bugün "devam ediyor", gelecek günler girmez; arkadaşın saat dilimi --------
-- Hafta (arkadaşın saat diliminde) Pazartesi'den bugüne kadar sayılır. Beklenen
-- değer burada bağımsız hesaplanır: bugünden önceki veri günleri paydada,
-- bugün yalnızca hedefi tutturduysa, sonraki günler hiç.
do $$
declare
  c_viewer constant uuid := 'd1000000-0000-0000-0000-000000000001';
  c_friend constant uuid := 'd2000000-0000-0000-0000-000000000002';
  tz text;
  today date;
  k integer;        -- bugünün hafta içi indeksi (Pzt = 0)
  monday date;
  today_hit boolean;
  i integer;
  d date;
  exp_goal integer;
  exp_data integer;
  r jsonb;
begin
  foreach tz in array array['Europe/Istanbul', 'Pacific/Kiritimati', 'Pacific/Pago_Pago', 'UTC'] loop
    foreach today_hit in array array[true, false] loop
      update public.user_settings set timezone = tz, daily_steps = 8000, sleep_minutes = 450,
        daily_calories = 2000 where user_id = c_friend;
      delete from public.daily_health_metrics where user_id = c_friend;
      delete from public.nutrition_logs where user_id = c_friend;

      today := (now() at time zone tz)::date;
      k := extract(isodow from today)::integer - 1;
      monday := today - k;
      exp_goal := 0;
      exp_data := 0;

      for i in 0..6 loop
        d := monday + i;
        -- Tüm haftaya veri yazılır (gelecek günler dahil): çift gün tutar, tek gün tutmaz;
        -- bugün today_hit'e göre.
        insert into public.daily_health_metrics (user_id, metric_date, steps, sleep_minutes)
        values (c_friend, d,
          case when (case when i = k then today_hit else i % 2 = 0 end) then 9000 else 2000 end,
          case when (case when i = k then today_hit else i % 2 = 0 end) then 480 else 100 end);
        insert into public.nutrition_logs (user_id, food_name, calories, eaten_at)
        values (c_friend, 'g', case when (case when i = k then today_hit else i % 2 = 0 end) then 2000 else 500 end,
                ((d::timestamp + interval '12 hours') at time zone tz));
        if i < k then
          exp_data := exp_data + 1;
          if i % 2 = 0 then exp_goal := exp_goal + 1; end if;
        elsif i = k and today_hit then
          exp_data := exp_data + 1;
          exp_goal := exp_goal + 1;
        end if;
      end loop;

      r := tf.run('authenticated', c_viewer, format(
        $q$select jsonb_agg(to_jsonb(s)) from public.friend_goal_summary(%L, %L) s$q$, c_friend, monday));
      if r is distinct from jsonb_build_array(
           jsonb_build_object('metric', 'steps', 'shared', true, 'goal_days', exp_goal, 'data_days', exp_data),
           jsonb_build_object('metric', 'sleep', 'shared', true, 'goal_days', exp_goal, 'data_days', exp_data),
           jsonb_build_object('metric', 'calories', 'shared', true, 'goal_days', exp_goal, 'data_days', exp_data)) then
        raise exception 'BAŞARISIZ: tz=% bugün_tutar=% pzt=% beklenen %/% gelen %',
          tz, today_hit, monday, exp_goal, exp_data, r;
      end if;

      -- Gelecek hafta: tüm günler gelecek, 0/0 (paylaşılıyor).
      r := tf.run('authenticated', c_viewer, format(
        $q$select jsonb_agg(to_jsonb(s)) from public.friend_goal_summary(%L, %L) s$q$, c_friend, monday + 7));
      if r is distinct from jsonb_build_array(
           '{"metric":"steps","shared":true,"goal_days":0,"data_days":0}'::jsonb,
           '{"metric":"sleep","shared":true,"goal_days":0,"data_days":0}'::jsonb,
           '{"metric":"calories","shared":true,"goal_days":0,"data_days":0}'::jsonb) then
        raise exception 'BAŞARISIZ: gelecek hafta sayıldı (tz=%): %', tz, r;
      end if;
    end loop;
  end loop;

  update public.user_settings set timezone = 'Europe/Istanbul' where user_id = c_friend;
  delete from public.daily_health_metrics where user_id = c_friend;
  delete from public.nutrition_logs where user_id = c_friend;
  raise notice 'tamam: bugün devam ediyor, gelecek günler, saat dilimi (4 dilim × 2 durum)';
end;
$$;

-- Önceki haftalar tamamen sayılır (bitmemiş gün yok); sınır günü Pazar gecesi/Pazartesi
-- sabahı saat dilimine göre ayrışır.
do $$
declare
  c_viewer constant uuid := 'd1000000-0000-0000-0000-000000000001';
  c_friend constant uuid := 'd2000000-0000-0000-0000-000000000002';
  r jsonb;
begin
  update public.user_settings set timezone = 'Pacific/Kiritimati' where user_id = c_friend;
  -- 2026-01-04 (Pazar) 23:30 UTC = Kiritimati'de 2026-01-05 (Pazartesi) 13:30 → Pazartesi'ye yazılır;
  -- 2026-01-11 (Pazar) 09:00 UTC = Kiritimati'de 2026-01-11 23:00 → o hafta, son gün.
  insert into public.nutrition_logs (user_id, food_name, calories, eaten_at) values
    (c_friend, 'pzt', 2000, '2026-01-04 23:30+00'),
    (c_friend, 'paz', 2000, '2026-01-11 09:00+00'),
    (c_friend, 'sonraki-hafta', 2000, '2026-01-11 11:00+00'); -- Kiritimati'de 12 Oca 01:00 → sonraki hafta
  r := tf.run('authenticated', c_viewer, format(
    $q$select to_jsonb(s) from public.friend_goal_summary(%L, '2026-01-05') s where s.metric = 'calories'$q$, c_friend));
  if r is distinct from '{"metric":"calories","shared":true,"goal_days":2,"data_days":2}'::jsonb then
    raise exception 'BAŞARISIZ: arkadaşın saat diliminde hafta sınırı yanlış: %', r;
  end if;
  delete from public.nutrition_logs where user_id = c_friend;
  update public.user_settings set timezone = 'Europe/Istanbul' where user_id = c_friend;
  raise notice 'tamam: arkadaşın saat diliminde Pazartesi–Pazar sınırı';
end;
$$;

\echo tamam: SQL-Dart eşlik testi (SQL tarafı) geçti
