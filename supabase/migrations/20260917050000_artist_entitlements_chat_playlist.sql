-- Subscription entitlements, permanent artist chat, and the shareable Global Playlist.
alter table public.artist_profiles
  add column if not exists subscription_status text not null default 'free',
  add column if not exists subscription_price_cents integer not null default 0,
  add column if not exists subscription_current_period_end timestamptz,
  add column if not exists audiodiin_period_start date,
  add column if not exists audiodiin_uses integer not null default 0;

create table if not exists public.artist_subscriptions (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artist_profiles(id) on delete cascade,
  tier text not null check (tier in ('free','studio','radio','pro')),
  price_cents integer not null check (price_cents >= 0),
  status text not null default 'active' check (status in ('active','past_due','canceled','incomplete')),
  provider text,
  provider_subscription_id text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (artist_id)
);
alter table public.artist_subscriptions enable row level security;
drop policy if exists artist_subscriptions_owner on public.artist_subscriptions;
create policy artist_subscriptions_owner on public.artist_subscriptions
for select to authenticated using (artist_id = (select auth.uid()) or private.is_admin());

create table if not exists public.artist_chat_messages (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artist_profiles(id) on delete restrict,
  body text not null default '' check (char_length(body) <= 5000),
  attachment_bucket text,
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  attachment_size bigint,
  created_at timestamptz not null default now(),
  check (char_length(body) > 0 or attachment_path is not null)
);
create index if not exists artist_chat_messages_created_idx on public.artist_chat_messages(created_at desc);
alter table public.artist_chat_messages enable row level security;
drop policy if exists artist_chat_read_paid on public.artist_chat_messages;
create policy artist_chat_read_paid on public.artist_chat_messages
for select to authenticated using (
  private.is_admin() or exists (
    select 1 from public.artist_profiles p
    where p.id = (select auth.uid()) and p.account_status = 'active' and p.tier in ('studio','radio','pro')
  )
);
drop policy if exists artist_chat_insert_paid on public.artist_chat_messages;
create policy artist_chat_insert_paid on public.artist_chat_messages
for insert to authenticated with check (
  artist_id = (select auth.uid()) and exists (
    select 1 from public.artist_profiles p
    where p.id = (select auth.uid()) and p.account_status = 'active' and p.tier in ('studio','radio','pro')
  )
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('artist-chat','artist-chat',false,52428800,array[
  'image/jpeg','image/png','image/webp','audio/mpeg','audio/wav','audio/x-wav','audio/flac','audio/mp4','audio/x-m4a'
])
on conflict (id) do update set file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists artist_chat_file_read on storage.objects;
create policy artist_chat_file_read on storage.objects for select to authenticated using (
  bucket_id = 'artist-chat' and (
    private.is_admin() or exists (select 1 from public.artist_profiles p where p.id=(select auth.uid()) and p.account_status='active' and p.tier in ('studio','radio','pro'))
  )
);
drop policy if exists artist_chat_file_insert on storage.objects;
create policy artist_chat_file_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'artist-chat' and (storage.foldername(name))[1]=(select auth.uid())::text and exists (select 1 from public.artist_profiles p where p.id=(select auth.uid()) and p.account_status='active' and p.tier in ('studio','radio','pro'))
);

create table if not exists public.global_playlists (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'ODIIN GLOBAL PLAYLIST',
  share_token text not null unique default encode(gen_random_bytes(18),'hex'),
  is_public boolean not null default true,
  created_by uuid references public.artist_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.global_playlist_tracks (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.global_playlists(id) on delete cascade,
  recording_id uuid not null references public.recordings(id) on delete restrict,
  artist_id uuid not null references public.artist_profiles(id) on delete restrict,
  position integer not null default 0 check (position >= 0),
  added_by uuid references public.artist_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (playlist_id, recording_id)
);
create index if not exists global_playlist_tracks_position_idx on public.global_playlist_tracks(playlist_id,position,created_at);
alter table public.global_playlists enable row level security;
alter table public.global_playlist_tracks enable row level security;
drop policy if exists global_playlists_read on public.global_playlists;
create policy global_playlists_read on public.global_playlists for select to anon,authenticated using (is_public or private.is_admin());
drop policy if exists global_playlists_manage on public.global_playlists;
create policy global_playlists_insert on public.global_playlists for insert to authenticated with check (private.is_admin());
create policy global_playlists_update on public.global_playlists for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy global_playlists_delete on public.global_playlists for delete to authenticated using (private.is_admin());
drop policy if exists global_playlist_tracks_read on public.global_playlist_tracks;
create policy global_playlist_tracks_read on public.global_playlist_tracks for select to anon,authenticated using (exists (select 1 from public.global_playlists p where p.id=playlist_id and (p.is_public or private.is_admin())));
drop policy if exists global_playlist_tracks_manage on public.global_playlist_tracks;
create policy global_playlist_tracks_insert on public.global_playlist_tracks for insert to authenticated with check (private.is_admin());
create policy global_playlist_tracks_update on public.global_playlist_tracks for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy global_playlist_tracks_delete on public.global_playlist_tracks for delete to authenticated using (private.is_admin());
drop policy if exists playlist_recording_read on public.recordings;
create policy playlist_recording_read on public.recordings for select to anon,authenticated using (
  exists (select 1 from public.global_playlist_tracks t join public.global_playlists p on p.id=t.playlist_id where t.recording_id=recordings.id and (p.is_public or private.is_admin()))
  or owner_artist_id=(select auth.uid()) or private.is_admin()
);

insert into public.global_playlists (name,is_public)
select 'ODIIN GLOBAL PLAYLIST',true
where not exists (select 1 from public.global_playlists);

-- Artists may edit profile information, but never grant themselves entitlements.
create or replace function public.protect_artist_entitlements()
returns trigger language plpgsql set search_path = public, private as $$
begin
  if not private.is_admin() then
    new.tier := old.tier;
    new.subscription_status := old.subscription_status;
    new.subscription_price_cents := old.subscription_price_cents;
    new.subscription_current_period_end := old.subscription_current_period_end;
    new.audiodiin_period_start := old.audiodiin_period_start;
    new.audiodiin_uses := old.audiodiin_uses;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_artist_entitlements on public.artist_profiles;
create trigger protect_artist_entitlements before update on public.artist_profiles for each row execute function public.protect_artist_entitlements();

-- Allow the public playlist feed to read only the metadata needed for a shareable playlist.
grant select on public.global_playlists, public.global_playlist_tracks, public.recordings to anon;
create index if not exists artist_chat_messages_artist_idx on public.artist_chat_messages(artist_id);
create index if not exists global_playlist_tracks_recording_idx on public.global_playlist_tracks(recording_id);
create index if not exists global_playlist_tracks_artist_idx on public.global_playlist_tracks(artist_id);
create index if not exists global_playlist_tracks_added_by_idx on public.global_playlist_tracks(added_by);
create index if not exists global_playlists_created_by_idx on public.global_playlists(created_by);
