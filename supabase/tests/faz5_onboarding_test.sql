-- faz5_onboarding: user_settings.activity_level ve complete_onboarding'in
-- profil (boy, doğum yılı, cinsiyet, hareket düzeyi) ve saat dilimi yazımı.
--   * sütun check'leri: boy 100..250, cinsiyet female/male/unspecified/null,
--     hareket düzeyi beş değerden biri ya da null
--   * RPC profili ve geçerli saat dilimini tek çağrıda yazar; aynı op_key ile
--     tekrar çağrı aynı sonucu döndürür
--   * geçersiz saat dilimi tüm kurulumu geri alır; saat dilimi verilmezse
--     mevcut değer korunur
-- Çalıştırma: supabase/tests/run_local.sh
\set ON_ERROR_STOP on
set client_min_messages = notice;

alter table auth.users disable trigger signup_invite_gate;
insert into auth.users (id, email) values
  ('f5f5f5f5-0000-0000-0000-000000000001', 'faz5-a@test'),
  ('f5f5f5f5-0000-0000-0000-000000000002', 'faz5-b@test')
on conflict (id) do nothing;
alter table auth.users enable trigger signup_invite_gate;

-- Şema: sütunlar ve check'ler.
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'user_settings'
                   and column_name = 'activity_level' and is_nullable = 'YES') then
    raise exception 'BAŞARISIZ: user_settings.activity_level yok ya da not null';
  end if;
  insert into public.user_settings (user_id) values
    ('f5f5f5f5-0000-0000-0000-000000000002') on conflict do nothing;
  if (select activity_level from public.user_settings
      where user_id = 'f5f5f5f5-0000-0000-0000-000000000002') is not null then
    raise exception 'BAŞARISIZ: activity_level varsayılanı null olmalı';
  end if;
  -- Dart UserSettings.defaults() ile aynı varsayılanlar.
  if (select (daily_protein_g, daily_carbs_g, daily_steps)
      from public.user_settings
      where user_id = 'f5f5f5f5-0000-0000-0000-000000000002')
     is distinct from (120, 220, 8000) then
    raise exception 'BAŞARISIZ: protein/karbonhidrat/adım varsayılanları 120/220/8000 değil';
  end if;

  begin
    update public.user_settings set activity_level = 'lazy'
    where user_id = 'f5f5f5f5-0000-0000-0000-000000000002';
    raise exception 'BAŞARISIZ: geçersiz activity_level kabul edildi';
  exception when check_violation then null;
  end;
  begin
    update public.user_settings set height_cm = 99
    where user_id = 'f5f5f5f5-0000-0000-0000-000000000002';
    raise exception 'BAŞARISIZ: 99 cm boy kabul edildi';
  exception when check_violation then null;
  end;
  begin
    update public.user_settings set height_cm = 251
    where user_id = 'f5f5f5f5-0000-0000-0000-000000000002';
    raise exception 'BAŞARISIZ: 251 cm boy kabul edildi';
  exception when check_violation then null;
  end;
  begin
    update public.user_settings set sex = 'other'
    where user_id = 'f5f5f5f5-0000-0000-0000-000000000002';
    raise exception 'BAŞARISIZ: geçersiz cinsiyet kabul edildi';
  exception when check_violation then null;
  end;
  update public.user_settings
     set activity_level = 'very_active', height_cm = 100, sex = null
   where user_id = 'f5f5f5f5-0000-0000-0000-000000000002';
  update public.user_settings
     set activity_level = null, height_cm = 250
   where user_id = 'f5f5f5f5-0000-0000-0000-000000000002';
  raise notice 'tamam: activity_level ve profil check''leri';
end;
$$;

