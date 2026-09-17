import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Content-Type': 'application/json',
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  const token = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!token) return reply({ error: 'Authentication required' }, 401);
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: { user } } = await admin.auth.getUser(token);
  if (user?.app_metadata?.role !== 'admin') return reply({ error: 'Admin access required' }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply({ error: 'Invalid JSON' }, 400); }
  const action = String(body.action || 'update');

  if (action === 'list') {
    const page = Math.max(1, Number(body.page) || 1);
    const perPage = Math.min(100, Math.max(1, Number(body.perPage) || 50));
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) return reply({ error: 'Account list failed' }, 500);
    const ids = data.users.map((item) => item.id);
    const { data: profiles } = await admin.from('artist_profiles')
      .select('id,odiin_artist_id,artist_name,legal_name,account_status,tier,created_at')
      .in('id', ids);
    const profileMap = new Map((profiles || []).map((item) => [item.id, item]));
    return reply({ users: data.users.map((item) => ({
      id: item.id, email: item.email, created_at: item.created_at,
      last_sign_in_at: item.last_sign_in_at, email_confirmed_at: item.email_confirmed_at,
      role: item.app_metadata?.role || 'artist', profile: profileMap.get(item.id) || null,
    })), total: data.total });
  }

  if (action === 'invite') {
    const email = String(body.email || '').trim().toLowerCase();
    const artistName = String(body.artistName || '').trim();
    const legalName = String(body.legalName || '').trim();
    if (!email || !artistName) return reply({ error: 'Email and artist name are required' }, 400);
    const redirectTo = typeof body.redirectTo === 'string' ? body.redirectTo : undefined;
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { artist_name: artistName, legal_name: legalName }, redirectTo,
    });
    if (error) return reply({ error: error.message }, 400);
    return reply({ id: data.user.id, email: data.user.email, invited: true }, 201);
  }

  if (action === 'update') {
    const artistId = String(body.artistId || '');
    const accountStatus = String(body.accountStatus || '');
    const tier = String(body.tier || '');
    if (!artistId || !['pending','active','suspended','banned'].includes(accountStatus) ||
        !['free','collaborator','ambassador'].includes(tier)) {
      return reply({ error: 'Valid artistId, accountStatus and tier are required' }, 400);
    }
    const { data, error } = await admin.from('artist_profiles')
      .update({ account_status: accountStatus, tier, updated_at: new Date().toISOString() })
      .eq('id', artistId)
      .select('id,odiin_artist_id,artist_name,account_status,tier').single();
    if (error) return reply({ error: 'Account update failed' }, 500);
    await admin.from('audit_log').insert({ actor_id: user.id, action: 'account.update', entity_type: 'artist_profile', entity_id: artistId, after_data: data });
    return reply(data);
  }

  return reply({ error: 'Unsupported action' }, 400);
});

