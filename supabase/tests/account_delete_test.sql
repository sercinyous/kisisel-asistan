-- Hesap silme (Faz 5): auth.users satırı silinince public şemada o kullanıcıya
-- ait hiçbir satır kalmamalı. delete-account Edge Function'ı önce arkadaş
-- bağlarını ve kullanıcıya gelen/giden istekleri siler, sonra auth kullanıcısını;
-- geri kalan her şey ON DELETE CASCADE ile gider. Bu test o sırayı taklit eder
-- ve tüm public tablolarındaki uuid sütunlarını dinamik tarar (sonradan eklenen
-- tablolar da kapsanır). Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

alter table auth.users disable trigger signup_invite_gate;
select tf.mkuser('d1000000-0000-0000-0000-000000000001', 'silinecek@example.com');
select tf.mkuser('d2000000-0000-0000-0000-000000000002', 'kalan@example.com');
alter table auth.users enable trigger signup_invite_gate;

-- 1) auth.users'a bağlı her FK kaskat olmalı (tek istisna: friend_requests.target_user
--    set null; o satırları Edge Function açıkça siler).
do $$
declare
  r record;
begin
  for r in
    select c.conrelid::regclass as tbl, a.attname as col, c.confdeltype
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.contype = 'f' and c.confrelid = 'auth.users'::regclass
      and c.connamespace = 'public'::regnamespace
  loop
    if r.confdeltype <> 'c'
       and not (r.tbl = 'public.friend_requests'::regclass and r.col = 'target_user') then
      raise exception 'BAŞARISIZ: %.% auth.users silinince kaskat değil (%)', r.tbl, r.col, r.confdeltype;
    end if;
  end loop;
  raise notice 'tamam: auth.users FK''ları kaskat';
end;
$$;

-- 2) Kullanıcının her türlü verisi.
insert into public.tasks (user_id, title) values ('d1000000-0000-0000-0000-000000000001', 'Görev');
insert into public.notes (user_id, title) values ('d1000000-0000-0000-0000-000000000001', 'Not');
insert into public.friend_sharing (user_id, share_steps)
  values ('d1000000-0000-0000-0000-000000000001', true) on conflict (user_id) do nothing;
insert into public.friendships (user_a, user_b)
  values ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002');
insert into public.friend_requests (from_user, target_email)
  values ('d1000000-0000-0000-0000-000000000001', 'baskasi@example.com');
insert into public.friend_requests (from_user, target_email, target_user)
  values ('d2000000-0000-0000-0000-000000000002', 'silinecek@example.com',
          'd1000000-0000-0000-0000-000000000001');
insert into public.app_errors (user_id, message) values ('d1000000-0000-0000-0000-000000000001', 'hata');
insert into public.feedback (user_id, message) values ('d1000000-0000-0000-0000-000000000001', 'not');

-- 3) Edge Function'ın açık silmeleri + auth kullanıcısının silinmesi.
delete from public.friendships
  where user_a = 'd1000000-0000-0000-0000-000000000001' or user_b = 'd1000000-0000-0000-0000-000000000001';
delete from public.friend_requests
  where from_user = 'd1000000-0000-0000-0000-000000000001'
     or target_user = 'd1000000-0000-0000-0000-000000000001'
     or target_email = 'silinecek@example.com';
delete from auth.users where id = 'd1000000-0000-0000-0000-000000000001';

-- 4) Hiçbir public tablo uuid sütununda bu kimlik kalmamalı; e-posta da.
do $$
declare
  r record;
  n bigint;
begin
  for r in
    select table_name, column_name, data_type
    from information_schema.columns
    where table_schema = 'public' and data_type in ('uuid', 'text')
      and table_name in (select table_name from information_schema.tables
                         where table_schema = 'public' and table_type = 'BASE TABLE')
  loop
    if r.data_type = 'uuid' then
      execute format('select count(*) from public.%I where %I = $1', r.table_name, r.column_name)
        into n using 'd1000000-0000-0000-0000-000000000001'::uuid;
    else
      execute format('select count(*) from public.%I where %I = $1', r.table_name, r.column_name)
        into n using 'silinecek@example.com';
    end if;
    if n > 0 then
      raise exception 'BAŞARISIZ: silinen kullanıcı public.%.% içinde kaldı (% satır)',
        r.table_name, r.column_name, n;
    end if;
  end loop;
  raise notice 'tamam: silinen kullanıcının public şemada satırı kalmadı';
end;
$$;

select tf.ok('diğer kullanıcının verisi duruyor',
  exists (select 1 from public.user_settings where user_id = 'd2000000-0000-0000-0000-000000000002'));
