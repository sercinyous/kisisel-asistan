-- Otomatik story'ler: friend_stories + story_reactions RLS'i ve
-- user_settings.share_stories gizlilik anahtarı (varsayılan kapalı).
-- Çalıştırma: supabase/tests/run_local.sh. Tekrar çalıştırılabilir.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

delete from auth.users where id in ('5a000000-0000-0000-0000-000000000001',
                                    '5a000000-0000-0000-0000-000000000002',
                                    '5a000000-0000-0000-0000-000000000003');
select tf.mkuser('5a000000-0000-0000-0000-000000000001', 'story-sahip@example.com');
select tf.mkuser('5a000000-0000-0000-0000-000000000002', 'story-arkadas@example.com');
select tf.mkuser('5a000000-0000-0000-0000-000000000003', 'story-yabanci@example.com');
insert into public.user_settings (user_id)
values ('5a000000-0000-0000-0000-000000000001'),
       ('5a000000-0000-0000-0000-000000000002'),
       ('5a000000-0000-0000-0000-000000000003')
on conflict (user_id) do nothing;
insert into public.friendships (user_a, user_b)
values ('5a000000-0000-0000-0000-000000000001', '5a000000-0000-0000-0000-000000000002');

do $$
declare
  owner_u  uuid := '5a000000-0000-0000-0000-000000000001';
  friend_u uuid := '5a000000-0000-0000-0000-000000000002';
  stranger uuid := '5a000000-0000-0000-0000-000000000003';
  ins      text := $q$insert into public.friend_stories (kind, day, payload)
                    values ('streak_7', current_date, '{"days":7}') returning to_jsonb(id)$q$;
  sid      uuid;
  old_sid  uuid;
  r        jsonb;
begin
  perform tf.eq('share_stories varsayılan kapalı',
    (select to_jsonb(share_stories) from public.user_settings where user_id = owner_u), 'false');

  -- 1) Paylaşım kapalıyken sahip bile story yazamaz.
  perform tf.fails('paylaşım kapalı: ekleme reddedilir', 'authenticated', owner_u, ins, '42501');

  update public.user_settings set share_stories = true where user_id = owner_u;
  sid := (tf.run('authenticated', owner_u, ins) #>> '{}')::uuid;
  perform tf.ok('paylaşım açık: sahip story yazar', sid is not null);
  perform tf.eq('süre sunucuda 24 saat',
    (select to_jsonb(expires_at - created_at = interval '24 hours') from public.friend_stories where id = sid),
    'true');
  perform tf.fails('aynı tür + gün ikinci kez yazılmaz', 'authenticated', owner_u, ins, '23505');
  perform tf.fails('başkası adına yazılmaz', 'authenticated', owner_u,
    format($q$insert into public.friend_stories (user_id, kind, day) values (%L, 'workout', current_date) returning to_jsonb(id)$q$, friend_u),
    '42501');
  perform tf.fails('büyük payload reddedilir', 'authenticated', owner_u,
    $q$insert into public.friend_stories (kind, day, payload)
       values ('workout', current_date, jsonb_build_object('x', repeat('a', 900))) returning to_jsonb(id)$q$,
    '23514');

  -- 2) Görünürlük: arkadaş görür, yabancı görmez.
  r := tf.run('authenticated', friend_u, 'select to_jsonb(count(*)) from public.friend_stories');
  perform tf.eq('arkadaş story''yi görür', r, '1');
  r := tf.run('authenticated', stranger, 'select to_jsonb(count(*)) from public.friend_stories');
  perform tf.eq('yabancı görmez', r, '0');
  perform tf.fails('anon okuyamaz', 'anon', null,
    'select to_jsonb(count(*)) from public.friend_stories', '42501');
  perform tf.fails('arkadaş güncelleyemez (yetki yok)', 'authenticated', friend_u,
    format($q$update public.friend_stories set payload = '{}' where id = %L returning to_jsonb(id)$q$, sid),
    '42501');

  -- Süresi dolmuş story arkadaşa görünmez, sahibe görünür.
  insert into public.friend_stories (user_id, kind, day) values (owner_u, 'workout', current_date - 2)
    returning id into old_sid;
  update public.friend_stories set expires_at = now() - interval '1 minute' where id = old_sid;
  r := tf.run('authenticated', friend_u,
    format('select to_jsonb(count(*)) from public.friend_stories where id = %L', old_sid));
  perform tf.eq('süresi dolan arkadaşa görünmez', r, '0');
  r := tf.run('authenticated', owner_u,
    format('select to_jsonb(count(*)) from public.friend_stories where id = %L', old_sid));
  perform tf.eq('süresi dolan sahibe görünür', r, '1');

  -- 3) Tepkiler.
  perform tf.run('authenticated', friend_u,
    format($q$insert into public.story_reactions (story_id, emoji) values (%L, '🔥') returning to_jsonb(story_id)$q$, sid));
  perform tf.fails('yabancı tepki veremez', 'authenticated', stranger,
    format($q$insert into public.story_reactions (story_id, emoji) values (%L, '👏') returning to_jsonb(story_id)$q$, sid),
    '42501');
  perform tf.fails('sahip kendi story''sine tepki veremez', 'authenticated', owner_u,
    format($q$insert into public.story_reactions (story_id, emoji) values (%L, '👏') returning to_jsonb(story_id)$q$, sid),
    '42501');
  perform tf.fails('süresi dolan story''ye tepki verilmez', 'authenticated', friend_u,
    format($q$insert into public.story_reactions (story_id, emoji) values (%L, '👏') returning to_jsonb(story_id)$q$, old_sid),
    '42501');
  perform tf.fails('izinsiz emoji reddedilir', 'authenticated', friend_u,
    format($q$insert into public.story_reactions (story_id, user_id, emoji) values (%L, %L, '😀') returning to_jsonb(story_id)$q$, sid, stranger),
    null);
  r := tf.run('authenticated', owner_u, 'select to_jsonb(count(*)) from public.story_reactions');
  perform tf.eq('sahip tepkiyi okur', r, '1');
  r := tf.run('authenticated', friend_u, 'select to_jsonb(count(*)) from public.story_reactions');
  perform tf.eq('tepki veren kendi tepkisini okur', r, '1');
  r := tf.run('authenticated', stranger, 'select to_jsonb(count(*)) from public.story_reactions');
  perform tf.eq('yabancı tepki okuyamaz', r, '0');

  -- 4) Paylaşım kapatılınca story'ler ve tepkileri silinir.
  update public.user_settings set share_stories = false where user_id = owner_u;
  perform tf.eq('kapatınca story kalmaz',
    (select to_jsonb(count(*)) from public.friend_stories where user_id = owner_u), '0');
  perform tf.eq('kapatınca tepki kalmaz',
    (select to_jsonb(count(*)) from public.story_reactions where story_id = sid), '0');
end;
$$;

delete from auth.users where id in ('5a000000-0000-0000-0000-000000000001',
                                    '5a000000-0000-0000-0000-000000000002',
                                    '5a000000-0000-0000-0000-000000000003');
