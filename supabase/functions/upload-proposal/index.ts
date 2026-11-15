// Edge Function: saves a fellow's campaign proposal as a PDF in their own Google Drive folder.
// It checks who is signed in, finds that fellow's folder (never sent from the browser), and passes the
// proposal to a small Google Apps Script (see drive-upload/Code.gs) that does the saving as your Google account.
// Deploy: Supabase dashboard > Edge Functions > Deploy a new function > paste this file, name it "upload-proposal".
// Secrets to set (Edge Functions > Secrets):
//   DRIVE_SCRIPT_URL    the Web app URL of the deployed Apps Script
//   DRIVE_SCRIPT_SECRET the same secret you set in the script's properties
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

export function folderId(url: string): string | null {
  const m = /\/folders\/([A-Za-z0-9_-]+)/.exec(url || '') || /[?&]id=([A-Za-z0-9_-]+)/.exec(url || '');
  return m ? m[1] : null;
}
export function safeName(n: string): string {
  return String(n || '').replace(/[^A-Za-z0-9_.-]+/g, '_').slice(0, 120);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const scriptUrl = Deno.env.get('DRIVE_SCRIPT_URL') || '';
    const secret = Deno.env.get('DRIVE_SCRIPT_SECRET') || '';
    if (!scriptUrl || !secret) return json(500, { error: 'The Drive upload is not set up yet.' });
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(401, { error: 'Please sign in again.' });
    const admin = createClient(url, svc);
    const { data: me } = await admin.from('profiles').select('*').eq('id', user.id).maybeSingle();
    if (!me || !me.active || me.role !== 'fellow' || !me.fellow_id) return json(403, { error: 'Only fellows can upload their proposal.' });
    const b = await req.json();
    const html = String(b.html || '');
    if (html.length < 50 || html.length > 2_000_000) return json(400, { error: 'The proposal looks empty or too large.' });
    const { data: fp } = await admin.from('fellow_private').select('folder_url').eq('fellow_id', me.fellow_id).maybeSingle();
    const id = folderId(fp?.folder_url || '');
    if (!id) return json(400, { error: 'Your Drive folder link has not been added yet. Ask your Coordination team.' });
    const r = await fetch(scriptUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify({ secret, folderId: id, fileName: safeName(b.fileName) || 'Proposal', html }),
      redirect: 'follow',
    });
    const out = await r.json().catch(() => null);
    if (!out || !out.ok) return json(502, { error: (out && out.error) || 'Google Drive did not accept the file.' });
    return json(200, { ok: true, name: out.name, url: out.url });
  } catch (e) {
    return json(500, { error: String((e as Error).message || e) });
  }
});
