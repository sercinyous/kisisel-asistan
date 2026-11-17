-- Kayıt kapısı (Faz 4B): auth.users üzerindeki before insert tetikleyicisi
-- signup_invite_gate. Yalnızca en az bir kullanıcıdan BEKLEYEN arkadaş isteği
-- almış e-posta hesap açabilir; mevcut hesaplar etkilenmez.
-- Bu test, şema yeni kurulmuş (kapı varsayılan açık) bir veritabanında İLK
-- çalışır. Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

-- 0) Varsayılan: kapı kurulum sonrası AÇIK ve "before insert, her satır".
select tf.ok('kapı tetikleyicisi kurulu, açık ve before insert',
  exists (
    select 1 from pg_trigger g
    where g.tgrelid = 'auth.users'::regclass and g.tgname = 'signup_invite_gate'
      and g.tgenabled = 'O' and (g.tgtype & 2) = 2 and (g.tgtype & 4) = 4
  ));

-- Gönderen hesaplar kapı kapalıyken açılır (kapının "mevcut hesap" tarafı).
alter table auth.users disable trigger signup_invite_gate;
select tf.mkuser('9a000000-0000-0000-0000-000000000001', 'gate-a@example.com');
select tf.mkuser('9b000000-0000-0000-0000-000000000002', 'gate-b@example.com');
select tf.mkuser('9c000000-0000-0000-0000-000000000003', 'gate-c@example.com');
alter table auth.users enable trigger signup_invite_gate;

\set A '''9a000000-0000-0000-0000-000000000001'''
\set B '''9b000000-0000-0000-0000-000000000002'''
\set C '''9c000000-0000-0000-0000-000000000003'''

-- 1) Davetsiz e-posta hesap açamaz.
do $$
declare
  v_msg text;
begin
  begin
    insert into auth.users (id, email, email_confirmed_at)
    values ('9f000000-0000-0000-0000-000000000001', 'davetsiz@example.com', now());
    raise exception 'BAŞARISIZ: davetsiz e-posta hesap açabildi';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'Bu e-posta için davet yok' then
      raise exception 'BAŞARISIZ: beklenmeyen hata: %', v_msg;
    end if;
  end;
  begin
    insert into auth.users (id, email) values ('9f000000-0000-0000-0000-000000000002', null);
    raise exception 'BAŞARISIZ: e-postasız hesap açılabildi';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'Bu e-posta için davet yok' then
      raise exception 'BAŞARISIZ: e-postasız hesapta beklenmeyen hata: %', v_msg;
    end if;
  end;
  begin
    insert into auth.users (id, email) values ('9f000000-0000-0000-0000-000000000003', '   ');
    raise exception 'BAŞARISIZ: boş e-posta ile hesap açılabildi';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'Bu e-posta için davet yok' then
      raise exception 'BAŞARISIZ: boş e-postada beklenmeyen hata: %', v_msg;
    end if;
  end;
  raise notice 'tamam: davetsiz, e-postasız ve boş e-posta reddedilir';
end;
$$;

-- 2) Bekleyen davet kapıyı açar (büyük/küçük harf ve boşluk fark etmez).
select tf.eq('A, davetli@example.com adresine istek gönderir',
  tf.run('authenticated', :A, $q$select to_jsonb(public.send_friend_request('Davetli@Example.com '))$q$),
  '"İstek gönderildi"'::jsonb);
insert into auth.users (id, email, email_confirmed_at)
values ('9f000000-0000-0000-0000-000000000010', 'DAVETLI@example.com', now());
select tf.ok('davetli e-posta hesap açabildi',
  exists (select 1 from auth.users where id = '9f000000-0000-0000-0000-000000000010'));
select tf.ok('yeni hesabın ayar satırı açıldı, kılavuz bekliyor (onboarded_at boş)',
  exists (select 1 from public.user_settings
          where user_id = '9f000000-0000-0000-0000-000000000010' and onboarded_at is null));
select tf.eq('yeni hesaba rutin/görev/not/tartı yüklenmedi',
  (select to_jsonb(count(*)) from (
    select 1 from public.routines where user_id = '9f000000-0000-0000-0000-000000000010'
    union all select 1 from public.tasks where user_id = '9f000000-0000-0000-0000-000000000010'
    union all select 1 from public.notes where user_id = '9f000000-0000-0000-0000-000000000010'
    union all select 1 from public.fitness_logs where user_id = '9f000000-0000-0000-0000-000000000010'
  ) z),
  '0'::jsonb);

-- Hesap açılınca davet doğrulanmış e-postayla gelen kutusunda görünür.
select tf.eq('hesabı sonradan açılan kişi daveti görür',
  tf.run('authenticated', '9f000000-0000-0000-0000-000000000010',
    $q$select (select count(*) from public.my_incoming_requests())::text::jsonb$q$),
  '1'::jsonb);

