# The Good Chat portal

Web app for The Good Chat (makesense Asia): paperwork status, campaign plans, social listening, events, The Good Chat Club and leaderboards.
Money, ID copies and invoices stay in Google Sheets and a restricted Drive folder. They are never stored here.

- **Site:** static files on GitHub Pages (`index.html`, no build step).
- **Logins and data:** Supabase (email + password per person, role-based access, live updates).
- **Without config** the app runs as a local demo with sample data.

## What works in this first version

Live and shared in real time: programme coordinator, country coordinators, social listening expert, programme partners.
They can enter paperwork status and notes, organisation invoice details, benchmarks, listening briefs and analysis, deck status,
programme events (agenda, hotel, check-in), the events board, ways to help, and the Good Chat Club.

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
Fellow logins now open a first page with Slides, Events, People and The Good Chat Club. Their own campaign pages are still being built. KOL friend and organisation logins can be created, but see a short "still being built" message.

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

## KOL friends
A fellow adds a KOL friend on their KOL friends tab (name, how to reach them, what they will do). The country coordinator or programme coordinator then opens
**People**, picks that friend under KOL friends, and enters their email to send the login. The friend sees their invitation and the campaign message, logs posts with
numbers and insight screenshots, and sees masterclasses, events, the Good Chat Club and Impact. Friend posts are saved under the friend's fellow
(`fp:posts`), so the fellow, the country coordinator, the programme coordinator and the social listening expert can read them. The fellow cannot edit them.
Country coordinators (their own country), the programme coordinator and the social listening expert can edit a friend's post. The database records who edited last
and the post shows "Last edited by ...", unless the friend made the last edit themselves. Re-deploy the `invite-user` function after updating, because friend logins now link to a specific friend.

## View as (preview)
The programme coordinator can preview any fellow's or KOL friend's pages, a country coordinator can preview those in their own country, and the social listening expert can preview fellows.
On the **People** tab, use **View as** on a fellow's card, or on a KOL friend under KOL friends. A yellow banner shows who you are viewing and has an **Exit preview** button.
It is read only: forms are blocked, nothing is saved, and local changes are discarded when you exit. It uses your own access, so a draft the fellow cannot see yet may show.

## Known limits (first version)
- Programme partners cannot read events, so their Events tab is empty.
- Fellows and KOL friends can log in and use their pages. CSO pages are not live yet (CSO accounts are still blocked).
- Everyone signed in has an Impact tab with programme totals (posts, reach, engagement, events, civic actions). Totals come from a database function, so fellows and partners see numbers only, never other fellows' posts, reflections, screenshots, spending lines or KOL friend contacts.
- The feed lets any signed-in team member edit any post (needed for reactions and replies). Moderation is by coordinators.
- The Leaderboard and some benchmark charts still use built-in sample scores until real posts exist.
- Passwords are handled by Supabase. Consider enabling multi-factor sign-in for coordinators.

