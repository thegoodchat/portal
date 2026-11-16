# Analytics export for the social expert

Every night the portal sends the programme's data to Google Drive. One Google Sheet ("The Good Chat analytics") is refreshed in place, so the expert can connect Looker Studio or pivot tables to it. On the first night of each month, dated CSV backups are also saved. About 15 minutes, on top of the Drive upload setup you already did (SETUP.md).

What is exported (tabs and files): Posts (fellows and KOL friends, with all numbers), Events, Civic actions, KPIs, Campaigns. Not exported: contact details, paperwork, money, screenshots.

## 1. Make the Drive folder
1. In Drive, create a folder called "The Good Chat analytics" and share it with the social expert (Viewer, or Editor if they should add their own tabs in a copy).
2. Open the folder. The address ends in `/folders/XXXXXXXX`. Copy that last part (the folder ID).

## 2. Update the Google script
1. Open your Apps Script project (the one from SETUP.md) and replace its code with the latest `drive-upload/Code.gs`.
2. Project Settings > Script Properties > add `ANALYTICS_FOLDER_ID` with the folder ID.
3. Deploy > Manage deployments > edit the existing web app > Version: New version > Deploy. The web app URL stays the same.
4. The Google account running the script must be able to edit the analytics folder (it is its own if it made it).

## 3. Deploy the function
1. Supabase dashboard > Edge Functions > Deploy a new function > name it `export-analytics` > paste `supabase/functions/export-analytics/index.ts`.
2. Turn OFF "Enforce JWT verification" for this function. The function checks the caller itself: the cron secret, or a signed-in programme or operations account.
3. Edge Functions > Secrets: add `EXPORT_CRON_SECRET` (any long random text). `DRIVE_SCRIPT_URL` and `DRIVE_SCRIPT_SECRET` are already there.

## 4. Try it
Sign in as the programme coordinator or operations > Impact tab > **Export to Drive now**. The sheet appears in the folder and a link opens it. **Download CSV files** gives you the same data without Drive.

## 5. Schedule it every night
Supabase dashboard > Database > Extensions > turn on `pg_cron` and `pg_net`. Then SQL Editor > run this (replace the two placeholders). It runs at 01:00 Bangkok time.

```sql
select cron.schedule(
  'tgc-analytics-nightly',
  '0 18 * * *',
  $$ select net.http_post(
       url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/export-analytics',
       headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', 'YOUR-EXPORT_CRON_SECRET'),
       body := '{}'::jsonb
     ) $$
);
```
To stop it: `select cron.unschedule('tgc-analytics-nightly');`

## Notes
- The sheet is overwritten every night. The expert should copy a tab into their own sheet to work on it.
- The monthly CSVs are saved in "Monthly backups" inside the same folder, named like `2027_03_Mar_01_TGC_Posts.csv`. They capture the data as it stands on the first night of the month.
- If the Drive export fails, the portal shows the error and nothing in the portal is affected.
