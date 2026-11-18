-- Apple inceleyici demo hesabına gerçekçi ama kişisel olmayan veri yükler.
-- Supabase > SQL Editor'da çalıştırılır (sahibin yetkisiyle). Önce aşağıdaki
-- e-posta yer tutucusunu demo hesabın adresiyle değiştir; hesap Dashboard'dan
-- açılmış olmalı (docs/apple_inceleme.md). Tekrar çalıştırmak güvenlidir:
-- demo kullanıcının görev, not, rutin, öğün, antrenman ve sağlık özeti
-- satırları silinip yeniden yazılır. Başka hiçbir kullanıcıya dokunulmaz.
do $$
declare
  v_email text := lower(btrim('demo-inceleme@ornek.invalid'));  -- ← DEĞİŞTİR
  v_user  uuid;
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
  d       integer;
begin
  select id into v_user from auth.users where lower(email) = v_email;
  if v_user is null then
    raise exception 'Demo kullanıcı bulunamadı: %', v_email;
  end if;

  -- Profil: ilk kurulum tamamlanmış sayılır, hedefler makul.
  insert into public.user_settings (user_id) values (v_user)
    on conflict (user_id) do nothing;
  update public.user_settings
     set display_name = 'Demo',
         timezone = 'Europe/Istanbul',
         height_cm = 175,
         birth_year = 1992,
         onboarded_at = coalesce(onboarded_at, now())
   where user_id = v_user;

  delete from public.tasks where user_id = v_user;
  delete from public.notes where user_id = v_user;
  delete from public.routine_completions where user_id = v_user;
  delete from public.routines where user_id = v_user;
  delete from public.nutrition_logs where user_id = v_user;
  delete from public.fitness_logs where user_id = v_user;
  delete from public.daily_health_metrics where user_id = v_user;

  insert into public.tasks (user_id, title, description, category, priority, status, due_at) values
    (v_user, 'Haftalık plan toplantısı', 'Sprint hedeflerini gözden geçir', 'İş', 'high', 'todo',
       (v_today + 1)::timestamp + time '10:00'),
    (v_user, 'Fatura ödemeleri', 'Elektrik ve internet', 'Finans', 'medium', 'todo',
       (v_today + 3)::timestamp + time '18:00'),
    (v_user, 'Sunum taslağını bitir', null, 'İş', 'high', 'in_progress',
       (v_today + 2)::timestamp + time '17:00'),
    (v_user, 'Ekip için eğitim notları', null, 'Ekip', 'low', 'todo', null),
    (v_user, 'Market alışverişi', 'Sebze, meyve, yoğurt', 'Kişisel', 'medium', 'done',
       (v_today - 1)::timestamp + time '19:00'),
    (v_user, 'Diş hekimi randevusu al', null, 'Kişisel', 'low', 'done', null);

  insert into public.notes (user_id, title, content, category, is_pinned) values
    (v_user, 'Toplantı notları', 'Yeni özellik listesi önceliklendirildi. Takip: cuma.', 'Toplantı', true),
    (v_user, 'Kitap önerileri', 'Atomik Alışkanlıklar, Derin Çalışma', 'Kişisel', false),
    (v_user, 'Uygulama fikri', 'Haftalık özetleri e-postayla gönderme', 'Fikir', false);

  insert into public.routines (user_id, title, scope, category, frequency, time_of_day, days_of_week) values
    (v_user, 'Sabah yürüyüşü', 'Kişisel', 'spor', 'weekly', '07:30', '{1,2,3,4,5}'),
    (v_user, 'Gelen kutusunu temizle', 'İş', 'operasyon', 'weekly', '09:00', '{1,2,3,4,5}'),
    (v_user, 'Haftalık bütçe kontrolü', 'Kişisel', 'finans', 'weekly', '20:00', '{7}');

  for d in 0..13 loop
    insert into public.daily_health_metrics (user_id, metric_date, steps, active_kcal, sleep_minutes, source)
    values (v_user, v_today - d, 6500 + ((d * 1373) % 5200), 320 + ((d * 61) % 260),
            380 + ((d * 37) % 110), 'appleHealth');

    insert into public.nutrition_logs (user_id, meal_type, food_name, quantity_text, calories, protein_g, carbs_g, fat_g, eaten_at) values
      (v_user, 'breakfast', 'Yulaf ezmesi ve muz', '1 kase', 380, 12, 62, 8,
         (v_today - d)::timestamp + time '08:15'),
      (v_user, 'lunch', 'Izgara tavuk salata', '1 porsiyon', 520, 42, 24, 26,
         (v_today - d)::timestamp + time '13:00'),
      (v_user, 'dinner', 'Mercimek çorbası ve bulgur pilavı', '1 porsiyon', 610, 22, 96, 14,
         (v_today - d)::timestamp + time '19:30');
  end loop;

  insert into public.fitness_logs (user_id, log_type, workout_type, title, duration_min, distance_km, calories_burned, logged_at) values
    (v_user, 'workout', 'running', 'Akşam koşusu', 35, 5.2, 340, (v_today - 1)::timestamp + time '19:00'),
    (v_user, 'workout', 'weights', 'Ağırlık antrenmanı', 50, null, 280, (v_today - 3)::timestamp + time '18:30'),
    (v_user, 'workout', 'football', 'Halı saha', 60, null, 520, (v_today - 6)::timestamp + time '21:00');
  insert into public.fitness_logs (user_id, log_type, weight_kg, logged_at) values
    (v_user, 'weight', 78.4, (v_today - 7)::timestamp + time '08:00'),
    (v_user, 'weight', 77.9, (v_today)::timestamp + time '08:00');

  raise notice 'Demo verisi yüklendi: %', v_email;
end;
$$;
