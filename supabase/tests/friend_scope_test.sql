-- friend_scope_source: hedef paylaşımı yalnızca hedef gün sayısını açar; ham
-- değerler ayrı onayla (share_details) gelir. Rapor ve sıralama seçili sağlık
-- kaynağını (user_settings.health_source) okur; kaynağı boş satır Apple sayılır.
-- Çalıştırma: supabase/tests/run_local.sh. Tekrar çalıştırılabilir.
\set ON_ERROR_STOP on
set client_min_messages = notice;
\ir helpers_faz4b.sql

alter table auth.users add column if not exists raw_user_meta_data jsonb;

delete from auth.users where id in ('f8100000-0000-0000-0000-000000000001',
                                    'f8200000-0000-0000-0000-000000000002');
alter table auth.users disable trigger signup_invite_gate;
select tf.mkuser('f8100000-0000-0000-0000-000000000001', 'scope-eski@example.com');
select tf.mkuser('f8200000-0000-0000-0000-000000000002', 'scope-arkadas@example.com');
alter table auth.users enable trigger signup_invite_gate;

insert into public.user_settings (user_id, timezone)
values ('f8100000-0000-0000-0000-000000000001', 'Europe/Istanbul'),
       ('f8200000-0000-0000-0000-000000000002', 'Europe/Istanbul')
on conflict (user_id) do update set timezone = 'Europe/Istanbul', health_source = null;

insert into public.friendships (user_a, user_b)
values ('f8100000-0000-0000-0000-000000000001', 'f8200000-0000-0000-0000-000000000002');

-- Eski sürüm istemcisinin yazdığı satır: yalnızca eski sütunlar (hedef
-- paylaşımı açık), ayrıntı onayı hiç yazılmamış.
insert into public.friend_sharing (user_id, share_steps, share_sleep, share_calories)
values ('f8100000-0000-0000-0000-000000000001', true, true, true);

-- Bugün: Apple Health verisi (biri kaynağı boş eski HealthKit satırı sayılır).
insert into public.daily_health_metrics (user_id, metric_date, steps, sleep_minutes, source)
values ('f8100000-0000-0000-0000-000000000001',
        (now() at time zone 'Europe/Istanbul')::date, 9000, 480, null);
insert into public.nutrition_logs (user_id, food_name, calories, eaten_at)
values ('f8100000-0000-0000-0000-000000000001', 'Öğle', 2000, now());

do $$
declare
  old_u  uuid := 'f8100000-0000-0000-0000-000000000001';
  friend uuid := 'f8200000-0000-0000-0000-000000000002';
  today  date := (now() at time zone 'Europe/Istanbul')::date;
  wk     date := date_trunc('week', (now() at time zone 'Europe/Istanbul'))::date;
  q      text;
  r      jsonb;
  g      jsonb;
  rep    jsonb;
