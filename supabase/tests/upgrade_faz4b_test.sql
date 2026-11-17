-- Eski sürümden (v2 ya da v3) Faz 4B şemasına yükseltmeden SONRA: sahibin
-- mevcut verisi ve hesabı bozulmadan duruyor mu?
--   * onboarded_at mevcut hesapta dolu (kılavuza zorlanmaz) ve updated_at ezilmedi
--   * eski varsayılanlı ayar satırı değişmedi (nötr varsayılan yalnızca yeni satırlar)
--   * seed verisi (rutin/görev/not/tartı) olduğu gibi duruyor, yalnızca
--     'Pusholder' → 'İş' taşındı (updated_at bozulmadan)
-- Çalıştırma: run_local.sh, -v fixture_user=<uuid> ile.
\set ON_ERROR_STOP on
set client_min_messages = notice;

select set_config('tf.fixture_user', :'fixture_user', false) is not null as yuklendi \gset

do $$
declare
  v_user constant uuid := current_setting('tf.fixture_user')::uuid;
  r record;
  v_count integer;
begin
  select * into strict r from public.user_settings where user_id = v_user;
  if r.onboarded_at is null then
    raise exception 'BAŞARISIZ: mevcut hesap kılavuza zorlanıyor (onboarded_at boş)';
  end if;
  if r.updated_at >= r.onboarded_at then
    raise exception 'BAŞARISIZ: toplu onboarded_at yazısı updated_at''i ezdi (% >= %)',
      r.updated_at, r.onboarded_at;
  end if;
  if r.display_name is not null or r.work_description is not null then
    raise exception 'BAŞARISIZ: yeni metin sütunları boş başlamalı';
  end if;
  -- Eski satır eski değerlerini korur (varsayılan değişikliği yalnızca yeni satırlara).
  if r.start_weight_kg <> 84.5 or r.target_weight_kg <> 78 or r.daily_steps <> 10000
     or r.daily_protein_g <> 170 or r.daily_carbs_g <> 180 then
    raise exception 'BAŞARISIZ: eski ayar satırının değerleri değişti: %', to_jsonb(r);
  end if;
  if cardinality(r.team_members) = 0 then
    raise exception 'BAŞARISIZ: eski ekip listesi silindi';
  end if;

  -- Seed verisi aynen duruyor.
  select count(*) into v_count from public.routines where user_id = v_user;
  if v_count <> 13 then
    raise exception 'BAŞARISIZ: rutinler değişti (% adet)', v_count;
  end if;
  select count(*) into v_count from public.routines where user_id = v_user and scope = 'İş';
  if v_count <> 7 then
    raise exception 'BAŞARISIZ: Pusholder rutinleri İş''e taşınmadı (% adet İş)', v_count;
  end if;
  select count(*) into v_count from public.routines where user_id = v_user and scope = 'Kişisel';
  if v_count <> 6 then
    raise exception 'BAŞARISIZ: kişisel rutinler değişti (% adet)', v_count;
  end if;
  -- Taşınan (İş) satırların updated_at'i bozulmadı (v3 yükseltmesinin kendi
  -- notify düzeltmesi başka satırlara dokunabilir; yalnızca taşınanlara bakılır).
  if exists (select 1 from public.routines where user_id = v_user and scope = 'İş' and updated_at <> created_at)
     or exists (select 1 from public.tasks where user_id = v_user and category = 'İş' and updated_at <> created_at)
     or exists (select 1 from public.notes where user_id = v_user and category = 'İş' and updated_at <> created_at) then
    raise exception 'BAŞARISIZ: taşıma satırların updated_at değerini değiştirdi';
  end if;
  if not exists (select 1 from public.tasks where user_id = v_user and category = 'İş'
                 and title = 'Push bildirim performans raporunu hazırla') then
    raise exception 'BAŞARISIZ: Pusholder görevi İş olarak taşınmadı';
  end if;
  if not exists (select 1 from public.tasks where user_id = v_user
                 and title = 'Haftalık vardiya çizelgesini yayınla' and category = 'Ekip')
     or not exists (select 1 from public.notes where user_id = v_user
                    and title = 'Form hedefi' and content like '84.5 kg → 78 kg%')
     or not exists (select 1 from public.fitness_logs where user_id = v_user
                    and log_type = 'weight' and weight_kg = 84.5) then
    raise exception 'BAŞARISIZ: sahibin seed verisi bozuldu';
  end if;
  if exists (select 1 from public.tasks where category = 'Pusholder')
     or exists (select 1 from public.notes where category = 'Pusholder')
     or exists (select 1 from public.routines where scope = 'Pusholder') then
    raise exception 'BAŞARISIZ: Pusholder değeri kaldı';
  end if;

  -- Yeni tablolar boş kuruldu, eski kullanıcı arkadaşsız başlar.
  if exists (select 1 from public.friendships) or exists (select 1 from public.friend_requests) then
    raise exception 'BAŞARISIZ: yeni tablolar boş olmalı';
  end if;

  -- Eski kullanıcı yeni arkadaş işlevlerini çağırabilir.
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  select count(*) into v_count from public.my_friends();
  reset role;
  if v_count <> 0 then
    raise exception 'BAŞARISIZ: yükseltilmiş kullanıcının arkadaşı olmamalı';
  end if;
end;
$$;
\echo tamam: Faz 4B yukseltme verisi dogru
