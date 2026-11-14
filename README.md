# The Good Chat portal

Web app for The Good Chat (makesense Asia): paperwork status, campaign plans, social listening, events, community and leaderboards.
Money, ID copies and invoices stay in Google Sheets and a restricted Drive folder. They are never stored here.

- **Site:** static files on GitHub Pages (`index.html`, no build step).
- **Logins and data:** Supabase (email + password per person, role-based access, live updates).
- **Without config** the app runs as a local demo with sample data.

## What works in this first version

Live and shared in real time: programme coordinator, country coordinators, social listening expert, programme partners.
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
6. SQL Editor: make it the programme coordinator (replace the email):
   ```sql
   insert into public.profiles (id, email, label, role)
   select id, email, 'Programme coordinator', 'program' from auth.users where email = 'you@example.org';
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
- Programme coordinator: edit any fellow or organisation, upload photos, invite or switch off any login (including coordinators, the social listening expert and partners).
- Country coordinator: the same for fellows, organisations and logins in their own country.
- Invited people get an email, click the link and choose their own password.
Fellow logins now open a first page with Slides, Events, People and Community. Their own campaign pages are still being built. KOL friend and organisation logins can be created, but see a short "still being built" message.

**Campaign dates:** the programme coordinator sets them on the Campaigns tab. Until then the portal shows "Dates to be confirmed".

**Masterclasses and slides:** there is one masterclass a month, January to July. Programme and country coordinators set them up on the **Masterclasses** tab (one click creates the seven slots; add a date, topic and join link to each). The social listening expert, country coordinators and the programme coordinator can add slides, as a link or an uploaded PDF or PowerPoint (up to 45 MB). Coordinators can reorder the slides in each masterclass and tick whether fellows and/or KOL friends see each one. Fellows and KOL friends open the tab and see only what is meant for them, in that order. KOL friends get a login from **People > KOL friends**. Run `schema.sql` again after updating, and redeploy the `invite-user` function.

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

## Fellow pages and insight screenshots
Each fellow's campaign setup, KPIs, plan, posts with reflections, events, collaborators and KOL friends are saved in Supabase under that fellow
(kinds `fd:*`). Fellows see only their own. Their country coordinator and the programme coordinator can read them, the social listening expert can
read posts, plans, setup and KPIs, and partners see only totals. A **Posts** tab shows coordinators and the expert every post with its numbers, reflection and screenshots.

Insight screenshots go to a private storage bucket called `insights`, resized to about 1600 px, at `<fellow id>/<post id>/`. The post record keeps only the file name.
Who can open them: the fellow, the coordinator of that fellow's country, the programme coordinator and the social listening expert. Not partners or other fellows.
Run the latest `supabase/schema.sql` once to create the bucket and its rules (safe to run again).

## Known limits (first version)
- Programme partners cannot read events, so their Events tab is empty.
- Fellows can log in and use their pages. KOL friend pages and CSO pages are not live yet (CSO accounts are still blocked; friends see masterclasses, events and the community).
- Everyone signed in has an Impact tab with programme totals (posts, reach, engagement, events, civic actions). Totals come from a database function, so fellows and partners see numbers only, never other fellows' posts, reflections, screenshots, spending lines or KOL friend contacts.
- The feed lets any signed-in team member edit any post (needed for reactions and replies). Moderation is by coordinators.
- The Leaderboard and some benchmark charts still use built-in sample scores until real posts exist.
- Passwords are handled by Supabase. Consider enabling multi-factor sign-in for coordinators.

## Next phases
1. KOL friend logging pages (a friend's own posts), CSO pages.
2. KOL friend and CSO pages with row-level limits, including session-level agenda filtering for CSOs.
3. In-app invites (Edge Function), email notifications for event changes, change history.
