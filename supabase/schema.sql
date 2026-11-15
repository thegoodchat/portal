-- The Good Chat portal: database, logins and access rules.
-- Run this whole file once in Supabase: SQL Editor > New query > paste > Run.
-- Safe to run again: it drops and recreates the policies.

create extension if not exists pgcrypto;

-- ---------- people ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  label text not null,                       -- name shown in the portal, e.g. "Thailand coordinator"
  role text not null check (role in ('program','country','fellow','friend','cso','listener','partner')),
  country text check (country in ('TH','ID')),  -- country coordinators and fellows
  fellow_id text,                            -- fellows only, e.g. 'nok'
  cso_id text,                               -- civil society organisations only
  friend_id text,                            -- KOL friends only
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.fellows (
  id text primary key,
  name text not null,
  country text not null check (country in ('TH','ID'))
);
insert into public.fellows (id, name, country) values
  ('nok','Thai Fellow 1','TH'),('mind','Thai Fellow 2','TH'),('pim','Thai Fellow 3','TH'),('ton','Thai Fellow 4','TH'),
  ('sari','Indonesian Fellow 1','ID'),('dimas','Indonesian Fellow 2','ID'),('ayu','Indonesian Fellow 3','ID'),('raka','Indonesian Fellow 4','ID')
on conflict (id) do nothing;

-- ---------- data ----------
-- Every piece of portal data is one row here. kind says what it is, key says which one.
create table if not exists public.records (
  kind text not null,
  key text not null,
  data jsonb not null,
  country text,                              -- set automatically
  owner_ref text,                            -- set automatically: 'f:nok', 'c:c1', 'k:f1'
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (kind, key)
);
create index if not exists records_country_idx on public.records (country);