-- RPC: profil + saat dilimi, idempotent, geri alma.
do $$
declare
  v_a    uuid := 'f5f5f5f5-0000-0000-0000-000000000001';
  v_key  uuid := 'f5000000-2222-4333-8444-555555555555';
  v_bad  uuid := 'f5000000-9999-4333-8444-555555555555';
  v_body jsonb := jsonb_build_object(
    'weight_kg', 72.4,
    'timezone', 'Europe/Berlin',
    'routines', jsonb_build_array(),
    'settings', jsonb_build_object(
      'start_weight_kg', 72.4, 'target_weight_kg', 70, 'daily_calories', 2100,
      'daily_protein_g', 116, 'daily_carbs_g', 240, 'daily_fat_g', 63,
      'daily_steps', 8000, 'sleep_minutes', 450,
      'height_cm', 176, 'birth_year', 1994, 'sex', 'unspecified',
      'activity_level', 'moderate', 'display_name', 'Deniz',
      'onboarded_at', '2026-11-18T08:00:00Z'));
  v_r1 jsonb;
  v_r2 jsonb;
  v_rejected boolean;
begin
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  -- Geçersiz saat dilimi: hiçbir şey yazılmaz.
  v_rejected := false;
  begin
    perform public.complete_onboarding(
      jsonb_set(v_body, '{timezone}', '"Mars/Olympus"'), v_bad);
  exception when invalid_parameter_value then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'BAŞARISIZ: geçersiz saat dilimi reddedilmedi';
  end if;
  if exists (select 1 from public.fitness_logs where user_id = v_a)
     or exists (select 1 from public.user_settings
                where user_id = v_a and onboarded_at is not null) then
    raise exception 'BAŞARISIZ: geçersiz saat dilimiyle kurulum kısmen yazıldı';
  end if;

  -- Geçersiz hareket düzeyi: check düşer.
  v_rejected := false;
  begin
    perform public.complete_onboarding(
      jsonb_set(v_body, '{settings,activity_level}', '"lazy"'), v_bad);
  exception when check_violation then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'BAŞARISIZ: geçersiz hareket düzeyi reddedilmedi';
  end if;

  v_r1 := public.complete_onboarding(v_body, v_key);
  v_r2 := public.complete_onboarding(
    jsonb_set(v_body, '{timezone}', '"Asia/Tokyo"'), v_key);
  if v_r1 is distinct from v_r2 then
    raise exception 'BAŞARISIZ: aynı anahtarla tekrar çağrı farklı sonuç döndürdü';
  end if;
  if (v_r1 -> 'settings' ->> 'height_cm')::int <> 176
     or (v_r1 -> 'settings' ->> 'birth_year')::int <> 1994
     or (v_r1 -> 'settings' ->> 'sex') <> 'unspecified'
     or (v_r1 -> 'settings' ->> 'activity_level') <> 'moderate'
     or (v_r1 -> 'settings' ->> 'timezone') <> 'Europe/Berlin' then
    raise exception 'BAŞARISIZ: profil/saat dilimi yazılmadı: %', v_r1;
  end if;
  if (select timezone from public.user_settings where user_id = v_a)
     <> 'Europe/Berlin' then
    raise exception 'BAŞARISIZ: tekrar çağrı saat dilimini değiştirdi';
  end if;
  if (select count(*) from public.fitness_logs where user_id = v_a) <> 1 then
    raise exception 'BAŞARISIZ: tek tartı satırı olmalı';
  end if;

  -- Saat dilimi gönderilmeyen yeni kurulum mevcut dilimi korur.
  perform public.complete_onboarding(v_body - 'timezone', gen_random_uuid());
  if (select timezone from public.user_settings where user_id = v_a)
     <> 'Europe/Berlin' then
    raise exception 'BAŞARISIZ: saat dilimi gönderilmeden değişti';
  end if;
  reset role;
  raise notice 'tamam: complete_onboarding profil, hareket düzeyi ve saat dilimi';
end;
$$;

delete from auth.users
where id in ('f5f5f5f5-0000-0000-0000-000000000001',
             'f5f5f5f5-0000-0000-0000-000000000002');
