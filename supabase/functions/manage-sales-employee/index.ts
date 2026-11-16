// Ananta Vastra: Admin-only Sales account provisioning and management.
// Deploy as: supabase functions deploy manage-sales-employee
// Required server secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// The service-role key must ONLY be stored as an Edge Function secret.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const allowedOrigins = new Set([
  'https://anantavastra-test.pages.dev',
  'https://de73591d.anantavastra-test.pages.dev',
  'http://localhost:8788',
  'http://localhost:3000',
]);

function isAllowedOrigin(origin: string | null): boolean {
  return !!origin && (allowedOrigins.has(origin) || /^https:\/\/[a-z0-9-]+\.anantavastra-test\.pages\.dev$/.test(origin));
}

function cors(origin: string | null) {
  const allowed = isAllowedOrigin(origin) ? origin! : 'null';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

function response(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(origin), 'Content-Type': 'application/json' },
  });
}

function normalizeUsername(value: unknown): string {
  const username = String(value ?? '').trim().toLowerCase();
  if (!/^[a-z0-9._-]{3,32}$/.test(username)) {
    throw new Error('Username must be 3–32 characters: letters, numbers, dot, underscore or hyphen.');
  }
  return username;
}

function syntheticSalesEmail(username: string): string {
  // Internal Supabase Auth identity. Sales signs in with username in the UI;
  // the client derives this same email locally before calling signInWithPassword.
  return `${username}@sales.anantavastra.in`;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') {
    if (origin && !isAllowedOrigin(origin)) return response({ error: 'Origin not allowed' }, 403, null);
    return new Response('ok', { headers: cors(origin) });
  }
  if (req.method !== 'POST') return response({ error: 'Method not allowed' }, 405, origin);
  if (!isAllowedOrigin(origin)) return response({ error: 'Origin not allowed' }, 403, null);

  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return response({ error: 'Authentication required' }, 401, origin);

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) throw new Error('Server configuration is incomplete.');

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await caller.auth.getUser();
    if (userError || !user) return response({ error: 'Invalid or expired session.' }, 401, origin);
    const { data: activeSession, error: activeSessionError } = await caller.rpc('is_active_user');
    if (activeSessionError || activeSession !== true) return response({ error: 'Session expired or account inactive. Sign in again.' }, 401, origin);

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actor, error: actorError } = await admin
      .from('profiles').select('id,role,is_active').eq('id', user.id).maybeSingle();
    if (actorError || !actor || !actor.is_active || actor.role !== 'admin') {
      return response({ error: 'Only the active Owner Admin can manage Sales accounts.' }, 403, origin);
    }

    const body = await req.json();
    const action = String(body.action ?? '');
    const username = normalizeUsername(body.username);
    const email = syntheticSalesEmail(username);

    if (action === 'create') {
      const fullName = String(body.fullName ?? '').trim();
      const password = String(body.password ?? '');
      if (fullName.length < 2) return response({ error: 'Employee full name is required.' }, 400, origin);
      if (password.length < 10) return response({ error: 'Sales password must contain at least 10 characters.' }, 400, origin);

      const { data: existing } = await admin.from('profiles').select('id').eq('username', username).maybeSingle();
      if (existing) return response({ error: 'This username is already in use.' }, 409, origin);

      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, username, role: 'sales' },
              });
      if (createError || !created.user) return response({ error: createError?.message ?? 'Unable to create Auth account.' }, 400, origin);

      const { error: profileError } = await admin.from('profiles').insert({
        id: created.user.id, full_name: fullName, username, role: 'sales', is_active: true,
      });
      if (profileError) {
        await admin.auth.admin.deleteUser(created.user.id);
        return response({ error: profileError.message }, 400, origin);
      }
      await admin.from('activity_log').insert({
        actor_id: user.id, action: 'sales_employee_created', entity_type: 'profile',
        entity_id: created.user.id, details: { username, full_name: fullName },
      });
      return response({ ok: true, employeeId: created.user.id, username }, 200, origin);
    }

    const { data: target, error: targetError } = await admin
      .from('profiles').select('id,role,full_name,is_active').eq('username', username).maybeSingle();
    if (targetError || !target || target.role !== 'sales') {
      return response({ error: 'Sales employee not found. Admin credentials cannot be changed through this function.' }, 404, origin);
    }

    if (action === 'update-profile') {
      const fullName = String(body.fullName ?? '').trim();
      if (fullName.length < 2) return response({ error: 'Employee full name is required.' }, 400, origin);
      const { error } = await admin.auth.admin.updateUserById(target.id, {
        user_metadata: { full_name: fullName, username, role: 'sales' },
      });
      if (error) return response({ error: error.message }, 400, origin);
      const { error: profileError } = await admin.from('profiles')
        .update({ full_name: fullName, updated_at: new Date().toISOString() }).eq('id', target.id);
      if (profileError) return response({ error: profileError.message }, 400, origin);
      await admin.from('activity_log').insert({
        actor_id: user.id, action: 'sales_employee_updated', entity_type: 'profile',
        entity_id: target.id, details: { username, full_name: fullName },
      });
      return response({ ok: true, username, action }, 200, origin);
    }

    if (action === 'reset-password') {
      const password = String(body.password ?? '');
      if (password.length < 10) return response({ error: 'New Sales password must contain at least 10 characters.' }, 400, origin);
      const { error } = await admin.auth.admin.updateUserById(target.id, { password });
      if (error) return response({ error: error.message }, 400, origin);
      await admin.from('activity_log').insert({
        actor_id: user.id, action: 'sales_password_reset', entity_type: 'profile',
        entity_id: target.id, details: { username },
      });
      return response({ ok: true, username, action }, 200, origin);
    }

    if (action === 'deactivate') {
      const { error: profileError } = await admin.from('profiles')
        .update({ is_active: false, deactivated_at: new Date().toISOString(), updated_at: new Date().toISOString(), session_iat_valid_after: Math.ceil(Date.now() / 1000) + 1 })
        .eq('id', target.id);
      if (profileError) return response({ error: profileError.message }, 400, origin);
      // RLS rejects previously issued JWTs immediately via session_iat_valid_after. Auth ban also blocks new sign-ins.
      const { error: banError } = await admin.auth.admin.updateUserById(target.id, { ban_duration: '876000h' });
      if (banError) return response({ error: 'Profile disabled, but Auth ban failed: ' + banError.message }, 500, origin);
      await admin.from('activity_log').insert({
        actor_id: user.id, action: 'sales_employee_deactivated', entity_type: 'profile',
        entity_id: target.id, details: { username },
      });
      return response({ ok: true, username, action, accessDisabled: true }, 200, origin);
    }

    if (action === 'reactivate') {
      const password = String(body.password ?? '');
      if (password.length < 10) return response({ error: 'Set a new password (at least 10 characters) when reactivating.' }, 400, origin);
      const { error: authError } = await admin.auth.admin.updateUserById(target.id, {
        password, ban_duration: 'none',
      });
      if (authError) return response({ error: authError.message }, 400, origin);
      const { error: profileError } = await admin.from('profiles')
        .update({ is_active: true, deactivated_at: null, updated_at: new Date().toISOString() })
        .eq('id', target.id);
      if (profileError) return response({ error: profileError.message }, 400, origin);
      await admin.from('activity_log').insert({
        actor_id: user.id, action: 'sales_employee_reactivated', entity_type: 'profile',
        entity_id: target.id, details: { username },
      });
      return response({ ok: true, username, action }, 200, origin);
    }

    return response({ error: 'Action must be create, update-profile, reset-password, deactivate or reactivate.' }, 400, origin);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected request error.';
    return response({ error: message }, 400, origin);
  }
});