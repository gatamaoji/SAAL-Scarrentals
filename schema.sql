-- =====================================================================
-- Car Rental Management System — shared database for Supabase
-- Run once: Supabase dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run (it replaces functions and policies).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- One table holds every record as JSON, keyed by collection + id.
create table if not exists public.records (
  collection  text        not null,
  id          text        not null,
  data        jsonb       not null,
  deleted     boolean     not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  uuid                 default auth.uid(),
  primary key (collection, id)
);
create index if not exists records_updated_idx on public.records (updated_at);

-- Atomic document-number counters (booking, agreement, invoice, payment, customer numbers)
create table if not exists public.counters (
  kind text primary key,
  n    bigint not null default 0
);

alter table public.records  enable row level security;
alter table public.counters enable row level security;   -- no policies: only reachable through functions below

-- Supabase grants ALL (incl. DELETE/TRUNCATE, which bypass RLS) by default — take it all back first.
revoke all on public.records  from public, anon, authenticated;
revoke all on public.counters from public, anon, authenticated;
grant select, insert, update on public.records to authenticated;

-- ---------- helper functions (run with owner rights, used by the policies) ----------
create or replace function public.crms_profile() returns jsonb
language sql stable security definer set search_path = public as $$
  select data from public.records
  where collection = 'users' and id = auth.uid()::text and not deleted
$$;

create or replace function public.crms_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.crms_profile() ->> 'active')::boolean, false)
$$;

create or replace function public.crms_can(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.crms_active() and exists (
    select 1 from public.records r
    where r.collection = 'roles' and not r.deleted
      and r.id = public.crms_profile() ->> 'roleId'
      and (r.data -> 'perms') ? p)
$$;

-- Is the database already set up (has at least one user)? Callable before sign-in.
create or replace function public.crms_is_setup() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.records where collection = 'users' and not deleted)
$$;

-- First administrator. Only works while the database has no users at all.
create or replace function public.crms_bootstrap(p_roles jsonb, p_profile jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  perform pg_advisory_xact_lock(424242);
  if exists (select 1 from public.records where collection = 'users' and not deleted) then
    raise exception 'This database is already set up';
  end if;
  for r in select * from jsonb_array_elements(p_roles) loop
    insert into public.records (collection, id, data) values ('roles', r ->> 'id', r)
    on conflict (collection, id) do update set data = excluded.data, deleted = false, updated_at = now();
  end loop;
  insert into public.records (collection, id, data)
  values ('users', auth.uid()::text, p_profile || jsonb_build_object('id', auth.uid()::text, 'active', true))
  on conflict (collection, id) do update set data = excluded.data, deleted = false, updated_at = now();
  return 'ok';
end $$;

-- Reserve a block of document numbers, never below p_floor (highest number already used).
create or replace function public.crms_reserve(p_kind text, p_size int, p_floor bigint default 0) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not public.crms_active() then raise exception 'Permission denied'; end if;
  if p_size < 1 or p_size > 5000 then raise exception 'Invalid block size'; end if;
  insert into public.counters as c (kind, n) values (p_kind, greatest(coalesce(p_floor, 0), 0) + p_size)
  on conflict (kind) do update set n = greatest(c.n, coalesce(p_floor, 0)) + p_size
  returning n into v;
  return v - p_size + 1;
end $$;

-- Administrator sets / resets another user's password.
create or replace function public.crms_set_password(p_user uuid, p_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.crms_can('users') then raise exception 'Permission denied'; end if;
  if length(coalesce(p_password, '')) < 6 then raise exception 'Password must be at least 6 characters'; end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
   where id = p_user;
  if not found then raise exception 'User not found'; end if;
end $$;

-- A user updates their own last sign-in time / clears "must change password".
create or replace function public.crms_self_update(p_last_login text, p_clear_must boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update public.records
     set data = data
               || case when p_last_login is not null then jsonb_build_object('lastLogin', p_last_login) else '{}'::jsonb end
               || case when coalesce(p_clear_must, false) then jsonb_build_object('mustChange', false) else '{}'::jsonb end,
         updated_at = now()
   where collection = 'users' and id = auth.uid()::text;
end $$;

revoke all on function public.crms_bootstrap(jsonb, jsonb)       from public, anon;
revoke all on function public.crms_reserve(text, int, bigint)     from public, anon;
revoke all on function public.crms_set_password(uuid, text)      from public, anon;
revoke all on function public.crms_self_update(text, boolean)    from public, anon;
revoke all on function public.crms_profile()                      from public, anon;
revoke all on function public.crms_active()                       from public, anon;
revoke all on function public.crms_can(text)                      from public, anon;
grant execute on function public.crms_is_setup()                 to anon, authenticated;
grant execute on function public.crms_bootstrap(jsonb, jsonb)    to authenticated;
grant execute on function public.crms_reserve(text, int, bigint)  to authenticated;
grant execute on function public.crms_set_password(uuid, text)   to authenticated;
grant execute on function public.crms_self_update(text, boolean) to authenticated;
grant execute on function public.crms_profile(), public.crms_active(), public.crms_can(text) to authenticated;

-- ---------- row-level security ----------
drop policy if exists rec_select on public.records;
drop policy if exists rec_insert on public.records;
drop policy if exists rec_update on public.records;

-- Active staff see everything; anyone signed in can see their own profile (to be told it is disabled).
create policy rec_select on public.records for select to authenticated
  using (public.crms_active() or (collection = 'users' and id = auth.uid()::text));

-- Writing: users/roles need "users"; settings/categories need "settings"; others need an active account.
create policy rec_insert on public.records for insert to authenticated
  with check (
    public.crms_active() and case
      when collection in ('users', 'roles')        then public.crms_can('users')
      when collection in ('settings', 'categories') then public.crms_can('settings')
      else true end);

-- Audit log is append-only: no updates, no deletes.
create policy rec_update on public.records for update to authenticated
  using (public.crms_active() and collection <> 'audit')
  with check (
    public.crms_active() and collection <> 'audit' and case
      when collection in ('users', 'roles')        then public.crms_can('users')
      when collection in ('settings', 'categories') then public.crms_can('settings')
      else true end);
-- No delete policy: records are never physically deleted (deleted = true instead).

-- ---------- live updates to every signed-in user ----------
do $$ begin
  alter publication supabase_realtime add table public.records;
exception when duplicate_object then null; end $$;
