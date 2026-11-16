// Edge Function: exports the programme's posts, events, civic actions and KPIs to Google Drive for the social expert.
// Nightly (Supabase cron) and on demand (the "Export to Drive now" button for the programme team and ops).
// The Google Apps Script (drive-upload/Code.gs) keeps ONE Google Sheet up to date and, on the first run of each month,
// saves dated CSV backups. No contact details, paperwork or money are exported.
// Deploy: Edge Functions > Deploy a new function > name it "export-analytics" > turn OFF "Enforce JWT verification"
// (the function checks who is calling itself: the cron secret, or a signed-in programme or ops account).
// Secrets: DRIVE_SCRIPT_URL, DRIVE_SCRIPT_SECRET (same as upload-proposal) and EXPORT_CRON_SECRET (any long random text).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

// ---- pure: turns the saved records into flat tables (first row is the header) ----
const unwrap = (d: any) => (d && typeof d === 'object' && Object.keys(d).length === 1 && '_v' in d ? d._v : d);
const num = (v: any) => (v === undefined || v === null || v === '' ? '' : Number(v) || 0);
const txt = (v: any) => (v === undefined || v === null ? '' : String(v));
const dateOnly = (v: any) => txt(v).slice(0, 10);
const METRICS = ['reach', 'reactions', 'comments', 'saves', 'shares', 'repost'];

