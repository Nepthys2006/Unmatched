-- Online lobbies for Unmatched.
--
-- A host creates a named lobby (optionally with a password); others see it in the lobby list
-- and join. The match itself runs over a Supabase Realtime channel whose name (`topic`) is a
-- secret handed out only by join_lobby, after the password check. When a match ends, the
-- lobby row is deleted and only the winner and the players' names are kept (match_results).
--
-- Security: row level security is on and there are NO table policies, so the publishable key
-- can't read or change the tables directly. Everything goes through the functions below, which
-- check the host's secret token before changing a lobby and never return password hashes,
-- tokens or topics to anyone but the right person.
--
-- Apply: Supabase dashboard > SQL Editor > paste this file > Run. Safe to run again.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.lobbies (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(name) between 1 and 32),
  host_name     text not null check (char_length(host_name) between 1 and 24),
  mode          text not null check (mode in ('duel', 'teams2', 'teams3', 'ffa')),
  players       int  not null check (players between 2 and 6),
  open_seats    int  not null default 0 check (open_seats between 0 and 6),
  status        text not null default 'waiting' check (status in ('waiting', 'playing')),
  password_hash text,                -- bcrypt; null = no password
  topic         text not null unique, -- secret Realtime channel name
  host_token    text not null,        -- secret: proves a call comes from the host
  created_at    timestamptz not null default now(),
  seen_at       timestamptz not null default now()  -- host heartbeat
);

create table if not exists public.match_results (
  id          bigint generated always as identity primary key,
  winner      text,
  players     text[] not null,
  finished_at timestamptz not null default now()
);

alter table public.lobbies enable row level security;
alter table public.match_results enable row level security;
revoke all on public.lobbies, public.match_results from anon, authenticated;

-- Lobbies whose host stopped sending heartbeats (app closed, phone died) are removed.
create or replace function public._sweep_lobbies() returns void
language sql security definer set search_path = public, extensions as $$
  delete from lobbies where seen_at < now() - interval '2 minutes';
$$;

create or replace function public.list_lobbies()
returns table (id uuid, name text, host_name text, mode text, players int, open_seats int, has_password boolean)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _sweep_lobbies();
  return query
    select l.id, l.name, l.host_name, l.mode, l.players, l.open_seats, l.password_hash is not null
    from lobbies l
    where l.status = 'waiting'
    order by l.created_at desc
    limit 100;
end $$;

create or replace function public.create_lobby(
  p_name text, p_host_name text, p_password text, p_mode text, p_players int, p_open int)
returns table (id uuid, topic text, host_token text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  r lobbies;
begin
  perform _sweep_lobbies();
  insert into lobbies (name, host_name, mode, players, open_seats, password_hash, topic, host_token)
  values (
    left(trim(p_name), 32),
    left(trim(p_host_name), 24),
    p_mode, p_players, p_open,
    case when coalesce(p_password, '') = '' then null else crypt(p_password, gen_salt('bf')) end,
    encode(gen_random_bytes(16), 'hex'),
    encode(gen_random_bytes(24), 'hex'))
  returning * into r;
  return query select r.id, r.topic, r.host_token;
end $$;

-- Returns the lobby's channel name if the player may join.
create or replace function public.join_lobby(p_id uuid, p_password text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  r lobbies;
begin
  select * into r from lobbies where id = p_id;
  if not found then raise exception 'This lobby is gone.'; end if;
  if r.status <> 'waiting' then raise exception 'That match has already started.'; end if;
  if r.open_seats < 1 then raise exception 'The lobby is full.'; end if;
  if r.password_hash is not null and (p_password is null or crypt(p_password, r.password_hash) <> r.password_hash) then
    raise exception 'Wrong password.';
  end if;
  return r.topic;
end $$;

-- Host only: keeps the lobby listed (heartbeat) and up to date.
create or replace function public.update_lobby(
  p_id uuid, p_token text, p_mode text, p_players int, p_open int, p_status text)
returns void
language sql security definer set search_path = public, extensions as $$
  update lobbies
  set mode = p_mode, players = p_players, open_seats = p_open, status = p_status, seen_at = now()
  where id = p_id and host_token = p_token;
$$;

-- Host only: the match ended. Keep who won and who played; delete everything else.
create or replace function public.finish_lobby(p_id uuid, p_token text, p_winner text, p_players text[])
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from lobbies where id = p_id and host_token = p_token) then
    insert into match_results (winner, players)
    values (left(p_winner, 64), (select coalesce(array_agg(left(x, 24)), '{}') from unnest(p_players[1:6]) x));
    delete from lobbies where id = p_id;
  end if;
end $$;

-- Host only: closed without a result (left the lobby or the match).
create or replace function public.close_lobby(p_id uuid, p_token text)
returns void
language sql security definer set search_path = public, extensions as $$
  delete from lobbies where id = p_id and host_token = p_token;
$$;

revoke all on function public._sweep_lobbies() from public, anon, authenticated;
grant execute on function public.list_lobbies() to anon, authenticated;
grant execute on function public.create_lobby(text, text, text, text, int, int) to anon, authenticated;
grant execute on function public.join_lobby(uuid, text) to anon, authenticated;
grant execute on function public.update_lobby(uuid, text, text, int, int, text) to anon, authenticated;
grant execute on function public.finish_lobby(uuid, text, text, text[]) to anon, authenticated;
grant execute on function public.close_lobby(uuid, text) to anon, authenticated;
