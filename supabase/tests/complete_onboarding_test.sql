-- complete_onboarding: ilk kurulum tek transaction'da ve işlem anahtarıyla
-- idempotent.
--   * aynı op_key ile iki çağrı → tek tartı, tek rutin seti, aynı sonuç
--   * bir adım düşerse (geçersiz kilo) hiçbir şey yazılmaz, anahtar kaydolmaz
--   * oturumsuz çağrı reddedilir; başka kullanıcının işlem satırı görünmez
-- Çalıştırma: supabase/tests/run_local.sh
\set ON_ERROR_STOP on
set client_min_messages = notice;

insert into auth.users (id, email) values
  ('c0c0c0c0-0000-0000-0000-000000000001', 'kurulum-a@test'),
  ('c0c0c0c0-0000-0000-0000-000000000002', 'kurulum-b@test')
on conflict (id) do nothing;

do $$
declare
  v_a     uuid := 'c0c0c0c0-0000-0000-0000-000000000001';
  v_b     uuid := 'c0c0c0c0-0000-0000-0000-000000000002';
  v_key   uuid := '11111111-2222-4333-8444-555555555555';
  v_bad   uuid := '66666666-2222-4333-8444-555555555555';
  v_body  jsonb := jsonb_build_object(
    'weight_kg', 80.5,
    'routines', jsonb_build_array(
      jsonb_build_object('title', 'Yürüyüş yap', 'scope', 'Kişisel',
        'category', 'spor', 'frequency', 'weekly',
        'days_of_week', jsonb_build_array(1,2,3,4,5,6,7), 'time_of_day', '07:30',
        'notify', true, 'is_active', true, 'sort_order', 0),
      jsonb_build_object('title', 'Kirayı öde', 'scope', 'Kişisel',
        'category', 'finans', 'frequency', 'monthly', 'day_of_month', 1,
        'days_of_week', jsonb_build_array(1,2,3,4,5,6,7), 'time_of_day', null,
        'notify', true, 'is_active', true, 'sort_order', 1)),
    'settings', jsonb_build_object(
      'start_weight_kg', 80.5, 'target_weight_kg', 75, 'daily_calories', 1900,
      'daily_protein_g', 144, 'daily_carbs_g', 190, 'daily_fat_g', 60,
      'daily_steps', 9000, 'sleep_minutes', 450, 'notifications_enabled', true,
      'quiet_start', '23:00', 'quiet_end', '07:30', 'team_members', jsonb_build_array(),
      'height_cm', 180, 'birth_year', 1990, 'sex', 'male', 'display_name', 'Ayşe',
      'work_description', null, 'onboarded_at', '2026-11-17T09:00:00Z'));
  v_r1 jsonb;
  v_r2 jsonb;
  v_n  integer;
  v_rejected boolean;
begin
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  -- Başarısız deneme: kilo check'i düşer → rutin/ayar/anahtar da yazılmaz.
  v_rejected := false;
  begin
    perform public.complete_onboarding(jsonb_set(v_body, '{weight_kg}', '999'), v_bad);
  exception when check_violation then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'BAŞARISIZ: geçersiz kilo reddedilmedi';
  end if;
  if exists (select 1 from public.fitness_logs where user_id = v_a)
     or exists (select 1 from public.routines where user_id = v_a)
     or exists (select 1 from public.onboarding_ops where user_id = v_a and op_key is not null)
     or exists (select 1 from public.user_settings where user_id = v_a and onboarded_at is not null) then
    raise exception 'BAŞARISIZ: yarım kurulum kısmen yazıldı';
  end if;

  v_r1 := public.complete_onboarding(v_body, v_key);
  v_r2 := public.complete_onboarding(v_body, v_key);

  select count(*) into v_n from public.fitness_logs
  where user_id = v_a and log_type = 'weight';
  if v_n <> 1 then
    raise exception 'BAŞARISIZ: aynı anahtarla iki çağrı % tartı satırı yazdı (1 olmalı)', v_n;
  end if;
  select count(*) into v_n from public.routines where user_id = v_a;
  if v_n <> 2 then
    raise exception 'BAŞARISIZ: rutin sayısı % (2 olmalı)', v_n;
  end if;
  if v_r1 is distinct from v_r2 then
    raise exception 'BAŞARISIZ: tekrar çağrı farklı sonuç döndürdü';
  end if;
  if (v_r1 -> 'settings' ->> 'onboarded_at') is null
     or (v_r1 -> 'settings' ->> 'daily_calories')::int <> 1900
     or (v_r1 -> 'settings' ->> 'display_name') <> 'Ayşe' then
    raise exception 'BAŞARISIZ: ayar satırı beklenen değerde değil: %', v_r1;
  end if;
  if (select time_of_day from public.routines where user_id = v_a and title = 'Yürüyüş yap')
     is distinct from '07:30'::time then
    raise exception 'BAŞARISIZ: rutin saati yazılmadı';
  end if;

  -- B, A'nın işlem satırını göremez; kendi çağrısı ayrı sayılır.
  perform set_config('request.jwt.claim.sub', v_b::text, true);
  select count(*) into v_n from public.onboarding_ops where user_id = v_a;
  if v_n <> 0 then
    raise exception 'BAŞARISIZ: B, A''nın işlem satırını gördü';
  end if;
  perform public.complete_onboarding(v_body, v_key);
  select count(*) into v_n from public.fitness_logs where log_type = 'weight';
  if v_n <> 1 then
    raise exception 'BAŞARISIZ: B, A''nın tartısını gördü ya da kendi tartısı yazılmadı (%)', v_n;
  end if;

  -- Oturumsuz çağrı reddedilir.
  perform set_config('request.jwt.claim.sub', '', true);
  v_rejected := false;
  begin
    perform public.complete_onboarding(v_body, gen_random_uuid());
  exception when invalid_authorization_specification then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'BAŞARISIZ: oturumsuz çağrı kabul edildi';
  end if;

  reset role;
  if (select count(*) from public.fitness_logs
      where user_id = v_a and log_type = 'weight') <> 1 then
    raise exception 'BAŞARISIZ: A için tek tartı satırı olmalı';
  end if;
  raise notice 'tamam: complete_onboarding (aynı anahtar → tek tartı)';
end;
$$;

-- anon çalıştıramaz.
do $$
begin
  if has_function_privilege('anon', 'public.complete_onboarding(jsonb, uuid)', 'execute') then
    raise exception 'BAŞARISIZ: anon complete_onboarding çalıştırabiliyor';
  end if;
  if not has_function_privilege('authenticated', 'public.complete_onboarding(jsonb, uuid)', 'execute') then
    raise exception 'BAŞARISIZ: authenticated complete_onboarding çalıştıramıyor';
  end if;
end;
$$;

-- Sonraki testler kullanıcı sayısına baktığı için test kullanıcıları silinir
-- (ayar, tartı, rutin ve işlem satırları cascade ile gider).
delete from auth.users
where id in ('c0c0c0c0-0000-0000-0000-000000000001',
             'c0c0c0c0-0000-0000-0000-000000000002');
