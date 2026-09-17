# ODIIN Backend Administration

This module is the operating layer for OTS Royalty Recovery & Monitoring and ODIIN Distro platform delivery.

## System boundaries

The dashboard stores catalog data, connection status, secret *references*, search cases, registrations, recovery claims, sync jobs, and audit events. API keys, OAuth refresh tokens, SFTP passwords, and webhook secrets must remain in the Supabase Edge Function secret store and must never be written to browser code or database rows.

## Royalty workflow

1. Create a royalty search using artist/title plus ISRC, ISWC, IPI/CAE, UPC and provider account identifiers.
2. Search authorized sources: distributor statements, The MLC, SoundExchange, PRO exports, YouTube Content ID, neighboring-rights sources, and approved Mogul feeds.
3. Normalize statement lines and match by exact identifier first, then title/artist/date review.
4. Turn verified findings into recovery cases.
5. Collect chain-of-title, split sheets, registrations, identity/tax documents, and statement evidence.
6. Submit through the rights holder's authorized account or approved partner API.
7. Record external case references, decisions, recoveries, fees, and audit history.

No system should claim money automatically without rights-holder authority and evidence. Potential amounts are estimates until accepted by the paying society or platform.

## Registration workflow

Use separate registrations for composition/public performance, US mechanicals, sound recording performance, neighboring rights, YouTube Content ID, and distribution delivery. Validate writer and publisher shares before submission; writer shares and publisher shares must each balance under the receiving organization's rules.

## Platform connection model

Platforms are classified by access model:

- `open_api` / `oauth`: public developer access, usually metadata or analytics only.
- `partner_api`, `ddex`, `sftp`: commercial delivery after contract and technical certification.
- `aggregator`: ODIIN sends to an approved intermediary that delivers to outlets.
- `contract_only`: licensing/acquisition relationship; no general self-service ingestion API.
- `statement_import`: authorized CSV/XLSX/SFTP ingestion when an API is unavailable.

Spotify, Apple Music, Amazon, TikTok, Meta, Netflix, Hulu, Tubi, and most FAST outlets require commercial approval or an approved aggregator for content delivery. A consumer/developer API key does not create distributor rights.

## Connection order

1. Mogul and Labelcaster: obtain written API/export specifications, sandbox credentials, rate limits, webhooks, and data-processing terms.
2. Rights sources: authorize The MLC, SoundExchange, BMI/ASCAP/SESAC, HFA or export ingestion per account.
3. Music delivery: secure DDEX/ERN delivery through Labelcaster or another approved aggregator before seeking direct DSP certification.
4. Movie delivery: begin with Filmhub or another approved aggregator; pursue direct FAST/licensing contracts after a qualified catalog and delivery history exist.
5. Analytics: add public/OAuth analytics connections separately from delivery contracts.

## Required production controls

- Admin users use Supabase `app_metadata.role=admin`; artists cannot grant themselves this role.
- Every operational table has RLS. Artist views are read-only and limited to their own cases.
- Edge Functions verify the access token and admin role before service-role operations.
- Each delivery is idempotent, logged, retry-limited, and reconciled against the response or later statement.
- Webhooks are signature-verified and stored with replay protection.
- Secrets are rotated and referenced by name only.
- PII, tax documents, contracts, and evidence files use private storage with short-lived signed links.

## Credentials still required

For each provider, ODIIN needs the legal account owner, contract status, developer/partner approval, sandbox and production endpoints, authentication method, scopes, credential secret name, webhook signing secret, and a technical contact. The dashboard can manage and test these connections after the provider grants access; it cannot bypass provider approval.