-- 3) Kapı yalnızca BEKLEYEN isteğe bakar: iptal, red ve kabul açmaz.
select tf.eq('B, iptal-edilecek@example.com adresine istek gönderir',
  tf.run('authenticated', :B, $q$select to_jsonb(public.send_friend_request('iptal-edilecek@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.run('authenticated', :B, format(
  $q$select to_jsonb(count(*)) from (select public.cancel_friend_request(%L::uuid)) z$q$,
  (select id from public.friend_requests
   where from_user = :B and target_email = 'iptal-edilecek@example.com')));
select tf.ok('istek iptal edildi (satır silindi)',
  not exists (select 1 from public.friend_requests where target_email = 'iptal-edilecek@example.com'));
select tf.fails('iptal edilen davet kapıyı açmaz', 'postgres', null,
  $q$insert into auth.users (id, email) values ('9f000000-0000-0000-0000-000000000020', 'iptal-edilecek@example.com') returning to_jsonb(id)$q$,
  'P0001', 'Bu e-posta için davet yok');

insert into public.friend_requests (from_user, target_email, status, responded_at)
values (:A, 'reddedilen@example.com', 'declined', now()),
       (:A, 'kabul-edilen@example.com', 'accepted', now());
select tf.fails('reddedilmiş davet kapıyı açmaz', 'postgres', null,
  $q$insert into auth.users (id, email) values ('9f000000-0000-0000-0000-000000000021', 'reddedilen@example.com') returning to_jsonb(id)$q$,
  'P0001', 'Bu e-posta için davet yok');
select tf.fails('kabul edilmiş (bitmiş) davet kapıyı açmaz', 'postgres', null,
  $q$insert into auth.users (id, email) values ('9f000000-0000-0000-0000-000000000022', 'kabul-edilen@example.com') returning to_jsonb(id)$q$,
  'P0001', 'Bu e-posta için davet yok');

-- 4) Gönderen hesap silinince bekleyen isteği de gider, kapı kapanır.
select tf.eq('C, silinecek-davet@example.com adresine istek gönderir',
  tf.run('authenticated', :C, $q$select to_jsonb(public.send_friend_request('silinecek-davet@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.ok('istek bekliyor',
  exists (select 1 from public.friend_requests where from_user = :C and status = 'pending'));
delete from auth.users where id = :C;
select tf.fails('göndereni silinen davet kapıyı açmaz', 'postgres', null,
  $q$insert into auth.users (id, email) values ('9f000000-0000-0000-0000-000000000023', 'silinecek-davet@example.com') returning to_jsonb(id)$q$,
  'P0001', 'Bu e-posta için davet yok');

-- 5) Mevcut hesaplar etkilenmez: güncelleme ve silme serbest.
update auth.users set email = 'gate-b-yeni@example.com' where id = :B;
update auth.users set email = 'gate-b@example.com' where id = :B;
select tf.ok('mevcut hesap güncellenebilir', exists (select 1 from auth.users where id = :B));

-- 6) Hook işlevi (isteğe bağlı "Before User Created"): aynı kural, 403 mesajı.
select tf.eq('A, yeni-davetli@example.com adresine istek gönderir',
  tf.run('authenticated', :A, $q$select to_jsonb(public.send_friend_request('yeni-davetli@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('hook: davetli e-posta için boş nesne döner',
  public.hook_before_user_created('{"user":{"email":"Yeni-Davetli@example.com"}}'::jsonb),
  '{}'::jsonb);
select tf.eq('hook: davetsiz e-posta için 403 hatası döner',
  public.hook_before_user_created('{"user":{"email":"yok@example.com"}}'::jsonb),
  '{"error": {"message": "Bu e-posta için davet yok", "http_code": 403}}'::jsonb);
select tf.eq('hook: e-postasız kullanıcı için 403 hatası döner',
  public.hook_before_user_created('{"user":{}}'::jsonb),
  '{"error": {"message": "Bu e-posta için davet yok", "http_code": 403}}'::jsonb);

-- 7) Yetkiler: kapı işlevlerini istemci rolleri çalıştıramaz.
select tf.fails('authenticated has_pending_invite çalıştıramaz', 'authenticated', :A,
  $q$select to_jsonb(public.has_pending_invite('a@b.co'))$q$, '42501');
select tf.fails('anon has_pending_invite çalıştıramaz', 'anon', null,
  $q$select to_jsonb(public.has_pending_invite('a@b.co'))$q$, '42501');
select tf.fails('authenticated kapı hook''unu çalıştıramaz', 'authenticated', :A,
  $q$select public.hook_before_user_created('{}'::jsonb)::text::jsonb$q$, '42501');
select tf.fails('anon kapı hook''unu çalıştıramaz', 'anon', null,
  $q$select public.hook_before_user_created('{}'::jsonb)::text::jsonb$q$, '42501');
select tf.fails('authenticated tetikleyici işlevini çalıştıramaz', 'authenticated', :A,
  $q$select to_jsonb(public.enforce_signup_invite() is null)$q$, '42501');

\echo tamam: kayıt kapısı testleri geçti