-- Who may read and write each kind of data. Scope: none, own, country, all.
create table if not exists public.kind_access (
  kind text not null,
  role text not null,
  read_scope text not null default 'none' check (read_scope in ('none','own','country','all')),
  write_scope text not null default 'none' check (write_scope in ('none','own','country','all')),
  primary key (kind, role)
);
delete from public.kind_access;
insert into public.kind_access (kind, role, read_scope, write_scope) values
  -- paperwork status and notes to fellows (never documents or money)
  ('map:paper','program','all','all'),('map:paper','country','country','country'),
  ('map:notes','program','all','all'),('map:notes','country','country','country'),
  -- organisation details for invoices
  ('map:camps','program','all','all'),('map:camps','country','all','none'),('map:camps','listener','all','none'),('map:camps','partner','all','none'),('map:camps','fellow','all','none'),('map:camps','friend','all','none'),
  ('map:org','program','all','all'),('map:org','country','country','country'),
  -- social listening: benchmarks, briefs, analysis, comparisons, notes
  ('listen:bench','program','all','all'),('listen:bench','listener','all','all'),('listen:bench','country','country','none'),
  ('listen:pre','program','all','all'),('listen:pre','listener','all','all'),('listen:pre','country','country','none'),
  ('listen:post','program','all','all'),('listen:post','listener','all','all'),('listen:post','country','country','none'),
  ('listen:cmp','program','all','all'),('listen:cmp','listener','all','all'),('listen:cmp','country','country','none'),
  ('listen:data','program','all','all'),('listen:data','listener','all','all'),('listen:data','country','country','none'),
  ('listen:decks','program','all','all'),('listen:decks','listener','all','all'),('listen:decks','country','all','none'),('listen:decks','partner','all','none'),
  ('listen:sec','program','all','all'),('listen:sec','listener','all','all'),
  -- reminders and follow-ups by coordinators
  ('map:reminded','program','all','all'),('map:reminded','country','country','country'),
  ('map:followed','program','all','all'),('map:followed','country','all','all'),('map:followed','listener','all','all'),
  -- programme events, kickoff and co-creation (agenda, hotel, check-in)
  ('list:pevents','program','all','all'),('list:pevents','country','all','country'),('list:pevents','listener','all','none'),
  -- campaign events board, ways to help, community feed
  ('list:cevents','program','all','all'),('list:cevents','country','all','country'),('list:cevents','listener','all','none'),('list:cevents','partner','all','none'),
  ('list:boosts','program','all','all'),('list:boosts','country','all','all'),('list:boosts','listener','all','none'),('list:boosts','partner','all','none'),
  ('list:feed','program','all','all'),('list:feed','country','all','all'),('list:feed','listener','all','all'),('list:feed','partner','all','none'),
  -- civil society organisations and their support
  ('list:csos','program','all','all'),('list:csos','country','country','country'),('list:csos','partner','all','none'),
  ('list:support','program','all','all'),('list:support','country','country','none'),('list:support','partner','all','none'),
  ('list:asks','program','all','all'),('list:asks','country','country','none'),
  -- labelled links to the expert's slides (fellows and partners only see ones meant for them)
  ('list:slides','program','all','all'),('list:slides','listener','all','all'),('list:slides','country','all','all'),
  ('list:slides','partner','all','none'),('list:slides','fellow','all','none'),
  -- fellows: see events, the community board and organisations; post to the board and the events board
  ('list:pevents','fellow','all','none'),('list:cevents','fellow','all','all'),('list:boosts','fellow','all','all'),
  ('list:feed','fellow','all','all'),('list:csos','fellow','all','none'),
  -- key dates: everyone reads, coordinators and the listening expert edit
  ('list:dates','program','all','all'),('list:dates','country','all','all'),('list:dates','listener','all','all'),
  ('list:dates','fellow','all','none'),('list:dates','friend','all','none'),('list:dates','cso','all','none'),('list:dates','partner','all','none'),
  -- monthly masterclasses (Jan to July) and who may arrange their slides
  ('list:classes','program','all','all'),('list:classes','country','all','all'),('list:classes','listener','all','all'),
  ('list:classes','fellow','all','none'),('list:classes','friend','all','none'),('list:classes','partner','all','none'),
  -- country coordinators can add and rearrange slides; KOL friends see slides marked for them
  ('list:slides','friend','all','none'),
  ('list:pevents','friend','all','none'),('list:cevents','friend','all','none'),('list:boosts','friend','all','none'),('list:feed','friend','all','all'),
  -- each fellow's own campaign work: setup, KPIs, plan, posts with reflections, events, collaborators, KOL friends
  ('fd:posts','fellow','own','own'),('fd:posts','country','country','none'),('fd:posts','program','all','all'),('fd:posts','listener','all','none'),('fd:posts','partner','all','none'),
  ('fd:events','fellow','own','own'),('fd:events','country','country','none'),('fd:events','program','all','all'),('fd:events','listener','all','none'),('fd:events','partner','all','none'),
  ('fd:collabs','fellow','own','own'),('fd:collabs','country','country','none'),('fd:collabs','program','all','all'),
  ('fp:posts','friend','all','all'),('fp:posts','fellow','own','none'),('fp:posts','country','country','country'),('fp:posts','program','all','all'),('fp:posts','listener','all','all'),
  ('fd:friends','fellow','own','own'),('fd:friends','country','country','none'),('fd:friends','program','all','all'),
  ('fd:plan','fellow','own','own'),('fd:plan','country','country','country'),('fd:plan','program','all','all'),('fd:plan','listener','all','none'),
  ('fd:setup','fellow','own','own'),('fd:setup','country','country','none'),('fd:setup','program','all','all'),('fd:setup','listener','all','none'),('fd:setup','partner','all','none'),
  ('fd:kpis','fellow','own','own'),('fd:kpis','country','country','none'),('fd:kpis','program','all','all'),('fd:kpis','listener','all','none'),('fd:kpis','partner','all','none'),
  -- fellows see what the expert has shared with them, and their own paperwork status and notes
  ('listen:pre','fellow','own','none'),('listen:post','fellow','own','none'),('listen:cmp','fellow','own','none'),('listen:bench','fellow','own','none'),('listen:data','fellow','own','none'),
  ('map:paper','fellow','own','none'),('map:notes','fellow','own','none'),
  ('list:asks','fellow','own','own'),('list:support','fellow','own','none');

-- ---------- helpers ----------
create or replace function public.my_profile() returns public.profiles
language sql stable security definer set search_path = public as $$
  select * from public.profiles where id = auth.uid() and active;
$$;

