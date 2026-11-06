-- Emulación mínima de Supabase para validar las migraciones en PostgreSQL local.
-- No forma parte de las migraciones: se ejecuta antes de 0001.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_app_meta_data  jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

grant select, insert, update, delete on auth.users to service_role;

-- Equivalente a auth.jwt() de Supabase: claims del request.
create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$$;

-- Equivalente a auth.uid(): sub del JWT, con conversión segura.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select case
    when (auth.jwt() ->> 'sub')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then (auth.jwt() ->> 'sub')::uuid
    else null
  end;
$$;
