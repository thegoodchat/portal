# The Good Chat portal

Web app for The Good Chat (makesense Asia): paperwork status, campaign plans, social listening, events, community and leaderboards.
Money, ID copies and invoices stay in Google Sheets and a restricted Drive folder. They are never stored here.

- **Site:** static files on GitHub Pages (`index.html`, no build step).
- **Logins and data:** Supabase (email + password per person, role-based access, live updates).
- **Without config** the app runs as a local demo with sample data.

## What works in this first version

Live and shared in real time: program coordinator, country coordinators, social listening expert, programme partners.
They can enter paperwork status and notes, organisation invoice details, benchmarks, listening briefs and analysis, deck status,
programme events (agenda, hotel, check-in), the events board, ways to help, and the community feed.

Not yet live: fellow, KOL friend and CSO pages. Those accounts can be created but show a "still being built" message.
Fellow campaign data (plans, posts, KPIs, KOL friends, suppliers) is the next phase and needs per-fellow storage.

## Set up (about 30 minutes, once)

### 1. Supabase
1. Create a project at supabase.com (free tier is fine). Pick the region closest to your team (Singapore).
2. SQL Editor > New query > paste all of `supabase/schema.sql` > Run.
3. Authentication > Providers > Email: keep enabled. Turn **off** "Allow new users to sign up" (Authentication > Sign In / Providers, or Settings) so only people you add can log in.
4. Authentication > URL Configuration: set Site URL to your published site address (below) and add it to Redirect URLs.
5. Authentication > Users > Add user: create your own account with a strong password.
6. SQL Editor: make it the program coordinator (replace the email):
   ```sql
   insert into public.profiles (id, email, label, role)
   select id, email, 'Program coordinator', 'program' from auth.users where email = 'you@example.org';
   ```
7. Project settings > API: copy the **Project URL** and the **anon public** key.

Never put the `service_role` key in this repo or the site.

### 2. This repo
1. Edit `config.js` and paste the Project URL and anon key.
2. Commit and push to `main`.
3. GitHub: Settings > Pages > Build and deployment > Source: **GitHub Actions**. The workflow in `.github/workflows/pages.yml` publishes the site.
4. Your site is at `https://<owner>.github.io/<repo>/`. Use that as the Site URL in Supabase step 4.

### 3. Adding people (from the portal)
Run the whole of `supabase/schema.sql` again (it is safe to re-run; it adds photos and the People rules), then deploy the invite function once:
1. Supabase > Edge Functions > Deploy a new function > name it `invite-user` > paste `supabase/functions/invite-user/index.ts` > Deploy.
2. Edge Functions > Secrets: add `SITE_URL` = your site address (for example `https://thegoodchat.github.io/portal/`).

After that nobody needs the Supabase dashboard. In the portal, open **People**:
- Program coordinator: edit any fellow or organisation, upload photos, invite or switch off any login (including coordinators, the social listening expert and partners).
- Country coordinator: the same for fellows, organisations and logins in their own country.
- Invited people get an email, click the link and choose their own password.
Fellow, KOL friend and organisation logins can be created now, but their own pages are still being built, so for now they see a short "still being built" message.

### 3b. Adding people by hand (backup)
For each person: Authentication > Users > Add user (email + temporary password, tick "Auto confirm"), then add a profile row.
Roles: `program`, `country` (set country), `listener`, `partner`, `fellow` (set country and fellow_id), `friend`, `cso`.
```sql
insert into public.profiles (id, email, label, role, country)
select id, email, 'Thailand coordinator', 'country', 'TH' from auth.users where email = 'th.coord@example.org';
```
Ask people to use "Forgot password" to set their own password the first time.
To remove someone: `update public.profiles set active = false where email = '...';`

## Demo page
Anyone can open `https://thegoodchat.github.io/portal/demo.html` (or add `?demo` to the address) to click through every view with made-up names and numbers. No login, nothing is saved, and a banner says it is a demo. It never touches the real data. The sign-in page also links to it.

## How access works
Every row of data lives in one table (`records`) with a kind and key. `kind_access` in `schema.sql` says which role can read or write each kind,
and whether that is all rows, only their country, or only their own. Postgres enforces it, so hiding a button in the page is not what protects the data.
Changing who can see what means editing the `kind_access` rows, not the app.

## Known limits (first version)
- Programme partners cannot read events, so their Events tab is empty.
- Fellow, friend and CSO accounts are blocked until their pages are built.
- The feed lets any signed-in team member edit any post (needed for reactions and replies). Moderation is by coordinators.
- Seeing "sample data" in tabs such as Campaign plans, Leaderboard and the Impact numbers is expected: those use built-in samples until fellow data is live.
- Passwords are handled by Supabase. Consider enabling multi-factor sign-in for coordinators.

## Next phases
1. Per-fellow storage and fellow pages (plans, posts, KPIs, KOL friends, suppliers, screenshots in Supabase Storage).
2. KOL friend and CSO pages with row-level limits, including session-level agenda filtering for CSOs.
3. In-app invites (Edge Function), email notifications for event changes, change history.