create or replace function public.can_access(k text, rc text, ro text, rec jsonb, want_write boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; a public.kind_access; sc text;
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null then return false; end if;
  select * into a from public.kind_access where kind = k and role = p.role;
  if a.kind is null then return false; end if;
  sc := case when want_write then a.write_scope else a.read_scope end;
  -- partners see only decks that are Shared or Final
  if p.role = 'partner' and k = 'listen:decks' and coalesce(rec->>'st','') not in ('Shared','Final') then return false; end if;
  -- slide links: fellows see their own, their country's and everyone's; partners see programme-wide ones
  if k = 'list:slides' and p.role = 'fellow' and coalesce(rec->>'to','') not in ('all', coalesce(p.country,'-'), coalesce(p.fellow_id,'-')) then return false; end if;
  if k = 'list:slides' and p.role = 'fellow' and coalesce(rec->>'fellows','true') = 'false' then return false; end if;
  if k = 'list:slides' and p.role = 'friend' and (coalesce(rec->>'friends','false') <> 'true' or coalesce(rec->>'to','') not in ('all', coalesce(p.country,'-'))) then return false; end if;
  -- fellows see expert write-ups only once they are shared, and a benchmark only once confirmed
  if p.role = 'fellow' and k in ('listen:pre','listen:post','listen:cmp') and coalesce(rec->>'status','') <> 'Shared' then return false; end if;
  if p.role = 'fellow' and k = 'listen:bench' and coalesce(rec->>'st','') <> 'Confirmed' then return false; end if;
  if k = 'fp:posts' and p.role = 'friend' and coalesce(rec->>'friend','-') <> coalesce(p.friend_id,'-') then return false; end if;
  if k = 'list:pevents' and p.role = 'friend' and coalesce(rec->>'friends','false') not in ('true') then return false; end if;
  if k = 'list:slides' and p.role = 'partner' and coalesce(rec->>'to','') not in ('all','TH','ID') then return false; end if;
  -- key links: only the roles named on the link can read it
  if k = 'list:keylinks' and not public.keylink_visible(p.role, rec) then return false; end if;
  -- content features: fellows, KOL friends and CSOs only see the ones that feature them
  if k = 'list:features' and p.role in ('fellow','friend','cso') and not exists (
    select 1 from jsonb_array_elements(coalesce(rec->'who','[]'::jsonb)) w
    where (p.role = 'fellow' and w->>'t' = 'fellow' and w->>'id' = p.fellow_id)
       or (p.role = 'friend' and w->>'t' = 'friend' and w->>'id' = p.friend_id)
       or (p.role = 'cso' and w->>'t' = 'cso' and w->>'id' = p.cso_id)) then return false; end if;
  return case sc
    when 'all' then true
    when 'country' then rc is not null and rc = p.country
    when 'own' then ro is not null and (ro = 'f:' || p.fellow_id or ro = 'c:' || p.cso_id or ro = 'k:' || p.friend_id)
    else false end;
end $$;

create or replace function public.records_set_meta() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text; pr public.profiles;
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  -- KOL friend posts: <fellow>/<friend>/<post>. A friend can only write their own. The server records who edited last.
  if new.kind = 'fp:posts' then
    f := split_part(new.key, '/', 1);
    select * into pr from public.profiles where id = auth.uid();
    if pr.role = 'friend' and (pr.friend_id is null or split_part(new.key, '/', 2) <> pr.friend_id
        or not exists (select 1 from public.records where kind = 'fd:friends' and key = f || '/' || pr.friend_id)) then
      raise exception 'not your post';
    end if;
    new.data := (new.data - 'edited' - 'country') || jsonb_build_object('fellow', f, 'friend', split_part(new.key, '/', 2));
    if pr.role is not null and pr.role <> 'friend' then
      new.data := new.data || jsonb_build_object('edited', jsonb_build_object('by', pr.label, 'role', pr.role, 'at', now()));
    end if;
    select country into new.country from public.fellows where id = f;
    new.owner_ref := 'f:' || f;
    return new;
  end if;
  if new.kind = 'map:org' then
    new.country := new.key;
  elsif new.data ? 'country' and new.data->>'country' in ('TH','ID') then
    new.country := new.data->>'country';
  else
    f := split_part(new.key, '/', 1);
    select country into new.country from public.fellows where id = f;
  end if;
  new.owner_ref := case when new.data ? 'fellow' then 'f:' || (new.data->>'fellow')
                        when exists (select 1 from public.fellows where id = split_part(new.key,'/',1)) then 'f:' || split_part(new.key,'/',1)
                        else null end;
  return new;
end $$;
drop trigger if exists records_meta on public.records;
create trigger records_meta before insert or update on public.records
  for each row execute function public.records_set_meta();

-- ---------- access rules (row level security) ----------
alter table public.profiles enable row level security;
alter table public.fellows enable row level security;
alter table public.records enable row level security;
alter table public.kind_access enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (id = auth.uid() or (select role from public.my_profile()) = 'program');
drop policy if exists profiles_manage on public.profiles;
create policy profiles_manage on public.profiles for all using ((select role from public.my_profile()) = 'program') with check ((select role from public.my_profile()) = 'program');

drop policy if exists fellows_read on public.fellows;
create policy fellows_read on public.fellows for select using (auth.uid() is not null);

drop policy if exists access_read on public.kind_access;
create policy access_read on public.kind_access for select using ((select role from public.my_profile()) = 'program');

drop policy if exists records_read on public.records;
create policy records_read on public.records for select using (public.can_access(kind, country, owner_ref, data, false));
drop policy if exists records_insert on public.records;
create policy records_insert on public.records for insert with check (public.can_access(kind, country, owner_ref, data, true));
drop policy if exists records_update on public.records;
create policy records_update on public.records for update using (public.can_access(kind, country, owner_ref, data, true)) with check (public.can_access(kind, country, owner_ref, data, true));
drop policy if exists records_delete on public.records;
create policy records_delete on public.records for delete using (public.can_access(kind, country, owner_ref, data, true));

-- ---------- live updates ----------
do $$ begin
  alter publication supabase_realtime add table public.records;
exception when duplicate_object then null; end $$;
alter table public.records replica identity full;

-- ---------- after you create the first account in Authentication > Users ----------
-- Make it the programme coordinator (replace the email):
--   insert into public.profiles (id, email, label, role)
--   select id, email, 'Programme coordinator', 'program' from auth.users where email = 'you@example.org';


-- =====================================================================
-- People: fellow and CSO profiles, photos, and who can create logins
-- (added after the first version; safe to run on top of it)
-- =====================================================================
alter table public.fellows add column if not exists photo text;      -- storage path
alter table public.fellows add column if not exists bio text;
alter table public.fellows add column if not exists handles jsonb not null default '{}';

-- Programme coordinator manages every fellow; a country coordinator edits fellows in their own country.
drop policy if exists fellows_program on public.fellows;
create policy fellows_program on public.fellows for all
  using ((select role from public.my_profile()) = 'program')
  with check ((select role from public.my_profile()) = 'program');
drop policy if exists fellows_country on public.fellows;
create policy fellows_country on public.fellows for update
  using ((select role from public.my_profile()) = 'country' and country = (select country from public.my_profile()))
  with check ((select role from public.my_profile()) = 'country' and country = (select country from public.my_profile()));
drop policy if exists fellows_read on public.fellows;
create policy fellows_read on public.fellows for select using (exists (select 1 from public.my_profile()));

-- Country coordinators can see the login accounts of fellows, CSOs and KOL friends in their country.
drop policy if exists profiles_read_country on public.profiles;
create policy profiles_read_country on public.profiles for select using (
  (select role from public.my_profile()) = 'country'
  and country = (select country from public.my_profile())
  and role in ('fellow','cso','friend'));

do $$ begin
  alter publication supabase_realtime add table public.fellows;
exception when duplicate_object then null; end $$;
alter table public.fellows replica identity full;

-- Photos live in a private storage bucket. Any signed-in person can view; coordinators upload.
insert into storage.buckets (id, name, public) values ('people', 'people', false) on conflict (id) do nothing;

create or replace function public.can_edit_photo(path text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; k text := split_part(path, '/', 1); r text := split_part(path, '/', 2); c text;
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null then return false; end if;
  if k = 'me' then return r = auth.uid()::text; end if;   -- anyone may change their own profile photo
  if p.role = 'program' then return true; end if;
  if p.role <> 'country' then return false; end if;
  if k = 'fellow' then select f.country into c from public.fellows f where f.id = r;
  elsif k = 'cso' then select x.country into c from public.records x where x.kind = 'list:csos' and x.key = r;
  else return false; end if;
  return c is not null and c = p.country;
end $$;

drop policy if exists people_photos_read on storage.objects;
create policy people_photos_read on storage.objects for select using (bucket_id = 'people' and exists (select 1 from public.my_profile()));
drop policy if exists people_photos_insert on storage.objects;
create policy people_photos_insert on storage.objects for insert with check (bucket_id = 'people' and public.can_edit_photo(name));
drop policy if exists people_photos_update on storage.objects;
create policy people_photos_update on storage.objects for update using (bucket_id = 'people' and public.can_edit_photo(name));
drop policy if exists people_photos_delete on storage.objects;
create policy people_photos_delete on storage.objects for delete using (bucket_id = 'people' and public.can_edit_photo(name));


-- Make the tables reachable by signed-in users even if "Automatically expose new tables" was switched off.
-- Row Level Security (enabled above) still decides which rows each person can see or change.
grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant execute on all functions in schema public to authenticated, service_role;


-- Slide files (PDF or PowerPoint) live in a private bucket. Uploaders: program, country coordinators, the expert.
-- Anyone else can open a file only if they are allowed to see a slide record that points to it.
insert into storage.buckets (id, name, public) values ('slides', 'slides', false) on conflict (id) do nothing;
create or replace function public.can_manage_slides() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role in ('program','country','listener','comms'));
$$;
drop policy if exists slide_files_read on storage.objects;
create policy slide_files_read on storage.objects for select using (bucket_id = 'slides' and (
  public.can_manage_slides() or exists (select 1 from public.records r where r.kind = 'list:slides' and r.data->>'file' = name)));
drop policy if exists slide_files_insert on storage.objects;
create policy slide_files_insert on storage.objects for insert with check (bucket_id = 'slides' and public.can_manage_slides());
drop policy if exists slide_files_update on storage.objects;
create policy slide_files_update on storage.objects for update using (bucket_id = 'slides' and public.can_manage_slides());
drop policy if exists slide_files_delete on storage.objects;
create policy slide_files_delete on storage.objects for delete using (bucket_id = 'slides' and public.can_manage_slides());


-- Insight screenshots from posts. Private bucket; files sit under <fellow id>/<post id>/.
-- Read: the fellow, the coordinator of that fellow's country, the programme coordinator and the social listening expert.
-- Not partners, not other fellows. Write and delete: the fellow and the programme coordinator.
insert into storage.buckets (id, name, public) values ('insights', 'insights', false) on conflict (id) do nothing;
create or replace function public.can_insight(path text, want_write boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; fid text; fc text;
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null then return false; end if;
  fid := split_part(path, '/', 1);
  if p.role = 'program' then return true; end if;
  -- KOL friends: <fellow id>/<friend id>/<post id>/ is theirs. A fellow can read it but only writes their own posts (numeric post ids).
  if p.role = 'friend' then return p.friend_id is not null and p.friend_id = split_part(path, '/', 2); end if;
  if p.role = 'fellow' then return p.fellow_id is not null and p.fellow_id = fid and (not want_write or split_part(path, '/', 2) ~ '^[0-9]+$'); end if;
  if want_write then return false; end if;
  if p.role in ('listener','comms') then return true; end if;
  if p.role = 'country' then
    select country into fc from public.fellows where id = fid;
    return fc is not null and fc = p.country;
  end if;
  return false;
end $$;
drop policy if exists insight_files_read on storage.objects;
create policy insight_files_read on storage.objects for select using (bucket_id = 'insights' and public.can_insight(name, false));
drop policy if exists insight_files_insert on storage.objects;
create policy insight_files_insert on storage.objects for insert with check (bucket_id = 'insights' and public.can_insight(name, true));
drop policy if exists insight_files_update on storage.objects;
create policy insight_files_update on storage.objects for update using (bucket_id = 'insights' and public.can_insight(name, true));
drop policy if exists insight_files_delete on storage.objects;
create policy insight_files_delete on storage.objects for delete using (bucket_id = 'insights' and public.can_insight(name, true));


-- Programme totals for the Impact tab. Everyone who is signed in can call this, and it returns only numbers and
-- the public parts of plans (message, civic action). It never returns captions, links, reflections, screenshots,
-- spending lines or KOL friend contact details.
create or replace function public.impact_stats() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from public.profiles where id = auth.uid() and active) then jsonb_build_object(
    'posts',   coalesce((select jsonb_agg(jsonb_build_object('f', split_part(key,'/',1), 'camp', data->>'camp',
                 'm', case when jsonb_typeof(data->'refl') = 'object' then jsonb_build_object('reach', data->'refl'->'reach', 'reactions', data->'refl'->'reactions', 'comments', data->'refl'->'comments', 'saves', data->'refl'->'saves', 'shares', data->'refl'->'shares', 'repost', data->'refl'->'repost') else null end))
                 from public.records where kind = 'fd:posts'), '[]'::jsonb),
    'events',  coalesce((select jsonb_agg(jsonb_build_object('f', split_part(key,'/',1), 'camp', data->>'camp', 'att', data->>'attendance')) from public.records where kind = 'fd:events'), '[]'::jsonb),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('f', split_part(r.key,'/',1), 'camp', r.data->>'camp', 'status', r.data->>'status',
                 'm', coalesce((select jsonb_agg(q.data->'m') from public.records q where q.kind = 'fp:posts' and q.key like r.key || '/%'), '[]'::jsonb))) from public.records r where r.kind = 'fd:friends'), '[]'::jsonb),
    'plans',   coalesce((select jsonb_agg(jsonb_build_object('f', split_part(key,'/',1), 'c', split_part(key,'/',2), 'message', data->>'message', 'action', data->'action')) from public.records where kind = 'fd:plan'), '[]'::jsonb),
    'setup',   coalesce((select jsonb_agg(jsonb_build_object('f', split_part(key,'/',1), 'c', split_part(key,'/',2), 'name', data->>'name', 'type', data->>'type', 'partners', coalesce(data->'partners','[]'::jsonb))) from public.records where kind = 'fd:setup'), '[]'::jsonb),
    'kpis',    coalesce((select jsonb_agg(jsonb_build_object('f', split_part(key,'/',1), 'c', split_part(key,'/',2), 'n', jsonb_array_length(case when jsonb_typeof(data->'_v') = 'array' then data->'_v' else '[]'::jsonb end))) from public.records where kind = 'fd:kpis'), '[]'::jsonb),
    'csos',    coalesce((select jsonb_agg(case when jsonb_typeof(data->'partners') = 'array' then data->'partners' else '[]'::jsonb end) from public.records where kind = 'list:csos'), '[]'::jsonb),
    'hours',   coalesce((select sum(coalesce((data->>'hours')::numeric, 0)) from public.records where kind = 'list:support'), 0)
  ) else null end;
