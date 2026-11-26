-- AI kotası (Faz 4B): consume_ai_quota ve ai_usage. Eşzamanlı (atomik)
-- davranış run_local.sh içinde ayrıca, paralel oturumlarla sınanır.
-- Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

select tf.mkuser('c1000000-0000-0000-0000-000000000001', 'kota-a@example.com');
select tf.mkuser('c2000000-0000-0000-0000-000000000002', 'kota-b@example.com');
\set A '''c1000000-0000-0000-0000-000000000001'''
\set B '''c2000000-0000-0000-0000-000000000002'''

-- Yalnızca service_role çalıştırır.
select tf.fails('authenticated consume_ai_quota çalıştıramaz', 'authenticated', :A,
  $q$select to_jsonb(public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 100))$q$, '42501');
select tf.fails('anon consume_ai_quota çalıştıramaz', 'anon', null,
  $q$select to_jsonb(public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 100))$q$, '42501');

-- Kota: limit 3 → üç true, sonra false; sayaç limitte durur.
select tf.eq('ilk üç çağrı kota içinde',
  tf.run('service_role', null, $q$select jsonb_build_array(
    public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 3),
    public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 3),
    public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 3))$q$),
  '[true, true, true]'::jsonb);
select tf.eq('dördüncü çağrı kotayı aşar (false), sayaç artmaz',
  tf.run('service_role', null, $q$select jsonb_build_array(
    public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 3),
    public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 3))$q$),
  '[false, false]'::jsonb);
select tf.eq('sayaç tam limitte',
  (select to_jsonb(count) from public.ai_usage where user_id = :A and kind = 'ai'), '3'::jsonb);
select tf.eq('limit sonradan yükselirse devam eder',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai', 4))$q$),
  'true'::jsonb);

-- Tür ve kullanıcı bağımsız sayılır.
select tf.eq('başka tür (report_regen, günde 10) bağımsız: 10 true, 11. false',
  tf.run('service_role', null, $q$select jsonb_agg(public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'report_regen', 10))
    from generate_series(1, 11)$q$),
  '[true, true, true, true, true, true, true, true, true, true, false]'::jsonb);
select tf.eq('başka kullanıcı bağımsız',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'ai', 3))$q$),
  'true'::jsonb);
select tf.eq('satırlar (kullanıcı, tür) başına tek: ai=4, report_regen=10, B ai=1',
  (select jsonb_object_agg(user_id::text || ':' || kind, count) from public.ai_usage
   where user_id in (:A, :B)),
  '{"c1000000-0000-0000-0000-000000000001:ai": 4, "c1000000-0000-0000-0000-000000000001:report_regen": 10,
    "c2000000-0000-0000-0000-000000000002:ai": 1}'::jsonb);

-- Sınır durumları.
select tf.eq('limit 0 → false, satır açılmaz',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'sifir', 0))$q$),
  'false'::jsonb);
select tf.eq('limit null → false',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'sifir', null))$q$),
  'false'::jsonb);
select tf.eq('negatif limit → false',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'sifir', -5))$q$),
  'false'::jsonb);
select tf.ok('false dönen çağrılar satır açmadı',
  not exists (select 1 from public.ai_usage where kind = 'sifir'));
select tf.fails('boş tür reddedilir', 'service_role', null,
  $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', '', 5))$q$, '22023');
select tf.fails('41 karakterlik tür reddedilir', 'service_role', null,
  $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', repeat('k', 41), 5))$q$, '22023');
select tf.fails('null tür reddedilir', 'service_role', null,
  $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', null, 5))$q$, '22023');
select tf.fails('null kullanıcı reddedilir', 'service_role', null,
  $q$select to_jsonb(public.consume_ai_quota(null, 'ai', 5))$q$, '22023');

-- Gün UTC günüdür; kullanıcının saat dilimi kotayı etkilemez (SEC-08).
update public.user_settings set timezone = 'Pacific/Kiritimati' where user_id = :A;
update public.user_settings set timezone = 'Pacific/Pago_Pago' where user_id = :B;
select tf.run('service_role', null, $q$select jsonb_build_array(
  public.consume_ai_quota('c1000000-0000-0000-0000-000000000001', 'tz', 5),
  public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'tz', 5))$q$);
select tf.ok('kota günü UTC günü',
  (select day from public.ai_usage where user_id = :A and kind = 'tz') =
    (now() at time zone 'UTC')::date
  and (select day from public.ai_usage where user_id = :B and kind = 'tz') =
    (now() at time zone 'UTC')::date);
update public.user_settings set timezone = 'Europe/Istanbul' where user_id in (:A, :B);

-- Önceki günün sayacı bugünü etkilemez.
insert into public.ai_usage (user_id, kind, day, count)
values (:B, 'dun', (now() at time zone 'UTC')::date - 1, 99);
select tf.eq('dünkü dolu sayaç bugünkü kotayı tüketmez',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'dun', 5))$q$),
  'true'::jsonb);

