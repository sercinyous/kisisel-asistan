-- Kiralamalı rapor yenileme (schema.sql "report_claim_lease" bloğu) testi.
-- Çalıştırma: supabase/tests/run_local.sh (auth_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;
alter table auth.users disable trigger signup_invite_gate;

create schema rc;
create function rc.ok(p_label text, p_cond boolean) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'BAŞARISIZ: %', p_label;
  end if;
  raise notice 'tamam: %', p_label;
end;
$$;

\set U '''c1000000-0000-0000-0000-000000000001'''

insert into auth.users (id, email) values (:U, 'kira@example.com') on conflict do nothing;
insert into public.user_settings (user_id) values (:U) on conflict (user_id) do nothing;
update public.user_settings set onboarded_at = now(), timezone = 'Europe/Istanbul' where user_id = :U;

-- Yalnızca bu testin raporları alınsın.
update public.daily_reports set dirty = false;
update public.weekly_reports set dirty = false;

select public.save_daily_report(:U, '2026-11-16', public.report_daily_metrics(:U, '2026-11-16'), 'eski', 'ok');
insert into public.daily_health_metrics (user_id, metric_date, steps) values (:U, '2026-11-16', 9000);
update public.weekly_reports set dirty = false where user_id = :U;
update public.daily_reports set dirty_at = now() - interval '1 hour' where user_id = :U;
select rc.ok('tetikleyici dirty_version artırır',
  (select dirty and dirty_version >= 1 from public.daily_reports where user_id = :U));

create temp table c as select * from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes');

-- 1) Geçici kayıt hatası: işçi release çağırır → sonraki geçiş yeniden alır.
select rc.ok('ilk claim raporu alır', (select count(*) = 1 from c));
select public.release_report_claim('daily', :U, '2026-11-16', (select claim_token from c));
select rc.ok('geçici hata: release sonrası dirty ve kirasız',
  (select dirty and claim_token is null from public.daily_reports where user_id = :U));
truncate c;
insert into c select * from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes');
select rc.ok('geçici hata: sonraki geçiş yeniden alır', (select count(*) = 1 from c));

-- 2) İşçi öldü (release yok): kira dolmadan alınmaz, dolunca alınır.
select rc.ok('kira dolmadan yeniden alınmaz',
  (select count(*) = 0 from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes')));
update public.daily_reports set claimed_at = now() - interval '16 minutes' where user_id = :U;
create temp table c2 as select * from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes');
select rc.ok('kira dolunca yeniden alınır (yeni jeton)',
  (select count(*) = 1 and bool_and(claim_token <> (select claim_token from c)) from c2));
-- Eski (ölü) işçinin geç gelen tamamlaması yeni kirayı bozmaz.
select rc.ok('eski jetonla tamamlama false döner',
  public.complete_report_claim('daily', :U, '2026-11-16', (select claim_token from c), (select dirty_version from c)) = false);
select rc.ok('eski jetonla tamamlama yeni kirayı bozmaz',
  (select dirty and claim_token = (select claim_token from c2) from public.daily_reports where user_id = :U));

-- 3) Yenileme sırasında veri değişir → kayıttan sonra dirty kalır.
insert into public.daily_health_metrics (user_id, metric_date, steps) values (:U, '2026-11-16', 1)
  on conflict (user_id, metric_date) do update set steps = 11000;
select public.save_refreshed_report('daily', :U, '2026-11-16',
  public.report_daily_metrics(:U, '2026-11-16'), 'yeni yorum',
  (select claim_token from c2), (select dirty_version from c2));
select rc.ok('yenileme sırasında gelen veri: kayıt sonrası dirty ve kirasız',
  (select dirty and claim_token is null and ai_summary = 'yeni yorum' from public.daily_reports where user_id = :U));

-- 4) Değişiklik yoksa başarılı kayıt temizler.
update public.daily_reports set dirty_at = now() - interval '1 hour' where user_id = :U;
create temp table c3 as select * from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes');
select public.save_refreshed_report('daily', :U, '2026-11-16',
  public.report_daily_metrics(:U, '2026-11-16'), 'son yorum',
  (select claim_token from c3), (select dirty_version from c3));
select rc.ok('başarılı kayıt: dirty temizlenir',
  (select not dirty and claim_token is null from public.daily_reports where user_id = :U));

-- 5) Yorumsuz kayıt (kota/AI): dirty kalır, kira bırakılır.
insert into public.daily_health_metrics (user_id, metric_date, steps) values (:U, '2026-11-16', 1)
  on conflict (user_id, metric_date) do update set steps = 12000;
update public.daily_reports set dirty_at = now() - interval '1 hour' where user_id = :U;
create temp table c4 as select * from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes');
select public.save_refreshed_report('daily', :U, '2026-11-16',
  public.report_daily_metrics(:U, '2026-11-16'), null,
  (select claim_token from c4), (select dirty_version from c4));
select rc.ok('yorumsuz kayıt: dirty kalır, kira bırakılır',
  (select dirty and claim_token is null from public.daily_reports where user_id = :U));

-- 6) Sayılar değişmedi: complete_report_claim temizler.
update public.daily_reports set dirty_at = now() - interval '1 hour' where user_id = :U;
create temp table c5 as select * from public.claim_dirty_reports(40, interval '10 minutes', interval '15 minutes');
select rc.ok('complete: sürüm aynıysa true döner',
  public.complete_report_claim('daily', :U, '2026-11-16', (select claim_token from c5), (select dirty_version from c5)));
select rc.ok('complete: dirty temizlendi, kira bırakıldı',
  (select not dirty and claim_token is null from public.daily_reports where user_id = :U));

delete from auth.users where id = :U;
alter table auth.users enable trigger signup_invite_gate;
drop schema rc cascade;
\echo RAPOR KIRA TESTLERI GECTI
