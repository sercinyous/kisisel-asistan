-- Faz 4B testlerinin ortak yardımcıları (schema tf). Yalnızca supabase/tests/
-- altındaki testler \ir ile içe aktarır; gerçek projede ÇALIŞTIRILMAZ.
-- Tekrar çalıştırılabilir (create or replace).
create schema if not exists tf;
grant usage on schema tf to anon, authenticated, service_role;

-- [p_sql] (tek jsonb döndüren sorgu) verilen rol + kullanıcı ile çalıştırılır.
-- Hata olursa rol sıfırlanır ve hata yeniden fırlatılır.
create or replace function tf.run(p_role text, p_uid uuid, p_sql text)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claim.role', p_role, true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
  exception when others then
    reset role;
    raise;
  end;
  reset role;
  return v;
end;
$$;

create or replace function tf.eq(p_label text, p_actual jsonb, p_expected jsonb)
returns void
language plpgsql
as $$
begin
  if p_actual is distinct from p_expected then
    raise exception E'BAŞARISIZ: %\n  beklenen: %\n  gelen:    %', p_label, p_expected, p_actual;
  end if;
  raise notice 'tamam: %', p_label;
end;
$$;

create or replace function tf.ok(p_label text, p_cond boolean)
returns void
language plpgsql
as $$
begin
  if p_cond is distinct from true then
    raise exception 'BAŞARISIZ: %', p_label;
  end if;
  raise notice 'tamam: %', p_label;
end;
$$;

-- [p_sql] verilen rol + kullanıcı ile çalışınca hata vermelidir. p_state
-- doluysa SQLSTATE, p_msg doluysa mesaj parçası da eşleşmelidir.
create or replace function tf.fails(
  p_label text, p_role text, p_uid uuid, p_sql text,
  p_state text default null, p_msg text default null)
returns void
language plpgsql
as $$
declare
  v_state text;
  v_text  text;
  v_failed boolean := false;
begin
  begin
    perform tf.run(p_role, p_uid, p_sql);
  exception when others then
    v_failed := true;
    get stacked diagnostics v_state = returned_sqlstate, v_text = message_text;
  end;
  if not v_failed then
    raise exception 'BAŞARISIZ: % — hata beklenirdi (%/%)', p_label, p_role, p_sql;
  end if;
  if p_state is not null and v_state <> p_state then
    raise exception 'BAŞARISIZ: % — SQLSTATE % (beklenen %): %', p_label, v_state, p_state, v_text;
  end if;
  if p_msg is not null and position(p_msg in v_text) = 0 then
    raise exception 'BAŞARISIZ: % — mesaj "%" "%" içermiyor', p_label, v_text, p_msg;
  end if;
  raise notice 'tamam: % (%)', p_label, v_state;
end;
$$;

-- Test kullanıcısı: doğrulanmış e-posta, ayar satırı seed tetikleyicisinden.
create or replace function tf.mkuser(p_id uuid, p_email text, p_confirmed boolean default true)
returns uuid
language plpgsql
as $$
begin
  insert into auth.users (id, email, email_confirmed_at)
  values (p_id, p_email, case when p_confirmed then now() end);
  return p_id;
end;
$$;
