-- Açık kayıt: davet kapısı kaldırıldı. auth.users üzerindeki signup_invite_gate
-- tetikleyicisi (Supabase'de silinemediği için) yerinde kalır ama her satırı
-- geçirir; "Before User Created" kancası da her zaman izin verir.
-- Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

\set A '''9a000000-0000-0000-0000-000000000001'''
\set N '''9f000000-0000-0000-0000-000000000001'''

-- 0) Eski kapı yardımcı işlevi kaldırıldı.
select tf.ok('has_pending_invite kaldırıldı',
  to_regprocedure('public.has_pending_invite(text)') is null);

-- 1) Davetsiz e-posta hesap açabilir.
insert into auth.users (id, email, email_confirmed_at)
values (:N, 'davetsiz@example.com', now());
select tf.ok('davetsiz e-posta hesap açabildi',
  exists (select 1 from auth.users where id = :N));
select tf.ok('yeni hesabın ayar satırı açıldı, kılavuz bekliyor (onboarded_at boş)',
  exists (select 1 from public.user_settings
          where user_id = :N and onboarded_at is null));
select tf.eq('yeni hesaba rutin/görev/not/tartı yüklenmedi',
  (select to_jsonb(count(*)) from (
    select 1 from public.routines where user_id = :N
    union all select 1 from public.tasks where user_id = :N
    union all select 1 from public.notes where user_id = :N
    union all select 1 from public.fitness_logs where user_id = :N
  ) z),
  '0'::jsonb);

-- 2) Henüz kaydolmamış e-postaya gönderilen istek, kayıttan sonra görünür.
select tf.mkuser('9a000000-0000-0000-0000-000000000001', 'acik-a@example.com');
select tf.eq('A, sonra-gelen@example.com adresine istek gönderir',
  tf.run('authenticated', :A, $q$select to_jsonb(public.send_friend_request('Sonra-Gelen@Example.com '))$q$),
  '"İstek gönderildi"'::jsonb);
insert into auth.users (id, email, email_confirmed_at)
values ('9f000000-0000-0000-0000-000000000010', 'SONRA-GELEN@example.com', now());
select tf.eq('hesabı sonradan açılan kişi isteği görür',
  tf.run('authenticated', '9f000000-0000-0000-0000-000000000010',
    $q$select (select count(*) from public.my_incoming_requests())::text::jsonb$q$),
  '1'::jsonb);

-- 3) Hook her durumda boş nesne döner.
select tf.eq('hook: herhangi bir e-posta için boş nesne döner',
  public.hook_before_user_created('{"user":{"email":"yok@example.com"}}'::jsonb),
  '{}'::jsonb);
select tf.eq('hook: e-postasız kullanıcı için de boş nesne döner',
  public.hook_before_user_created('{"user":{}}'::jsonb),
  '{}'::jsonb);

-- 4) Yetkiler: kanca ve tetikleyici işlevini istemci rolleri çalıştıramaz.
select tf.fails('authenticated hook''u çalıştıramaz', 'authenticated', :A,
  $q$select public.hook_before_user_created('{}'::jsonb)::text::jsonb$q$, '42501');
select tf.fails('anon hook''u çalıştıramaz', 'anon', null,
  $q$select public.hook_before_user_created('{}'::jsonb)::text::jsonb$q$, '42501');
select tf.fails('authenticated tetikleyici işlevini çalıştıramaz', 'authenticated', :A,
  $q$select to_jsonb(public.enforce_signup_invite() is null)$q$, '42501');

\echo tamam: açık kayıt testleri geçti
