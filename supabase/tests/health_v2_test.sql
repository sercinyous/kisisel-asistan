-- Sağlık v2: user_settings yeni sütunları, body_measurements ve
-- progress_photos (yalnızca sahibi; arkadaş da okuyamaz) ve Storage
-- `body_photos` kovası. Çalıştırma: supabase/tests/run_local.sh
-- (storage_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

select tf.mkuser('c1000000-0000-0000-0000-000000000001', 'beden@example.com');
select tf.mkuser('c2000000-0000-0000-0000-000000000002', 'dost@example.com');
insert into public.friendships (user_a, user_b)
values ('c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002')
on conflict do nothing;

\set U1 '''c1000000-0000-0000-0000-000000000001'''
\set U2 '''c2000000-0000-0000-0000-000000000002'''

-- 1) user_settings varsayılanları ve kısıtlar -----------------------------
select tf.eq('yeni sütun varsayılanları',
  tf.run('authenticated', :U1,
    $q$select jsonb_build_array(weekly_rate, expenditure_kcal_manual, meal_count,
         targets_source, checkin_cadence, checkin_weekday, checkin_monthday,
         checkin_reminder, hide_photos) from public.user_settings$q$),
  '["classic", null, 3, "plan", "weekly", 1, 1, true, false]');
select tf.eq('sahip hızı ve kaynağı yazar',
  tf.run('authenticated', :U1,
    $q$update public.user_settings set weekly_rate = '0.75', targets_source = 'manual',
         targets_updated_at = now(), expenditure_kcal_manual = 2600, meal_count = 2,
         checkin_cadence = 'monthly', checkin_monthday = 28
       returning jsonb_build_array(weekly_rate, targets_source, meal_count)$q$),
  '["0.75", "manual", 2]');
select tf.fails('geçersiz hız reddedilir', 'authenticated', :U1,
  $q$update public.user_settings set weekly_rate = '0.25' returning to_jsonb(1)$q$, '23514');
select tf.fails('geçersiz kaynak reddedilir', 'authenticated', :U1,
  $q$update public.user_settings set targets_source = 'ai' returning to_jsonb(1)$q$, '23514');
select tf.fails('ayın 29. günü reddedilir', 'authenticated', :U1,
  $q$update public.user_settings set checkin_monthday = 29 returning to_jsonb(1)$q$, '23514');
select tf.fails('haftanın 0. günü reddedilir', 'authenticated', :U1,
  $q$update public.user_settings set checkin_weekday = 0 returning to_jsonb(1)$q$, '23514');
select tf.fails('elle harcama aralık dışı reddedilir', 'authenticated', :U1,
  $q$update public.user_settings set expenditure_kcal_manual = 900 returning to_jsonb(1)$q$, '23514');

-- 2) body_measurements ---------------------------------------------------
select tf.eq('sahip ölçü ekler',
  tf.run('authenticated', :U1,
    $q$insert into public.body_measurements (measured_on, waist_cm, hip_cm)
       values ('2026-11-02', 88.5, 101) returning to_jsonb(waist_cm)$q$),
  '88.5');
select tf.eq('aynı gün upsert',
  tf.run('authenticated', :U1,
    $q$insert into public.body_measurements (measured_on, waist_cm)
       values ('2026-11-02', 88.0)
       on conflict (user_id, measured_on) do update set waist_cm = excluded.waist_cm
       returning to_jsonb(waist_cm)$q$),
  '88.0');
select tf.fails('boş ölçü reddedilir', 'authenticated', :U1,
  $q$insert into public.body_measurements (measured_on) values ('2026-11-03')
     returning to_jsonb(1)$q$, '23514');
select tf.fails('aralık dışı ölçü reddedilir', 'authenticated', :U1,
  $q$insert into public.body_measurements (measured_on, neck_cm) values ('2026-11-03', 10)
     returning to_jsonb(1)$q$, '23514');
select tf.fails('başkası adına ölçü yazılamaz', 'authenticated', :U2,
  $q$insert into public.body_measurements (user_id, measured_on, waist_cm)
     values ('c1000000-0000-0000-0000-000000000001', '2026-11-04', 80)
     returning to_jsonb(1)$q$, '42501');
