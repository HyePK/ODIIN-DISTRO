-- Split provider readiness into six independent operational dimensions.
-- The legacy status column is retained as a trigger-maintained summary for
-- backwards compatibility; it is no longer the source of truth.

alter table public.platform_connections
  add column if not exists account_authentication_status text not null default 'not_configured',
  add column if not exists data_import_status text not null default 'not_configured',
  add column if not exists registration_authority_status text not null default 'not_applicable',
  add column if not exists content_delivery_status text not null default 'not_applicable',
  add column if not exists royalty_collection_status text not null default 'not_applicable',
  add column if not exists production_testing_status text not null default 'not_started';

alter table public.platform_connections
  drop constraint if exists platform_connections_account_authentication_status_check,
  drop constraint if exists platform_connections_data_import_status_check,
  drop constraint if exists platform_connections_registration_authority_status_check,
  drop constraint if exists platform_connections_content_delivery_status_check,
  drop constraint if exists platform_connections_royalty_collection_status_check,
  drop constraint if exists platform_connections_production_testing_status_check;

alter table public.platform_connections
  add constraint platform_connections_account_authentication_status_check check (
    account_authentication_status in (
      'not_applicable','not_configured','contract_required','credentials_required',
      'authorization_required','blocked','testing','partial','authenticated',
      'working','authorized','production_ready','passed','paused','expired','error'
    )
  ),
  add constraint platform_connections_data_import_status_check check (
    data_import_status in (
      'not_applicable','not_configured','contract_required','credentials_required',
      'authorization_required','blocked','testing','partial','authenticated',
      'working','authorized','production_ready','passed','paused','expired','error'
    )
  ),
  add constraint platform_connections_registration_authority_status_check check (
    registration_authority_status in (
      'not_applicable','not_configured','contract_required','credentials_required',
      'authorization_required','blocked','testing','partial','authenticated',
      'working','authorized','production_ready','passed','paused','expired','error'
    )
  ),
  add constraint platform_connections_content_delivery_status_check check (
    content_delivery_status in (
      'not_applicable','not_configured','contract_required','credentials_required',
      'authorization_required','blocked','testing','partial','authenticated',
      'working','authorized','production_ready','passed','paused','expired','error'
    )
  ),
  add constraint platform_connections_royalty_collection_status_check check (
    royalty_collection_status in (
      'not_applicable','not_configured','contract_required','credentials_required',
      'authorization_required','blocked','testing','partial','authenticated',
      'working','authorized','production_ready','passed','paused','expired','error'
    )
  ),
  add constraint platform_connections_production_testing_status_check check (
    production_testing_status in (
      'not_applicable','not_started','contract_required','credentials_required',
      'authorization_required','blocked','ready','testing','partial','passed',
      'paused','expired','failed','error'
    )
  );

-- Establish a capability-aware baseline for every existing connection.
update public.platform_connections pc
set
  account_authentication_status = case
    when pc.status = 'connected' then 'authenticated'
    when pc.status = 'testing' then 'testing'
    when pc.status = 'paused' then 'paused'
    when pc.status = 'error' then 'error'
    else pc.status
  end,
  data_import_status = case
    when mp.capabilities && array['catalog','metadata','analytics','statements','royalty_search','status']::text[] then
      case
        when pc.status = 'connected' then 'working'
        when pc.status = 'testing' then 'testing'
        when pc.status = 'paused' then 'paused'
        when pc.status = 'error' then 'error'
        else pc.status
      end
    else 'not_applicable'
  end,
  registration_authority_status = case
    when mp.capabilities && array['registration','claims','content_id','rights_management','licensing']::text[] then
      case when pc.status = 'connected' then 'authorized' else pc.status end
    else 'not_applicable'
  end,
  content_delivery_status = case
    when mp.capabilities && array['catalog_delivery','upload','channel','fast_channel']::text[] then
      case when pc.status = 'connected' then 'production_ready' else pc.status end
    else 'not_applicable'
  end,
  royalty_collection_status = case
    when mp.capabilities && array['statements','claims','monetization']::text[] then
      case when pc.status = 'connected' then 'working' else pc.status end
    else 'not_applicable'
  end,
  production_testing_status = case
    when pc.status = 'connected' and pc.last_tested_at is not null then 'passed'
    when pc.status = 'testing' then 'testing'
    when pc.status = 'error' then 'failed'
    else 'not_started'
  end
