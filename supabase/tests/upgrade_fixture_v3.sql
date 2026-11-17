-- Sürüm 3 şemasıyla kurulmuş veritabanına yükseltmeden ÖNCE konan veri.
-- Kullanıcı eklenince auth.users trigger'ı ayar satırını ve seed'i açar.
insert into auth.users (id, email) values
  ('eeeeeeee-0000-0000-0000-000000000006', 'v3@test');

update public.user_settings set daily_calories = 2300
  where user_id = 'eeeeeeee-0000-0000-0000-000000000006';