begin
  q := format($q$select jsonb_build_object('sst', share_steps, 'ssl', share_sleep,
        'sca', share_calories, 'st', steps_today, 'sw', steps_week, 'sl', sleep_today,
        'sla', sleep_week_avg, 'kt', kcal_today, 'kw', kcal_week)
      from public.friend_leaderboard(%L) where user_id = %L$q$, wk, old_u);

  perform tf.eq('yeni sütun varsayılan kapalı (geri doldurulmadı)',
    (select to_jsonb(share_details) from public.friend_sharing where user_id = old_u), 'false');

  -- 1) Eski kullanıcı, hedef paylaşımı açık: arkadaş ham değer görmez.
  r := tf.run('authenticated', friend, q);
  perform tf.eq('arkadaş: hedef paylaşımı açık ama ham değerler null', r,
    jsonb_build_object('sst', true, 'ssl', true, 'sca', true,
      'st', null, 'sw', null, 'sl', null, 'sla', null, 'kt', null, 'kw', null));
  -- Hedef gün sayısı (eski kapsam) hâlâ açık.
  g := tf.run('authenticated', friend, format(
    $q$select jsonb_object_agg(metric, shared) from public.friend_goal_summary(%L, %L)$q$,
    old_u, wk));
  perform tf.eq('arkadaş: hedef gün sayısı paylaşılıyor', g,
    '{"steps": true, "sleep": true, "calories": true}');
  -- Kişinin kendi satırı kendi değerlerini görür.
  r := tf.run('authenticated', old_u, q);
  perform tf.eq('kendi satırı: kendi ham değerleri', r -> 'st', '9000');
  perform tf.eq('kendi satırı: kendi kcal', r -> 'kt', '2000.0');

  -- 2) Ayrıntı onayı verildi: değerler görünür.
  update public.friend_sharing set share_details = true where user_id = old_u;
  r := tf.run('authenticated', friend, q);
  perform tf.eq('onaydan sonra adım', r -> 'st', '9000');
  perform tf.eq('onaydan sonra uyku', r -> 'sl', '480');
  perform tf.eq('onaydan sonra kcal', r -> 'kt', '2000.0');

  -- Ayrıntı onayı hedef paylaşımı kapalı metriği açmaz.
  update public.friend_sharing set share_calories = false where user_id = old_u;
  r := tf.run('authenticated', friend, q);
  perform tf.eq('hedef paylaşımı kapalı metrik null kalır', r -> 'kt', 'null');
  update public.friend_sharing set share_calories = true where user_id = old_u;

  -- 3) Kaynak: Apple verisi var, seçili kaynak Google (Google verisi yok).
  rep := public.report_period_metrics(old_u, today, today, true);
  perform tf.eq('rapor (Apple, kaynak boş satır): adım', rep -> 'health' -> 'steps', '9000');
  update public.user_settings set health_source = 'googleHealth' where user_id = old_u;
  rep := public.report_period_metrics(old_u, today, today, true);
  perform tf.eq('rapor (Google seçili, verisi yok): adım 0', rep -> 'health' -> 'steps', '0');
  perform tf.eq('rapor (Google seçili): gün adımı 0', rep -> 'days' -> 0 -> 'steps', '0');
  perform tf.eq('rapor (Google seçili): veri günü 0', rep -> 'health' -> 'days_with_data', '0');
  r := tf.run('authenticated', friend, q);
  perform tf.eq('sıralama (Google seçili): arkadaş adımı 0', r -> 'st', '0');
  perform tf.eq('sıralama (Google seçili): arkadaş uykusu 0', r -> 'sl', '0');
  r := tf.run('authenticated', old_u, q);
  perform tf.eq('sıralama (Google seçili): kendi adımı 0', r -> 'st', '0');

  -- Google verisi gelince o sayılır.
  update public.daily_health_metrics set steps = 1234, source = 'googleHealth'
    where user_id = old_u and metric_date = today;
  rep := public.report_period_metrics(old_u, today, today, false);
  perform tf.eq('rapor (Google verisi): adım', rep -> 'health' -> 'steps', '1234');
  update public.user_settings set health_source = 'appleHealth' where user_id = old_u;
  rep := public.report_period_metrics(old_u, today, today, false);
  perform tf.eq('rapor (Apple seçili, yalnız Google satırı): adım 0', rep -> 'health' -> 'steps', '0');

  -- Hedef gün sayısı da seçili kaynağı okur: Apple verisi (9000 adım, hedef
  -- 8000), Google seçili ve Google verisi yok → 0 gün.
  update public.daily_health_metrics set steps = 9000, source = null
    where user_id = old_u and metric_date = today;
  update public.user_settings set daily_steps = 8000, health_source = 'appleHealth'
    where user_id = old_u;
  g := tf.run('authenticated', friend, format(
    $q$select to_jsonb(goal_days) from public.friend_goal_summary(%L, %L) where metric = 'steps'$q$,
    old_u, wk));
  perform tf.eq('hedef günü (Apple seçili): 1', g, '1');
  update public.user_settings set health_source = 'googleHealth' where user_id = old_u;
  g := tf.run('authenticated', friend, format(
    $q$select to_jsonb(goal_days) from public.friend_goal_summary(%L, %L) where metric = 'steps'$q$,
    old_u, wk));
  perform tf.eq('hedef günü (Google seçili, verisi yok): 0', g, '0');

  -- Kaynak değişince mevcut raporlar dirty olur.
  perform public.save_daily_report(old_u, today - 3,
    public.report_daily_metrics(old_u, today - 3), 'eski', 'ok');
  perform public.save_daily_report(old_u, today,
    public.report_daily_metrics(old_u, today), 'bugün', 'ok');
  perform public.save_weekly_report(old_u, wk, public.report_weekly_metrics(old_u, wk), 'hafta', 'ok');
  update public.daily_reports set dirty = false where user_id = old_u;
  update public.weekly_reports set dirty = false where user_id = old_u;
  update public.user_settings set timezone = 'Europe/Istanbul' where user_id = old_u;
  perform tf.ok('ilgisiz ayar değişimi raporları kirletmez',
    not exists (select 1 from public.daily_reports where user_id = old_u and dirty));
  update public.user_settings set health_source = 'appleHealth' where user_id = old_u;
  perform tf.ok('kaynak değişince gün raporları dirty',
    (select bool_and(dirty) and count(*) = 2 from public.daily_reports where user_id = old_u));
  perform tf.ok('kaynak değişince hafta raporu dirty',
    (select bool_and(dirty) from public.weekly_reports where user_id = old_u));
  update public.daily_reports set dirty = false where user_id = old_u;
  update public.user_settings set health_source = null where user_id = old_u;
  perform tf.ok('null ↔ appleHealth aynı kaynak: dirty olmaz',
    not exists (select 1 from public.daily_reports where user_id = old_u and dirty));

  -- Geçersiz kaynak reddedilir.
  begin
    update public.user_settings set health_source = 'fitbit' where user_id = old_u;
    raise exception 'BAŞARISIZ: geçersiz health_source kabul edildi';
  exception when check_violation then
    raise notice 'tamam: health_source kısıtı';
  end;
end;
$$;
