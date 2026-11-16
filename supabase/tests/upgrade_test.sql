-- Sürüm 2 → 3 yükseltmesinden SONRA: veri duruyor mu, yeni kurallar geçerli mi?
\set ON_ERROR_STOP on
do $$
declare
  v_user constant uuid := 'eeeeeeee-0000-0000-0000-000000000005';
  r record;
  v_count integer;
begin
  select * into strict r from public.weekly_reports where user_id = v_user;
  if r.ai_summary <> 'eski özet' or r.tasks_done <> 4 or r.metrics <> '{"eski": true}'::jsonb
     or r.ai_status <> 'pending' or r.generated_at is null then
    raise exception 'BAŞARISIZ: eski haftalık rapor satırı bozuldu: %', to_jsonb(r);
  end if;

  select * into strict r from public.user_settings where user_id = v_user;
  if r.timezone <> 'Europe/Istanbul' or r.daily_calories <> 2400 or r.team_members <> '{Ayşe}' then
    raise exception 'BAŞARISIZ: ayar satırı bozuldu: %', to_jsonb(r);
  end if;

  select count(*) into v_count from public.routines where user_id = v_user;
  if v_count <> 13 then
    raise exception 'BAŞARISIZ: seed rutinleri değişti (% adet)', v_count;
  end if;

  if exists (select 1 from pg_policies
             where schemaname = 'public' and policyname = 'weekly_reports_owner_all') then
    raise exception 'BAŞARISIZ: eski yazma politikası duruyor';
  end if;
  select count(*) into v_count from pg_policies
  where schemaname = 'public' and tablename in ('weekly_reports', 'daily_reports');
  if v_count <> 2 then
    raise exception 'BAŞARISIZ: rapor tablolarında % politika var (2 olmalı)', v_count;
  end if;

  if has_table_privilege('authenticated', 'public.weekly_reports', 'insert')
     or has_table_privilege('authenticated', 'public.weekly_reports', 'update')
     or has_table_privilege('authenticated', 'public.weekly_reports', 'delete')
     or not has_table_privilege('authenticated', 'public.weekly_reports', 'select') then
    raise exception 'BAŞARISIZ: weekly_reports yetkileri yanlış';
  end if;

  -- Eski kullanıcı kendi eski raporunu okumaya devam eder.
  perform set_config('request.jwt.claim.sub', v_user::text, true);
  set local role authenticated;
  select count(*) into v_count from public.weekly_reports;
  reset role;
  if v_count <> 1 then
    raise exception 'BAŞARISIZ: kullanıcı eski raporunu okuyamıyor';
  end if;
end;
$$;
\echo tamam: yukseltme verisi ve yetkileri dogru
