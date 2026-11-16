# KOL mapping in the portal (read only)

Coordination gets a **KOL mapping** page in the portal (under People and paperwork). It reads the KOL mapping Google Sheet:
summary tiles, filters (country, management, applied, interest as a fellow, ready to collaborate), search, and a details row for each KOL.
The sheet stays the place where people edit. The portal never writes to it.

Emails, WhatsApp numbers and manager contacts are **not** sent to the portal. They stay in the sheet.

## One-time setup

1. **Make it a native Google Sheet.** If the address has `rtpof=true`, or the file name ends in `.xlsx`, it is still an Excel file.
   Open it in Google Sheets, then File > Save as Google Sheets. Use the new file from now on and update the link on the portal's Links page.
2. **Share it.** The Google account that runs the Apps Script (the one that deployed `Code.gs`) needs at least Viewer access to the sheet.
3. **Update the Apps Script.** Open the script project, paste in the new `Code.gs`, then Deploy > Manage deployments > edit the existing deployment > Version: New version > Deploy. The web app address stays the same.
4. **Find the sheet ID.** It is the long text between `/d/` and `/edit` in the sheet's address.
5. **Add the secret in Supabase.** Edge Functions > Secrets > add `KOL_SHEET_ID` with that ID. (`DRIVE_SCRIPT_URL` and `DRIVE_SCRIPT_SECRET` are already there from the proposal upload.)
6. **Deploy the function.** Edge Functions > Deploy a new function > name `kol-map` > paste `supabase/functions/kol-map/index.ts` > turn **off** Enforce JWT verification (the function checks who is calling) > Deploy.
7. Upload the new `index.html` to GitHub. Sign in as Coordination and open People and paperwork > KOL mapping.

## How it behaves

- Opening the page reads the sheet. **Refresh** reads it again. The function keeps the last read for one minute so many people opening the page do not hit Google each time.
- Only active Coordination accounts can use it. Ops, social listening, partners, fellows, friends and CSOs cannot.
- The Thailand and Indonesia tabs must keep those names, and the header row (row 1) must keep the column names. The portal finds columns by header text, so you can reorder columns. Do not rename the headers.
- New KOLs added below the last row show up on the next Refresh.
