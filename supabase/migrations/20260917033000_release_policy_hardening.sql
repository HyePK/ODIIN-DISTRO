drop policy if exists release_insert on public.releases;
create policy release_insert on public.releases
for insert to authenticated
with check (
  artist_id = (select auth.uid())
  and (
    status = 'review'
    or (is_sandbox = true and status = 'draft')
  )
  and exists (
    select 1 from public.artist_profiles p
    where p.id = (select auth.uid()) and p.account_status = 'active'
  )
);

drop policy if exists release_update on public.releases;
create policy release_update on public.releases
for update to authenticated
using (artist_id = (select auth.uid()) or private.is_admin())
with check (
  private.is_admin()
  or (
    artist_id = (select auth.uid())
    and (status = 'review' or (is_sandbox = true and status = 'draft'))
  )
);