$$;
grant execute on function public.impact_stats() to authenticated;


-- What a KOL friend needs to see on their own page: their invitation and the campaign message, nothing else from the fellow.
create or replace function public.friend_context() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; r public.records; fid text; c text; pl jsonb; su jsonb;
begin
  select * into p from public.profiles where id = auth.uid() and active and role = 'friend';
  if p.id is null or p.friend_id is null then return null; end if;
  select * into r from public.records where kind = 'fd:friends' and key like '%/' || p.friend_id limit 1;
  if r.key is null then return null; end if;
  fid := split_part(r.key, '/', 1); c := r.data->>'camp';
  select data into pl from public.records where kind = 'fd:plan' and key = fid || '/' || c;
  select data into su from public.records where kind = 'fd:setup' and key = fid || '/' || c;
  return jsonb_build_object('fellow', fid, 'fellowName', (select name from public.fellows where id = fid),
    'friend', (r.data - 'posts' - 'token'), 'message', coalesce(pl->>'message', ''), 'action', coalesce(pl->'action', '{}'::jsonb),
    'campaign', coalesce(su->>'name', ''), 'type', coalesce(su->>'type', ''));
end $$;
grant execute on function public.friend_context() to authenticated;



-- =====================================================================
-- Everyone can change their own name and profile photo
-- =====================================================================
alter table public.profiles add column if not exists photo text;

