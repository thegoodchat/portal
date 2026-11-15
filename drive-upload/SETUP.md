# Automatic proposal upload to Google Drive: setup (about 15 minutes)

When a fellow presses **Share with the team**, the portal saves their proposal as a PDF in their own Drive folder.
It needs three things: a small Google script, two Supabase secrets, and one Supabase function.

## 1. Make the Google script

1. Sign in to the Google account that owns (or can edit) all the fellows' Drive folders.
2. Go to script.google.com and press **New project**. Name it "Good Chat proposal upload".
3. Delete the example code and paste in everything from `drive-upload/Code.gs`. Press **Save**.
4. Press the **gear icon (Project settings)**. Under **Script properties**, press **Add script property**.
   - Property: `SECRET`
   - Value: a long random phrase, for example 30 letters and numbers. Keep a copy of it.
5. Press **Deploy**, then **New deployment**, then the gear next to "Select type" and choose **Web app**.
   - Execute as: **Me**
   - Who has access: **Anyone**
   Press **Deploy** and allow the permissions when Google asks (it needs access to Drive).
6. Copy the **Web app URL**. It ends in `/exec`.

The script only saves files when the correct secret is sent, so the open link is safe to use.

## 2. Add the secrets in Supabase

Supabase dashboard > Edge Functions > Secrets. Add two:

- `DRIVE_SCRIPT_URL` = the Web app URL from step 1
- `DRIVE_SCRIPT_SECRET` = the same phrase you used as `SECRET`

## 3. Deploy the function

Supabase dashboard > Edge Functions > Deploy a new function. Name it `upload-proposal` and paste in
`supabase/functions/upload-proposal/index.ts`.

## 4. Make sure folders are ready

- Each fellow's **Drive folder link** must be added on the People tab.
- The Google account from step 1 must be able to **edit** each of those folders.

## 5. Test it

1. Sign in as a fellow who has a folder link.
2. Fill in a proposal and press **Share with the team**.
3. Within a few seconds a file like `2027_03_Mar_14_Nok_Campaign1_Proposal_v1.pdf` appears in their folder.

If it does not: the portal still shares the proposal, and tells the fellow to use Download and upload it by hand.
The most common causes are a missing folder link, the Google account not having edit access to the folder,
or a wrong secret.

## Changing the script later

After editing the script, press **Deploy**, then **Manage deployments**, then the pencil, choose **New version**, and **Deploy**.
The Web app URL stays the same.
