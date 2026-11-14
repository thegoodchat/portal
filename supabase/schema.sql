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
  -- monthly masterclasses (Jan to July) and who may arrange their slides
  ('list:classes','program','all','all'),('list:classes','country','all','all'),('list:classes','listener','all','all'),
  ('list:classes','fellow','all','none'),('list:classes','friend','all','none'),('list:classes','partner','all','none'),
  -- country coordinators can add and rearrange slides; KOL friends see slides marked for them
  ('list:slides','friend','all','none'),
  ('list:pevents','friend','all','none'),('list:cevents','friend','all','none'),('list:boosts','friend','all','none'),('list:feed','friend','all','all');

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
  if k = 'list:pevents' and p.role = 'friend' and coalesce(rec->>'friends','false') not in ('true') then return false; end if;
  if k = 'list:slides' and p.role = 'partner' and coalesce(rec->>'to','') not in ('all','TH','ID') then return false; end if;
  return case sc
    when 'all' then true
    when 'country' then rc is not null and rc = p.country
    when 'own' then ro is not null and (ro = 'f:' || p.fellow_id or ro = 'c:' || p.cso_id or ro = 'k:' || p.friend_id)
    else false end;
end $$;

create or replace function public.records_set_meta() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text;
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
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
-- Make it the program coordinator (replace the email):
--   insert into public.profiles (id, email, label, role)
--   select id, email, 'Program coordinator', 'program' from auth.users where email = 'you@example.org';


-- =====================================================================
-- People: fellow and CSO profiles, photos, and who can create logins
-- (added after the first version; safe to run on top of it)
-- =====================================================================
alter table public.fellows add column if not exists photo text;      -- storage path
alter table public.fellows add column if not exists bio text;
alter table public.fellows add column if not exists handles jsonb not null default '{}';

-- Program coordinator manages every fellow; a country coordinator edits fellows in their own country.
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
  select exists (select 1 from public.profiles where id = auth.uid() and active and role in ('program','country','listener'));
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
