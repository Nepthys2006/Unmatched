-- Player accounts: a username and a password, the same on every device (phone, PC, web).
--
-- Usernames are unique ignoring case ("Daryl" and "daryl" are the same account), 3-16 letters,
-- digits or underscores. Passwords are stored only as bcrypt hashes. Signing in hands out a
-- random session token; only its SHA-256 is stored, so a leaked table can't be used to sign in.
--
-- Security: row level security is on with NO table policies; the publishable key can only call
-- the functions below, which never return hashes.
--
-- Apply: Supabase dashboard > SQL Editor > paste this file > Run. Safe to run again.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.accounts (
  id            uuid primary key default gen_random_uuid(),
  username      text not null check (username ~ '^[A-Za-z0-9_]{3,16}$'),
  password_hash text not null,
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);
-- One account per name, whatever the capitals.
create unique index if not exists accounts_username_key on public.accounts (lower(username));

create table if not exists public.account_sessions (
  token_hash  text primary key,                 -- sha256 of the token the device keeps
  account_id  uuid not null references public.accounts (id) on delete cascade,
  created_at  timestamptz not null default now(),
  seen_at     timestamptz not null default now()
);

alter table public.accounts enable row level security;
alter table public.account_sessions enable row level security;
revoke all on public.accounts, public.account_sessions from anon, authenticated;

create or replace function public._new_session(p_account uuid)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  t text := encode(gen_random_bytes(32), 'hex');
begin
  insert into account_sessions (token_hash, account_id) values (encode(digest(t, 'sha256'), 'hex'), p_account);
  -- Sessions not used for 90 days are dropped.
  delete from account_sessions where seen_at < now() - interval '90 days';
  return t;
end $$;

-- Creates an account and signs it in. Fails if the name is taken (in any capitals).
create or replace function public.register_account(p_username text, p_password text)
returns table (username text, token text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  u text := trim(coalesce(p_username, ''));
  a accounts;
begin
  if u !~ '^[A-Za-z0-9_]{3,16}$' then
    raise exception 'Usernames are 3 to 16 letters, numbers or _.';
  end if;
  if char_length(coalesce(p_password, '')) < 6 or char_length(p_password) > 72 then
    raise exception 'Passwords are 6 to 72 characters.';
  end if;
  if lower(p_password) = lower(u) then
    raise exception 'The password can''t be the same as the username.';
  end if;
  if exists (select 1 from accounts where lower(accounts.username) = lower(u)) then
    raise exception 'That username is taken.';
  end if;
  begin
    insert into accounts (username, password_hash) values (u, crypt(p_password, gen_salt('bf', 10))) returning * into a;
  exception when unique_violation then
    raise exception 'That username is taken.';
  end;
  return query select a.username, _new_session(a.id);
end $$;

-- Signs in with a username (any capitals) and password.
create or replace function public.sign_in(p_username text, p_password text)
returns table (username text, token text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  a accounts;
begin
  select * into a from accounts where lower(accounts.username) = lower(trim(coalesce(p_username, '')));
  if not found or crypt(coalesce(p_password, ''), a.password_hash) <> a.password_hash then
    raise exception 'Wrong username or password.';
  end if;
  update accounts set last_seen_at = now() where id = a.id;
  return query select a.username, _new_session(a.id);
end $$;

-- The account a device's saved token belongs to (null if it was signed out or expired).
create or replace function public.check_session(p_token text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  name text;
begin
  update account_sessions s set seen_at = now()
  from accounts a
  where s.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') and a.id = s.account_id
  returning a.username into name;
  return name;
end $$;

create or replace function public.sign_out(p_token text)
returns void
language sql security definer set search_path = public, extensions as $$
  delete from account_sessions where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

revoke all on function public._new_session(uuid) from public, anon, authenticated;
grant execute on function public.register_account(text, text) to anon, authenticated;
grant execute on function public.sign_in(text, text) to anon, authenticated;
grant execute on function public.check_session(text) to anon, authenticated;
grant execute on function public.sign_out(text) to anon, authenticated;