create or replace function public.update_my_profile(new_name text, new_photo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare p public.profiles; nm text := btrim(coalesce(new_name, '')); ph text := nullif(btrim(coalesce(new_photo, '')), '');
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null then raise exception 'not signed in'; end if;
  if nm = '' or length(nm) > 80 then raise exception 'Add a name of up to 80 characters'; end if;
  if ph is not null and ph not like 'me/' || auth.uid()::text || '/%' then raise exception 'photo path not allowed'; end if;
  update public.profiles set label = nm, photo = coalesce(ph, photo) where id = p.id;
  if p.role = 'fellow' and p.fellow_id is not null then
    update public.fellows set name = nm, photo = coalesce(ph, photo) where id = p.fellow_id;
  elsif p.role = 'cso' and p.cso_id is not null then
    update public.records set data = data || jsonb_build_object('name', nm) || case when ph is null then '{}'::jsonb else jsonb_build_object('photo', ph) end
      where kind = 'list:csos' and key = p.cso_id;
  elsif p.role = 'friend' and p.friend_id is not null then
    update public.records set data = data || jsonb_build_object('name', nm) || case when ph is null then '{}'::jsonb else jsonb_build_object('photo', ph) end
      where kind = 'fd:friends' and key like '%/' || p.friend_id;
  end if;
end $$;
revoke all on function public.update_my_profile(text, text) from public;
grant execute on function public.update_my_profile(text, text) to authenticated;


-- =====================================================================
-- Communications expert (same access as the social listening expert) and content features
-- =====================================================================
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('program','country','fellow','friend','cso','listener','comms','partner'));