from public.media_platforms mp
where mp.id = pc.platform_id;

-- Verified provider-specific truth. Read access/import success does not imply
-- registration, delivery, collection, or production-test authority.
update public.platform_connections pc
set account_authentication_status = 'authenticated',
    data_import_status = 'working',
    registration_authority_status = 'authorization_required',
    content_delivery_status = 'not_applicable',
    royalty_collection_status = 'authorization_required',
    production_testing_status = 'partial',
    auth_type = coalesce(pc.auth_type, 'oauth2'),
    last_synced_at = coalesce(pc.last_synced_at, timestamptz '2026-09-17 03:38:47+00'),
    updated_at = now()
from public.media_platforms mp
where mp.id = pc.platform_id and mp.slug = 'mogul';

update public.platform_connections pc
set account_authentication_status = 'authenticated',
    data_import_status = 'working',
    registration_authority_status = 'not_applicable',
    content_delivery_status = 'credentials_required',
    royalty_collection_status = 'authorization_required',
    production_testing_status = 'partial',
    auth_type = 'manual_import',
    last_synced_at = coalesce(pc.last_synced_at, timestamptz '2026-09-17 03:38:47+00'),
    updated_at = now()
from public.media_platforms mp
where mp.id = pc.platform_id and mp.slug = 'labelcaster';

update public.platform_connections pc
set account_authentication_status = 'authenticated',
    data_import_status = 'working',
    registration_authority_status = 'authorization_required',
    content_delivery_status = 'not_applicable',
    royalty_collection_status = 'authorization_required',
    production_testing_status = 'partial',
    auth_type = 'manual_import',
    updated_at = now()
from public.media_platforms mp
where mp.id = pc.platform_id and mp.slug in ('bmi','soundexchange');

create or replace function private.sync_platform_connection_summary_status()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  dimension_statuses text[];
begin
  dimension_statuses := array[
    new.account_authentication_status,
    new.data_import_status,
    new.registration_authority_status,
    new.content_delivery_status,
    new.royalty_collection_status,
    new.production_testing_status
  ];

  new.status := case
    when 'error' = any(dimension_statuses) or 'failed' = any(dimension_statuses) then 'error'
    when 'paused' = any(dimension_statuses) or 'expired' = any(dimension_statuses) then 'paused'
    when 'contract_required' = any(dimension_statuses) then 'contract_required'
    when 'credentials_required' = any(dimension_statuses) then 'credentials_required'
    when 'authorization_required' = any(dimension_statuses) or 'blocked' = any(dimension_statuses) then 'authorization_required'
    when 'testing' = any(dimension_statuses) or 'partial' = any(dimension_statuses) then 'testing'
    when new.production_testing_status = 'passed' then 'connected'
    else 'not_configured'
  end;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists platform_connections_sync_summary_status on public.platform_connections;
create trigger platform_connections_sync_summary_status
before insert or update of
  account_authentication_status,
  data_import_status,
  registration_authority_status,
  content_delivery_status,
  royalty_collection_status,
  production_testing_status
on public.platform_connections
for each row execute function private.sync_platform_connection_summary_status();

-- Recompute the compatibility summary after the trigger exists.
update public.platform_connections
set account_authentication_status = account_authentication_status;

comment on column public.platform_connections.status is
  'Derived compatibility summary. Use the six readiness status columns for operational decisions.';
comment on column public.platform_connections.account_authentication_status is
  'Whether ODIIN can authenticate to the provider account.';
comment on column public.platform_connections.data_import_status is
  'Whether ODIIN can import catalog, usage, or statement data.';
comment on column public.platform_connections.registration_authority_status is
  'Whether ODIIN is legally and technically authorized to submit registrations or claims.';
comment on column public.platform_connections.content_delivery_status is
  'Whether ODIIN can deliver releases, films, channels, updates, and takedowns.';
comment on column public.platform_connections.royalty_collection_status is
  'Whether ODIIN is authorized and configured to collect or reconcile royalties.';
comment on column public.platform_connections.production_testing_status is
  'Result of end-to-end production readiness testing.';
