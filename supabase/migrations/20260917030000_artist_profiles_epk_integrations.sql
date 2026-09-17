alter table public.artist_profiles
  add column if not exists bio text,
  add column if not exists genres text[] not null default '{}',
  add column if not exists city text,
  add column if not exists state_region text,
  add column if not exists booking_email text,
  add column if not exists website_url text,
  add column if not exists social_links jsonb not null default '{}'::jsonb,
  add column if not exists avatar_path text,
  add column if not exists banner_path text,
  add column if not exists is_published boolean not null default false;

alter table public.releases
  add column if not exists is_sandbox boolean not null default false,
  add column if not exists source_system text not null default 'odiin_distro',
  add column if not exists external_release_id text,
  add column if not exists provider_status jsonb not null default '{}'::jsonb;

create table if not exists public.epks (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artist_profiles(id) on delete cascade,
  version integer not null default 1 check (version > 0),
  status text not null default 'processing' check (status in ('processing','ready','failed','archived')),
  profile_snapshot jsonb not null default '{}'::jsonb,
  bucket_id text not null default 'epk-files',
  object_path text,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists epks_artist_created_idx on public.epks (artist_id, created_at desc);
alter table public.epks enable row level security;

drop policy if exists epks_owner on public.epks;
create policy epks_owner on public.epks
for all to authenticated
using (artist_id = (select auth.uid()) or private.is_admin())
with check (artist_id = (select auth.uid()) or private.is_admin());

create table if not exists public.artist_provider_connections (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artist_profiles(id) on delete cascade,
  provider text not null check (provider in ('mogul','labelcaster')),
  external_account_id text,
  status text not null default 'credentials_required'
    check (status in ('credentials_required','authorization_required','testing','connected','paused','error')),
  scopes text[] not null default '{}',
  last_synced_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (artist_id, provider)
);

create table if not exists public.integration_sync_runs (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artist_profiles(id) on delete cascade,
  provider text not null check (provider in ('mogul','labelcaster')),
  sync_type text not null,
  status text not null default 'queued' check (status in ('queued','running','complete','partial','failed')),
  records_received integer not null default 0 check (records_received >= 0),
  records_matched integer not null default 0 check (records_matched >= 0),
  records_unmatched integer not null default 0 check (records_unmatched >= 0),
  cursor_value text,
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists integration_sync_runs_artist_idx
  on public.integration_sync_runs (artist_id, provider, started_at desc);

alter table public.artist_provider_connections enable row level security;
alter table public.integration_sync_runs enable row level security;

drop policy if exists artist_provider_connections_owner on public.artist_provider_connections;
create policy artist_provider_connections_owner on public.artist_provider_connections
for select to authenticated
using (artist_id = (select auth.uid()) or private.is_admin());

drop policy if exists integration_sync_runs_owner on public.integration_sync_runs;
create policy integration_sync_runs_owner on public.integration_sync_runs
for select to authenticated
using (artist_id = (select auth.uid()) or private.is_admin());

drop policy if exists artist_profile_insert on public.artist_profiles;
create policy artist_profile_insert on public.artist_profiles
for insert to authenticated
with check (id = (select auth.uid()));

create or replace function public.handle_new_artist_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.artist_profiles (id, artist_name, legal_name, account_status)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'artist_name', ''), split_part(coalesce(new.email, 'artist'), '@', 1)),
    nullif(new.raw_user_meta_data ->> 'legal_name', ''),
    'active'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_artist_profile on auth.users;
create trigger on_auth_user_created_artist_profile
after insert on auth.users
for each row execute function public.handle_new_artist_user();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('artist-media', 'artist-media', false, 20971520, array['image/jpeg','image/png','image/webp']),
  ('artist-documents', 'artist-documents', false, 52428800, array['application/pdf','image/jpeg','image/png']),
  ('epk-files', 'epk-files', false, 52428800, array['text/html','application/pdf','application/zip'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists artist_extended_file_read on storage.objects;
create policy artist_extended_file_read on storage.objects
for select to authenticated
using (
  bucket_id in ('artist-media','artist-documents','epk-files')
  and ((storage.foldername(name))[1] = (select auth.uid())::text or private.is_admin())
);

drop policy if exists artist_extended_file_insert on storage.objects;
create policy artist_extended_file_insert on storage.objects
for insert to authenticated
with check (
  bucket_id in ('artist-media','artist-documents','epk-files')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists artist_extended_file_update on storage.objects;
create policy artist_extended_file_update on storage.objects
for update to authenticated
using (
  bucket_id in ('artist-media','artist-documents','epk-files')
  and ((storage.foldername(name))[1] = (select auth.uid())::text or private.is_admin())
)
with check (
  bucket_id in ('artist-media','artist-documents','epk-files')
  and ((storage.foldername(name))[1] = (select auth.uid())::text or private.is_admin())
);

drop policy if exists artist_extended_file_delete on storage.objects;
create policy artist_extended_file_delete on storage.objects
for delete to authenticated
using (
  bucket_id in ('artist-media','artist-documents','epk-files')
  and ((storage.foldername(name))[1] = (select auth.uid())::text or private.is_admin())
);

insert into public.provider_connections (provider, connection_type, status, notes)
values
  ('Mogul', 'partner API, webhook, or statement export', 'credentials_required', 'Awaiting official partner credentials and documentation.'),
  ('Labelcaster', 'distribution API, webhook, DDEX, SFTP, or statement export', 'credentials_required', 'Awaiting official partner credentials and documentation.')
on conflict (provider) do update set
  connection_type = excluded.connection_type,
  status = case when public.provider_connections.status = 'connected' then 'connected' else excluded.status end,
  notes = excluded.notes,
  updated_at = now();

update public.provider_connections
set provider = 'Platform Playback',
    connection_type = 'verified usage API',
    updated_at = now()
where provider = ('ODIIN ' || 'Streaming');
