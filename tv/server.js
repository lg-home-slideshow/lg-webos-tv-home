// server.js - the TV side of TV Home: serves the Home page and answers it.
//
// The page (ui/index.html) cannot talk to the TV's services itself, so this
// small Node service does: it lists the apps and inputs from the app manager,
// serves their icons, launches them and keeps the dock order. It runs with
// the TV's own Node (v16) as root and calls /usr/bin/luna-send.
//
//   node server.js              on the TV, http://127.0.0.1:8650/
//   node server.js --demo       on a PC: no TV, the page shows the demo apps from ui/demo.js
//   options: --port N  --host H (default 127.0.0.1; 0.0.0.0 to reach it from
//            another device - there is no login, so only on a trusted network)
'use strict';

var http = require('http');
var fs = require('fs');
var path = require('path');
var execFile = require('child_process').execFile;
var iconFill = require('./iconfill');

var ROOT = __dirname;
var args = process.argv.slice(2);
function arg(name, def) { var i = args.indexOf(name); return i !== -1 && args[i + 1] ? args[i + 1] : def; }
var DEMO = args.indexOf('--demo') !== -1 || !fs.existsSync('/usr/bin/luna-send');
var PORT = Number(arg('--port', 8650));
var HOST = arg('--host', '127.0.0.1');
var CONFIG_FILE = path.join(ROOT, 'config.json');
var STATE_FILE = path.join(ROOT, 'state.json');   // dock order, written by the page
var PHOTOS = path.join(ROOT, 'photos');

var DEFAULT_CONFIG = {
  name: '',
  locale: 'en-GB',
  hour24: true,
  photoSeconds: 30,
  dockSize: 6,     // apps in the dock until you change it
  dockMax: 12,     // the dock's tiles get narrower up to this many
  // LG's promotions and helpers that are never shown as tiles
  hiddenApps: ['com.webos.app.lgchannels', 'com.webos.app.sportsteamsettings', 'amazon.alexa.view',
    'com.webos.app.camera', 'com.webos.app.lifeonscreen', 'com.webos.app.homeconnect',
    'com.webos.app.discovery.notice', 'com.webos.app.tvuserguide', 'com.webos.app.membership']
};

function log(line) { console.log(new Date().toISOString() + ' ' + line); }
function readJson(file, def) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return def; } }
function config() {
  var c = readJson(CONFIG_FILE, {});
  var out = {};
  Object.keys(DEFAULT_CONFIG).forEach(function (k) { out[k] = k in c ? c[k] : DEFAULT_CONFIG[k]; });
  return out;
}

// ---- luna -------------------------------------------------------------------------
function luna(uri, payload, cb) {
  execFile('/usr/bin/luna-send', ['-n', '1', '-w', '8000', uri, JSON.stringify(payload || {})],
    { timeout: 10000, maxBuffer: 8 * 1024 * 1024 }, function (err, stdout) {
      var r = null;
      try { r = JSON.parse(stdout); } catch (e) {}
      if (!r) r = { returnValue: false, errorText: err ? err.message : 'no answer' };
      cb(r);
    });
}

// ---- apps and inputs ------------------------------------------------------------
var iconPaths = {};   // tile id -> icon file on the TV

function isInput(id) { return /^com\.webos\.app\.(hdmi|externalinput|dp|usbc)/.test(id); }

function listTiles(cb) {
  if (DEMO) return cb(null, []);   // the page uses its demo list
  luna('luna://com.webos.applicationManager/listLaunchPoints', {}, function (r) {
    if (!r.returnValue || !Array.isArray(r.launchPoints)) return cb(r.errorText || 'listLaunchPoints failed');
    var hidden = config().hiddenApps;
    var tiles = [];
    r.launchPoints.forEach(function (lp) {
      if (hidden.indexOf(lp.id) !== -1) return;
      // our own Home must not list itself
      if (lp.id === 'com.webos.app.home') return;
      var key = lp.launchPointId || lp.id;
      var icon = lp.largeIcon || lp.icon || '';
      if (icon) iconPaths[key] = icon;
      tiles.push({
        key: key,
        id: lp.id,
        name: lp.title || lp.id,
        kind: isInput(lp.id) ? 'input' : 'app',
        color: lp.bgColor || lp.iconColor || '#2a2a30',
        icon: icon ? '/icon/' + encodeURIComponent(key) : '',
        fill: icon ? iconFill(icon) : null,   // the icon's own background colour, if it has one
        params: lp.params || null,
        removable: lp.removable === true && !isInput(lp.id)
      });
    });
    cb(null, tiles);
  });
}

function photos() {
  try {
    return fs.readdirSync(PHOTOS).filter(function (n) { return /\.(jpe?g|png|webp)$/i.test(n); }).sort()
      .map(function (n) { return '/photos/' + encodeURIComponent(n); });
  } catch (e) { return []; }
}

// ---- http -------------------------------------------------------------------------
var TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml',
  '.json': 'application/json' };

