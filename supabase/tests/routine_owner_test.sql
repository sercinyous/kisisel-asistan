-- routine_owner_fk testi: rutin tamamlaması yalnızca sahibinin rutinine
-- bağlanabilir (insert ve update) ve rapor yabancı satırları saymaz.
-- İki gerçek kullanıcı, authenticated rolü + RLS ile çalışır.
-- Çalıştırma: supabase/tests/run_local.sh (auth_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;

alter table auth.users disable trigger signup_invite_gate;

create schema ro;

-- p_sql verilen kullanıcıyla (authenticated) çalışınca reddedilmelidir.
create function ro.rejected(p_label text, p_uid uuid, p_sql text) returns void
language plpgsql as $$
declare
  v_state text := null;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    execute p_sql;
  exception when foreign_key_violation or insufficient_privilege then
    v_state := sqlstate;
  end;
  reset role;
  if v_state is null then
    raise exception 'BAŞARISIZ: % — çapraz kullanıcı yazması kabul edildi', p_label;
  end if;
  raise notice 'tamam: % (sqlstate %)', p_label, v_state;
end;
$$;

create function ro.as_user(p_uid uuid, p_sql text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  execute p_sql;
  reset role;
end;
$$;

grant usage on schema ro to authenticated;

begin;

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-00000000000a', 'ro-a@example.com'),
  ('b0000000-0000-0000-0000-00000000000b', 'ro-b@example.com');

insert into public.routines (id, user_id, title, category, frequency, days_of_week, is_active, created_at)
values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-00000000000a',
   'A rutini', 'operasyon', 'weekly', '{1,2,3,4,5,6,7}', true, '2026-09-01 09:00+00'),
  ('b0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-00000000000b',
   'B rutini', 'operasyon', 'weekly', '{1,2,3,4,5,6,7}', true, '2026-09-01 09:00+00');

-- B kendi rutinine yazabilir (olumlu kontrol).
select ro.as_user('b0000000-0000-0000-0000-00000000000b',
  $q$insert into public.routine_completions (id, user_id, routine_id, completed_on)
     values ('b0000000-0000-0000-0000-0000000000c1', 'b0000000-0000-0000-0000-00000000000b',
             'b0000000-0000-0000-0000-0000000000b1', '2026-09-28')$q$);

-- 1) Çapraz insert: B, A'nın routine_id'si + kendi user_id'si.
select ro.rejected('B, A''nın rutinine tamamlama EKLEYEMEZ', 'b0000000-0000-0000-0000-00000000000b',
  $q$insert into public.routine_completions (user_id, routine_id, completed_on)
     values ('b0000000-0000-0000-0000-00000000000b', 'a0000000-0000-0000-0000-0000000000a1', '2026-09-29')$q$);

-- 2) Çapraz update: B kendi satırını A'nın rutinine yönlendiremez.
select ro.rejected('B, tamamlamasını A''nın rutinine TAŞIYAMAZ', 'b0000000-0000-0000-0000-00000000000b',
  $q$update public.routine_completions set routine_id = 'a0000000-0000-0000-0000-0000000000a1'
     where id = 'b0000000-0000-0000-0000-0000000000c1'$q$);

-- A aynı dönemi engelsiz işaretleyebilir.
select ro.as_user('a0000000-0000-0000-0000-00000000000a',
  $q$insert into public.routine_completions (user_id, routine_id, completed_on)
     values ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', '2026-09-29')$q$);

-- 3) Rapor: FK'dan önce oluşmuş eski bir yabancı satırı taklit et (FK
-- tetikleyicileri replica modunda atlanır), sonra A'nın raporu onu saymamalı.
delete from public.routine_completions
 where routine_id = 'a0000000-0000-0000-0000-0000000000a1';
set local session_replication_role = replica;
insert into public.routine_completions (user_id, routine_id, completed_on)
values ('b0000000-0000-0000-0000-00000000000b', 'a0000000-0000-0000-0000-0000000000a1', '2026-09-30');
set local session_replication_role = origin;

do $$
declare
  v jsonb := public.report_daily_metrics('a0000000-0000-0000-0000-00000000000a', '2026-09-30');
begin
  if (v -> 'work' ->> 'routines_planned')::int is distinct from 1
     or (v -> 'work' ->> 'routines_done')::int is distinct from 0 then
    raise exception 'BAŞARISIZ: rapor yabancı tamamlamayı saydı: planned=% done=%',
      v -> 'work' ->> 'routines_planned', v -> 'work' ->> 'routines_done';
  end if;
  raise notice 'tamam: rapor yabancı tamamlamayı saymaz (planned=1, done=0)';
end;
$$;

rollback;

drop schema ro cascade;
alter table auth.users enable trigger signup_invite_gate;
