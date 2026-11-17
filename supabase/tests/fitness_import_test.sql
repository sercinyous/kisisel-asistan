-- Google Health antrenman içe aktarımı: fitness_logs.source = 'google',
-- external_id ve (user_id, source, external_id) tekil dizini.
-- Uygulama PostgREST upsert'i ile yazar: on_conflict=user_id,source,external_id
-- + Prefer: resolution=ignore-duplicates, yani
--   insert ... on conflict (user_id, source, external_id) do nothing
-- Bu test aynı ifadeyi authenticated rolüyle (RLS açık) çalıştırır.
-- Çalıştırma: supabase/tests/run_local.sh (temiz ve yükseltilmiş veritabanında).
\set ON_ERROR_STOP on

-- Kayıt kapısı (signup_invite_gate) bu testin fikstür kullanıcılarını
-- engellemesin; kapının kendisi signup_gate_test.sql'de sınanır.
alter table auth.users disable trigger signup_invite_gate;

insert into auth.users (id, email) values
  ('f1f1f1f1-0000-0000-0000-000000000001', 'fi-a@test'),
  ('f2f2f2f2-0000-0000-0000-000000000002', 'fi-b@test')
on conflict (id) do nothing;

do $$
declare
  v_a constant uuid := 'f1f1f1f1-0000-0000-0000-000000000001';
  v_b constant uuid := 'f2f2f2f2-0000-0000-0000-000000000002';
  v_count integer;
  v_failed boolean;
begin
  -- Şema: source'u denetleyen tek check var ve adı sabit.
  select count(*) into v_count from pg_constraint
  where conrelid = 'public.fitness_logs'::regclass and contype = 'c'
    and conname <> 'fitness_logs_external_id_check'
    and pg_get_constraintdef(oid) ~ '\msource\M';
  if v_count <> 1 or not exists (
    select 1 from pg_constraint
    where conrelid = 'public.fitness_logs'::regclass
      and conname = 'fitness_logs_source_check'
      and pg_get_constraintdef(oid) like '%google%'
  ) then
    raise exception 'BAŞARISIZ: fitness_logs source check''i yanlış (% adet)', v_count;
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'fitness_logs_external_uidx'
      and indexdef like '%UNIQUE%' and indexdef like '%(user_id, source, external_id)%'
  ) then
    raise exception 'BAŞARISIZ: fitness_logs_external_uidx tekil dizini yok';
  end if;
  raise notice 'tamam: şema (source check, tekil dizin)';

  delete from public.fitness_logs where user_id in (v_a, v_b);

  -- A kullanıcısı: aynı Google antrenmanı iki eşitlemede iki kez gelir.
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  insert into public.fitness_logs
    (user_id, log_type, workout_type, title, duration_min, distance_km,
     calories_burned, logged_at, source, external_id)
  values
    (v_a, 'workout', 'running', 'Sabah koşusu', 38, 6.12, 402,
     '2026-11-16T04:05:00Z', 'google', 'ex-1'),
    (v_a, 'workout', 'weights', 'Ağırlık', 45, null, 310,
     '2026-11-16T16:30:00Z', 'google', 'ex-2')
  on conflict (user_id, source, external_id) do nothing;
  -- İkinci eşitleme: ex-1 tekrar (başlığı farklı) + yeni ex-3.
  insert into public.fitness_logs
    (user_id, log_type, workout_type, title, duration_min, logged_at, source, external_id)
  values
    (v_a, 'workout', 'running', 'Koşu (yeniden)', 39, '2026-11-16T04:05:00Z', 'google', 'ex-1'),
    (v_a, 'workout', 'other', 'Yürüyüş', 30, '2026-11-17T06:00:00Z', 'google', 'ex-3')
  on conflict (user_id, source, external_id) do nothing;
  -- Elle girilen iki kayıt (external_id boş) dizine takılmaz.
  insert into public.fitness_logs (log_type, workout_type, title, logged_at)
  values ('workout', 'running', 'Elle koşu', '2026-11-16T04:05:00Z'),
         ('workout', 'running', 'Elle koşu', '2026-11-16T04:05:00Z');
  reset role;

  select count(*) into v_count from public.fitness_logs
  where user_id = v_a and source = 'google';
  if v_count <> 3 then
    raise exception 'BAŞARISIZ: yeniden eşitleme kopya üretti (% google satırı)', v_count;
  end if;
  if (select title from public.fitness_logs
      where user_id = v_a and external_id = 'ex-1') <> 'Sabah koşusu' then
    raise exception 'BAŞARISIZ: var olan satır üzerine yazıldı';
  end if;
  select count(*) into v_count from public.fitness_logs
  where user_id = v_a and source = 'manual';
  if v_count <> 2 then
    raise exception 'BAŞARISIZ: external_id boş elle kayıtlar reddedildi (% satır)', v_count;
  end if;
  raise notice 'tamam: aynı kaynak kimliği ikinci kez yazılmaz, elle kayıtlar etkilenmez';

  -- B kullanıcısı aynı kaynak kimliğini kendi hesabına yazabilir.
  perform set_config('request.jwt.claim.sub', v_b::text, true);
  set local role authenticated;
  insert into public.fitness_logs
    (user_id, log_type, workout_type, logged_at, source, external_id)
  values (v_b, 'workout', 'running', '2026-11-16T04:05:00Z', 'google', 'ex-1')
  on conflict (user_id, source, external_id) do nothing;
  -- RLS: B, A'nın satırlarını görmez.
  select count(*) into v_count from public.fitness_logs;
  reset role;
  if v_count <> 1 then
    raise exception 'BAŞARISIZ: B kullanıcısı % satır görüyor (1 olmalı)', v_count;
  end if;
  raise notice 'tamam: tekillik kullanıcı başınadır, RLS korunur';

  -- Geçersiz kaynak ve elle kayıtta external_id reddedilir.
  v_failed := false;
  begin
    insert into public.fitness_logs (user_id, log_type, workout_type, source)
    values (v_a, 'workout', 'running', 'garmin');
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'BAŞARISIZ: tanımsız kaynak (garmin) kabul edildi';
  end if;
  v_failed := false;
  begin
    insert into public.fitness_logs (user_id, log_type, workout_type, source, external_id)
    values (v_a, 'workout', 'running', 'manual', 'ex-9');
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'BAŞARISIZ: elle kayıtta external_id kabul edildi';
  end if;
  v_failed := false;
  begin
    insert into public.fitness_logs (user_id, log_type, workout_type, source, external_id)
    values (v_a, 'workout', 'running', 'google', '');
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'BAŞARISIZ: boş external_id kabul edildi';
  end if;
  raise notice 'tamam: kaynak ve external_id check''leri';

  -- Rapor: içe aktarılan antrenmanlar yapılan antrenman sayısına girer.
  if (public.report_daily_metrics(v_a, '2026-11-16') #>> '{form,workouts_done}')::int <> 4 then
    raise exception 'BAŞARISIZ: günlük rapor Google antrenmanlarını saymadı: %',
      public.report_daily_metrics(v_a, '2026-11-16') -> 'form';
  end if;
  raise notice 'tamam: rapor içe aktarılan antrenmanları sayar';

  delete from public.fitness_logs where user_id in (v_a, v_b);
end;
$$;
\echo tamam: fitness_logs içe aktarma testleri geçti
