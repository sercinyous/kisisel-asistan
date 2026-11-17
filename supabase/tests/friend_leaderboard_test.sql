-- friend_leaderboard: yalnızca kabul edilmiş arkadaşlar + kendisi, paylaşım
-- anahtarına göre null, Google meta verisinden ad/fotoğraf, anon çağıramaz.
-- Çalıştırma: supabase/tests/run_local.sh (faz4b veritabanında).
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

-- Yerel taklitte yoksa Supabase'teki meta sütunu eklenir.
alter table auth.users add column if not exists raw_user_meta_data jsonb;

alter table auth.users disable trigger signup_invite_gate;
select tf.mkuser('f7100000-0000-0000-0000-000000000001', 'lb-sercan@example.com');
select tf.mkuser('f7200000-0000-0000-0000-000000000002', 'lb-deniz@example.com');
select tf.mkuser('f7300000-0000-0000-0000-000000000003', 'lb-yabanci@example.com');
alter table auth.users enable trigger signup_invite_gate;
update auth.users set raw_user_meta_data =
  '{"full_name": "Sercan Kılıç", "avatar_url": "https://example.com/s.png"}'
  where id = 'f7100000-0000-0000-0000-000000000001';
update auth.users set raw_user_meta_data = '{"name": "Deniz", "picture": "https://example.com/d.png"}'
  where id = 'f7200000-0000-0000-0000-000000000002';

insert into public.friendships (user_a, user_b)
values ('f7100000-0000-0000-0000-000000000001', 'f7200000-0000-0000-0000-000000000002');
insert into public.friend_sharing (user_id, share_steps, share_sleep, share_calories)
values ('f7200000-0000-0000-0000-000000000002', true, false, false)
on conflict (user_id) do update set share_steps = true, share_sleep = false, share_calories = false;
update public.user_settings set timezone = 'Europe/Istanbul'
  where user_id in ('f7100000-0000-0000-0000-000000000001', 'f7200000-0000-0000-0000-000000000002');

insert into public.daily_health_metrics (user_id, metric_date, steps, sleep_minutes)
select 'f7200000-0000-0000-0000-000000000002', d, 1000, 400
from generate_series(date_trunc('week', (now() at time zone 'Europe/Istanbul'))::date,
                     (now() at time zone 'Europe/Istanbul')::date, interval '1 day') d
on conflict (user_id, metric_date) do update set steps = 1000, sleep_minutes = 400;
insert into public.daily_health_metrics (user_id, metric_date, steps, sleep_minutes)
values ('f7100000-0000-0000-0000-000000000001', (now() at time zone 'Europe/Istanbul')::date, 5000, 420)
on conflict (user_id, metric_date) do update set steps = 5000, sleep_minutes = 420;
insert into public.daily_health_metrics (user_id, metric_date, steps)
values ('f7300000-0000-0000-0000-000000000003', (now() at time zone 'Europe/Istanbul')::date, 99999)
on conflict (user_id, metric_date) do update set steps = 99999;

do $$
declare
  me   uuid := 'f7100000-0000-0000-0000-000000000001';
  wk   date := date_trunc('week', (now() at time zone 'Europe/Istanbul'))::date;
  days integer := (now() at time zone 'Europe/Istanbul')::date - wk + 1;
  r    jsonb;
begin
  if has_function_privilege('anon', 'public.friend_leaderboard(date)', 'execute') then
    raise exception 'BAŞARISIZ: anon friend_leaderboard çalıştırabiliyor';
  end if;
  if not has_function_privilege('authenticated', 'public.friend_leaderboard(date)', 'execute') then
    raise exception 'BAŞARISIZ: authenticated friend_leaderboard çalıştıramıyor';
  end if;

  r := tf.run('authenticated', me, format(
    $q$select jsonb_agg(jsonb_build_object('id', user_id, 'self', is_self, 'name', display_name,
        'email', email, 'avatar', avatar_url, 'st', steps_today, 'sw', steps_week,
        'sl', sleep_today, 'kc', kcal_week) order by is_self desc)
       from public.friend_leaderboard(%L)$q$, wk));
  perform tf.eq('iki kişi (yabancı yok)', to_jsonb(jsonb_array_length(r)), '2');
  perform tf.eq('kendisi', r -> 0, jsonb_build_object(
    'id', me, 'self', true, 'name', 'Sercan Kılıç', 'email', 'lb-sercan@example.com',
    'avatar', 'https://example.com/s.png', 'st', 5000, 'sw', 5000, 'sl', 420, 'kc', 0));
  perform tf.eq('arkadaş: adım açık, uyku/kalori null', r -> 1, jsonb_build_object(
    'id', 'f7200000-0000-0000-0000-000000000002', 'self', false, 'name', 'Deniz',
    'email', 'lb-deniz@example.com', 'avatar', 'https://example.com/d.png',
    'st', 1000, 'sw', 1000 * days, 'sl', null, 'kc', null));

  begin
    perform tf.run('authenticated', me, format(
      $q$select to_jsonb(count(*)) from public.friend_leaderboard(%L)$q$, wk + 1));
    raise exception 'BAŞARISIZ: Pazartesi olmayan hafta kabul edildi';
  exception when sqlstate '22023' then
    raise notice 'tamam: Pazartesi kontrolü';
  end;
end;
$$;
