-- Güvenlik turu 1: hesap silme yetkisi (SEC-01), ret/engel kalıcılığı ve
-- günlük istek sınırı (SEC-04), UTC kota günü (SEC-08), metin/geri bildirim/
-- hikâye sınırları (SEC-10). Çalıştırma: supabase/tests/run_local.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

select tf.mkuser('5ec00000-0000-0000-0000-000000000001', 'sec-ali@example.com');
select tf.mkuser('5ec00000-0000-0000-0000-000000000002', 'sec-bora@example.com');
select tf.mkuser('5ec00000-0000-0000-0000-000000000003', 'sec-cem@example.com');

-- SEC-01: service_role arkadaş tablolarını silebilir.
select tf.ok('service_role friendships/friend_requests delete yetkisi',
  has_table_privilege('service_role', 'public.friendships', 'delete')
  and has_table_privilege('service_role', 'public.friend_requests', 'delete'));
select tf.run('service_role', null,
  $q$with a as (delete from public.friendships where user_a = '5ec00000-0000-0000-0000-000000000001' returning 1),
          b as (delete from public.friend_requests where from_user = '5ec00000-0000-0000-0000-000000000001' returning 1)
     select to_jsonb((select count(*) from a) + (select count(*) from b))$q$);

-- SEC-04: ret kalıcı, yeniden gönderim gelen kutusuna düşmez.
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$select to_jsonb(public.send_friend_request('sec-bora@example.com'))$q$);
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000002',
  $q$select to_jsonb(public.respond_friend_request((select id from public.my_incoming_requests() limit 1), false))$q$);
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$select to_jsonb(public.send_friend_request('sec-bora@example.com'))$q$);
select tf.eq('reddedilen gönderen yeniden istek açamaz',
  tf.run('authenticated', '5ec00000-0000-0000-0000-000000000002',
    $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$), '0');

-- Engelle: arkadaşlık biter, engellenen yeniden istek açamaz.
insert into public.friendships (user_a, user_b)
  values ('5ec00000-0000-0000-0000-000000000002', '5ec00000-0000-0000-0000-000000000003');
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000002',
  $q$select to_jsonb(public.block_user('5ec00000-0000-0000-0000-000000000003'))$q$);
select tf.ok('engel arkadaşlığı siler', not exists (
  select 1 from public.friendships where user_b = '5ec00000-0000-0000-0000-000000000003'));
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000003',
  $q$select to_jsonb(public.send_friend_request('sec-bora@example.com'))$q$);
select tf.eq('engellenen istek açamaz',
  tf.run('authenticated', '5ec00000-0000-0000-0000-000000000002',
    $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$), '0');
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000002',
  $q$select to_jsonb(public.block_user('5ec00000-0000-0000-0000-000000000003'))$q$);
select tf.ok('ikinci engel çift kayıt açmaz', (
  select count(*) from public.friend_requests
  where from_user = '5ec00000-0000-0000-0000-000000000003' and status = 'declined') = 1);

-- Engel hesap silinip aynı e-postayla yeniden açılınca da sürer.
delete from auth.users where id = '5ec00000-0000-0000-0000-000000000003';
select tf.mkuser('5ec00000-0000-0000-0000-000000000004', 'sec-cem@example.com');
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000004',
  $q$select to_jsonb(public.send_friend_request('sec-bora@example.com'))$q$);
select tf.eq('yeniden açılan engelli hesap istek açamaz',
  tf.run('authenticated', '5ec00000-0000-0000-0000-000000000002',
    $q$select to_jsonb(count(*)) from public.my_incoming_requests()$q$), '0');
select tf.ok('engel kaydı istemciye kapalı',
  not has_table_privilege('authenticated', 'public.blocked_emails', 'select'));

-- Günlük istek sınırı: 30.
do $$
begin
  update public.ai_usage set count = 30
   where user_id = '5ec00000-0000-0000-0000-000000000004' and kind = 'friend_request';
  begin
    perform tf.run('authenticated', '5ec00000-0000-0000-0000-000000000004',
      $q$select to_jsonb(public.send_friend_request('yeni@example.com'))$q$);
    raise exception 'BAŞARISIZ: günlük istek sınırı uygulanmadı';
  exception when sqlstate '54000' then
    raise notice 'tamam: günlük istek sınırı';
  end;
end;
$$;

