// Edge Function: lets coordinators create and switch off logins without touching the database.
// Programme coordinator: any role. Country coordinator: fellows, CSOs and KOL friends in their own country.
// Communications: KOL friends (any country).
// Deploy: Supabase dashboard > Edge Functions > Deploy a new function > paste this file, name it "invite-user".
// Set one secret: SITE_URL = your site address, e.g. https://thegoodchat.github.io/tgc4/
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const ROLES = ['program', 'country', 'fellow', 'friend', 'cso', 'listener', 'comms', 'ops', 'partner'];
const COUNTRY_MANAGED = ['fellow', 'cso', 'friend'];
const TEAM_ROLES = ['program', 'country', 'listener', 'comms', 'ops', 'partner'];
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Pure rule check, easy to test: may this caller do this?
export function allowed(me: any, target: any): string | null {
  if (!me || !me.active) return 'Not allowed.';
  if (me.role === 'program') return TEAM_ROLES.includes(target.role) && !me.is_admin ? 'Only portal admins can manage team logins.' : null;
  if (me.role === 'comms') return target.role === 'friend' ? null : 'Communications can manage KOL friends only.';
  if (me.role !== 'country') return 'Only coordinators can manage logins.';
  if (!COUNTRY_MANAGED.includes(target.role)) return 'Country coordinators can manage fellows, CSOs and KOL friends only.';
  if (!me.country || target.country !== me.country) return 'You can only manage people in your own country.';
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const svc = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const site = Deno.env.get('SITE_URL') || '';
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json(401, { error: 'Please sign in again.' });
    const admin = createClient(url, svc);
    const { data: me } = await admin.from('profiles').select('*').eq('id', user.id).maybeSingle();
    const b = await req.json();

    if (b.action === 'invite') {
      const email = String(b.email || '').trim().toLowerCase();
      const t = { role: b.role, country: b.country || null, fellow_id: b.fellow_id || null, cso_id: b.cso_id || null, friend_id: b.friend_id || null };
      if (!EMAIL.test(email)) return json(400, { error: 'That email does not look right.' });
      if (!ROLES.includes(t.role)) return json(400, { error: 'Pick a role.' });
      if (['country', 'fellow'].includes(t.role) && !['TH', 'ID'].includes(t.country)) return json(400, { error: 'Pick a country.' });
      if (t.role === 'friend') {
        if (!t.friend_id) return json(400, { error: 'Pick the KOL friend.' });
        const { data: fr } = await admin.from('records').select('key').eq('kind', 'fd:friends').like('key', '%/' + t.friend_id).maybeSingle();
        if (!fr) return json(400, { error: 'That KOL friend does not exist.' });
        const { data: ff } = await admin.from('fellows').select('country').eq('id', String(fr.key).split('/')[0]).maybeSingle();
        if (!ff) return json(400, { error: 'That KOL friend does not belong to a fellow.' });
        t.country = ff.country;
      }
      if (t.role === 'fellow') {
        if (!t.fellow_id) return json(400, { error: 'Pick the fellow.' });
        const { data: f } = await admin.from('fellows').select('country').eq('id', t.fellow_id).maybeSingle();
        if (!f) return json(400, { error: 'That fellow does not exist.' });
        t.country = f.country;
      }
      if (t.role === 'cso') {
        if (!t.cso_id) return json(400, { error: 'Pick the organisation.' });
        const { data: r } = await admin.from('records').select('data').eq('kind', 'list:csos').eq('key', t.cso_id).maybeSingle();
        if (!r) return json(400, { error: 'That organisation does not exist.' });
        t.country = r.data.country || null;
      }
      const deny = allowed(me, t);
      if (deny) return json(403, { error: deny });
      const redirectTo = typeof b.redirectTo === 'string' && site && b.redirectTo.startsWith(site) ? b.redirectTo : site || undefined;
      const { data: inv, error: ie } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo, data: { needs_password: true } });
      if (ie || !inv?.user) {
        const why = String(ie?.message || '');
        if (/already|registered|exists/i.test(why)) {
          // The person was invited before: send them a fresh link to choose a password instead of failing.
          const { data: old } = await admin.from('profiles').select('id,active').eq('email', email).maybeSingle();
          if (old) {
            const { error: re } = await admin.auth.resetPasswordForEmail(email, { redirectTo });
            if (re) return json(400, { error: 'Could not send the email: ' + re.message });
            return json(200, { ok: true, resent: true });
          }
          return json(400, { error: 'That email already has an account that is not set up in the portal. Delete that user in Supabase (Authentication > Users) and invite again.' });
        }
        return json(400, { error: 'Could not send the invite: ' + (why || 'unknown error') + (/rate|limit|too many/i.test(why) ? ' Supabase limits how many emails it sends each hour. Wait a while, or set up your own email sender in Supabase (Authentication > SMTP).' : '') });
      }
      const label = String(b.label || email).slice(0, 80);
      const { error: pe } = await admin.from('profiles').upsert({ id: inv.user.id, email, label, role: t.role, country: t.country, fellow_id: t.fellow_id, cso_id: t.cso_id, friend_id: t.friend_id, active: true });
      if (pe) { await admin.auth.admin.deleteUser(inv.user.id); return json(400, { error: 'Could not save the profile.' }); }
      return json(200, { ok: true });
    }

    if (b.action === 'set_admin') {
      if (!me || !me.active || me.role !== 'program' || !me.is_admin) return json(403, { error: 'Only portal admins can do this.' });
      const { data: target } = await admin.from('profiles').select('*').eq('id', b.profile_id).maybeSingle();
      if (!target || !['program', 'country'].includes(target.role)) return json(404, { error: 'Admins are chosen from Coordination users.' });
      if (target.id === user.id) return json(400, { error: 'You cannot change your own admin access.' });
      await admin.from('profiles').update({ is_admin: !!b.is_admin }).eq('id', target.id);
      return json(200, { ok: true });
    }

    if (b.action === 'deactivate' || b.action === 'reactivate') {
      const { data: target } = await admin.from('profiles').select('*').eq('id', b.profile_id).maybeSingle();
      if (!target) return json(404, { error: 'No such account.' });
      if (target.id === user.id) return json(400, { error: 'You cannot switch off your own login.' });
      const deny = allowed(me, target);
      if (deny) return json(403, { error: deny });
      const on = b.action === 'reactivate';
      await admin.from('profiles').update({ active: on }).eq('id', target.id);
      await admin.auth.admin.updateUserById(target.id, { ban_duration: on ? 'none' : '876000h' });
      return json(200, { ok: true });
    }
    return json(400, { error: 'Unknown action.' });
  } catch (_e) {
    return json(500, { error: 'Something went wrong.' });
  }
});
