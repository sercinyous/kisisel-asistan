-- Sürüm 2 şemasıyla kurulmuş veritabanına yükseltmeden ÖNCE konan veri.
insert into auth.users (id, email) values
  ('eeeeeeee-0000-0000-0000-000000000005', 'eski@test');

update public.user_settings set daily_calories = 2400, team_members = '{Ayşe}'
  where user_id = 'eeeeeeee-0000-0000-0000-000000000005';

-- Sürüm 2'de uygulamanın yazabildiği eski biçimli haftalık rapor.
insert into public.weekly_reports
  (user_id, week_start, tasks_total, tasks_done, task_completion_rate, ai_summary, metrics)
values
  ('eeeeeeee-0000-0000-0000-000000000005', '2026-09-21', 5, 4, 80, 'eski özet', '{"eski": true}');
