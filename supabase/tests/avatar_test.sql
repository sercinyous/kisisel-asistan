-- Profil avatarı (sürüm 8): user_settings avatar sütunları, arkadaş RPC'lerinde
-- avatar alanları ve Storage `avatars` kovası politikaları (sahip kendi
-- klasörüne yazar, başkasınınkine yazamaz; arkadaş okur, yabancı okuyamaz).
-- Çalıştırma: supabase/tests/run_local.sh (storage_stub.sql + schema.sql sonrası).
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

select tf.mkuser('b1000000-0000-0000-0000-000000000001', 'sahip@example.com');
select tf.mkuser('b2000000-0000-0000-0000-000000000002', 'arkadas@example.com');
select tf.mkuser('b3000000-0000-0000-0000-000000000003', 'yabanci@example.com');
insert into public.friendships (user_a, user_b)
values ('b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002');

\set U1 '''b1000000-0000-0000-0000-000000000001'''
\set U2 '''b2000000-0000-0000-0000-000000000002'''
\set U3 '''b3000000-0000-0000-0000-000000000003'''

-- 1) Kova ve sütunlar ---------------------------------------------------
select tf.ok('avatars kovası özel',
  (select public = false from storage.buckets where id = 'avatars'));
select tf.eq('varsayılan avatar baş harfler',
  tf.run('authenticated', :U1,
    $q$select to_jsonb(avatar_kind) from public.user_settings$q$),
  '"initials"');
select tf.fails('geçersiz avatar türü reddedilir', 'authenticated', :U1,
  $q$update public.user_settings set avatar_kind = 'emoji' returning to_jsonb(1)$q$, '23514');
select tf.eq('sahip maskot seçer',
  tf.run('authenticated', :U1,
    $q$update public.user_settings set avatar_kind = 'mascot', avatar_mascot = 'bal_porsugu',
         avatar_color = 'accent' returning to_jsonb(avatar_mascot)$q$),
  '"bal_porsugu"');

-- 2) Arkadaş RPC'leri avatarı döndürür ----------------------------------
select tf.eq('my_friends arkadaşın avatarını döndürür',
  tf.run('authenticated', :U2,
    $q$select jsonb_agg(jsonb_build_array(f.avatar_kind, f.avatar_mascot, f.avatar_color, f.avatar_version))
       from public.my_friends() f$q$),
  '[["mascot", "bal_porsugu", "accent", 0]]');
select tf.eq('friend_leaderboard avatar alanlarını döndürür',
  tf.run('authenticated', :U2,
    $q$select jsonb_agg(jsonb_build_array(l.is_self, l.avatar_kind, l.avatar_mascot) order by l.is_self)
       from public.friend_leaderboard(date_trunc('week', now())::date) l$q$),
  '[[false, "mascot", "bal_porsugu"], [true, "initials", null]]');

-- 3) Storage politikaları -----------------------------------------------
select tf.eq('sahip kendi klasörüne yazar',
  tf.run('authenticated', :U1,
    $q$insert into storage.objects (bucket_id, name)
       values ('avatars', 'b1000000-0000-0000-0000-000000000001/avatar.jpg')
       returning to_jsonb(name)$q$),
  '"b1000000-0000-0000-0000-000000000001/avatar.jpg"');
select tf.eq('sahip kendi dosyasını günceller (upsert)',
  tf.run('authenticated', :U1,
    $q$update storage.objects set created_at = now()
       where name = 'b1000000-0000-0000-0000-000000000001/avatar.jpg'
       returning to_jsonb(true)$q$),
  'true');
select tf.fails('sahip başkasının klasörüne yazamaz', 'authenticated', :U1,
  $q$insert into storage.objects (bucket_id, name)
     values ('avatars', 'b2000000-0000-0000-0000-000000000002/avatar.jpg')
     returning to_jsonb(1)$q$, '42501');
select tf.fails('kök dizine yazılamaz', 'authenticated', :U1,
  $q$insert into storage.objects (bucket_id, name)
     values ('avatars', 'avatar.jpg') returning to_jsonb(1)$q$, '42501');
select tf.eq('arkadaş fotoğrafı okur',
  tf.run('authenticated', :U2,
    $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'avatars'$q$),
  '1');
select tf.eq('yabancı fotoğrafı okuyamaz',
  tf.run('authenticated', :U3,
    $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'avatars'$q$),
  '0');
select tf.fails('anon okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'avatars'$q$, '42501');
select tf.eq('arkadaş güncelleyemez (0 satır)',
  tf.run('authenticated', :U2,
    $q$with x as (update storage.objects set created_at = now()
       where bucket_id = 'avatars' returning 1) select to_jsonb(count(*)) from x$q$),
  '0');
select tf.eq('arkadaş silemez (0 satır)',
  tf.run('authenticated', :U2,
    $q$with x as (delete from storage.objects
       where bucket_id = 'avatars' returning 1) select to_jsonb(count(*)) from x$q$),
  '0');
delete from public.friendships where user_a = 'b1000000-0000-0000-0000-000000000001';
select tf.eq('arkadaşlık bitince okuma kapanır',
  tf.run('authenticated', :U2,
    $q$select to_jsonb(count(*)) from storage.objects where bucket_id = 'avatars'$q$),
  '0');
select tf.eq('sahip kendi dosyasını siler',
  tf.run('authenticated', :U1,
    $q$with x as (delete from storage.objects
       where bucket_id = 'avatars' returning 1) select to_jsonb(count(*)) from x$q$),
  '1');
