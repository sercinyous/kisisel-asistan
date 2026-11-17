-- Geç gelen veriyle rapor yenileme (schema.sql "report_dirty" bloğu) testi.
-- Çalıştırma: supabase/tests/run_local.sh (auth_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;
alter table auth.users disable trigger signup_invite_gate;

create schema rd;
create function rd.ok(p_label text, p_cond boolean) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'BAŞARISIZ: %', p_label;
  end if;
  raise notice 'tamam: %', p_label;
end;
$$;

\set U '''d1000000-0000-0000-0000-000000000001'''
\set V '''d1000000-0000-0000-0000-000000000002'''

insert into auth.users (id, email) values
  (:U, 'kirli@example.com'), (:V, 'diger@example.com') on conflict do nothing;
insert into public.user_settings (user_id) values (:U), (:V) on conflict (user_id) do nothing;
update public.user_settings set onboarded_at = now(), timezone = 'Europe/Istanbul'
where user_id in (:U, :V);

-- 16 Kasım 2026 Pazartesi. Gün raporu 16'sı ve 15'i, hafta raporu 16'sı ve 9'u.
select public.save_daily_report(:U, '2026-11-16', public.report_daily_metrics(:U, '2026-11-16'), 'yorum16', 'ok');
select public.save_daily_report(:U, '2026-11-15', public.report_daily_metrics(:U, '2026-11-15'), 'yorum15', 'ok');
select public.save_daily_report(:V, '2026-11-16', public.report_daily_metrics(:V, '2026-11-16'), 'v16', 'ok');
select public.save_weekly_report(:U, '2026-11-16', public.report_weekly_metrics(:U, '2026-11-16'), 'hafta', 'ok');
select public.save_weekly_report(:U, '2026-11-09', public.report_weekly_metrics(:U, '2026-11-09'), 'gecen', 'ok');

select rd.ok('yeni rapor temiz, ai_basis = metrics',
  (select bool_and(not dirty and ai_basis = metrics) from public.daily_reports where user_id = :U));

-- Sağlık özeti geç gelir → yalnızca o günün raporu ve haftası kirlenir.
insert into public.daily_health_metrics (user_id, metric_date, steps) values (:U, '2026-11-16', 12000);
select rd.ok('sağlık: 16 Kasım günlük dirty',
  (select dirty and dirty_at is not null from public.daily_reports where user_id = :U and report_date = '2026-11-16'));
select rd.ok('sağlık: 15 Kasım günlük temiz',
  (select not dirty from public.daily_reports where user_id = :U and report_date = '2026-11-15'));
select rd.ok('sağlık: o haftanın raporu dirty, önceki hafta temiz',
  (select bool_and(dirty = (week_start = '2026-11-16')) from public.weekly_reports where user_id = :U));
select rd.ok('başka kullanıcının raporu kirlenmez',
  (select not dirty from public.daily_reports where user_id = :V));

-- Aynı değerle güncelleme kirletmez.
update public.daily_reports set dirty = false where user_id = :U;
update public.weekly_reports set dirty = false where user_id = :U;
update public.daily_health_metrics set synced_at = now() where user_id = :U;
select rd.ok('sağlık: yalnızca synced_at değişince kirlenmez',
  (select not bool_or(dirty) from public.daily_reports where user_id = :U));

-- Öğün: eaten_at 15 Kasım 23:30 İstanbul (= 20:30 UTC) → 15'i kirletir.
insert into public.nutrition_logs (user_id, food_name, calories, eaten_at)
values (:U, 'Gece', 300, '2026-11-15 20:30:00+00');
select rd.ok('öğün: kullanıcının saat dilimine göre 15 Kasım dirty, 16 temiz',
  (select bool_and(dirty = (report_date = '2026-11-15')) from public.daily_reports where user_id = :U));
select rd.ok('öğün: 15 Kasım (Pazar) önceki haftayı kirletir',
  (select dirty from public.weekly_reports where user_id = :U and week_start = '2026-11-09'));

-- Görev: due_at değişince hem eski hem yeni gün kirlenir.
update public.daily_reports set dirty = false where user_id = :U;
insert into public.tasks (user_id, title, due_at) values (:U, 'iş', '2026-11-16 09:00:00+00');
update public.daily_reports set dirty = false where user_id = :U;
update public.tasks set due_at = '2026-11-15 09:00:00+00' where user_id = :U;
select rd.ok('görev: termin taşınınca eski ve yeni gün dirty',
  (select count(*) = 2 from public.daily_reports where user_id = :U and dirty));
update public.daily_reports set dirty = false where user_id = :U;
update public.tasks set title = 'yeni ad' where user_id = :U;
select rd.ok('görev: başlık değişikliği kirletmez',
  (select not bool_or(dirty) from public.daily_reports where user_id = :U));
update public.tasks set status = 'done' where user_id = :U;
select rd.ok('görev: tamamlanınca dirty',
  (select dirty from public.daily_reports where user_id = :U and report_date = '2026-11-15'));
update public.daily_reports set dirty = false where user_id = :U;
delete from public.tasks where user_id = :U;
select rd.ok('görev: silinince dirty',
  (select dirty from public.daily_reports where user_id = :U and report_date = '2026-11-15'));

-- Rutin işareti.
update public.daily_reports set dirty = false where user_id = :U;
insert into public.routines (id, user_id, title) values ('d2000000-0000-0000-0000-000000000001', :U, 'r');
insert into public.routine_completions (user_id, routine_id, completed_on)
values (:U, 'd2000000-0000-0000-0000-000000000001', '2026-11-16');
select rd.ok('rutin işareti: o gün dirty',
  (select bool_and(dirty = (report_date = '2026-11-16')) from public.daily_reports where user_id = :U));

-- Tartı: sonraki haftanın başlangıç kilosunu etkiler.
update public.weekly_reports set dirty = false where user_id = :U;
insert into public.fitness_logs (user_id, log_type, weight_kg, logged_at)
values (:U, 'weight', 80, '2026-11-12 08:00:00+00');
select rd.ok('tartı: kendi haftası ve sonraki hafta dirty',
  (select count(*) = 2 from public.weekly_reports where user_id = :U and dirty));

-- Yetki: kullanıcılar raporu doğrudan kirletemez ya da toplu fonksiyonları çağıramaz.
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.mark_reports_dirty(uuid,date,date)',
    'public.claim_dirty_reports(integer,interval)',
    'public.refresh_report_metrics(text,uuid,date)',
    'public.save_refreshed_report(text,uuid,date,jsonb,text)']
  loop
    if has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('anon', f, 'execute') then
      raise exception 'BAŞARISIZ: % authenticated/anon için açık', f;
    end if;
  end loop;
  if not has_function_privilege('service_role', 'public.claim_dirty_reports(integer,interval)', 'execute') then
    raise exception 'BAŞARISIZ: service_role claim_dirty_reports çalıştıramıyor';
  end if;
  raise notice 'tamam: toplu fonksiyonlar yalnızca service_role';