-- Features: a piece of content that features fellows, KOL friends or CSOs, with requests to them
insert into public.kind_access (kind, role, read_scope, write_scope) values
  ('list:features','program','all','all'),('list:features','listener','all','all'),('list:features','country','all','none'),
  ('list:features','fellow','all','none'),('list:features','friend','all','none'),('list:features','cso','all','none'),
  ('list:csos','listener','all','none')
on conflict (kind, role) do nothing;

-- The communications expert has the same access as the social listening expert
insert into public.kind_access (kind, role, read_scope, write_scope)
  select kind, 'comms', read_scope, write_scope from public.kind_access where role = 'listener'
on conflict (kind, role) do nothing;

-- A featured person ticks a request done (they cannot edit the feature itself)
create or replace function public.feature_done(feat_id text, req_id text, is_done boolean) returns void
language plpgsql security definer set search_path = public as $$
declare p public.profiles; r public.records; hit boolean := false; arr jsonb;
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null then raise exception 'not signed in'; end if;
  select * into r from public.records where kind = 'list:features' and key = feat_id;
  if r.kind is null then raise exception 'feature not found'; end if;
  select coalesce(jsonb_agg(
      case when e->>'id' = req_id
             and ((p.role = 'fellow' and e->'to'->>'t' = 'fellow' and e->'to'->>'id' = p.fellow_id)
               or (p.role = 'friend' and e->'to'->>'t' = 'friend' and e->'to'->>'id' = p.friend_id)
               or (p.role = 'cso' and e->'to'->>'t' = 'cso' and e->'to'->>'id' = p.cso_id))
           then e || jsonb_build_object('done', is_done, 'doneBy', p.label)
           else e end order by ord), '[]'::jsonb)
    into arr from jsonb_array_elements(coalesce(r.data->'requests','[]'::jsonb)) with ordinality as t(e, ord);
  if arr = coalesce(r.data->'requests','[]'::jsonb) then raise exception 'That request is not yours'; end if;
  update public.records set data = jsonb_set(data, '{requests}', arr) where kind = 'list:features' and key = feat_id;