function send(res, code, body, type) {
  res.writeHead(code, { 'Content-Type': type || 'application/json', 'Cache-Control': 'no-store' });
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

// A file from inside one folder only, never outside it.
function sendFile(res, dir, rel) {
  var file = path.join(dir, path.normalize('/' + rel).replace(/^[\\/]+/, ''));
  if (file.indexOf(path.resolve(dir)) !== 0) return send(res, 403, { error: 'forbidden' });
  fs.readFile(file, function (err, data) {
    if (err) return send(res, 404, { error: 'not found' });
    send(res, 200, data, TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream');
  });
}

function body(req, cb) {
  var chunks = [];
  req.on('data', function (c) { chunks.push(c); if (chunks.length > 64) req.destroy(); });
  req.on('end', function () { var b = {}; try { b = JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch (e) {} cb(b); });
}

var lastHeartbeat = 0;
var benchWanted = false, benchResult = null;
var remoteCmd = null;

http.createServer(function (req, res) {
  var url = decodeURIComponent((req.url || '/').split('?')[0]);

  if (req.method === 'GET' && (url === '/' || url === '/index.html')) {
    res.writeHead(302, { Location: '/ui/index.html' });
    return res.end();
  }
  if (req.method === 'GET' && url.indexOf('/ui/') === 0) return sendFile(res, path.join(ROOT, 'ui'), url.slice(4));
  if (req.method === 'GET' && url.indexOf('/photos/') === 0) return sendFile(res, PHOTOS, url.slice(8));

  if (req.method === 'GET' && url.indexOf('/icon/') === 0) {
    var p = iconPaths[url.slice(6)];
    if (!p) return send(res, 404, { error: 'no icon' });
    return fs.readFile(p, function (err, data) {
      if (err) return send(res, 404, { error: 'no icon' });
      send(res, 200, data, TYPES[path.extname(p).toLowerCase()] || 'image/png');
    });
  }

  if (req.method === 'GET' && url === '/api/state') {
    return listTiles(function (err, tiles) {
      send(res, err ? 500 : 200, {
        demo: DEMO, error: err || null, config: config(), tiles: tiles || [],
        order: readJson(STATE_FILE, {}).order || [], dock: readJson(STATE_FILE, {}).dock || null,
        hidden: readJson(STATE_FILE, {}).hidden || [], photos: photos()
      });
    });
  }

  if (req.method === 'POST' && url === '/api/launch') {
    return body(req, function (b) {
      if (!b.id) return send(res, 400, { error: 'id needed' });
      log('launch ' + b.id);
      if (DEMO) return send(res, 200, { returnValue: true, demo: true });
      var payload = { id: b.id };
      if (b.params) payload.params = b.params;
      luna('luna://com.webos.applicationManager/launch', payload, function (r) { send(res, 200, r); });
    });
  }

  if (req.method === 'POST' && url === '/api/order') {
    return body(req, function (b) {
      if (!Array.isArray(b.order)) return send(res, 400, { error: 'order needed' });
      var strings = function (a) { return a.filter(function (x) { return typeof x === 'string'; }).slice(0, 200); };
      var st = readJson(STATE_FILE, {});
      st.order = strings(b.order);
      if (Array.isArray(b.dock)) st.dock = strings(b.dock);
      if (Array.isArray(b.hidden)) st.hidden = strings(b.hidden);
      fs.writeFileSync(STATE_FILE, JSON.stringify(st, null, 2));
      send(res, 200, { ok: true });
    });
  }

  // Uninstall: only an app the app manager marks removable (not LG's own,
  // not inputs). The page asks the user first.
  if (req.method === 'POST' && url === '/api/uninstall') {
    return body(req, function (b) {
      if (!b.id) return send(res, 400, { error: 'id needed' });
      if (DEMO) { log('uninstall ' + b.id + ' (demo, nothing done)'); return send(res, 200, { returnValue: true, demo: true }); }
      listTiles(function (err, tiles) {
        var t = (tiles || []).filter(function (x) { return x.id === b.id; })[0];
        if (!t || !t.removable) return send(res, 400, { returnValue: false, errorText: 'this app cannot be uninstalled' });
        log('uninstall ' + b.id);
        luna('luna://com.webos.appInstallService/remove', { id: b.id }, function (r) { send(res, 200, r); });
      });
    });
  }

  // Messages from the Home page (errors, unknown remote keys) into server.log.
  if (req.method === 'POST' && url === '/api/log') {
    return body(req, function (b) { log('page: ' + String(b.msg || '').slice(0, 500)); send(res, 200, { ok: true }); });
  }

  // A frame-rate measurement, asked for over ssh and run by the page at its
  // next heartbeat: POST /api/bench, then GET /api/bench for the result.
  if (req.method === 'POST' && url === '/api/bench') { benchWanted = true; benchResult = null; return send(res, 200, { ok: true }); }
  if (req.method === 'GET' && url === '/api/bench') return send(res, 200, { wanted: benchWanted, result: benchResult });
  if (req.method === 'POST' && url === '/api/bench/result') {
    return body(req, function (b) { benchResult = b; log('bench ' + JSON.stringify(b)); send(res, 200, { ok: true }); });
  }

  // For testing over ssh without the remote: POST /api/remote {"area":
  // "drawer"|"dock"|"photo", "index": N}; the page takes it at its next heartbeat.
  if (req.method === 'POST' && url === '/api/remote') {
    return body(req, function (b) { remoteCmd = b; send(res, 200, { ok: true }); });
  }

  // The page reports it is alive; the Home takeover's watchdog reads this.
  if (req.method === 'POST' && url === '/api/heartbeat') {
    lastHeartbeat = Date.now();
    var bench = benchWanted; benchWanted = false;
    var remote = remoteCmd; remoteCmd = null;
    return send(res, 200, { ok: true, bench: bench, remote: remote });
  }
  if (req.method === 'GET' && url === '/api/heartbeat') return send(res, 200, { last: lastHeartbeat, age: lastHeartbeat ? Date.now() - lastHeartbeat : null });

  send(res, 404, { error: 'not found' });
}).on('error', function (e) { log('server error: ' + e.message); process.exit(1); })
  .listen(PORT, HOST, function () { log('TV Home on http://' + HOST + ':' + PORT + (DEMO ? ' (demo, no TV)' : '')); });