select tf.eq('arkadaş ölçüyü göremez',
  tf.run('authenticated', :U2,
    $q$select to_jsonb(count(*)) from public.body_measurements$q$),
  '0');
select tf.eq('arkadaş ölçüyü silemez (0 satır)',
  tf.run('authenticated', :U2,
    $q$with x as (delete from public.body_measurements returning 1)
       select to_jsonb(count(*)) from x$q$),
  '0');
select tf.fails('anon ölçü okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.body_measurements$q$, '42501');

-- 3) progress_photos -----------------------------------------------------
select tf.eq('sahip fotoğraf satırı ekler',
  tf.run('authenticated', :U1,
    $q$insert into public.progress_photos (taken_on, pose, storage_path)
       values ('2026-11-02', 'front',
               'c1000000-0000-0000-0000-000000000001/2026-11-02/front.jpg')
       returning to_jsonb(pose)$q$),
  '"front"');
select tf.fails('yol satırla uyuşmazsa reddedilir', 'authenticated', :U1,
  $q$insert into public.progress_photos (taken_on, pose, storage_path)
     values ('2026-11-02', 'side',
             'c2000000-0000-0000-0000-000000000002/2026-11-02/side.jpg')
     returning to_jsonb(1)$q$, '23514');
select tf.fails('geçersiz poz reddedilir', 'authenticated', :U1,
  $q$insert into public.progress_photos (taken_on, pose, storage_path)
     values ('2026-11-02', 'top',
             'c1000000-0000-0000-0000-000000000001/2026-11-02/top.jpg')
     returning to_jsonb(1)$q$, '23514');
select tf.eq('arkadaş fotoğraf satırını göremez',
  tf.run('authenticated', :U2,
    $q$select to_jsonb(count(*)) from public.progress_photos$q$),
  '0');

-- 4) Storage body_photos -------------------------------------------------
select tf.ok('body_photos kovası özel',
  (select public = false from storage.buckets where id = 'body_photos'));
select tf.eq('sahip kendi klasörüne yükler',
  tf.run('authenticated', :U1,
    $q$insert into storage.objects (bucket_id, name)
       values ('body_photos', 'c1000000-0000-0000-0000-000000000001/2026-11-02/front.jpg')
       returning to_jsonb(name)$q$),
  '"c1000000-0000-0000-0000-000000000001/2026-11-02/front.jpg"');
select tf.fails('başkasının klasörüne yüklenemez', 'authenticated', :U1,
  $q$insert into storage.objects (bucket_id, name)
     values ('body_photos', 'c2000000-0000-0000-0000-000000000002/2026-11-02/front.jpg')
     returning to_jsonb(1)$q$, '42501');
select tf.fails('geçersiz yol reddedilir', 'authenticated', :U1,
  $q$insert into storage.objects (bucket_id, name)
     values ('body_photos', 'c1000000-0000-0000-0000-000000000001/x.png')
     returning to_jsonb(1)$q$, '42501');
select tf.eq('arkadaş fotoğrafı okuyamaz',
  tf.run('authenticated', :U2,
    $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'body_photos'$q$),
  '0');
select tf.eq('arkadaş silemez (0 satır)',
  tf.run('authenticated', :U2,
    $q$with x as (delete from storage.objects where bucket_id = 'body_photos' returning 1)
       select to_jsonb(count(*)) from x$q$),
  '0');
select tf.fails('anon okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'body_photos'$q$, '42501');
select tf.eq('sahip okur',
  tf.run('authenticated', :U1,
    $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'body_photos'$q$),
  '1');
select tf.eq('sahip siler',
  tf.run('authenticated', :U1,
    $q$with x as (delete from storage.objects where bucket_id = 'body_photos' returning 1)
       select to_jsonb(count(*)) from x$q$),
  '1');

-- 5) Hesap silinince satırlar gider --------------------------------------
delete from auth.users where id = 'c1000000-0000-0000-0000-000000000001';
select tf.eq('ölçüler cascade silinir',
  (select to_jsonb(count(*)) from public.body_measurements
   where user_id = 'c1000000-0000-0000-0000-000000000001'),
  '0');
select tf.eq('fotoğraf satırları cascade silinir',
  (select to_jsonb(count(*)) from public.progress_photos
   where user_id = 'c1000000-0000-0000-0000-000000000001'),
  '0');
