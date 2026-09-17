-- ODIIN Backend Administration: royalty discovery, registration, recovery,
-- and music/movie platform connection control.

create table if not exists public.media_platforms (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]*$'),
  name text not null unique,
  vertical text not null check (vertical in ('music','movie','both','rights')),
  access_model text not null check (access_model in ('open_api','oauth','partner_api','ddex','sftp','aggregator','contract_only','statement_import')),
  capabilities text[] not null default '{}',
  onboarding_url text,
  default_status text not null default 'not_configured'
    check (default_status in ('not_configured','contract_required','credentials_required','authorization_required','testing','connected','paused','error')),
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_connections (
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references public.media_platforms(id) on delete restrict,
  status text not null default 'not_configured'
    check (status in ('not_configured','contract_required','credentials_required','authorization_required','testing','connected','paused','error')),
  auth_type text check (auth_type in ('none','api_key','oauth2','service_account','sftp','ddex','manual_import')),
  external_account_id text,
  scopes text[] not null default '{}',
  secret_reference text,
  webhook_secret_reference text,
  expires_at timestamptz,
  last_tested_at timestamptz,
  last_synced_at timestamptz,
  last_error text,
  config jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform_id)
);

create table if not exists public.royalty_searches (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artist_profiles(id) on delete set null,
  recording_id uuid references public.recordings(id) on delete set null,
  musical_work_id uuid references public.musical_works(id) on delete set null,
  query_name text not null,
  identifiers jsonb not null default '{}'::jsonb,
  sources text[] not null default '{}',
  territories text[] not null default array['US'],
  date_from date,
  date_to date,
  status text not null default 'draft'
    check (status in ('draft','queued','searching','review','complete','cancelled','error')),
  findings_count integer not null default 0 check (findings_count >= 0),
  potential_cents bigint not null default 0 check (potential_cents >= 0),
  recovered_cents bigint not null default 0 check (recovered_cents >= 0),
  result_summary jsonb not null default '{}'::jsonb,
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.registration_cases (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artist_profiles(id) on delete set null,
  recording_id uuid references public.recordings(id) on delete set null,
  musical_work_id uuid references public.musical_works(id) on delete set null,
  agency text not null,
  registration_type text not null check (registration_type in ('composition','mechanical','performance','sound_recording','neighboring_rights','content_id','distribution','movie_delivery')),
  status text not null default 'information_needed'
    check (status in ('information_needed','ready','submitted','accepted','rejected','correction_needed','withdrawn')),
  external_reference text,
  submission_payload jsonb not null default '{}'::jsonb,
  missing_fields text[] not null default '{}',
  submitted_at timestamptz,
  resolved_at timestamptz,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recovery_cases (
  id uuid primary key default gen_random_uuid(),
  search_id uuid references public.royalty_searches(id) on delete set null,
  artist_id uuid references public.artist_profiles(id) on delete set null,
  recording_id uuid references public.recordings(id) on delete set null,
  musical_work_id uuid references public.musical_works(id) on delete set null,
  source text not null,
  claim_type text not null check (claim_type in ('unmatched','unclaimed','underpaid','missing_registration','ownership_conflict','usage_dispute','other')),
  status text not null default 'identified'
    check (status in ('identified','evidence_needed','ready','submitted','provider_review','offer_received','recovered','denied','appealed','closed')),
  period_start date,
  period_end date,
  potential_cents bigint not null default 0 check (potential_cents >= 0),
  claimed_cents bigint not null default 0 check (claimed_cents >= 0),
  recovered_cents bigint not null default 0 check (recovered_cents >= 0),
  fee_cents bigint not null default 0 check (fee_cents >= 0),
  external_reference text,
  evidence jsonb not null default '[]'::jsonb,
  notes text,
  assigned_to uuid references auth.users(id) on delete set null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  recovered_at timestamptz
);

create table if not exists public.integration_jobs (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.platform_connections(id) on delete cascade,
  job_type text not null check (job_type in ('connection_test','catalog_delivery','metadata_update','takedown','statement_import','royalty_search','registration','webhook_replay')),
  status text not null default 'queued' check (status in ('queued','running','complete','partial','failed','cancelled')),
  request_summary jsonb not null default '{}'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  idempotency_key text unique,
  attempts integer not null default 0 check (attempts >= 0),
  error_message text,
  requested_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz
);

create index if not exists royalty_searches_status_idx on public.royalty_searches(status, created_at desc);
create index if not exists registration_cases_status_idx on public.registration_cases(status, created_at desc);
create index if not exists recovery_cases_status_idx on public.recovery_cases(status, created_at desc);
create index if not exists recovery_cases_artist_idx on public.recovery_cases(artist_id, created_at desc);
create index if not exists integration_jobs_connection_idx on public.integration_jobs(connection_id, created_at desc);

alter table public.media_platforms enable row level security;
alter table public.platform_connections enable row level security;
alter table public.royalty_searches enable row level security;
alter table public.registration_cases enable row level security;
alter table public.recovery_cases enable row level security;
alter table public.integration_jobs enable row level security;

drop policy if exists media_platforms_authenticated_read on public.media_platforms;
create policy media_platforms_authenticated_read on public.media_platforms
for select to authenticated using (active = true or private.is_admin());

drop policy if exists media_platforms_admin_all on public.media_platforms;
create policy media_platforms_admin_all on public.media_platforms
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists platform_connections_admin_all on public.platform_connections;
create policy platform_connections_admin_all on public.platform_connections
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists royalty_searches_admin_all on public.royalty_searches;
create policy royalty_searches_admin_all on public.royalty_searches
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists royalty_searches_artist_read on public.royalty_searches;
create policy royalty_searches_artist_read on public.royalty_searches
for select to authenticated using (artist_id = (select auth.uid()));

drop policy if exists registration_cases_admin_all on public.registration_cases;
create policy registration_cases_admin_all on public.registration_cases
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists registration_cases_artist_read on public.registration_cases;
create policy registration_cases_artist_read on public.registration_cases
for select to authenticated using (artist_id = (select auth.uid()));

drop policy if exists recovery_cases_admin_all on public.recovery_cases;
create policy recovery_cases_admin_all on public.recovery_cases
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists recovery_cases_artist_read on public.recovery_cases;
create policy recovery_cases_artist_read on public.recovery_cases
for select to authenticated using (artist_id = (select auth.uid()));

drop policy if exists integration_jobs_admin_all on public.integration_jobs;
create policy integration_jobs_admin_all on public.integration_jobs
for all to authenticated using (private.is_admin()) with check (private.is_admin());

insert into public.media_platforms (slug,name,vertical,access_model,capabilities,onboarding_url,default_status,notes) values
('mogul','Mogul','rights','partner_api',array['catalog','royalty_search','registration','statements'],'https://www.usemogul.com/','credentials_required','Partner credentials and approved API access are required.'),
('labelcaster','Labelcaster','music','partner_api',array['catalog_delivery','status','statements'],null,'credentials_required','Confirm current API, DDEX, SFTP, or statement export access.'),
('spotify','Spotify','music','ddex',array['catalog_delivery','metadata','analytics','statements'],'https://artists.spotify.com/','contract_required','Commercial delivery is normally through an approved distributor and DDEX feed; public developer APIs do not deliver releases.'),
('apple-music','Apple Music / iTunes','both','ddex',array['catalog_delivery','metadata','analytics','statements'],'https://artists.apple.com/','contract_required','Direct delivery requires an approved content-provider agreement or authorized aggregator.'),
('amazon','Amazon Music / Prime Video','both','ddex',array['catalog_delivery','metadata','analytics','statements'],null,'contract_required','Music and video onboarding are separate partner programs.'),
('youtube','YouTube Music / Content ID / Movies','both','partner_api',array['catalog_delivery','content_id','claims','analytics','statements'],'https://support.google.com/youtube/','contract_required','Content Manager and delivery access require approval; ordinary YouTube Data API keys are insufficient.'),
('tiktok','TikTok / CapCut','music','ddex',array['catalog_delivery','metadata','analytics','statements'],null,'contract_required','Use an approved distributor or direct content partnership.'),
('meta','Meta Music','music','ddex',array['catalog_delivery','rights_management','analytics','statements'],null,'contract_required','Rights Manager and commercial music delivery require partner approval.'),
('pandora','Pandora','music','aggregator',array['catalog_delivery','analytics','statements'],'https://amp.pandora.com/','contract_required','Catalog delivery is generally through an approved distributor.'),
('deezer','Deezer','music','ddex',array['catalog_delivery','metadata','analytics','statements'],null,'contract_required','Direct content delivery requires a commercial agreement.'),
('tidal','TIDAL','music','ddex',array['catalog_delivery','metadata','analytics','statements'],null,'contract_required','Direct content delivery requires a commercial agreement.'),
('soundcloud','SoundCloud','music','oauth',array['catalog','upload','analytics','monetization'],'https://developers.soundcloud.com/','authorization_required','Public API and monetization/distribution access are separate approvals.'),
('audiomack','Audiomack','music','partner_api',array['catalog_delivery','analytics','statements'],null,'contract_required','Confirm partner delivery eligibility.'),
('iheartradio','iHeartRadio','music','aggregator',array['catalog_delivery','analytics','statements'],null,'contract_required','Delivery normally occurs through distributor relationships.'),
('napster','Napster','music','ddex',array['catalog_delivery','metadata','statements'],null,'contract_required','Direct delivery requires partner onboarding.'),
('qobuz','Qobuz','music','ddex',array['catalog_delivery','metadata','statements'],null,'contract_required','Direct delivery requires partner onboarding.'),
('boomplay','Boomplay','music','aggregator',array['catalog_delivery','analytics','statements'],null,'contract_required','Use aggregator or approved direct agreement.'),
('anghami','Anghami','music','aggregator',array['catalog_delivery','analytics','statements'],null,'contract_required','Use aggregator or approved direct agreement.'),
('mlc','The MLC','rights','partner_api',array['registration','royalty_search','claims','statements'],'https://www.themlc.com/','authorization_required','Connect the publisher or self-administered songwriter account; API availability depends on program access.'),
('soundexchange','SoundExchange','rights','statement_import',array['registration','royalty_search','claims','statements'],'https://www.soundexchange.com/','authorization_required','Account authorization and repertoire/statement export access are required.'),
('bmi','BMI','rights','statement_import',array['registration','catalog','statements'],'https://www.bmi.com/','authorization_required','Use authorized songwriter/publisher account access and supported exports.'),
('ascap','ASCAP','rights','statement_import',array['registration','catalog','statements'],'https://www.ascap.com/','authorization_required','Use authorized writer/publisher account access and supported exports.'),
('sesac','SESAC','rights','statement_import',array['registration','catalog','statements'],'https://www.sesac.com/','authorization_required','Use authorized writer/publisher account access and supported exports.'),
('harry-fox-agency','Harry Fox Agency','rights','partner_api',array['registration','licensing','royalty_search'],'https://www.harryfox.com/','contract_required','Licensing/data access requires the appropriate agreement.'),
('netflix','Netflix','movie','contract_only',array['catalog_delivery','metadata','quality_control','statements'],'https://npfp.netflixstudios.com/','contract_required','Netflix accepts delivery through approved partners and licensed suppliers.'),
('hulu','Hulu','movie','contract_only',array['catalog_delivery','metadata','quality_control','statements'],null,'contract_required','Requires acquisition/licensing relationship or approved distributor.'),
('roku','Roku','movie','partner_api',array['channel','catalog_delivery','ads','analytics'],'https://developer.roku.com/','authorization_required','Channel development is open; premium licensing and FAST distribution require commercial approval.'),
('tubi','Tubi','movie','aggregator',array['catalog_delivery','metadata','quality_control','statements'],null,'contract_required','Use an approved aggregator or direct licensing agreement.'),
('pluto-tv','Pluto TV','movie','contract_only',array['fast_channel','catalog_delivery','ads','analytics'],null,'contract_required','FAST channel/content onboarding requires a commercial agreement.'),
('samsung-tv-plus','Samsung TV Plus','movie','contract_only',array['fast_channel','catalog_delivery','ads','analytics'],null,'contract_required','FAST distribution requires partner approval.'),
('xumo','Xumo Play','movie','contract_only',array['fast_channel','catalog_delivery','ads','analytics'],null,'contract_required','FAST distribution requires partner approval.'),
('vizio-watchfree','VIZIO WatchFree+','movie','contract_only',array['fast_channel','catalog_delivery','ads','analytics'],null,'contract_required','FAST distribution requires partner approval.'),
('filmhub','Filmhub','movie','aggregator',array['catalog_delivery','metadata','statements'],'https://filmhub.com/','authorization_required','Aggregator account can route films to eligible channels; outlet acceptance is not guaranteed.'),
('google-tv','Google TV / YouTube Movies','movie','aggregator',array['catalog_delivery','metadata','statements'],null,'contract_required','Use an approved film aggregator or direct studio/content-provider agreement.')
on conflict (slug) do update set
  name=excluded.name, vertical=excluded.vertical, access_model=excluded.access_model,
  capabilities=excluded.capabilities, onboarding_url=excluded.onboarding_url,
  default_status=excluded.default_status, notes=excluded.notes, updated_at=now();

insert into public.platform_connections (platform_id,status,auth_type,created_by,updated_by)
select id, default_status,
  case access_model when 'oauth' then 'oauth2' when 'ddex' then 'ddex' when 'sftp' then 'sftp'
    when 'statement_import' then 'manual_import' else 'none' end,
  auth.uid(), auth.uid()
from public.media_platforms
on conflict (platform_id) do nothing;

revoke all on public.media_platforms, public.platform_connections, public.royalty_searches,
  public.registration_cases, public.recovery_cases, public.integration_jobs from anon;

