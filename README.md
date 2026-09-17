# ODIIN Distro

Standalone artist distribution, catalog, royalty, and EPK dashboard.

## Production services

- Supabase Auth for artist accounts
- Supabase Postgres for profiles, releases, rights, royalties, payouts, and provider status
- Private Supabase Storage buckets for artist media, audio, artwork, documents, and generated EPK files
- JWT-protected Edge Functions for EPK generation and provider connection checks
- Row-level security limiting artist records and files to their owner or an authorized administrator

The browser uses only the public Supabase project URL and publishable key. Service-role and provider credentials must remain in the Supabase Edge Function secret store.