end;
$$;

-- Tetikleyici authenticated rolüyle (RLS altında) çalışınca da kirletir.
update public.daily_reports set dirty = false where user_id = :U;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into public.daily_health_metrics (user_id, metric_date, steps) values (:U, '2026-11-15', 4000);
reset role;
select rd.ok('authenticated yazımı da raporu kirletir',
  (select dirty from public.daily_reports where user_id = :U and report_date = '2026-11-15'));

-- claim: bekleme süresi dolmadan alınmaz; dolunca alınır ve temizlenir.
select rd.ok('claim: bekleme süresi dolmadan boş',
  (select count(*) = 0 from public.claim_dirty_reports(40, interval '10 minutes')));
-- Diğer testlerin raporları bu sayımı bozmasın.
update public.daily_reports set dirty = false where user_id <> :U;
update public.weekly_reports set dirty = false where user_id <> :U;
update public.daily_reports set dirty_at = now() - interval '1 hour' where dirty;
update public.weekly_reports set dirty_at = now() - interval '1 hour' where dirty;
create temp table claimed as select * from public.claim_dirty_reports(40, interval '10 minutes');
select rd.ok('claim: işaretli gün ve haftalar alınır',
  (select count(*) filter (where kind = 'daily' and report_date = '2026-11-15') = 1
      and count(*) filter (where kind = 'weekly') = 2 from claimed));
