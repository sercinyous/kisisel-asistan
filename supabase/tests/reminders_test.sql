-- faz5_reminders testi: hatırlatıcılar ve "Yaptım" kayıtları yalnızca
-- sahibine açıktır; çapraz kullanıcı insert/update/done reddedilir.
-- Çalıştırma: supabase/tests/run_local.sh (auth_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;


create schema rt;

-- p_sql verilen kullanıcıyla (authenticated) çalışınca reddedilmeli ya da
-- hiçbir satırı etkilememelidir (RLS'in görünmez kıldığı update/delete).
create function rt.rejected(p_label text, p_uid uuid, p_sql text) returns void
language plpgsql as $$
declare
  v_state text := null;
  v_rows  integer := 0;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    get diagnostics v_rows = row_count;
  exception
    when foreign_key_violation or insufficient_privilege or check_violation then
      v_state := sqlstate;
  end;
  reset role;
  if v_state is null and v_rows > 0 then
    raise exception 'BAŞARISIZ: % — çapraz kullanıcı yazması kabul edildi', p_label;
  end if;
  raise notice 'tamam: % (sqlstate %, satır %)', p_label, coalesce(v_state, '-'), v_rows;
end;
$$;

create function rt.as_user(p_uid uuid, p_sql text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  execute p_sql;
  reset role;
end;
$$;

create function rt.count_as(p_uid uuid, p_sql text) returns bigint
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

grant usage on schema rt to authenticated;

begin;

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-00000000000a', 'rt-a@example.com'),
  ('b1000000-0000-0000-0000-00000000000b', 'rt-b@example.com');

-- A ve B kendi hatırlatıcılarını ekler (olumlu kontrol; user_id varsayılandır).
select rt.as_user('a1000000-0000-0000-0000-00000000000a',
  $q$insert into public.reminders (id, title, time_of_day, repeat)
     values ('a1000000-0000-0000-0000-0000000000a1', 'Su iç', '22:00', 'daily')$q$);
select rt.as_user('b1000000-0000-0000-0000-00000000000b',
  $q$insert into public.reminders (id, title, time_of_day, repeat, days_mask)
     values ('b1000000-0000-0000-0000-0000000000b1', 'İlaç', '09:00', 'custom', 5)$q$);
select rt.as_user('b1000000-0000-0000-0000-00000000000b',
  $q$insert into public.reminder_done (id, reminder_id, done_on)
     values ('b1000000-0000-0000-0000-0000000000d1', 'b1000000-0000-0000-0000-0000000000b1', '2026-11-18')$q$);

-- 1) B, A adına hatırlatıcı EKLEYEMEZ.
select rt.rejected('B, A adına hatırlatıcı ekleyemez', 'b1000000-0000-0000-0000-00000000000b',
  $q$insert into public.reminders (user_id, title, time_of_day)
     values ('a1000000-0000-0000-0000-00000000000a', 'Sahte', '10:00')$q$);

-- 2) B, A'nın hatırlatıcısını GÜNCELLEYEMEZ (görünmez: 0 satır).
select rt.rejected('B, A''nın hatırlatıcısını güncelleyemez', 'b1000000-0000-0000-0000-00000000000b',
  $q$update public.reminders set title = 'Ele geçirildi'
     where id = 'a1000000-0000-0000-0000-0000000000a1'$q$);

-- 3) B kendi hatırlatıcısını A'ya devredemez.
select rt.rejected('B, hatırlatıcısını A''ya devredemez', 'b1000000-0000-0000-0000-00000000000b',
  $q$update public.reminders set user_id = 'a1000000-0000-0000-0000-00000000000a'
     where id = 'b1000000-0000-0000-0000-0000000000b1'$q$);

-- 4) B, A'nın hatırlatıcısına kendi adıyla "Yaptım" yazamaz (bileşik FK).
select rt.rejected('B, A''nın hatırlatıcısına Yaptım yazamaz', 'b1000000-0000-0000-0000-00000000000b',
  $q$insert into public.reminder_done (user_id, reminder_id, done_on)
     values ('b1000000-0000-0000-0000-00000000000b', 'a1000000-0000-0000-0000-0000000000a1', '2026-11-18')$q$);