export function buildTables(records: any[], fellows: any[]) {
  const fel: Record<string, any> = {};
  fellows.forEach((f) => { fel[f.id] = f; });
  const name = (id: string) => (fel[id] ? fel[id].name : id);
  const country = (id: string) => (fel[id] ? fel[id].country : '');
  const of = (k: string) => records.filter((r) => r.kind === k);
  const friends: Record<string, any> = {};
  of('fd:friends').forEach((r) => { friends[r.key] = r.data || {}; });
  const setup: Record<string, any> = {};
  of('fd:setup').forEach((r) => { setup[r.key] = r.data || {}; });
  const posts: any[][] = [['fellow_id', 'fellow', 'country', 'campaign', 'posted_by', 'posted_by_type', 'platform', 'post_date', 'post_type', 'link', 'caption', 'topic',
    'audience', 'what_we_expected', 'kpis_aimed_at', 'reflected', ...METRICS, 'what_happened', 'what_surprised', 'what_to_change', 'note', 'post_id', 'updated_at']];
  of('fd:posts').forEach((r) => {
    const [f, id] = r.key.split('/'), d = r.data || {}, m = (d.refl && typeof d.refl === 'object') ? d.refl : null;
    posts.push([f, name(f), country(f), num(d.camp), name(f), 'Fellow', txt(d.platform), dateOnly(d.date), txt(d.format), txt(d.url), txt(d.caption), txt(d.topic),
      txt(d.audience), txt(d.expect), (d.kpis || []).join('; '), m ? 'Yes' : 'No', ...METRICS.map((k) => (m ? num(m[k]) : '')),
      m ? txt(m.happened) : '', m ? txt(m.surprise) : '', m ? txt(m.change) : '', '', id, txt(r.updated_at)]);
  });
  of('fp:posts').forEach((r) => {
    const [f, fr, id] = r.key.split('/'), d = r.data || {}, m = d.m || {}, fd = friends[f + '/' + fr] || {};
    posts.push([f, name(f), country(f), num(fd.camp), txt(fd.name || fr), 'KOL friend', txt(d.platform), dateOnly(d.date), txt(d.fmt), txt(d.url), txt(d.caption), '',
      '', '', '', 'Yes', ...METRICS.map((k) => num(m[k])), '', '', '', txt(d.note), id, txt(r.updated_at)]);
  });
  const events: any[][] = [['fellow_id', 'fellow', 'country', 'campaign', 'event', 'type', 'date', 'place', 'attendance', 'showed_up_online', 'event_id']];
  of('fd:events').forEach((r) => {
    const [f, id] = r.key.split('/'), d = r.data || {};
    events.push([f, name(f), country(f), num(d.camp), txt(d.name), txt(d.type), txt(d.date), txt(d.place), num(d.attendance), txt(d.echo), id]);
  });
  const actions: any[][] = [['fellow_id', 'fellow', 'country', 'campaign', 'civic_action', 'measure', 'date', 'people_who_took_action', 'note']];
  of('fd:plan').forEach((r) => {
    const [f, c] = r.key.split('/'), a = (r.data || {}).action || {};
    (a.log || []).forEach((l: any) => actions.push([f, name(f), country(f), num(c), txt(a.text), txt(a.measure), dateOnly(l.date), num(l.count), txt(l.note)]));
  });
  const kpis: any[][] = [['fellow_id', 'fellow', 'country', 'campaign', 'kpi', 'target', 'actual', 'percent_of_target']];
  of('fd:kpis').forEach((r) => {
    const [f, c] = r.key.split('/'), list = unwrap(r.data);
    if (!Array.isArray(list)) return;
    list.forEach((k: any) => {
      let actual = Number(k.a) || 0;
      if (k.auto === 'reach') {
        actual = of('fd:posts').filter((p) => p.key.startsWith(f + '/') && String((p.data || {}).camp) === c && p.data.refl).reduce((s, p) => s + (Number(p.data.refl.reach) || 0), 0)
          + of('fp:posts').filter((p) => p.key.startsWith(f + '/') && String((friends[f + '/' + p.key.split('/')[1]] || {}).camp) === c).reduce((s, p) => s + (Number(((p.data || {}).m || {}).reach) || 0), 0);
      } else if (k.auto === 'att') {
        actual = of('fd:events').filter((e) => e.key.startsWith(f + '/') && String((e.data || {}).camp) === c).reduce((s, e) => s + (Number(e.data.attendance) || 0), 0);
      }
      const t = Number(k.t) || 0;
      kpis.push([f, name(f), country(f), num(c), txt(k.n), t || '', actual, t > 0 ? Math.round((100 * actual) / t) : '']);
    });
  });
  const campaigns: any[][] = [['fellow_id', 'fellow', 'country', 'campaign', 'campaign_name', 'type', 'collaborating_with']];
  Object.keys(setup).forEach((k) => {
    const [f, c] = k.split('/'), d = setup[k];
    if (d && d.name) campaigns.push([f, name(f), country(f), num(c), txt(d.name), txt(d.type), (d.partners || []).map((p: string) => name(p)).join('; ')]);
  });
  return { Posts: posts, Events: events, 'Civic actions': actions, KPIs: kpis, Campaigns: campaigns };
}
export const csv = (rows: any[][]) =>
  rows.map((r) => r.map((v) => { const s = txt(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }).join(',')).join('\r\n');
// ---- end pure ----

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const scriptUrl = Deno.env.get('DRIVE_SCRIPT_URL') || '';
    const secret = Deno.env.get('DRIVE_SCRIPT_SECRET') || '';
    const cron = Deno.env.get('EXPORT_CRON_SECRET') || '';
    const admin = createClient(url, svc);
    const b = await req.json().catch(() => ({}));
    const byCron = !!cron && req.headers.get('x-cron-secret') === cron;
    if (!byCron) {
      const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
      const { data: { user } } = await caller.auth.getUser();
      if (!user) return json(401, { error: 'Please sign in again.' });
      const { data: me } = await admin.from('profiles').select('*').eq('id', user.id).maybeSingle();
      if (!me || !me.active || !['program', 'ops'].includes(me.role)) return json(403, { error: 'Only the programme team and operations can export.' });
    }
    const { data: recs, error: e1 } = await admin.from('records').select('kind,key,data,updated_at').in('kind', ['fd:posts', 'fp:posts', 'fd:friends', 'fd:events', 'fd:plan', 'fd:kpis', 'fd:setup']).limit(50000);
    if (e1) return json(500, { error: 'Could not read the data.' });
    const { data: fellows } = await admin.from('fellows').select('id,name,country');
    const tables = buildTables(recs || [], fellows || []);
    if (b.download) return json(200, { ok: true, files: Object.keys(tables).map((k) => ({ name: k, csv: csv((tables as any)[k]) })) });
    if (!scriptUrl || !secret) return json(500, { error: 'The Drive export is not set up yet.' });
    const res = await fetch(scriptUrl, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ secret, action: 'analytics', tables }), redirect: 'follow' });
    const out = await res.json().catch(() => null);
    if (!out || !out.ok) return json(502, { error: (out && out.error) || 'Google Drive did not accept the export.' });
    return json(200, { ok: true, rows: out.rows, url: out.url, backup: out.backup || '' });
  } catch (e) {
    return json(500, { error: String((e as Error).message || e) });
  }
});