select rd.ok('claim: alınanların işareti kalkar',
  (select not bool_or(dirty) from public.daily_reports where user_id = :U)
  and (select not bool_or(dirty) from public.weekly_reports where user_id = :U));
select rd.ok('claim: limit uygulanır',
  (select count(*) = 0 from public.claim_dirty_reports(0, interval '0')));

-- Onboarded olmayan kullanıcının raporu alınmaz.
update public.user_settings set onboarded_at = null where user_id = :V;
update public.daily_reports set dirty = true, dirty_at = now() - interval '1 hour' where user_id = :V;
select rd.ok('claim: onboarded olmayan alınmaz',
  (select count(*) = 0 from public.claim_dirty_reports(40, interval '0')));

-- refresh: veri değişmediyse changed=false (AI gerekmez).
select public.save_daily_report(:U, '2026-11-14', public.report_daily_metrics(:U, '2026-11-14'), 'y14', 'ok');
select rd.ok('refresh: sayılar aynıysa changed=false',
  (public.refresh_report_metrics('daily', :U, '2026-11-14') ->> 'changed')::boolean = false);
-- 15 Kasım: yorum eski sayılara dayanıyor, veri değişti → changed=true.
select rd.ok('refresh: geç gelen veriyle changed=true ve yeni sayılar',
  (select (r ->> 'changed')::boolean and (r #>> '{metrics,health,steps}')::int = 4000
   from public.refresh_report_metrics('daily', :U, '2026-11-15') r));
select rd.ok('refresh: weekly changed=true',
  (public.refresh_report_metrics('weekly', :U, '2026-11-09') ->> 'changed')::boolean);

-- Kota yok / AI başarısız: sayılar güncellenir, eski yorum korunur, yeniden dirty.
select public.save_refreshed_report('daily', :U, '2026-11-15',
  public.report_daily_metrics(:U, '2026-11-15'), null);
select rd.ok('save_refreshed (yorumsuz): metrics yeni, yorum eski, dirty',
  (select dirty and ai_summary = 'yorum15' and ai_status = 'ok'
          and (metrics #>> '{health,steps}')::int = 4000
          and ai_basis is distinct from metrics
   from public.daily_reports where user_id = :U and report_date = '2026-11-15'));
select public.save_refreshed_report('weekly', :U, '2026-11-09',
  public.report_weekly_metrics(:U, '2026-11-09'), null);
select rd.ok('save_refreshed weekly (yorumsuz): yorum eski, dirty, dayanak eski',
  (select dirty and ai_summary = 'gecen' and ai_basis is distinct from metrics
   from public.weekly_reports where user_id = :U and week_start = '2026-11-09'));

-- Yeni yorumla: dayanak yeni sayılar olur, sonraki refresh AI istemez.
select public.save_refreshed_report('daily', :U, '2026-11-15',
  public.report_daily_metrics(:U, '2026-11-15'), 'yeni yorum');
select rd.ok('save_refreshed (yorumlu): ai_basis = metrics',
  (select ai_summary = 'yeni yorum' and ai_basis = metrics
   from public.daily_reports where user_id = :U and report_date = '2026-11-15'));
select rd.ok('refresh: yeni yorumdan sonra changed=false',
  (public.refresh_report_metrics('daily', :U, '2026-11-15') ->> 'changed')::boolean = false);

-- JSON gidiş-dönüşünde 1800.0 → 1800 olsa da eşit sayılır.
select rd.ok('jsonb sayı eşitliği (1800 = 1800.0)', '{"a": 1800.0}'::jsonb = '{"a": 1800}'::jsonb);

-- Başarısız (failed) rapor: dayanak yok → changed=true.
select public.save_daily_report(:U, '2026-11-13', public.report_daily_metrics(:U, '2026-11-13'), null, 'failed');
select rd.ok('failed raporda ai_basis null ve changed=true',
  (select ai_basis is null from public.daily_reports where user_id = :U and report_date = '2026-11-13')
  and (public.refresh_report_metrics('daily', :U, '2026-11-13') ->> 'changed')::boolean);

delete from auth.users where id in (:U, :V);
alter table auth.users enable trigger signup_invite_gate;
drop schema rd cascade;
\echo RAPOR DIRTY TESTLERI GECTI
