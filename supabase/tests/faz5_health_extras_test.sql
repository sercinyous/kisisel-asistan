-- =====================================================================
-- faz5_health_extras testi: water_logs ve weekly_checkins sahip RLS'si,
-- kısıtlar ve user_settings.daily_water_ml varsayılanı.
-- Çalıştırma: supabase/tests/run_local.sh (auth_stub.sql + schema.sql sonrası).
-- =====================================================================
\set ON_ERROR_STOP on
set client_min_messages = notice;


create schema fhx;

create function fhx.as_user(p_uid uuid, p_sql text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  execute p_sql;
  reset role;
end;
$$;

create function fhx.count_as(p_uid uuid, p_sql text) returns bigint
language plpgsql as $$
declare
  v bigint;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  return v;
end;
$$;

-- Kullanıcı olarak çalışınca reddedilmeli (RLS ya da kısıt).
create function fhx.rejected(p_label text, p_uid uuid, p_sql text) returns void
language plpgsql as $$
declare
  v_state text := null;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    execute p_sql;
  exception when insufficient_privilege or check_violation or unique_violation then
    v_state := sqlstate;
  end;
  reset role;
  if v_state is null then
    raise exception 'BAŞARISIZ: % — kabul edildi', p_label;
  end if;
  raise notice 'tamam: % (sqlstate %)', p_label, v_state;
end;
$$;

grant usage on schema fhx to authenticated;

begin;

insert into auth.users (id, email) values
  ('a5000000-0000-0000-0000-00000000000a', 'fhx-a@example.com'),
  ('b5000000-0000-0000-0000-00000000000b', 'fhx-b@example.com');

-- Su hedefi varsayılanı.
insert into public.user_settings (user_id) values ('a5000000-0000-0000-0000-00000000000a')
  on conflict (user_id) do nothing;
do $$
begin
  if (select daily_water_ml from public.user_settings
      where user_id = 'a5000000-0000-0000-0000-00000000000a') <> 2000 then
    raise exception 'BAŞARISIZ: daily_water_ml varsayılanı 2000 değil';
  end if;
end;
$$;

-- Sahip kendi su kaydını ekler ve okur.
select fhx.as_user('a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.water_logs (logged_on, ml) values ('2026-11-16', 250), ('2026-11-16', 500)$q$);
do $$
begin
  if fhx.count_as('a5000000-0000-0000-0000-00000000000a',
       'select coalesce(sum(ml), 0) from public.water_logs') <> 750 then
    raise exception 'BAŞARISIZ: A kendi su toplamını göremiyor';
  end if;
  if fhx.count_as('b5000000-0000-0000-0000-00000000000b',
       'select count(*) from public.water_logs') <> 0 then
    raise exception 'BAŞARISIZ: B, A''nın su kayıtlarını görüyor';
  end if;
end;
$$;

-- Çapraz kullanıcı yazması ve sınır dışı değerler reddedilir.
select fhx.rejected('B, A adına su kaydı ekleyemez',
  'b5000000-0000-0000-0000-00000000000b',
  $q$insert into public.water_logs (user_id, logged_on, ml)
     values ('a5000000-0000-0000-0000-00000000000a', '2026-11-16', 250)$q$);
select fhx.rejected('ml 0 reddedilir', 'a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.water_logs (logged_on, ml) values ('2026-11-16', 0)$q$);
select fhx.rejected('ml 3001 reddedilir', 'a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.water_logs (logged_on, ml) values ('2026-11-16', 3001)$q$);

-- B'nin silmesi A'nın satırlarına dokunmaz.
select fhx.as_user('b5000000-0000-0000-0000-00000000000b',
  $q$delete from public.water_logs$q$);
do $$
begin
  if (select count(*) from public.water_logs
      where user_id = 'a5000000-0000-0000-0000-00000000000a') <> 2 then
    raise exception 'BAŞARISIZ: B, A''nın su kayıtlarını sildi';
  end if;
end;
$$;

-- Haftalık check-in.
select fhx.as_user('a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.weekly_checkins (week_start, mood, note)
     values ('2026-11-16', 4, 'İyi hafta')$q$);
select fhx.rejected('aynı hafta iki check-in', 'a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.weekly_checkins (week_start, mood) values ('2026-11-16', 3)$q$);
select fhx.rejected('mood 6 reddedilir', 'a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.weekly_checkins (week_start, mood) values ('2026-11-23', 6)$q$);
select fhx.rejected('not 501 karakter reddedilir', 'a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.weekly_checkins (week_start, mood, note)
     values ('2026-11-23', 3, repeat('x', 501))$q$);
select fhx.rejected('pazartesi olmayan week_start reddedilir',
  'a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.weekly_checkins (week_start, mood) values ('2026-11-18', 3)$q$);
select fhx.rejected('B, A adına check-in ekleyemez',
  'b5000000-0000-0000-0000-00000000000b',
  $q$insert into public.weekly_checkins (user_id, week_start, mood)
     values ('a5000000-0000-0000-0000-00000000000a', '2026-11-23', 2)$q$);

-- B, A'nın check-in'ini göremez ve güncelleyemez.
select fhx.as_user('b5000000-0000-0000-0000-00000000000b',
  $q$update public.weekly_checkins set mood = 1$q$);
do $$
begin
  if fhx.count_as('b5000000-0000-0000-0000-00000000000b',
       'select count(*) from public.weekly_checkins') <> 0 then
    raise exception 'BAŞARISIZ: B, A''nın check-in''ini görüyor';
  end if;
  if (select mood from public.weekly_checkins
      where user_id = 'a5000000-0000-0000-0000-00000000000a') <> 4 then
    raise exception 'BAŞARISIZ: B, A''nın check-in''ini değiştirdi';
  end if;
end;
$$;

-- Sahip güncelleyebilir (upsert yolu).
select fhx.as_user('a5000000-0000-0000-0000-00000000000a',
  $q$insert into public.weekly_checkins (week_start, mood, note)
     values ('2026-11-16', 2, 'Yorucu')
     on conflict (user_id, week_start) do update
       set mood = excluded.mood, note = excluded.note$q$);
do $$
begin
  if (select mood from public.weekly_checkins
      where user_id = 'a5000000-0000-0000-0000-00000000000a') <> 2 then
    raise exception 'BAŞARISIZ: check-in upsert çalışmadı';
  end if;
end;
$$;

-- anon hiçbir şey okuyamaz.
do $$
declare
  v_state text := null;
begin
  set local role anon;
  begin
    perform 1 from public.water_logs;
  exception when insufficient_privilege then
    v_state := sqlstate;
  end;
  reset role;
  if v_state is null then
    raise exception 'BAŞARISIZ: anon water_logs okuyabildi';
  end if;
end;
$$;

rollback;

drop schema fhx cascade;
\echo 'tamam: faz5_health_extras'
