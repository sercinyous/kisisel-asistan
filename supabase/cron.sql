-- =====================================================================
-- Otomatik raporların zamanlaması (pg_cron → Edge Function generate-reports)
--
-- ÖNCE (bir kez) proje adresini ve zamanlayıcı gizli anahtarını Vault'a koy;
-- bu dosyada gizli değer yoktur. SQL Editor'da, kendi değerlerinle:
--
--   select vault.create_secret('https://PROJE-REF.supabase.co', 'project_url');
--   select vault.create_secret('CRON_SECRET-ile-ayni-deger', 'cron_secret');
--
-- cron_secret, Edge Function'a verilen CRON_SECRET ile AYNI olmalıdır
-- (bkz. README "Otomatik raporlar"). Sonra bu dosyayı SQL Editor'da çalıştır.
-- Tekrar çalıştırılabilir: aynı adlı işler silinip yeniden kurulur.
--
-- Zamanlar UTC'dir (pg_cron UTC çalışır):
--   45 20 * * *  → her gün 23:45 İstanbul: o günün günlük raporu
--   0 4 * * 1    → her Pazartesi 07:00 İstanbul: biten haftanın raporu
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Vault değerleri yoksa işler sessizce boşa çalışmasın: kurulum burada durur.
do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'project_url')
     or not exists (select 1 from vault.decrypted_secrets where name = 'cron_secret') then
    raise exception
      'Vault''ta project_url ve cron_secret bulunamadı. Dosyanın başındaki iki vault.create_secret satırını önce çalıştır.';
  end if;
end;
$$;

-- Aynı adlı eski işler kaldırılır (idempotent kurulum).
select cron.unschedule(jobid)
from cron.job
where jobname in ('kisisel-asistan-gunluk-rapor', 'kisisel-asistan-haftalik-rapor');

-- Adres ve gizli anahtar her çalışmada Vault'tan okunur; iş tanımında
-- (cron.job.command) gizli değer saklanmaz.
select cron.schedule(
  'kisisel-asistan-gunluk-rapor',
  '45 20 * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/generate-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('kind', 'daily'),
    timeout_milliseconds := 120000
  );
  $job$
);

select cron.schedule(
  'kisisel-asistan-haftalik-rapor',
  '0 4 * * 1',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/generate-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('kind', 'weekly'),
    timeout_milliseconds := 120000
  );
  $job$
);

-- Kontrol: kurulan işler.
select jobid, jobname, schedule, active
from cron.job
where jobname like 'kisisel-asistan-%'
order by jobname;
