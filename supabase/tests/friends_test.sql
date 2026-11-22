-- Arkadaşlar (Faz 4B): istek gönderme/gelen kutusu/kabul/red/iptal, arkadaş
-- listesi, paylaşım anahtarları, hedef özeti ve YETKİ SINIRLARI (bir kullanıcı
-- başkasının satırını ya da ham verisini okuyamaz, anon çağıramaz).
-- Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

-- Fikstür kullanıcıları kapı kapalıyken açılır (kapı signup_gate_test.sql'de).
select tf.mkuser('a1000000-0000-0000-0000-000000000001', 'ali@example.com');
select tf.mkuser('a2000000-0000-0000-0000-000000000002', 'veli@example.com');
select tf.mkuser('a3000000-0000-0000-0000-000000000003', 'ayse@example.com');
select tf.mkuser('a4000000-0000-0000-0000-000000000004', 'dogrulanmamis@example.com', false);
select tf.mkuser('a5000000-0000-0000-0000-000000000005', 'yabanci@example.com');
update public.user_settings set display_name = 'Ali'
  where user_id = 'a1000000-0000-0000-0000-000000000001';
update public.user_settings set display_name = 'Ayşe'
  where user_id = 'a3000000-0000-0000-0000-000000000003';

\set U1 '''a1000000-0000-0000-0000-000000000001'''
\set U2 '''a2000000-0000-0000-0000-000000000002'''
\set U3 '''a3000000-0000-0000-0000-000000000003'''
\set U4 '''a4000000-0000-0000-0000-000000000004'''
\set U5 '''a5000000-0000-0000-0000-000000000005'''

-- 1) Yetkiler: işlev ve tablo -----------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.send_friend_request(text)', 'public.my_incoming_requests()',
    'public.my_outgoing_requests()', 'public.cancel_friend_request(uuid)',
    'public.respond_friend_request(uuid, boolean)', 'public.my_friends()',
    'public.friend_goal_summary(uuid, date)', 'public.leave_friendship(uuid)']
  loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'BAŞARISIZ: anon % çalıştırabiliyor', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'BAŞARISIZ: authenticated % çalıştıramıyor', f;
    end if;
  end loop;
  foreach f in array array[
    'public.friend_mask_email(text)', 'public.verified_email_of(uuid)',
    'public.friend_display_name(uuid)', 'public.safe_timezone(text)',
    'public.goal_steps_hit(bigint, integer)', 'public.goal_sleep_hit(bigint, integer)',
    'public.goal_calories_hit(numeric, integer)',
    'public.consume_ai_quota(uuid, text, integer)']
  loop
    if has_function_privilege('anon', f, 'execute')
       or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'BAŞARISIZ: istemci rolü % çalıştırabiliyor', f;
    end if;
  end loop;
  -- Tablolar: RLS açık; anon hiçbir şey; authenticated yalnızca en dar yetki.
  foreach f in array array['friend_requests', 'friendships', 'friend_sharing', 'ai_usage']
  loop
    if not (select relrowsecurity from pg_class where oid = ('public.' || f)::regclass) then
      raise exception 'BAŞARISIZ: % tablosunda RLS kapalı', f;
    end if;
    if has_table_privilege('anon', 'public.' || f, 'select')
       or has_table_privilege('anon', 'public.' || f, 'insert')
       or has_any_column_privilege('anon', 'public.' || f, 'select') then
      raise exception 'BAŞARISIZ: anon % tablosuna erişebiliyor', f;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.friend_requests', 'select')
     or has_column_privilege('authenticated', 'public.friend_requests', 'target_user', 'select')
     or has_any_column_privilege('authenticated', 'public.friend_requests', 'insert')
     or has_any_column_privilege('authenticated', 'public.friend_requests', 'update')
     or has_table_privilege('authenticated', 'public.friend_requests', 'delete') then
    raise exception 'BAŞARISIZ: friend_requests yetkileri fazla geniş';
  end if;
  if has_any_column_privilege('authenticated', 'public.friendships', 'insert')
     or has_any_column_privilege('authenticated', 'public.friendships', 'update')
     or has_table_privilege('authenticated', 'public.friendships', 'delete') then
    raise exception 'BAŞARISIZ: friendships yazılabilir';
  end if;
  if has_any_column_privilege('authenticated', 'public.ai_usage', 'insert')
     or has_any_column_privilege('authenticated', 'public.ai_usage', 'update')
     or has_table_privilege('authenticated', 'public.ai_usage', 'delete') then
    raise exception 'BAŞARISIZ: ai_usage istemciden yazılabilir';
  end if;
  raise notice 'tamam: işlev ve tablo yetkileri';