## Next phases
1. KOL friend logging pages (a friend's own posts), CSO pages.
2. KOL friend and CSO pages with row-level limits, including session-level agenda filtering for CSOs.
3. In-app invites (Edge Function), email notifications for event changes, change history.

## My profile
Everyone signed in sees a **My profile** button in the top bar. They can change their own name and photo. It runs through the `update_my_profile` function (schema.sql), so people can only change themselves. Photos go to the private `people` bucket under `me/<user id>/`. Re-run schema.sql once to switch it on.

## Communications expert, features, masterclass leads
- **Communications expert** is a login type with the same access as the social listening expert. Invite it from People, Team logins. Redeploy the `invite-user` function once so it accepts the new role.
- **Features** tab: the programme coordinator, social listening expert and communications expert log content that features fellows, KOL friends and CSOs, and ask them for an interview, photo, quote or clip. Featured people see only their own features and mark requests done.
- **Masterclasses** have "Led by" and an expertise tag (social media, energy, community building, advocacy, communications, other). The leader does not need a login.
- **Impact** now starts with "Who is involved": fellows, KOL friends and CSOs in total and per campaign, with each fellow's own campaign listed inside Campaign 1 and Campaign 2.

## Country check on dates
Under every coming date on **Key dates**, a country coordinator can **Confirm** that it does not clash with a public holiday or anything else that affects the programme in their country, or **Flag a conflict** with a short note. Everyone can see the status. A date for one country only needs that country's confirmation. Changing a date clears its confirmations so it is checked again. Masterclass dates work the same way.

## Operations login and tab order
- **Operations** is a login type for paperwork and logistics: it edits Paperwork, Reminders, Events and Key dates, and can read People, Impact and Community. Features, posts, listening data and logins are hidden or read-only. Invite it from People, Team logins. Re-run schema.sql and redeploy `invite-user` once.
- Tab order: team logins start with People, then Paperwork. Impact and Leaderboard sit together. Masterclasses, Events and The Good Chat Club sit together.

## Money: USD is the main currency
Spending proposals are reviewed in **USD**. A fellow can price lines in THB or IDR as an estimate, and gives an exchange rate ("1 USD equals ..."). Every line and total then shows the USD figure, and the team's Campaign plans table totals the plans in USD with the local amount beside it. New plans start in USD. If no rate is entered, the USD figure shows a dash until one is added. No bank details or invoices are stored in the portal.

## Budget pages, exchange rates, operations and spending
- **Exchange rates:** paperwork pages and the spending proposal link to exchangerates.org.uk.
- **Links tab:** the programme coordinator or director adds named links (budget page, coordination sheet, communication assets with photos, videos and social media assets, or anything else) and ticks which roles can see each one: country coordinators, communications expert, social listening expert, operations, fellows, KOL friends, CSOs, partners. Everyone else never sees it, and the database enforces that. Country coordinators also see their links as buttons at the top of Paperwork and Campaign plans.
- **Operations** also gets the Campaign plans tab and read access to every plan, proposal, setup, supplier, event and support record, so it can see all spending. Re-run schema.sql once.

## Fellow contact details and private Drive folders

Each fellow has a contact card (email, phone, LINE, WhatsApp) and a link to their private Drive folder. The portal stores only the link, never the documents.

- Who sees it: programme team, ops, the country coordinator for that fellow's country, and the fellow. Nobody else (not other fellows, KOL friends, CSOs, partners or experts).
- Team edit it on the People tab (Edit contact). Fellows edit their own contact under My profile.
- The folder opens only for people signed in to a Google account you shared it with. In Drive, set the folder's General access to Restricted and add the fellow's email.
- Fellows see "Open my private folder" on their Paperwork tab when a document is still needed.
- Setup: re-run `supabase/schema.sql` (adds the `fellow_private` table and `update_my_contact`), then upload `index.html`.

## Points (no cap)

Points are open-ended. Nothing is capped at 20, 25 or 100.

- **Reach**: people reached by posts (own and KOL friends'). With a confirmed benchmark: 5 points for every "usual post's worth" of reach. Without one: 1 point per 1,000 people.
- **Engagement**: reactions, comments, saves, shares and reposts, the same way (5 points per usual post's worth, or 1 per 50).
- **Civic action**: 1 point per 5 people who took the action the fellow asked for. Fellows count these on the Log tab, Civic action. The numbers are stored with the campaign plan, so no database change is needed.
- **Self-designed KPIs**: 20 points when all of a fellow's KPIs are met, more when they go beyond them.
- **Mainstream integration**: 2 points for each collaborator, KOL friend, CSO partner and community event.

The Impact page's Mainstream integration card also shows civic actions, per campaign and per fellow.

## Coordinators and benchmarks

- The programme coordinator is also the Thailand country coordinator. You do not need a separate Thailand country login. In Key dates, the programme coordinator confirms dates for Thailand. Only create a country coordinator login for Indonesia.
- Starting benchmarks start empty. The social listening expert does the analysis outside the portal and enters the averages on the Benchmarks tab, then presses Confirm. Fellows then see their starting point on Listening insights, with every post compared against it (for example "1.4x your usual reach").
- The regional kickoff (12 to 14 Jan 2027, Bangkok, fellows from both countries) is in Key dates. Use "Add the programme dates" on a fresh portal, or add it by hand.

## Who can invite KOL friends

Programme coordinator (any country), country coordinators (friends of fellows in their own country) and the communications expert (any country). Fellows add the friend first on their KOL friends tab; then one of these people picks the friend on the People tab and sends the invite. Re-run `schema.sql` and redeploy the `invite-user` function after updating.

## Invoice details

One organisation for fellows in both countries: Sensecube LTD (for The Good Chat project), UEN 202324473C, 60 Paya Lebar Road #06-28 Paya Lebar Square, Singapore 409051. These are built in as the defaults, so fellows see them from day one. The programme coordinator can edit them on the Paperwork tab (changes apply to both countries). Add the "Send invoices to" email there when you have it.

## Masterclasses are open-ended

Team members (programme and country coordinators, social listening and communications experts) add and edit masterclasses themselves. Month and date are optional, and a free-text "Time or other details" line covers things like "mid-March, date to be confirmed". Any number per month is fine. Each masterclass can also carry a main slides link and, optionally, relevant links the expert mentions in class (title, link, one-line note), shown to fellows and KOL friends. No database change is needed.

## When campaigns are designed

Campaign 1 is designed at the regional kickoff (12 to 14 Jan 2027, Bangkok) and Campaign 2 at the co-creation event (Bangkok 21 to 23 Apr or Jakarta 28 to 30 Apr 2027, by country). Fellows see this on their campaign card and plan, with the dates taken from the Events tab. The team's "needs a nudge" list does not chase unfinished Campaign 1 proposals until the kickoff has ended.

The regional kickoff (12 to 14 Jan 2027, Bangkok) is always on the Key dates list, even on an empty portal. Events added on the Events tab also appear in Key dates automatically, so nothing is typed twice.

Key dates shows the full programme list (application deadline, fellow announcement, kickoff, both campaigns, both co-creation events, closing events, masterclasses) even before anyone types a date. Events that fellows lead in their own communities (from the Good Chat Club and the events fellows plan) are marked "Fellow-led", and the page can filter All, Programme or Fellow-led.

## Tab groups, reminders and content (restructure)
- One tab bar with small group labels: People and paperwork, Programme, Campaigns, Results, Together.
- Campaign plans are now Campaign proposals and come before Campaigns, Posts and Fellow-led events.
- Programme events and Links sit in the Programme group; the Events tab for the team is now Fellow-led events.
- The Reminders tab is gone. Remind buttons live on People, Paperwork and Campaign proposals (Remind all is on People).
- The Features tab is gone. Communications posts content on the Posts list, and fellows, KOL friends and CSOs see content featuring them on their home page. "Ask for an interview or photo" is on each People card.
- No Supabase change needed.

## Proposal screenshots
Fellows add screenshots (rental rates, prices, quotations) with a short note on their Campaign proposal while it is a draft. Files go to the existing private insights bucket under fellowId/timestamp/. The team sees them on Campaign proposals. No Supabase change.

## Good Chat Club (was The Social Club)
Three sub-tabs: Conversations, Inspiration (past events) and Ready to collaborate (KOLs). Programme team and country coordinators add and edit them (coordinators for their own country); everyone else reads. New record kinds list:inspo and list:ready: re-run supabase/schema.sql.

## One Campaign tab for fellows
Campaign now holds the whole cycle: listening insights, proposal and spending, campaign setup, KPIs, logging posts, events and civic actions, and your posts. Home keeps to-dos, alerts and points.
