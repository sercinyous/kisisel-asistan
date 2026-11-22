-- Görev kategorileri (sürüm 7): user_settings.task_categories ve serbest
-- tasks.category.
--   * sütun jsonb, boş olabilir; dizi olmayan değer ve 40'tan uzun dizi ret
--   * RLS: kullanıcı yalnızca kendi listesini yazar
--   * tasks.category özel ad kabul eder; boş/41+ karakter ret; 'Pusholder' → 'İş'
-- Çalıştırma: supabase/tests/run_local.sh
\set ON_ERROR_STOP on
set client_min_messages = notice;


insert into auth.users (id, email) values
  ('d1d1d1d1-0000-0000-0000-000000000001', 'kategori-a@test'),
  ('d2d2d2d2-0000-0000-0000-000000000002', 'kategori-b@test')
on conflict (id) do nothing;


do $$
declare
  v_a uuid := 'd1d1d1d1-0000-0000-0000-000000000001';
  v_b uuid := 'd2d2d2d2-0000-0000-0000-000000000002';
  v_type text;
  v_rows integer;
  v_rejected boolean;
  v_cat text;
  v_val jsonb;
begin
  select data_type into v_type from information_schema.columns
  where table_schema = 'public' and table_name = 'user_settings'
    and column_name = 'task_categories' and is_nullable = 'YES';
  if v_type is distinct from 'jsonb' then
    raise exception 'BAŞARISIZ: user_settings.task_categories jsonb değil (%)', v_type;
  end if;
  if (select count(*) from pg_constraint
      where conrelid = 'public.user_settings'::regclass
        and conname = 'user_settings_task_categories_check') <> 1 then
    raise exception 'BAŞARISIZ: task_categories check tek değil';
  end if;
  insert into public.user_settings (user_id) values (v_a), (v_b)
  on conflict (user_id) do nothing;

  perform set_config('request.jwt.claim.sub', v_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  update public.user_settings
     set task_categories = '[{"name":"Okul","icon":"school","color":"accent","enabled":true,"custom":true}]'
   where user_id = v_a;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'BAŞARISIZ: A kendi kategorilerini yazamadı';
  end if;

  update public.user_settings set task_categories = '[]' where user_id = v_b;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'BAŞARISIZ: A, B''nin kategorilerini değiştirdi';
  end if;

  foreach v_val in array array['{"name":"x"}'::jsonb, '"x"'::jsonb,
      (select jsonb_agg(jsonb_build_object('name', 'k' || i)) from generate_series(1, 41) i)] loop
    v_rejected := false;
    begin
      update public.user_settings set task_categories = v_val where user_id = v_a;
    exception when check_violation then
      v_rejected := true;
    end;
    if not v_rejected then
      raise exception 'BAŞARISIZ: geçersiz task_categories kabul edildi';
    end if;
  end loop;

  insert into public.tasks (title, category) values ('Ödev', 'Okul');
  insert into public.tasks (title, category) values ('Eski', 'Pusholder');
  select category into v_cat from public.tasks where user_id = v_a and title = 'Eski';
  if v_cat <> 'İş' then
    raise exception 'BAŞARISIZ: Pusholder → İş eşlemesi bozuldu (%)', v_cat;
  end if;

  foreach v_cat in array array['', '   ', repeat('a', 41)] loop
    v_rejected := false;
    begin
      insert into public.tasks (title, category) values ('Hatalı', v_cat);
    exception when check_violation then
      v_rejected := true;
    end;
    if not v_rejected then
      raise exception 'BAŞARISIZ: tasks.category = "%" kabul edildi', v_cat;
    end if;
  end loop;
  reset role;

  if (select task_categories from public.user_settings where user_id = v_b) is not null then
    raise exception 'BAŞARISIZ: B''nin listesi değişti';
  end if;
  delete from public.tasks where user_id = v_a;
  raise notice 'tamam: görev kategorileri (şema, RLS, serbest kategori)';
end;
$$;

-- Sonraki testler (reports_test.sql) kullanıcı sayısını sayar: fikstür silinir.
delete from auth.users
where id in ('d1d1d1d1-0000-0000-0000-000000000001', 'd2d2d2d2-0000-0000-0000-000000000002');