end;
$$;

select tf.fails('anon send_friend_request çağıramaz', 'anon', null,
  $q$select to_jsonb(public.send_friend_request('a@b.co'))$q$, '42501');
select tf.fails('anon my_friends çağıramaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.my_friends()$q$, '42501');
select tf.fails('anon friend_goal_summary çağıramaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.friend_goal_summary('a1000000-0000-0000-0000-000000000001', '2026-01-05')$q$, '42501');
select tf.fails('anon friend_requests okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.friend_requests$q$, '42501');
select tf.fails('anon friendships okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.friendships$q$, '42501');
select tf.fails('anon friend_sharing okuyamaz', 'anon', null,
  $q$select to_jsonb(count(*)) from public.friend_sharing$q$, '42501');

-- Oturumsuz (auth.uid() boş) authenticated çağrısı da reddedilir.
select tf.fails('oturumsuz send_friend_request', 'authenticated', null,
  $q$select to_jsonb(public.send_friend_request('a@b.co'))$q$, '28000');
select tf.fails('oturumsuz my_incoming_requests', 'authenticated', null,
  $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$, '28000');
select tf.fails('oturumsuz my_outgoing_requests', 'authenticated', null,
  $q$select to_jsonb(count(*)) from public.my_outgoing_requests()$q$, '28000');
select tf.fails('oturumsuz my_friends', 'authenticated', null,
  $q$select to_jsonb(count(*)) from public.my_friends()$q$, '28000');
select tf.fails('oturumsuz friend_goal_summary', 'authenticated', null,
  $q$select to_jsonb(count(*)) from public.friend_goal_summary('a1000000-0000-0000-0000-000000000001', '2026-01-05')$q$, '28000');
select tf.fails('oturumsuz cancel_friend_request', 'authenticated', null,
  $q$select to_jsonb(count(*)) from (select public.cancel_friend_request(gen_random_uuid())) z$q$, '28000');
select tf.fails('oturumsuz respond_friend_request', 'authenticated', null,
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(gen_random_uuid(), true)) z$q$, '28000');
select tf.fails('oturumsuz leave_friendship', 'authenticated', null,
  $q$select to_jsonb(count(*)) from (select public.leave_friendship(gen_random_uuid())) z$q$, '28000');

-- 2) İstek gönderme: e-posta sorgulanamaz -----------------------------
select tf.eq('hesabı olan e-postaya istek: sabit cevap',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request('veli@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('hesabı OLMAYAN e-postaya istek: aynı cevap',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request('kimse-yok@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('doğrulanmamış hesabın e-postasına istek: aynı cevap',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request('dogrulanmamis@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('kendine istek: aynı cevap',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request('  ALI@example.com '))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('tekrar istek (büyük harf/boşluk): aynı cevap',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request(' VELI@Example.com'))$q$),
  '"İstek gönderildi"'::jsonb);

select tf.eq('bekleyen istek sayısı: kendine ve tekrar sayılmaz (3)',
  (select to_jsonb(count(*)) from public.friend_requests where from_user = :U1 and status = 'pending'),
  '3'::jsonb);
select tf.ok('hedef e-posta küçük harf; doğrulanmış hesaba bağlanır, hesapsız/doğrulanmamışa bağlanmaz',
  (select target_user = :U2 from public.friend_requests where from_user = :U1 and target_email = 'veli@example.com')
  and (select target_user is null from public.friend_requests where from_user = :U1 and target_email = 'kimse-yok@example.com')
  and (select target_user is null from public.friend_requests where from_user = :U1 and target_email = 'dogrulanmamis@example.com'));

select tf.fails('geçersiz e-posta reddedilir', 'authenticated', :U1,
  $q$select to_jsonb(public.send_friend_request('bu-bir-eposta-degil'))$q$, '22023');
select tf.fails('boş e-posta reddedilir', 'authenticated', :U1,
  $q$select to_jsonb(public.send_friend_request('   '))$q$, '22023');
select tf.fails('null e-posta reddedilir', 'authenticated', :U1,
  $q$select to_jsonb(public.send_friend_request(null))$q$, '22023');

-- Kullanıcı başına en çok 20 bekleyen istek.
do $$
declare
  i integer;
begin
  for i in 1..20 loop
    perform tf.run('authenticated', 'a3000000-0000-0000-0000-000000000003'::uuid,
      format($q$select to_jsonb(public.send_friend_request('limit%s@example.com'))$q$, i));
  end loop;
end;
$$;
select tf.fails('21. bekleyen istek reddedilir', 'authenticated', :U3,
  $q$select to_jsonb(public.send_friend_request('limit21@example.com'))$q$, '54000');
select tf.fails('sınırdayken tekrar istek de (hedef bilgisi sızmasın) aynı hatayı verir', 'authenticated', :U3,
  $q$select to_jsonb(public.send_friend_request('limit1@example.com'))$q$, '54000');
select tf.run('authenticated', :U3, format(
  $q$select to_jsonb(count(*)) from (select public.cancel_friend_request(%L::uuid)) z$q$,
  (select id from public.friend_requests where from_user = :U3 and target_email = 'limit20@example.com')));
select tf.eq('iptalden sonra yeni istek yine olur',
  tf.run('authenticated', :U3, $q$select to_jsonb(public.send_friend_request('limit21@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
-- U3'ün istekleri temizlenir (sonraki testler için).
delete from public.friend_requests where from_user = :U3;

-- 3) Giden istekler ve iptal ------------------------------------------
select tf.eq('giden istekler: yalnızca benimkiler, hedef e-posta ile',
  tf.run('authenticated', :U1,
    $q$select jsonb_agg(r.target_email order by r.target_email) from public.my_outgoing_requests() r$q$),
  '["dogrulanmamis@example.com", "kimse-yok@example.com", "veli@example.com"]'::jsonb);
select tf.eq('başkasının giden istekleri görünmez',
  tf.run('authenticated', :U2, $q$select to_jsonb(count(*)) from public.my_outgoing_requests()$q$),
  '0'::jsonb);

-- Başkasının isteğini iptal edemez (sessizce hiçbir şey olmaz).
select tf.run('authenticated', :U2, format(
  $q$select to_jsonb(count(*)) from (select public.cancel_friend_request(%L::uuid)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'kimse-yok@example.com')));
select tf.ok('başkası iptal edemedi',
  exists (select 1 from public.friend_requests where from_user = :U1 and target_email = 'kimse-yok@example.com'));
select tf.run('authenticated', :U1, format(
  $q$select to_jsonb(count(*)) from (select public.cancel_friend_request(%L::uuid)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'kimse-yok@example.com')));
select tf.ok('gönderen iptal etti',
  not exists (select 1 from public.friend_requests where target_email = 'kimse-yok@example.com'));

-- 4) Gelen kutusu: yalnızca doğrulanmış e-posta ya da hedef kullanıcı ---
select tf.eq('U2 gelen kutusunda Ali var (görünen adla)',
  tf.run('authenticated', :U2, $q$select jsonb_agg(r.from_name) from public.my_incoming_requests() r$q$),
  '["Ali"]'::jsonb);
select tf.eq('U3 (alakasız) gelen kutusu boş',
  tf.run('authenticated', :U3, $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$),
  '0'::jsonb);
select tf.eq('doğrulanmamış e-postalı hesap daveti GÖRMEZ',
  tf.run('authenticated', :U4, $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$),
  '0'::jsonb);
update auth.users set email_confirmed_at = now() where id = :U4;
select tf.eq('e-posta doğrulanınca davet görünür',
  tf.run('authenticated', :U4, $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$),
  '1'::jsonb);
update auth.users set email_confirmed_at = null where id = :U4;

-- Hesabı sonradan açılan kişi: davet e-postayla beklerken hesap doğrulanmış gelir.
select tf.eq('Ali, sonradan-acilan@example.com adresine istek gönderir',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request('sonradan-acilan@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.mkuser('a6000000-0000-0000-0000-000000000006', 'Sonradan-Acilan@Example.com', false);
select tf.eq('hesap sonradan, DOĞRULANMAMIŞ açılırsa davet görünmez',
  tf.run('authenticated', 'a6000000-0000-0000-0000-000000000006',
    $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$),
  '0'::jsonb);
update auth.users set email_confirmed_at = now() where id = 'a6000000-0000-0000-0000-000000000006';
select tf.eq('hesap sonradan doğrulanınca davet görünür',
  tf.run('authenticated', 'a6000000-0000-0000-0000-000000000006',
    $q$select jsonb_agg(r.from_name) from public.my_incoming_requests() r$q$),
  '["Ali"]'::jsonb);

-- Görünen adı olmayan gönderen: maskelenmiş e-posta.
select tf.eq('Veli → Ayşe isteği gönderilir (Veli''nin görünen adı yok)',
  tf.run('authenticated', :U2, $q$select to_jsonb(public.send_friend_request('ayse@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('Ayşe gelen kutusunda v***@example.com görür',
  tf.run('authenticated', :U3, $q$select jsonb_agg(r.from_name) from public.my_incoming_requests() r$q$),
  '["v***@example.com"]'::jsonb);

-- 5) Yanıt: yalnızca hedef kabul/red edebilir -------------------------
select tf.fails('alakasız kullanıcı yanıtlayamaz (varlık sızmaz)', 'authenticated', :U3, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, true)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'veli@example.com')),
  'P0002', 'İstek bulunamadı');
select tf.fails('gönderen kendi isteğini yanıtlayamaz', 'authenticated', :U1, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, true)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'veli@example.com')),
  'P0002');
select tf.fails('olmayan istek', 'authenticated', :U2,
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(gen_random_uuid(), true)) z$q$,
  'P0002');
select tf.fails('null kabul/red değeri', 'authenticated', :U2, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, null)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'veli@example.com')),
  '22023');
select tf.ok('hiçbiri arkadaşlık kurmadı', not exists (select 1 from public.friendships));

-- Veli (U2) Ali'nin isteğini kabul eder; Veli'nin Ayşe'ye giden isteği de bekliyor.
select tf.run('authenticated', :U2, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, true)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'veli@example.com')));
select tf.ok('arkadaşlık sıralı çift olarak kuruldu (user_a < user_b)',
  exists (select 1 from public.friendships where user_a = :U1 and user_b = :U2)
  and (select count(*) from public.friendships) = 1);
