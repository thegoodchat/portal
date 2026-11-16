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
    if (b.action === 'analytics') return analytics_(b.tables || {});
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


/**
 * Analytics export for the social expert. Keeps one Google Sheet up to date (one tab per table) and, on the first
 * run of each month, saves dated CSV backups in a "Monthly backups" subfolder.
 * Needs the Script Property ANALYTICS_FOLDER_ID (the Drive folder for the export). See drive-upload/ANALYTICS.md
 */
function analytics_(tables) {
  var props = PropertiesService.getScriptProperties();
  var folderId = props.getProperty('ANALYTICS_FOLDER_ID');
  if (!folderId) return out_({ ok: false, error: 'ANALYTICS_FOLDER_ID is not set in the script.' });
  var folder = DriveApp.getFolderById(folderId);
  var ss, sid = props.getProperty('ANALYTICS_SHEET_ID');
  try { ss = sid ? SpreadsheetApp.openById(sid) : null; } catch (err) { ss = null; }
  if (!ss) {
    ss = SpreadsheetApp.create('The Good Chat analytics');
    var f = DriveApp.getFileById(ss.getId()); folder.addFile(f); DriveApp.getRootFolder().removeFile(f);
    props.setProperty('ANALYTICS_SHEET_ID', ss.getId());
  }
  var rows = 0, names = Object.keys(tables);
  names.forEach(function (n) {
    var data = tables[n] || [];
    var sh = ss.getSheetByName(n) || ss.insertSheet(n);
    sh.clearContents();
    if (data.length) {
      sh.getRange(1, 1, data.length, data[0].length).setValues(data);
      sh.getRange(1, 1, 1, data[0].length).setFontWeight('bold');
      sh.setFrozenRows(1);
      rows += data.length - 1;
    }
  });
  var info = ss.getSheetByName('About') || ss.insertSheet('About', 0);
  info.clearContents();
  info.getRange(1, 1, 3, 2).setValues([
    ['The Good Chat analytics', ''],
    ['Last updated', Utilities.formatDate(new Date(), 'Asia/Bangkok', 'yyyy-MM-dd HH:mm') + ' (Bangkok time)'],
    ['About', 'Refreshed every night from the portal. Do not type here: changes are overwritten. Copy a tab to a new sheet to work on it.']
  ]);
  var blank = ss.getSheetByName('Sheet1'); if (blank && ss.getSheets().length > 1) ss.deleteSheet(blank);
  var backup = monthlyBackup_(folder, tables);
  return out_({ ok: true, rows: rows, url: ss.getUrl(), backup: backup });
}
function monthlyBackup_(folder, tables) {
  var now = new Date();
  var stamp = Utilities.formatDate(now, 'Asia/Bangkok', 'yyyy_MM_MMM_dd');
  var month = stamp.slice(0, 11);
  var subs = folder.getFoldersByName('Monthly backups');
  var dir = subs.hasNext() ? subs.next() : folder.createFolder('Monthly backups');
  var files = dir.getFiles();
  while (files.hasNext()) { if (files.next().getName().indexOf(month) === 0) return ''; }
  Object.keys(tables).forEach(function (n) {
    var csv = (tables[n] || []).map(function (r) {
      return r.map(function (v) { var s = (v === null || v === undefined) ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }).join(',');
    }).join('\r\n');
    dir.createFile(stamp + '_TGC_' + n.replace(/ /g, '_') + '.csv', csv, MimeType.CSV);
  });
  return stamp;
}