-- SEC-08: saat dilimi değiştirmek kotayı sıfırlamaz.
select tf.ok('kota 1/1', public.consume_ai_quota('5ec00000-0000-0000-0000-000000000001', 'sec_ai', 1));
update public.user_settings set timezone = 'Pacific/Kiritimati'
 where user_id = '5ec00000-0000-0000-0000-000000000001';
select tf.ok('saat dilimi değişince kota yine dolu',
  not public.consume_ai_quota('5ec00000-0000-0000-0000-000000000001', 'sec_ai', 1));

-- SEC-10: metin sınırları, geri bildirim sınırı, hikâye günü.
do $$
begin
  begin
    insert into public.notes (user_id, title, content)
    values ('5ec00000-0000-0000-0000-000000000001', 'x', repeat('a', 20001));
    raise exception 'BAŞARISIZ: not uzunluk sınırı yok';
  exception when check_violation then
    raise notice 'tamam: not uzunluk sınırı';
  end;
  begin
    perform tf.run('authenticated', '5ec00000-0000-0000-0000-000000000001',
      $q$with i as (insert into public.feedback (message) select 'm' || g from generate_series(1, 21) g returning 1)
         select to_jsonb(count(*)) from i$q$);
    raise exception 'BAŞARISIZ: geri bildirim sınırı yok';
  exception when sqlstate 'P0001' then
    raise notice 'tamam: geri bildirim günlük sınırı';
  end;
  begin
    insert into public.friend_stories (user_id, kind, day)
    values ('5ec00000-0000-0000-0000-000000000001', 'workout', current_date - 30);
    raise exception 'BAŞARISIZ: eski gün hikâyesi kabul edildi';
  exception when sqlstate '22023' then
    raise notice 'tamam: hikâye günü sınırı';
  end;
end;
$$;

-- G2-02: engellenen kişi engelleyenin e-postasını/ret durumunu okuyamaz.
select tf.fails('engellenen friend_requests okuyamaz', 'authenticated', '5ec00000-0000-0000-0000-000000000003',
  $q$select to_jsonb(array_agg(target_email)) from public.friend_requests$q$, '42501');

-- G2-09: aynı op_key ikinci kez yazmaz; kalem sınırı.
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$select public.quick_add_entries('{"nutrition":[{"food_name":"elma","calories":50}]}'::jsonb,
                                     '0b000000-0000-0000-0000-0000000000a1'::uuid)$q$);
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$select public.quick_add_entries('{"nutrition":[{"food_name":"elma","calories":50}]}'::jsonb,
                                     '0b000000-0000-0000-0000-0000000000a1'::uuid)$q$);
select tf.eq('aynı op_key ile tek öğün yazılır',
  (select to_jsonb(count(*)) from public.nutrition_logs
    where user_id = '5ec00000-0000-0000-0000-000000000001' and food_name = 'elma'), '1');
select tf.run('authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$select public.quick_add_entries('{"nutrition":[{"food_name":"elma","calories":50}]}'::jsonb,
                                     '0b000000-0000-0000-0000-0000000000a2'::uuid)$q$);
select tf.eq('yeni op_key yeniden yazar',
  (select to_jsonb(count(*)) from public.nutrition_logs
    where user_id = '5ec00000-0000-0000-0000-000000000001' and food_name = 'elma'), '2');
select tf.fails('51 kalem reddedilir', 'authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$select public.quick_add_entries(jsonb_build_object('tasks',
       (select jsonb_agg(jsonb_build_object('title', 'g' || i)) from generate_series(1, 51) i)))$q$, '22023');

-- G2-13: ekip üyesi ve kategori boyutu.
insert into public.user_settings (user_id) values ('5ec00000-0000-0000-0000-000000000001')
  on conflict (user_id) do nothing;
select tf.fails('31 ekip üyesi reddedilir', 'authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$update public.user_settings set team_members = (select array_agg('k' || i) from generate_series(1, 31) i)
     where user_id = auth.uid() returning to_jsonb(user_id)$q$, '23514');
select tf.fails('uzun ekip üyesi adı reddedilir', 'authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$update public.user_settings set team_members = array[repeat('a', 61)]
     where user_id = auth.uid() returning to_jsonb(user_id)$q$, '23514');
select tf.fails('büyük kategori listesi reddedilir', 'authenticated', '5ec00000-0000-0000-0000-000000000001',
  $q$update public.user_settings set task_categories = jsonb_build_array(repeat(md5('x'), 700))
     where user_id = auth.uid() returning to_jsonb(user_id)$q$, '23514');
