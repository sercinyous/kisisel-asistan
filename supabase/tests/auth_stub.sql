-- Yerel PostgreSQL'de Supabase'in auth şemasını ve rollerini taklit eder.
-- Yalnızca supabase/tests/run_local.sh tarafından, boş bir veritabanında
-- çalıştırılır; gerçek Supabase projesinde ÇALIŞTIRILMAZ.
create schema auth;

create table auth.users (
  id         uuid primary key,
  email      text,
  created_at timestamptz default now()
);

create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create function auth.role() returns text
language sql stable
as $$ select current_setting('request.jwt.claim.role', true) $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.role() to anon, authenticated, service_role;
-- Yeni Supabase projelerindeki gibi: public tablolarında varsayılan yetki yok.
revoke all on schema public from public;
grant usage on schema public to anon;