select tf.ok('istek durumu accepted',
  (select status = 'accepted' and responded_at is not null from public.friend_requests
   where from_user = :U1 and target_email = 'veli@example.com'));
select tf.fails('bitmiş isteği tekrar yanıtlama', 'authenticated', :U2, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, false)) z$q$,
  (select id from public.friend_requests where from_user = :U1 and target_email = 'veli@example.com')),
  'P0002');
select tf.eq('Veli artık Ali isteğini gelen kutusunda görmez',
  tf.run('authenticated', :U2, $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$),
  '0'::jsonb);
select tf.eq('zaten arkadaşa istek: aynı cevap, yeni satır yok',
  tf.run('authenticated', :U1, $q$select to_jsonb(public.send_friend_request('veli@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('zaten arkadaş: Veli de Ali''ye istek atınca satır açılmaz',
  tf.run('authenticated', :U2, $q$select to_jsonb(public.send_friend_request('ali@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.ok('arkadaşlara yeni bekleyen istek açılmadı',
  not exists (select 1 from public.friend_requests
              where status = 'pending' and target_email in ('veli@example.com', 'ali@example.com')));

-- Ayşe (U3) Veli'nin isteğini REDDEDER; arkadaşlık kurulmaz, Veli yeniden gönderebilir.
select tf.run('authenticated', :U3, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, false)) z$q$,
  (select id from public.friend_requests where from_user = :U2 and target_email = 'ayse@example.com')));
select tf.ok('reddedilen istek: arkadaşlık yok, durum declined',
  (select count(*) from public.friendships) = 1
  and (select status = 'declined' from public.friend_requests
       where from_user = :U2 and target_email = 'ayse@example.com'));
select tf.eq('reddedilen isteğin yerine yeni istek açılabilir',
  tf.run('authenticated', :U2, $q$select to_jsonb(public.send_friend_request('ayse@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.eq('Ayşe yeni isteği görür',
  tf.run('authenticated', :U3, $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$),
  '1'::jsonb);
-- Karşı taraf (Veli) Ayşe'ye zaten istek göndermişse Ayşe'nin isteği yeni satır açmaz
-- (cevap aynı; Veli'nin isteği zaten Ayşe'nin gelen kutusunda).
select tf.eq('Ayşe, ona zaten istek atmış Veli''ye istek gönderir: aynı cevap',
  tf.run('authenticated', :U3, $q$select to_jsonb(public.send_friend_request('veli@example.com'))$q$),
  '"İstek gönderildi"'::jsonb);
select tf.ok('karşı yönde yeni bekleyen satır açılmadı',
  not exists (select 1 from public.friend_requests where from_user = :U3 and status = 'pending'));
-- Eşzamanlı gönderimi taklit: karşı yönde de bekleyen istek (doğrudan, yönetici yetkisiyle).
insert into public.friend_requests (from_user, target_email, target_user)
values (:U3, 'veli@example.com', :U2);
select tf.run('authenticated', :U2, format(
  $q$select to_jsonb(count(*)) from (select public.respond_friend_request(%L::uuid, true)) z$q$,
  (select id from public.friend_requests where from_user = :U3 and target_email = 'veli@example.com' and status = 'pending')));
select tf.ok('Veli–Ayşe arkadaş; Veli''nin Ayşe''ye giden bekleyen isteği (karşı yön) silindi',
  exists (select 1 from public.friendships where user_a = :U2 and user_b = :U3)
  and not exists (select 1 from public.friend_requests
                  where status = 'pending' and from_user in (:U2, :U3)));

-- 6) Arkadaş listesi -----------------------------------------------------
select tf.eq('Ali''nin listesi: Veli, maskelenmiş e-posta, anahtarlar kapalı',
  tf.run('authenticated', :U1, $q$select jsonb_agg(to_jsonb(f)) from public.my_friends() f$q$),
  jsonb_build_array(jsonb_build_object(
    'friend_id', 'a2000000-0000-0000-0000-000000000002', 'display_name', 'v***@example.com',
    'share_steps', false, 'share_sleep', false, 'share_calories', false)));
select tf.eq('Veli''nin listesi: Ali ve Ayşe (ada göre)',
  tf.run('authenticated', :U2, $q$select jsonb_agg(f.display_name order by f.display_name) from public.my_friends() f$q$),
  '["Ali", "Ayşe"]'::jsonb);
select tf.eq('alakasız kullanıcının listesi boş',
  tf.run('authenticated', :U5, $q$select to_jsonb(count(*)) from public.my_friends()$q$),
  '0'::jsonb);

-- 7) Paylaşım anahtarları + hedef özeti -----------------------------------
-- Veli (U2): sabit geçmiş hafta 2026-01-05 (Pzt). Hedefler tablo varsayılanı:
-- 8000 adım, 450 dk uyku, 2000 kcal.
insert into public.daily_health_metrics (user_id, metric_date, steps, sleep_minutes) values
  (:U2, '2026-01-05', 9000, 420),   -- adım tutar, uyku tutar (≥405)
  (:U2, '2026-01-06', 3000, 400),   -- ikisi de tutmaz
  (:U2, '2026-01-07', 0, 0),        -- veri yok (paydada yok)
  (:U2, '2026-01-08', 8000, 450);   -- ikisi de tutar
insert into public.nutrition_logs (user_id, food_name, calories, eaten_at) values
  (:U2, 'a', 1000, '2026-01-05 09:00+03'), (:U2, 'b', 800, '2026-01-05 19:00+03'), -- 1800 → tutar
  (:U2, 'c', 3000, '2026-01-06 12:00+03');                                           -- 3000 → tutmaz

select tf.eq('anahtar kapalıyken özet: üç metrik de paylaşılmıyor, 0/0',
  tf.run('authenticated', :U1, $q$select jsonb_agg(to_jsonb(s)) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[{"metric":"steps","shared":false,"goal_days":0,"data_days":0},
    {"metric":"sleep","shared":false,"goal_days":0,"data_days":0},
    {"metric":"calories","shared":false,"goal_days":0,"data_days":0}]'::jsonb);

-- Veli kendi anahtarını upsert eder (uygulamanın PostgREST upsert'i).
select tf.run('authenticated', :U2, $q$with i as (
  insert into public.friend_sharing (user_id, share_steps) values (auth.uid(), true)
  on conflict (user_id) do update set share_steps = excluded.share_steps
  returning 1) select to_jsonb(count(*)) from i$q$);
select tf.eq('yalnızca adım açık: adım sayılır, uyku/kalori paylaşılmıyor',
  tf.run('authenticated', :U1, $q$select jsonb_agg(to_jsonb(s)) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[{"metric":"steps","shared":true,"goal_days":2,"data_days":3},
    {"metric":"sleep","shared":false,"goal_days":0,"data_days":0},
    {"metric":"calories","shared":false,"goal_days":0,"data_days":0}]'::jsonb);
select tf.run('authenticated', :U2, $q$with i as (
  insert into public.friend_sharing (user_id, share_sleep, share_calories, share_steps)
  values (auth.uid(), true, true, true)
  on conflict (user_id) do update set share_sleep = excluded.share_sleep,
    share_calories = excluded.share_calories, share_steps = excluded.share_steps
  returning 1) select to_jsonb(count(*)) from i$q$);
select tf.eq('üç anahtar açık: adım 2/3, uyku 2/3, kalori 1/2',
  tf.run('authenticated', :U1, $q$select jsonb_agg(to_jsonb(s)) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[{"metric":"steps","shared":true,"goal_days":2,"data_days":3},
    {"metric":"sleep","shared":true,"goal_days":2,"data_days":3},
    {"metric":"calories","shared":true,"goal_days":1,"data_days":2}]'::jsonb);
select tf.eq('özet yalnızca bu alanları taşır (tarih/değer yok)',
  tf.run('authenticated', :U1, $q$select jsonb_agg(distinct k) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s, jsonb_object_keys(to_jsonb(s)) k$q$),
  '["data_days", "goal_days", "metric", "shared"]'::jsonb);
select tf.eq('arkadaşın profili/ham verisi arkadaş listesinde de yok (yalnızca beş alan)',
  tf.run('authenticated', :U1, $q$select jsonb_agg(distinct k) from public.my_friends() s, jsonb_object_keys(to_jsonb(s)) k$q$),
  '["display_name", "friend_id", "share_calories", "share_sleep", "share_steps"]'::jsonb);
select tf.eq('arkadaşın anahtarları listede görünür',
  tf.run('authenticated', :U1, $q$select jsonb_agg(f.share_steps and f.share_sleep and f.share_calories) from public.my_friends() f$q$),
  '[true]'::jsonb);

-- Arkadaş OLMAYANLAR anahtar açık olsa da sayı göremez.
select tf.eq('arkadaş olmayan (Yabancı) özeti göremez',
  tf.run('authenticated', :U5, $q$select jsonb_agg(s.shared) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[false, false, false]'::jsonb);
select tf.eq('olmayan kimlik için de aynı sessiz cevap',
  tf.run('authenticated', :U5, $q$select jsonb_agg(to_jsonb(s)) from public.friend_goal_summary(gen_random_uuid(), '2026-01-05') s$q$),
  '[{"metric":"steps","shared":false,"goal_days":0,"data_days":0},
    {"metric":"sleep","shared":false,"goal_days":0,"data_days":0},
    {"metric":"calories","shared":false,"goal_days":0,"data_days":0}]'::jsonb);
select tf.eq('kendi özetim "paylaşılmıyor" (arkadaş değilim)',
  tf.run('authenticated', :U2, $q$select jsonb_agg(s.shared) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[false, false, false]'::jsonb);
select tf.eq('null arkadaş kimliği sessiz cevap',
  tf.run('authenticated', :U1, $q$select jsonb_agg(s.shared) from public.friend_goal_summary(null, '2026-01-05') s$q$),
  '[false, false, false]'::jsonb);
select tf.fails('hafta Pazartesi olmalı', 'authenticated', :U1,
  $q$select to_jsonb(count(*)) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-06')$q$, '22023');
select tf.fails('hafta null olamaz', 'authenticated', :U1,
  $q$select to_jsonb(count(*)) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', null)$q$, '22023');

-- Anahtarı kapatmak anında etki eder.
update public.friend_sharing set share_calories = false where user_id = :U2;
select tf.eq('kalori anahtarı kapatılınca arkadaş göremez',
  tf.run('authenticated', :U1, $q$select jsonb_agg(s.shared) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[true, true, false]'::jsonb);
update public.friend_sharing set share_calories = true where user_id = :U2;

-- 8) Ham veri sızıntısı yok --------------------------------------------
-- Ali (U1), Veli'nin (U2) arkadaşı: yine de hiçbir ham tabloyu okuyamaz.
select tf.eq('arkadaş ham adım/uyku satırlarını okuyamaz',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.daily_health_metrics where user_id = 'a2000000-0000-0000-0000-000000000002'$q$),
  '0'::jsonb);
select tf.eq('arkadaş ham öğün satırlarını okuyamaz',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.nutrition_logs where user_id = 'a2000000-0000-0000-0000-000000000002'$q$),
  '0'::jsonb);
select tf.eq('arkadaş görev/not/rutin/tartı satırlarını okuyamaz',
  tf.run('authenticated', :U1, $q$select to_jsonb((select count(*) from public.tasks where user_id <> auth.uid())
    + (select count(*) from public.notes where user_id <> auth.uid())
    + (select count(*) from public.routines where user_id <> auth.uid())
    + (select count(*) from public.fitness_logs where user_id <> auth.uid()))$q$),
  '0'::jsonb);
select tf.eq('arkadaş ayar satırını (hedefler, ekip, iş tanımı) okuyamaz',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.user_settings where user_id <> auth.uid()$q$),
  '0'::jsonb);
select tf.eq('arkadaş paylaşım anahtarı satırını doğrudan okuyamaz',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.friend_sharing where user_id <> auth.uid()$q$),
  '0'::jsonb);
select tf.eq('Veli kendi anahtar satırını okur',
  tf.run('authenticated', :U2, $q$select to_jsonb(count(*)) from public.friend_sharing$q$),
  '1'::jsonb);
select tf.eq('arkadaşlık satırlarını yalnızca taraflar görür',
  tf.run('authenticated', :U5, $q$select to_jsonb(count(*)) from public.friendships$q$),
  '0'::jsonb);
select tf.eq('Ali yalnızca kendi arkadaşlık satırını görür',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.friendships$q$),
  '1'::jsonb);
select tf.eq('gönderen kendi isteğini (açık sütunlarla) okur',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.friend_requests where from_user = auth.uid()$q$),
  (select to_jsonb(count(*)) from public.friend_requests where from_user = :U1));
select tf.eq('hedef taraf istek tablosunda satır görmez (yalnızca RPC)',
  tf.run('authenticated', :U2, $q$select to_jsonb(count(*)) from public.friend_requests where from_user <> auth.uid()$q$),
  '0'::jsonb);
select tf.fails('hedef kullanıcı sütunu (hesap var mı sinyali) okunamaz', 'authenticated', :U1,
  $q$select to_jsonb(count(target_user)) from public.friend_requests$q$, '42501');
select tf.fails('friend_requests * okuması reddedilir (kısıtlı sütun yetkisi)', 'authenticated', :U1,
  $q$select to_jsonb(count(*)) from (select * from public.friend_requests) z$q$, '42501');
select tf.fails('istemci doğrudan istek ekleyemez', 'authenticated', :U1,
  $q$insert into public.friend_requests (from_user, target_email) values (auth.uid(), 'x@y.co') returning to_jsonb(id)$q$, '42501');
select tf.fails('istemci doğrudan arkadaşlık ekleyemez', 'authenticated', :U5,
  $q$insert into public.friendships (user_a, user_b) values ('a1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000005') returning to_jsonb(user_a)$q$, '42501');
select tf.fails('istemci istek durumunu doğrudan değiştiremez', 'authenticated', :U1,
  $q$update public.friend_requests set status = 'accepted' returning to_jsonb(id)$q$, '42501');
select tf.fails('istemci arkadaşlığı doğrudan silemez', 'authenticated', :U1,
  $q$delete from public.friendships returning to_jsonb(user_a)$q$, '42501');
-- Başkası adına anahtar yazamaz (RLS with check).
select tf.fails('başkası adına paylaşım anahtarı yazılamaz', 'authenticated', :U5,
  $q$insert into public.friend_sharing (user_id, share_steps) values ('a1000000-0000-0000-0000-000000000001', true) returning to_jsonb(user_id)$q$, '42501');
select tf.eq('başkasının anahtar satırı güncellenmez (0 satır)',
  tf.run('authenticated', :U5, $q$with u as (
    update public.friend_sharing set share_steps = false where user_id = 'a2000000-0000-0000-0000-000000000002' returning 1)
    select to_jsonb(count(*)) from u$q$),
  '0'::jsonb);

-- display_name ve iş tanımı arkadaşa yalnızca ad olarak çıkar; iş tanımı hiçbir RPC'de yok.
update public.user_settings set display_name = 'Veli', work_description = 'gizli iş tanımı'
  where user_id = :U2;
select tf.eq('arkadaş listesinde görünen ad gelir, iş tanımı sızmaz',
  tf.run('authenticated', :U1, $q$select jsonb_agg(f.display_name)::text::jsonb from public.my_friends() f$q$),
  '["Veli"]'::jsonb);
select tf.ok('hiçbir arkadaş işlevinin çıktısında iş tanımı yok',
  coalesce(tf.run('authenticated', :U1, $q$select jsonb_agg(to_jsonb(f)) from public.my_friends() f$q$)::text, '') not like '%gizli%'
  and coalesce(tf.run('authenticated', :U3, $q$select jsonb_agg(to_jsonb(f)) from public.my_incoming_requests() f$q$)::text, '') not like '%gizli%');

-- 9) Arkadaşlıktan çıkış ------------------------------------------------
select tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from (select public.leave_friendship('a2000000-0000-0000-0000-000000000002')) z$q$);
select tf.ok('arkadaşlık bitti (iki yön)',
  not exists (select 1 from public.friendships where user_a = :U1 and user_b = :U2));
select tf.eq('çıkınca arkadaş özeti göremez',
  tf.run('authenticated', :U1, $q$select jsonb_agg(s.shared) from public.friend_goal_summary('a2000000-0000-0000-0000-000000000002', '2026-01-05') s$q$),
  '[false, false, false]'::jsonb);
select tf.eq('çıkınca listeden düşer',
  tf.run('authenticated', :U1, $q$select to_jsonb(count(*)) from public.my_friends()$q$),
  '0'::jsonb);
select tf.eq('çıkış arkadaş olmayan için sessizce hiçbir şey yapmaz',
  tf.run('authenticated', :U5, $q$select to_jsonb(count(*)) from (select public.leave_friendship('a2000000-0000-0000-0000-000000000002')) z$q$),
  '1'::jsonb);
select tf.ok('Veli–Ayşe arkadaşlığı çıkıştan etkilenmedi',
  exists (select 1 from public.friendships where user_a = :U2 and user_b = :U3));
-- Veli çıkınca Ayşe de göremez (iki yönlü).
select tf.run('authenticated', :U2, $q$select to_jsonb(count(*)) from (select public.leave_friendship('a3000000-0000-0000-0000-000000000003')) z$q$);
select tf.eq('Veli–Ayşe de bitti',
  tf.run('authenticated', :U3, $q$select to_jsonb(count(*)) from public.my_friends()$q$),
  '0'::jsonb);

-- 10) Hesap silinince ilişkili satırlar da gider -----------------------
select tf.ok('silmeden önce Veli ile ilişkili satırlar var',
  exists (select 1 from public.friend_requests where from_user = :U2)
  and exists (select 1 from public.friend_sharing where user_id = :U2));
delete from auth.users where id = :U2;
select tf.ok('hesap silinince istek/anahtar satırları gider',
  not exists (select 1 from public.friend_requests where from_user = :U2)
  and not exists (select 1 from public.friend_sharing where user_id = :U2)
  and not exists (select 1 from public.friendships where :U2 in (user_a, user_b)));

\echo tamam: arkadaş testleri geçti
