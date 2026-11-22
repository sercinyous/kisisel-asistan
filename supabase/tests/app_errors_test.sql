-- Hata takibi ve Sorun bildir (Faz 5): app_errors/feedback yalnızca ekleme;
-- kullanıcı ne kendi ne başkasının satırını okuyabilir; başkası adına yazamaz;
-- app_errors kişi başına günde 50 kayıtla sınırlı. Çalıştırma: run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

select tf.mkuser('fb500000-0000-0000-0000-000000000001', 'faz5-hata1@example.com');
select tf.mkuser('fb500000-0000-0000-0000-000000000002', 'faz5-hata2@example.com');

select tf.run('authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ with i as (insert into public.app_errors (message, stack, app_version, platform)
     values ('boom', 'st', '1.0.0', 'ios')) select null::jsonb $q$);
select tf.run('authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ with i as (insert into public.feedback (message, category, app_version)
     values ('Bir öneri', 'öneri', '1.0.0')) select null::jsonb $q$);
select tf.eq('hata kaydı eklendi (user_id = auth.uid())',
  (select to_jsonb(count(*)) from public.app_errors where user_id = 'fb500000-0000-0000-0000-000000000001'), '1'::jsonb);
select tf.eq('geri bildirim eklendi',
  (select to_jsonb(count(*)) from public.feedback where user_id = 'fb500000-0000-0000-0000-000000000001'), '1'::jsonb);

select tf.fails('kendi hatasını okuyamaz', 'authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ select to_jsonb(count(*)) from public.app_errors $q$, '42501');
select tf.fails('başkasının hatasını okuyamaz', 'authenticated', 'fb500000-0000-0000-0000-000000000002',
  $q$ select to_jsonb(count(*)) from public.app_errors where user_id = 'fb500000-0000-0000-0000-000000000001' $q$, '42501');
select tf.fails('geri bildirimi okuyamaz', 'authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ select to_jsonb(count(*)) from public.feedback $q$, '42501');
select tf.fails('başkası adına hata yazamaz', 'authenticated', 'fb500000-0000-0000-0000-000000000002',
  $q$ with i as (insert into public.app_errors (user_id, message) values ('fb500000-0000-0000-0000-000000000001', 'x')) select null::jsonb $q$,
  '42501');
select tf.fails('başkası adına geri bildirim yazamaz', 'authenticated', 'fb500000-0000-0000-0000-000000000002',
  $q$ with i as (insert into public.feedback (user_id, message) values ('fb500000-0000-0000-0000-000000000001', 'x')) select null::jsonb $q$,
  '42501');
select tf.fails('anon hata yazamaz', 'anon', null,
  $q$ with i as (insert into public.app_errors (message) values ('x')) select null::jsonb $q$, '42501');
select tf.fails('silinemez', 'authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ with i as (delete from public.app_errors) select null::jsonb $q$, '42501');
select tf.fails('çok uzun mesaj reddedilir', 'authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ with i as (insert into public.app_errors (message) values (repeat('a', 2001))) select null::jsonb $q$,
  '23514');

-- Günlük sınır: 50. kayda kadar kabul, 51. reddedilir.
do $$
begin
  for i in 1..49 loop
    perform tf.run('authenticated', 'fb500000-0000-0000-0000-000000000001',
      $q$ with i as (insert into public.app_errors (message) values ('tekrar')) select null::jsonb $q$);
  end loop;
end;
$$;
select tf.fails('günde 50 hatadan fazlası reddedilir', 'authenticated', 'fb500000-0000-0000-0000-000000000001',
  $q$ with i as (insert into public.app_errors (message) values ('fazla')) select null::jsonb $q$,
  'P0001', 'rate limit');
select tf.eq('sınır yalnızca o kullanıcıya',
  tf.run('authenticated', 'fb500000-0000-0000-0000-000000000002',
    $q$ with i as (insert into public.app_errors (message) values ('ilk')) select null::jsonb $q$),
  null);