end $$;
revoke all on function public.feature_done(text, text, boolean) from public;
grant execute on function public.feature_done(text, text, boolean) to authenticated;

-- Names of KOL friends for the "featuring" picker (names only, no contact or payment details)
create or replace function public.feature_people() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null or p.role not in ('program','listener','comms') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', split_part(r.key,'/',2), 'name', r.data->>'name', 'fellow', split_part(r.key,'/',1),
            'fellowName', (select f.name from public.fellows f where f.id = split_part(r.key,'/',1)), 'country', r.country))
          from public.records r where r.kind = 'fd:friends'), '[]'::jsonb);
end $$;
revoke all on function public.feature_people() from public;
grant execute on function public.feature_people() to authenticated;


-- =====================================================================
-- Operations login: paperwork, reminders, events and key dates. Everything else is read-only or hidden.
-- =====================================================================
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('program','country','fellow','friend','cso','listener','comms','ops','partner'));
insert into public.kind_access (kind, role, read_scope, write_scope) values
  ('map:paper','ops','all','all'),('map:notes','ops','all','all'),('map:reminded','ops','all','all'),
  ('map:camps','ops','all','none'),('map:org','ops','all','none'),
  ('list:pevents','ops','all','all'),('list:cevents','ops','all','all'),('list:boosts','ops','all','none'),('list:feed','ops','all','all'),
  ('list:dates','ops','all','all'),('list:classes','ops','all','none'),('list:slides','ops','all','none'),('list:csos','ops','all','none')
