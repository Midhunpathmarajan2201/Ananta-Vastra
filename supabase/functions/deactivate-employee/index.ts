// Deploy as a Supabase Edge Function named `deactivate-employee`.
// Set SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY as server secrets.
// Never expose the service-role key in the browser.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Authentication required' }), {
      status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) throw new Error('Server secrets are not configured');

    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Invalid session' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const adminClient = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from('profiles').select('id, role, is_active').eq('id', user.id).maybeSingle();
    if (callerProfileError || !callerProfile?.is_active || callerProfile.role !== 'admin') {
      return new Response(JSON.stringify({ error: 'Admin permission required' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json().catch(() => ({}));
    const employeeId = String(body.employeeId || '').trim();
    if (!employeeId || employeeId === user.id) {
      return new Response(JSON.stringify({ error: 'A valid Sales employee ID is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: target, error: targetError } = await adminClient
      .from('profiles').select('id, role, full_name, is_active').eq('id', employeeId).maybeSingle();
    if (targetError || !target || target.role !== 'sales') {
      return new Response(JSON.stringify({ error: 'Sales employee not found' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!target.is_active) {
      return new Response(JSON.stringify({ ok: true, alreadyDeactivated: true }), {
        status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Disable at the database first. RLS rejects this user on their next request immediately.
    const { error: updateError } = await adminClient.from('profiles')
      .update({ is_active: false, deactivated_at: new Date().toISOString() })
      .eq('id', employeeId);
    if (updateError) throw updateError;

    // Revoke all refresh/access sessions for this employee.
    const { error: signOutError } = await adminClient.auth.admin.signOut(employeeId, 'global');
    if (signOutError) throw signOutError;

    await adminClient.from('activity_log').insert({
      actor_id: user.id,
      action: 'employee_deactivated',
      entity_type: 'profile',
      entity_id: employeeId,
      details: { employee_name: target.full_name, sessions_revoked: true },
    });

    await adminClient.from('app_notifications').insert({
      title: 'Employee account deactivated',
      message: `${target.full_name}'s access was deactivated by Admin. Historical sales records are retained.`,
      target_role: 'admin',
    });

    return new Response(JSON.stringify({ ok: true, employeeId, sessionsRevoked: true }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('deactivate-employee failed', error);
    return new Response(JSON.stringify({ error: 'Unable to complete employee deactivation' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