-- Kullanıcı yalnızca KENDİ sayacını okur; yazamaz.
select tf.eq('kullanıcı kendi sayaçlarını okur',
  tf.run('authenticated', :B, $q$select to_jsonb(count(*)) from public.ai_usage$q$),
  (select to_jsonb(count(*)) from public.ai_usage where user_id = :B));
select tf.eq('kullanıcı başkasının sayacını okuyamaz',
  tf.run('authenticated', :B, $q$select to_jsonb(count(*)) from public.ai_usage where user_id <> auth.uid()$q$),
  '0'::jsonb);
select tf.fails('kullanıcı sayacı sıfırlayamaz (update)', 'authenticated', :A,
  $q$with u as (update public.ai_usage set count = 0 returning 1) select to_jsonb(count(*)) from u$q$, '42501');
select tf.fails('kullanıcı sayaç satırı ekleyemez', 'authenticated', :A,
  $q$with i as (insert into public.ai_usage (user_id, kind, day, count) values (auth.uid(), 'ai', current_date, 0) returning 1)
     select to_jsonb(count(*)) from i$q$, '42501');
select tf.fails('kullanıcı sayacı silemez', 'authenticated', :A,
  $q$with d as (delete from public.ai_usage returning 1) select to_jsonb(count(*)) from d$q$, '42501');
select tf.fails('anon ai_usage okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.ai_usage$q$, '42501');
select tf.fails('negatif sayaç yazılamaz', 'postgres', null,
  $q$with i as (insert into public.ai_usage (user_id, kind, day, count) values ('c1000000-0000-0000-0000-000000000001', 'neg', current_date, -1) returning 1)
     select to_jsonb(count(*)) from i$q$, '23514');

-- İade: sayaç bir azalır, 0'ın altına inmez; authenticated çağıramaz.
select tf.fails('authenticated refund_ai_quota çalıştıramaz', 'authenticated', :A,
  $q$select to_jsonb(public.refund_ai_quota('c1000000-0000-0000-0000-000000000001', 'ai'))$q$, '42501');
select tf.eq('iade öncesi kota düşer',
  tf.run('service_role', null, $q$select to_jsonb(public.consume_ai_quota('c2000000-0000-0000-0000-000000000002', 'iade', 5))$q$),
  'true'::jsonb);
select tf.eq('sayaç 1',
  (select to_jsonb(count) from public.ai_usage where user_id='c2000000-0000-0000-0000-000000000002' and kind='iade'),
  '1'::jsonb);
select tf.run('service_role', null, $q$select to_jsonb(1) from (select public.refund_ai_quota('c2000000-0000-0000-0000-000000000002', 'iade')) x$q$);
select tf.run('service_role', null, $q$select to_jsonb(1) from (select public.refund_ai_quota('c2000000-0000-0000-0000-000000000002', 'iade')) x$q$);
select tf.eq('iade sayacı 0 yapar, negatife indirmez',
  (select to_jsonb(count) from public.ai_usage where user_id='c2000000-0000-0000-0000-000000000002' and kind='iade'),
  '0'::jsonb);

-- Proje geneli günlük sayaç (ICG2-02): yalnızca service_role; sınırda durur.
select tf.fails('authenticated consume_global_ai_quota çalıştıramaz', 'authenticated', :A,
  $q$select to_jsonb(public.consume_global_ai_quota(10))$q$, '42501');
select tf.eq('genel kota: limit 2 → true, true, false',
  jsonb_build_array(public.consume_global_ai_quota(2), public.consume_global_ai_quota(2),
                    public.consume_global_ai_quota(2)),
  '[true, true, false]'::jsonb);
select tf.eq('genel kota: limit 0 her zaman false',
  to_jsonb(public.consume_global_ai_quota(0)), 'false'::jsonb);

\echo tamam: AI kotası testleri geçti
