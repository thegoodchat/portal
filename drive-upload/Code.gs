/**
 * The Good Chat: saves a fellow's proposal as a PDF in a Google Drive folder.
 * Runs as the Google account that deploys it, so that account needs Editor access to every fellow's folder.
 * Setup: see drive-upload/SETUP.md
 */
function doPost(e) {
  try {
    var secret = PropertiesService.getScriptProperties().getProperty('SECRET');
    if (!secret) return out_({ ok: false, error: 'The script secret is not set.' });
    var b = JSON.parse(e.postData.contents);
    if (b.secret !== secret) return out_({ ok: false, error: 'Not allowed.' });
    if (!b.folderId || !b.html) return out_({ ok: false, error: 'Missing folder or proposal.' });
    var folder = DriveApp.getFolderById(b.folderId);
    var name = String(b.fileName || 'Proposal').replace(/[^A-Za-z0-9_.-]/g, '_').slice(0, 120);
    var pdf = Utilities.newBlob(b.html, 'text/html', name + '.html').getAs('application/pdf').setName(name + '.pdf');
    var file = folder.createFile(pdf);
    return out_({ ok: true, name: file.getName(), url: file.getUrl() });
  } catch (err) {
    return out_({ ok: false, error: String(err && err.message || err) });
  }
}
function out_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}