on conflict (kind, role) do nothing;


-- Key links (coordination sheet, budget, communication assets ...): the programme team adds them and chooses who sees each one.
-- A link has an "aud" list of roles. Everyone else only reads the links that name their role.
insert into public.kind_access (kind, role, read_scope, write_scope) values
  ('list:keylinks','program','all','all'),('list:keylinks','country','all','none'),('list:keylinks','listener','all','none'),('list:keylinks','comms','all','none'),
  ('list:keylinks','ops','all','none'),('list:keylinks','fellow','all','none'),('list:keylinks','friend','all','none'),('list:keylinks','cso','all','none'),('list:keylinks','partner','all','none')
on conflict (kind, role) do nothing;
create or replace function public.keylink_visible(role_ text, rec jsonb) returns boolean
language sql immutable as $$ select role_ = 'program' or coalesce(rec->'aud', '[]'::jsonb) ? role_ $$;

-- Operations can see every plan, proposal and spending-related record
insert into public.kind_access (kind, role, read_scope, write_scope) values
  ('fd:plan','ops','all','all'),('fd:setup','ops','all','none'),('fd:collabs','ops','all','none'),('fd:events','ops','all','none'),('list:support','ops','all','none')
on conflict (kind, role) do nothing;


-- =====================================================================
-- Fellow contact details and private Drive folder link
-- Visible to: programme team, ops, the country coordinator of that fellow's country, and the fellow.
-- The fellow edits their own contact through update_my_contact(); the folder link is set by the team.
-- =====================================================================
create table if not exists public.fellow_private (
  fellow_id text primary key references public.fellows(id) on delete cascade,
  email text, phone text, line text, whatsapp text, folder_url text,
  updated_at timestamptz not null default now()
);
alter table public.fellow_private enable row level security;

create or replace function public.fp_can(fid text, want_write boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; fc text;
begin
  select * into p from public.profiles where id = auth.uid() and active;
  if p.id is null then return false; end if;
  if p.role in ('program','ops') then return true; end if;
  select country into fc from public.fellows where id = fid;
  if p.role = 'country' then return p.country = fc; end if;
  if p.role = 'fellow' then return not want_write and p.fellow_id = fid; end if;
  return false;
end $$;

drop policy if exists fp_read on public.fellow_private;
create policy fp_read on public.fellow_private for select using (public.fp_can(fellow_id, false));
drop policy if exists fp_ins on public.fellow_private;
create policy fp_ins on public.fellow_private for insert with check (public.fp_can(fellow_id, true));
drop policy if exists fp_upd on public.fellow_private;
create policy fp_upd on public.fellow_private for update using (public.fp_can(fellow_id, true)) with check (public.fp_can(fellow_id, true));
drop policy if exists fp_del on public.fellow_private;
create policy fp_del on public.fellow_private for delete using (public.fp_can(fellow_id, true));

create or replace function public.update_my_contact(em text, ph text, ln text, wa text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid() and active and role = 'fellow';
  if p.id is null or p.fellow_id is null then raise exception 'only fellows can change their own contact'; end if;
  insert into public.fellow_private (fellow_id, email, phone, line, whatsapp)
  values (p.fellow_id, nullif(btrim(em),''), nullif(btrim(ph),''), nullif(btrim(ln),''), nullif(btrim(wa),''))
  on conflict (fellow_id) do update set email = excluded.email, phone = excluded.phone, line = excluded.line, whatsapp = excluded.whatsapp, updated_at = now();
end $$;
revoke all on function public.update_my_contact(text, text, text, text) from public;
grant execute on function public.update_my_contact(text, text, text, text) to authenticated;


-- =====================================================================
-- Communications expert can invite KOL friends (with country coordinators and the programme coordinator)
-- Needs: see the KOL friends fellows have added, and see the friend login accounts.
-- =====================================================================
insert into public.kind_access (kind, role, read_scope, write_scope) values ('fd:friends','comms','all','none') on conflict do nothing;
drop policy if exists profiles_read_comms on public.profiles;
create policy profiles_read_comms on public.profiles for select using (
  (select role from public.my_profile()) = 'comms' and role = 'friend');