-- 5) B, A adına "Yaptım" yazamaz (RLS).
select rt.rejected('B, A adına Yaptım yazamaz', 'b1000000-0000-0000-0000-00000000000b',
  $q$insert into public.reminder_done (user_id, reminder_id, done_on)
     values ('a1000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-0000000000a1', '2026-11-18')$q$);

-- 6) B, kendi Yaptım kaydını A'nın hatırlatıcısına taşıyamaz.
select rt.rejected('B, Yaptım kaydını A''nın hatırlatıcısına taşıyamaz', 'b1000000-0000-0000-0000-00000000000b',
  $q$update public.reminder_done set reminder_id = 'a1000000-0000-0000-0000-0000000000a1'
     where id = 'b1000000-0000-0000-0000-0000000000d1'$q$);

-- 7) B, A'nın hatırlatıcısını silemez ve göremez.
select rt.rejected('B, A''nın hatırlatıcısını silemez', 'b1000000-0000-0000-0000-00000000000b',
  $q$delete from public.reminders where id = 'a1000000-0000-0000-0000-0000000000a1'$q$);
do $$
begin
  if rt.count_as('b1000000-0000-0000-0000-00000000000b',
       'select count(*) from public.reminders') <> 1 then
    raise exception 'BAŞARISIZ: B yalnızca kendi hatırlatıcısını görmeli';
  end if;
  if rt.count_as('a1000000-0000-0000-0000-00000000000a',
       'select count(*) from public.reminder_done') <> 0 then
    raise exception 'BAŞARISIZ: A, B''nin Yaptım kayıtlarını görmemeli';
  end if;
end;
$$;

-- 8) Kısıtlar: aynı gün iki kez Yaptım, tarihsiz "once", günsüz "custom",
-- 120 karakteri aşan başlık reddedilir.
select rt.rejected('aynı gün ikinci Yaptım reddedilir', 'b1000000-0000-0000-0000-00000000000b',
  $q$insert into public.reminder_done (reminder_id, done_on)
     values ('b1000000-0000-0000-0000-0000000000b1', '2026-11-18')
     on conflict do nothing$q$);
do $$
declare
  v_state text;
  v_sql   text;
begin
  foreach v_sql in array array[
    $q$insert into public.reminders (title, time_of_day, repeat) values ('x', '10:00', 'once')$q$,
    $q$insert into public.reminders (title, time_of_day, repeat, days_mask) values ('x', '10:00', 'custom', 0)$q$,
    format('insert into public.reminders (title, time_of_day) values (%L, ''10:00'')', repeat('a', 121))
  ]
  loop
    v_state := null;
    begin
      perform rt.as_user('a1000000-0000-0000-0000-00000000000a', v_sql);
    exception when check_violation then
      v_state := sqlstate;
    end;
    if v_state is null then
      raise exception 'BAŞARISIZ: kısıt ihlali kabul edildi: %', v_sql;
    end if;
  end loop;
  raise notice 'tamam: kısıtlar';
end;
$$;

-- 9) Hatırlatıcı silinince Yaptım kayıtları da silinir.
select rt.as_user('b1000000-0000-0000-0000-00000000000b',
  $q$delete from public.reminders where id = 'b1000000-0000-0000-0000-0000000000b1'$q$);
do $$
begin
  if exists (select 1 from public.reminder_done
             where reminder_id = 'b1000000-0000-0000-0000-0000000000b1') then
    raise exception 'BAŞARISIZ: silinen hatırlatıcının Yaptım kayıtları kaldı';
  end if;
  raise notice 'tamam: silme zinciri';
end;
$$;

-- 10) anon rolü tabloya erişemez.
do $$
declare
  v_state text := null;
begin
  set local role anon;
  begin
    perform 1 from public.reminders;
  exception when insufficient_privilege then
    v_state := sqlstate;
  end;
  reset role;
  if v_state is null then
    raise exception 'BAŞARISIZ: anon hatırlatıcıları okuyabildi';
  end if;
  raise notice 'tamam: anon erişemez';
end;
$$;

rollback;

drop schema rt cascade;
