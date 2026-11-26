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
--   15 21 * * *  → her gün 00:15 İstanbul: biten günün (dünün) günlük raporu
--   20 * * * *   → saatte bir: geç gelen veriyle dirty işaretlenmiş günlük/haftalık
--                  raporların sayıları yenilenir; AI yorumu yalnızca sayılar
--                  değiştiyse (kişi başına günde en çok REPORT_REFRESH_DAILY_LIMIT)
--   0 4 * * 1    → her Pazartesi 07:00 İstanbul: biten haftanın raporu
--   30 3 * * 0   → her Pazar: 60 günden eski günlük AI kota sayaçları ve 90 günden
--                  eski hata kayıtları (app_errors) silinir
--
-- Raporlar yalnızca ilk kurulumunu bitirmiş (user_settings.onboarded_at dolu)
-- kullanıcılar için üretilir; bunu Edge Function generate-reports uygular
-- (kurulumu bitirmemiş hesaplar için boşuna AI maliyeti oluşmaz).
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
where jobname in ('kisisel-asistan-gunluk-rapor', 'kisisel-asistan-haftalik-rapor',
                  'kisisel-asistan-haftalik-rapor-bati',
                  'kisisel-asistan-kota-temizlik', 'kisisel-asistan-rapor-yenile');

-- Adres ve gizli anahtar her çalışmada Vault'tan okunur; iş tanımında
-- (cron.job.command) gizli değer saklanmaz.
select cron.schedule(
  'kisisel-asistan-gunluk-rapor',
  '15 21 * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/generate-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('kind', 'daily', 'previous', true),
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

-- İkinci haftalık çalıştırma (Pazartesi 14:00 UTC): 04:00 UTC'de hâlâ Pazar
-- olan batı saat dilimleri (Amerika) biten haftayı bu çalıştırmada alır.
-- Başarılı yorumu zaten olan raporlar atlanır (Gemini maliyeti tekrarlanmaz).
select cron.schedule(
  'kisisel-asistan-haftalik-rapor-bati',
  '0 14 * * 1',
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

-- Geç gelen veri (ertesi sabah yedeklenen sağlık verisi, sonradan girilen öğün
-- ya da görev) raporu dirty işaretler; bu iş onları toplu yeniler.
select cron.schedule(
  'kisisel-asistan-rapor-yenile',
  '20 * * * *',
  $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/generate-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := jsonb_build_object('kind', 'refresh'),
    timeout_milliseconds := 120000
  );
  $job$
);

-- Günlük AI kota sayaçları (ai_usage) birikmesin: yalnızca geçmiş günler silinir,
-- bugünün sayacına dokunulmaz.
select cron.schedule(
  'kisisel-asistan-kota-temizlik',
  '30 3 * * 0',
  $job$
  delete from public.ai_usage where day < current_date - 60;
  delete from public.ai_global_usage where day < current_date - 60;
  delete from public.app_errors where created_at < now() - interval '90 days';
  $job$
);

-- Kontrol: kurulan işler.
select jobid, jobname, schedule, active
from cron.job
where jobname like 'kisisel-asistan-%'
order by jobname;
