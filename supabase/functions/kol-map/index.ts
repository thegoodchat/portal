// Edge Function: reads the KOL mapping Google Sheet (via the Apps Script in drive-upload/Code.gs) for the Coordination page.
// Read only. Only active programme team (Coordination) accounts can call it. Emails, WhatsApp numbers and manager contacts are never returned.
// Deploy: Edge Functions > Deploy a new function > name it "kol-map" > turn OFF "Enforce JWT verification"
// (the function checks who is calling itself).
// Secrets: DRIVE_SCRIPT_URL and DRIVE_SCRIPT_SECRET (same as upload-proposal) and KOL_SHEET_ID (the Google Sheet's ID: the long text between /d/ and /edit in its address).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

// Only these fields leave the function, whatever the script returns.
const KEEP = ['country', 'ref', 'tick', 'name', 'platform', 'handle', 'stage', 'known', 'platform2', 'handle2', 'notes', 'first', 'referred', 'audience', 'score',
  'attend', 'followers', 'followers2', 'event', 'mgmt', 'mtype', 'mname', 'mdoes', 'mok', 'applied', 'adate', 'fellow', 'fwhy', 'ready', 'rnotes'];
export const shape = (rows: any[]) => (Array.isArray(rows) ? rows : []).map((r) => {
  const o: Record<string, unknown> = {};
  KEEP.forEach((k) => { if (r && r[k] !== undefined && r[k] !== '') o[k] = r[k]; });
  return o;
});

let cache: { at: number; body: unknown } | null = null;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const scriptUrl = Deno.env.get('DRIVE_SCRIPT_URL') || '';
    const secret = Deno.env.get('DRIVE_SCRIPT_SECRET') || '';
    const sheetId = Deno.env.get('KOL_SHEET_ID') || '';
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(401, { error: 'Please sign in again.' });
    const admin = createClient(url, svc);
    const { data: me } = await admin.from('profiles').select('role,active').eq('id', user.id).maybeSingle();
    if (!me || !me.active || !['program', 'country'].includes(me.role)) return json(403, { error: 'Only Coordination can see the KOL mapping.' });
    if (!scriptUrl || !secret || !sheetId) return json(500, { error: 'The KOL mapping link is not set up yet. Ask the portal admin to finish the setup (drive-upload/KOLMAP.md).' });
    const b = await req.json().catch(() => ({}));
    if (!b.refresh && cache && Date.now() - cache.at < 60000) return json(200, cache.body);
    const res = await fetch(scriptUrl, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ secret, action: 'kolmap', sheetId }), redirect: 'follow' });
    const out = await res.json().catch(() => null);
    if (!out || !out.ok) return json(502, { error: (out && out.error) || 'Google did not return the sheet.' });
    const body = { ok: true, rows: shape(out.rows), at: out.at, url: out.url };
    cache = { at: Date.now(), body };
    return json(200, body);
  } catch (e) {
    return json(500, { error: String((e as Error).message || e) });
  }
});
