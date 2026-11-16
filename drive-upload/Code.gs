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
    if (b.action === 'kolmap') return kolmap_(b.sheetId);
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


/**
 * KOL mapping reader. Returns one row per KOL from the Thailand and Indonesia tabs of the KOL mapping Google Sheet.
 * Read only. Emails, WhatsApp numbers and manager contacts are NOT returned; they stay in the sheet.
 * The sheet must be a native Google Sheet (not an uploaded Excel file) and this script's account needs access to it.
 * See drive-upload/KOLMAP.md
 */
function kolmap_(sheetId) {
  if (!sheetId) return out_({ ok: false, error: 'The KOL mapping sheet is not set up yet.' });
  var ss;
  try { ss = SpreadsheetApp.openById(sheetId); }
  catch (err) { return out_({ ok: false, error: 'Could not open the KOL mapping sheet. It must be a Google Sheet (File > Save as Google Sheets), shared with the account that runs this script.' }); }
  var WANT = {
    'name': 'name', 'primary platform': 'platform', "handle / channel's name #1": 'handle', 'status': 'stage', 'known for': 'known',
    'secondary platform': 'platform2', "handle / channel's name #2": 'handle2', 'notes': 'notes', 'first contact': 'first', 'referred by': 'referred',
    'country of audience': 'audience', 'total score': 'score', 'notes on attendance': 'attend',
    'has management or representation?': 'mgmt', 'type of management': 'mtype', 'manager or agency name': 'mname', 'what the manager handles': 'mdoes',
    'manager approval needed?': 'mok', 'applied to the programme?': 'applied', 'date applied': 'adate', 'interest as a fellow': 'fellow',
    'why, or concerns': 'fwhy', 'ready to collaborate?': 'ready', 'conditions or timing': 'rnotes'
  };
  var rows = [], tabs = ['Thailand', 'Indonesia'], tz = Session.getScriptTimeZone();
  tabs.forEach(function (tab) {
    var sh = ss.getSheetByName(tab); if (!sh) return;
    var last = sh.getLastRow(), cols = sh.getLastColumn(); if (last < 3) return;
    var head = sh.getRange(1, 1, 2, cols).getValues(), vals = sh.getRange(3, 1, last - 2, cols).getValues();
    var idx = {}, followersSeen = 0, fcols = [];
    head[0].forEach(function (h, i) {
      var k = String(h || '').toLowerCase().replace(/\s+/g, ' ').trim();
      if (k === 'followers') { fcols.push(i); return; }
      if (WANT[k] && idx[WANT[k]] === undefined) idx[WANT[k]] = i;
    });
    if (fcols.length) idx.followers = fcols[0];
    if (fcols.length > 1) idx.followers2 = fcols[1];
    // Thailand keeps the awareness-event answer in column C (dropdown); Indonesia has a tick box in column D.
    var eventCol = tab === 'Thailand' ? 2 : 3;
    vals.forEach(function (r, n) {
      var name = String(r[idx.name] === undefined ? '' : r[idx.name]).trim(), handle = String(r[idx.handle] === undefined ? '' : r[idx.handle]).trim();
      if (!name && !handle) return;
      var o = { country: tab === 'Thailand' ? 'TH' : 'ID', ref: tab + '!' + (n + 3), tick: r[0] === true };
      Object.keys(idx).forEach(function (k) {
        var v = r[idx[k]];
        if (v instanceof Date) v = Utilities.formatDate(v, tz, 'yyyy-MM-dd');
        o[k] = v === null || v === undefined ? '' : (typeof v === 'number' ? v : String(v).trim());
      });
      var ev = r[eventCol];
      o.event = tab === 'Thailand' ? String(ev || '') : (ev === true ? 'Coming' : '');
      rows.push(o);
    });
  });
  return out_({ ok: true, rows: rows, at: new Date().toISOString(), url: ss.getUrl() });
}
