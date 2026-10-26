// app.js - TV Home's page logic. Data comes from server.js (/api/state); opened
// as a file, or from server.js --demo, it shows the demo list in demo.js.
'use strict';

var CONFIG = { name: '', locale: 'en-GB', hour24: true, photoSeconds: 30, dockSize: 6, dockMax: 12,
  photos: ['../photos/01.jpg', '../photos/02.jpg', '../photos/03.jpg', '../photos/04.jpg'] };
var SERVER = /^https?:$/.test(location.protocol);
// TV mode: on the TV (or with ?lite), without the effects TV chips are slow at.
// ?full forces the full design, to compare.
var LITE = /[?&]lite\b/.test(location.search) || (/Web0S|webOS/i.test(navigator.userAgent) && !/[?&]full\b/.test(location.search));
if (LITE) document.body.classList.add('lite');
var TILES = [];      // { key, id, name, sub, kind: 'app' | 'input', color, icon (url) | svg, params, removable }
var ORDER = [];      // keys in the user's order (All apps)
var DOCK = null;     // keys in the dock, in order; null: the first dockSize apps
var HIDDEN = [];     // keys hidden from the dock and All apps

// The dock keeps one width: with more tiles they get narrower.
var DOCK_SPACE = 1920 - 2 * 110 - 92;   // stage width - side margins - dock padding
var TILE_W = 224, TILE_H = 134, GAP = 44, RADIUS = 26;
var COLS = 7;                           // All apps columns, as in .grid
var HOLD_MS = 650;

var $ = function (id) { return document.getElementById(id); };
var area = 'dock';                      // 'dock' | 'drawer'
var dockIndex = 0, drawerIndex = 0;
var lifted = false;                     // a dock tile is being moved
var menu = null;                        // { options, index }

// ---- data -------------------------------------------------------------------------
function api(method, url, data, cb) {
  var x = new XMLHttpRequest();
  x.open(method, url, true);
  x.timeout = 15000;
  x.setRequestHeader('Content-Type', 'application/json');
  x.onload = function () { var r = null; try { r = JSON.parse(x.responseText); } catch (e) {} cb(r); };
  x.onerror = x.ontimeout = function () { cb(null); };
  x.send(data ? JSON.stringify(data) : null);
}

function load(cb) {
  if (!SERVER) return useDemo(cb, false);
  api('GET', '/api/state', null, function (s) {
    if (!s) return useDemo(cb, false);
    Object.keys(s.config || {}).forEach(function (k) { CONFIG[k] = s.config[k]; });
    if (s.photos && s.photos.length) CONFIG.photos = s.photos;
    ORDER = s.order || []; DOCK = s.dock || null; HIDDEN = s.hidden || [];
    if (s.demo || !s.tiles || !s.tiles.length) return useDemo(cb, true);
    TILES = s.tiles;
    cb();
  });
}

function useDemo(cb, fromServer) {
  TILES = DEMO_TILES.slice();
  if (!fromServer) {
    var ls = function (k, d) { try { return JSON.parse(localStorage.getItem(k) || 'null') || d; } catch (e) { return d; } };
    ORDER = ls('tvhome.order', []); DOCK = ls('tvhome.dock', null); HIDDEN = ls('tvhome.hidden', []);
    if (!CONFIG.name) CONFIG.name = DEMO_NAME;
  }
  cb();
}

function saveState() {
  DOCK = dockKeys();
  if (SERVER) return api('POST', '/api/order', { order: ORDER, dock: DOCK, hidden: HIDDEN }, function () {});
  try {
    localStorage.setItem('tvhome.order', JSON.stringify(ORDER));
    localStorage.setItem('tvhome.dock', JSON.stringify(DOCK));
    localStorage.setItem('tvhome.hidden', JSON.stringify(HIDDEN));
  } catch (e) {}
}

function byKey(key) { return TILES.filter(function (t) { return t.key === key; })[0]; }
function isHidden(t) { return HIDDEN.indexOf(t.key) !== -1; }
function sorted(list) {
  function rank(t) { var i = ORDER.indexOf(t.key); return i === -1 ? 1000 + TILES.indexOf(t) : i; }
  return list.slice().sort(function (a, b) { return rank(a) - rank(b); });
}
function apps() { return sorted(TILES.filter(function (t) { return t.kind === 'app' && !isHidden(t); })); }
function inputs() { return TILES.filter(function (t) { return t.kind === 'input' && !isHidden(t); }); }
function hidden() { return TILES.filter(isHidden); }
function dockKeys() {
  var keys = DOCK && DOCK.length ? DOCK : apps().slice(0, CONFIG.dockSize).map(function (t) { return t.key; });
  // gone from the TV, or hidden: not in the dock
  return keys.filter(function (k) { var t = byKey(k); return t && !isHidden(t); });
}
function dockList() { return dockKeys().map(byKey); }
function inDock(t) { return dockKeys().indexOf(t.key) !== -1; }

// All apps: sections of rows of COLS tiles, walked as one list.
function sections() {
  return [['Apps', apps(), 'gridApps'], ['Inputs', inputs(), 'gridInputs'], ['Hidden', hidden(), 'gridHidden']];
}
function drawerList() { var all = []; sections().forEach(function (s) { all = all.concat(s[1]); }); return all; }
// position of every drawer tile: section, row (counted over all sections), column
function drawerLayout() {
  var out = [], row = 0;
  sections().forEach(function (s, si) {
    if (!s[1].length) return;
    s[1].forEach(function (t, i) { out.push({ sec: si, row: row + Math.floor(i / COLS), col: i % COLS }); });
    row += Math.ceil(s[1].length / COLS);
  });
  return out;
}

// ---- tiles ----------------------------------------------------------------------------
function face(t) {
  var f = document.createElement('div');
  f.className = 'face';
  if (t.svg) f.innerHTML = t.svg;
  else {
    // an icon with its own background fills the tile, in that colour
    f.style.background = t.fill || t.color || '#2a2a30';
    if (t.fill) f.className += ' fill';
    if (t.icon) { var img = new Image(); img.src = t.icon; img.alt = ''; f.appendChild(img); }
    else f.innerHTML = '<span class="initial">' + (t.name || '?').charAt(0) + '</span>';
  }
  return f;
}

function tile(t, label) {
  var el = document.createElement('div');
  el.className = 'tile';
  el.appendChild(face(t));
  var lab = document.createElement('div');
  lab.className = 'label';
  lab.textContent = label || t.name;
  el.appendChild(lab);
  return el;
}

// Pointer (Magic Remote, mouse): hover focuses, click opens, a long press
// opens the options, as holding OK does.
function pointer(el, where, i) {
  var timer = null, held = false;
  el.addEventListener('mouseenter', function () {
    if (lifted || menu) return;
    area = where; if (where === 'dock') dockIndex = i; else drawerIndex = i; focus(0);
  });
  el.addEventListener('mousedown', function () {
    held = false;
    timer = setTimeout(function () { held = true; area = where; if (where === 'dock') dockIndex = i; else drawerIndex = i; options(); }, HOLD_MS);
  });
  el.addEventListener('mouseup', function () { clearTimeout(timer); });
  el.addEventListener('mouseleave', function () { clearTimeout(timer); });
  el.addEventListener('click', function () {
    if (held) { held = false; return; }
    if (lifted) { drop(); return; }
    if (menu) return;
    area = where; if (where === 'dock') dockIndex = i; else drawerIndex = i; open();
  });
}

// Tile size for n dock tiles: full size up to what fits, then narrower.
function sizeDock(n) {
  var w = Math.min(TILE_W, Math.floor((DOCK_SPACE - (n - 1) * GAP) / n));
  var k = w / TILE_W, dock = $('dock');
  dock.style.setProperty('--tile-w', w + 'px');
  dock.style.setProperty('--tile-h', Math.round(TILE_H * k) + 'px');
  dock.style.setProperty('--radius', Math.round(RADIUS * Math.max(k, .6)) + 'px');
  dock.style.gap = Math.round(GAP * Math.max(k, .7)) + 'px';
}

function label(t) { return t.kind === 'input' && t.sub ? t.name + ' · ' + t.sub : t.name; }

function render() {
  var dock = $('dock'); dock.innerHTML = '';
  var dl = dockList();
  sizeDock(Math.max(dl.length, 1));
  dl.forEach(function (t, i) { var el = tile(t, label(t)); pointer(el, 'dock', i); dock.appendChild(el); });
  var n = 0;
  sections().forEach(function (s) {
    var grid = $(s[2]); grid.innerHTML = '';
    var title = grid.previousElementSibling;
    title.style.display = grid.style.display = s[1].length ? '' : 'none';
    s[1].forEach(function (t) { var el = tile(t, label(t)); pointer(el, 'drawer', n++); grid.appendChild(el); });
  });
  dockIndex = Math.min(dockIndex, Math.max(dl.length - 1, 0));
  drawerIndex = Math.min(drawerIndex, Math.max(drawerList().length - 1, 0));
}
function dockTiles() { return $('dock').children; }
function drawerTiles() {
  var all = [];
  ['gridApps', 'gridInputs', 'gridHidden'].forEach(function (g) { all = all.concat(Array.prototype.slice.call($(g).children)); });
  return all;
}
function current() { return area === 'dock' ? dockList()[dockIndex] : drawerList()[drawerIndex]; }

// ---- focus, with a little tilt toward the direction of travel ----------------------
function focus(dir) {
  Array.prototype.forEach.call(document.querySelectorAll('.tile.focus'), function (t) { t.classList.remove('focus'); });
  var el = area === 'dock' ? dockTiles()[dockIndex] : drawerTiles()[drawerIndex];
  var t = current();
  if (!el || !t) return;
  el.style.setProperty('--tilt', (dir * 5) + 'deg');
  void el.offsetWidth;   // restart the sheen
  el.classList.add('focus');
  setTimeout(function () { el.style.setProperty('--tilt', '0deg'); }, 160);
  var tint = $('tint');
  tint.style.background = 'radial-gradient(ellipse 90% 70% at 50% 100%, ' + (t.color || '#888') + ', transparent 75%)';
  tint.style.opacity = area === 'dock' ? (LITE ? '.32' : '.85') : '0';
  if (area === 'drawer') scrollDrawer(el);
}

// Keeps the focused row in view when All apps is taller than the screen.
function scrollDrawer(el) {
  var visible = 1080 - 96 - 60;
  var bottom = el.offsetTop + el.offsetHeight + 90;
  var shift = Math.max(0, bottom - visible);
  $('drawerScroll').style.transform = 'translateY(' + (-shift) + 'px)';
}

// ---- opening ------------------------------------------------------------------------------
var toastTimer = null;
function toast(text, sub, busy) {
  $('toastText').textContent = text;
  $('toastId').textContent = sub || '';
  $('toast').querySelector('.spin').style.display = busy ? '' : 'none';
  $('toast').classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function () { $('toast').classList.remove('show'); }, busy ? 1800 : 3500);
}
function open() {
  var t = current();
  if (!t) return;
  toast((t.kind === 'input' ? 'Switching to ' : 'Opening ') + t.name, SERVER ? '' : t.id, true);
  if (!SERVER) return;
  api('POST', '/api/launch', { id: t.id, params: t.params || null }, function (r) {
    if (!r || r.returnValue === false) toast('Could not open ' + t.name, (r && r.errorText) || 'no answer from the TV', false);
  });
}

// ---- drawer ----------------------------------------------------------------------------
function openDrawer() { area = 'drawer'; drawerIndex = Math.min(dockIndex, COLS - 1, drawerList().length - 1); document.body.classList.add('drawer-open'); focus(0); }
function closeDrawer() { area = 'dock'; document.body.classList.remove('drawer-open'); $('drawerScroll').style.transform = ''; focus(0); }

function drawerMove(k) {
  var lay = drawerLayout(), here = lay[drawerIndex];
  if (!here) return;
  if (k === 'ArrowLeft' || k === 'ArrowRight') {
    var j = drawerIndex + (k === 'ArrowLeft' ? -1 : 1);
    if (lay[j] && lay[j].row === here.row) { drawerIndex = j; focus(k === 'ArrowLeft' ? -1 : 1); }
    return;
  }
  var row = here.row + (k === 'ArrowDown' ? 1 : -1);
  if (row < 0) { closeDrawer(); return; }
  var best = -1;
  lay.forEach(function (p, i) { if (p.row === row && (best === -1 || Math.abs(p.col - here.col) < Math.abs(lay[best].col - here.col))) best = i; });
  if (best !== -1) { drawerIndex = best; focus(0); }
}

// ---- moving a dock tile -------------------------------------------------------------------
function liftAt(i) {
  document.body.classList.remove('drawer-open');
  area = 'dock'; dockIndex = i; render(); focus(0);
  lifted = true; dockTiles()[dockIndex].classList.add('lifted');
}
function drop() {
  lifted = false;
  var el = dockTiles()[dockIndex];
  if (el) el.classList.remove('lifted');
  saveState();
}
function moveLifted(dir) {
  var keys = dockKeys(), j = dockIndex + dir;
  if (j < 0 || j >= keys.length) return;
  var tmp = keys[dockIndex]; keys[dockIndex] = keys[j]; keys[j] = tmp;
  DOCK = keys;
  dockIndex = j; render(); focus(dir); dockTiles()[dockIndex].classList.add('lifted');
}

// ---- options (hold OK): move, dock, hide, uninstall ---------------------------------------
function options() {
  var t = current();
  if (!t) return;
  var list = [];
  if (isHidden(t)) {
    list.push(['Show again', function () { HIDDEN = HIDDEN.filter(function (k) { return k !== t.key; }); saveState(); render(); focus(0); toast(t.name + ' is back', '', false); }]);
  } else {
    if (inDock(t)) {
      list.push(['Move', function () { liftAt(dockKeys().indexOf(t.key)); toast('Moving ' + t.name, 'left / right, then OK', false); }]);
      if (dockKeys().length > 1) list.push(['Remove from dock', function () { removeFromDock(t); }]);
    } else {
      list.push(['Add to dock', function () { addToDock(t); }]);
    }
    list.push(['Hide', function () { hide(t); }]);
    if (t.removable) list.push(['Uninstall…', function () { confirmUninstall(t); }, true]);
  }
  list.push(['Cancel', function () {}]);
  showMenu(t, t.name, t.kind === 'input' ? t.sub || 'Input' : (inDock(t) ? 'In the dock' : 'In All apps'), list, 0);
}

function addToDock(t) {
  var keys = dockKeys();
  if (keys.length >= CONFIG.dockMax) { toast('The dock is full', 'remove an app from it first', false); return; }
  keys.push(t.key); DOCK = keys; saveState();
  liftAt(keys.length - 1);
  toast(t.name + ' is in the dock', 'left / right to place it, then OK', false);
}
function removeFromDock(t) {
  var keys = dockKeys();
  DOCK = keys.filter(function (k) { return k !== t.key; }); saveState();
  render(); focus(0);
  toast(t.name + ' is out of the dock', 'it stays in All apps', false);
}
function hide(t) {
  if (dockKeys().length === 1 && inDock(t)) { toast('The dock needs one app', 'add another first', false); return; }
  // The dock as it is now, so hiding only takes this one out of it (and the
  // next app does not slip in, as it would from the default "first apps").
  DOCK = dockKeys();
  HIDDEN.push(t.key); saveState(); render(); focus(0);
  toast(t.name + ' is hidden', 'All apps, at the end: hold OK to show it again', false);
}
function confirmUninstall(t) {
  showMenu(t, 'Uninstall ' + t.name + '?',
    'It is deleted from the TV. If the LG Content Store is blocked on this TV, it may not be possible to install it again.',
    [['Uninstall', function () { uninstall(t); }, true], ['Cancel', function () {}]], 1);
}
function uninstall(t) {
  toast('Uninstalling ' + t.name, '', true);
  if (!SERVER) { toast(t.name + ' would be uninstalled', 'demo: nothing deleted', false); return; }
  api('POST', '/api/uninstall', { id: t.id }, function (r) {
    if (!r || r.returnValue === false) { toast('Could not uninstall ' + t.name, (r && r.errorText) || 'no answer from the TV', false); return; }
    toast(t.name + ' is uninstalled', '', false);
    setTimeout(function () { load(function () { render(); focus(0); }); }, 2500);
  });
}

function showMenu(t, title, sub, list, index) {
  menu = { options: list, index: index };
  $('menuIcon').innerHTML = ''; $('menuIcon').appendChild(face(t));
  $('menuTitle').textContent = title;
  $('menuSub').textContent = sub || '';
  var box = $('menuList'); box.innerHTML = '';
  list.forEach(function (o, i) {
    var el = document.createElement('div');
    el.className = 'menu-item' + (o[2] ? ' danger' : '');
    el.textContent = o[0];
    el.addEventListener('mouseenter', function () { menu.index = i; menuFocus(); });
    el.addEventListener('click', function () { menu.index = i; choose(); });
    box.appendChild(el);
  });
  $('menuBack').classList.add('show');
  menuFocus();
}
function menuFocus() {
  Array.prototype.forEach.call($('menuList').children, function (el, i) { el.classList.toggle('focus', i === menu.index); });
}
function closeMenu() { menu = null; $('menuBack').classList.remove('show'); }
function choose() {
  var o = menu.options[menu.index];
  closeMenu();
  o[1]();
}

// ---- keys (the remote sends arrows and Enter; Back is 461) --------------------------------
// OK opens on release; held for HOLD_MS it opens the options instead. An OK
// that chose something on its press (a menu entry, dropping a tile) does not
// also open on its release.
var holdTimer = null, held = false, swallowUp = false;

document.addEventListener('keydown', function (e) {
  var k = e.key, back = (k === 'Escape' || k === 'Backspace' || e.keyCode === 461 || k === 'GoBack');
  if (k === '?') { $('help').classList.toggle('show'); return; }
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Enter'].indexOf(k) !== -1 || back) e.preventDefault();
  if (k === 'Enter' && e.repeat) return;

  if (menu) {
    if (k === 'ArrowUp' && menu.index > 0) { menu.index--; menuFocus(); }
    if (k === 'ArrowDown' && menu.index < menu.options.length - 1) { menu.index++; menuFocus(); }
    if (k === 'Enter') { swallowUp = true; choose(); }
    if (back) closeMenu();
    return;
  }
  if (lifted) {
    if (k === 'ArrowLeft') moveLifted(-1);
    if (k === 'ArrowRight') moveLifted(1);
    if (k === 'Enter' || back) { swallowUp = k === 'Enter'; drop(); }
    return;
  }
  if (k === 'Enter') {
    held = false;
    holdTimer = setTimeout(function () { held = true; options(); }, HOLD_MS);
    return;
  }
  if (area === 'dock') {
    var n = dockList().length;
    if (k === 'ArrowLeft' && dockIndex > 0) { dockIndex--; focus(-1); }
    if (k === 'ArrowRight' && dockIndex < n - 1) { dockIndex++; focus(1); }
    if (k === 'ArrowDown') openDrawer();
    return;
  }
  if (k.indexOf('Arrow') === 0) drawerMove(k);
  if (back) closeDrawer();
});

document.addEventListener('keyup', function (e) {
  if (e.key !== 'Enter') return;
  clearTimeout(holdTimer);
  if (swallowUp) { swallowUp = false; held = false; return; }
  if (!held && !menu && !lifted) open();
  held = false;
});

// ---- clock, greeting, date ------------------------------------------------------------
function tick() {
  var d = new Date(), h = d.getHours();
  $('clock').textContent = d.toLocaleTimeString(CONFIG.locale, { hour: '2-digit', minute: '2-digit', hour12: !CONFIG.hour24 });
  var part = h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : h < 23 ? 'Good evening' : 'Good night';
  $('greet').textContent = CONFIG.name ? part + ', ' + CONFIG.name : part;
  $('date').textContent = d.toLocaleDateString(CONFIG.locale, { weekday: 'long', day: 'numeric', month: 'long' });
}

// ---- background photos ------------------------------------------------------------------
var photoIndex = -1, front = 'bgA', photoSeq = 0;
function nextPhoto() {
  if (!CONFIG.photos.length) return;
  if (photoIndex === -1) photoIndex = Math.floor(Math.random() * CONFIG.photos.length);
  else photoIndex = (photoIndex + 1) % CONFIG.photos.length;
  // Only the latest change counts: two overlapping ones (start and becoming
  // visible) would otherwise both use the same layer and turn each other off.
  var seq = ++photoSeq, src = CONFIG.photos[photoIndex], img = new Image();
  img.onload = function () {
    if (seq !== photoSeq) return;
    var shown = front, next = shown === 'bgA' ? 'bgB' : 'bgA', b = $(next);
    b.style.backgroundImage = 'url("' + src + '")';
    b.classList.remove('on'); void b.offsetWidth; b.classList.add('on');
    $(shown).classList.remove('on');
    front = next;
  };
  img.src = src;
}

// ---- frame-rate measurement (asked for through server.js /api/bench) ------------------
// Moves the focus along the dock and back, opens and closes All apps, and
// reports the frame rate the page managed meanwhile.
function bench() {
  if (menu || lifted || area !== 'dock') return;
  var times = [], running = true, last = performance.now();
  function frame(t) { times.push(t - last); last = t; if (running) requestAnimationFrame(frame); }
  requestAnimationFrame(frame);
  var steps = [], n = Math.max(dockList().length - 1, 1);
  for (var i = 0; i < Math.min(n, 4); i++) steps.push(function () { dockIndex++; focus(1); });
  for (i = 0; i < Math.min(n, 4); i++) steps.push(function () { dockIndex--; focus(-1); });
  steps.push(openDrawer, function () { drawerMove('ArrowRight'); }, function () { drawerMove('ArrowRight'); }, closeDrawer);
  var start = performance.now();
  steps.forEach(function (s, i) { setTimeout(s, 400 * (i + 1)); });
  setTimeout(function () {
    running = false;
    var d = times.slice(2).sort(function (a, b) { return a - b; });
    var avg = d.reduce(function (a, b) { return a + b; }, 0) / d.length;
    api('POST', '/api/bench/result', {
      mode: document.body.classList.contains('lite') ? 'lite' : 'full',
      seconds: Math.round((performance.now() - start) / 100) / 10,
      fps: Math.round(1000 / avg), frames: d.length,
      p95ms: Math.round(d[Math.floor(d.length * .95)]), worstMs: Math.round(d[d.length - 1]),
      ua: navigator.userAgent.slice(0, 160)
    }, function () {});
  }, 400 * (steps.length + 2));
}

function fit() {
  var s = Math.min(innerWidth / 1920, innerHeight / 1080);
  $('stage').style.transform = 'translate(-50%, -50%) scale(' + s + ')';
}

// Back on Home after an app: the app list may have changed, and a new photo.
document.addEventListener('visibilitychange', function () {
  if (document.hidden) return;
  if (!menu && !lifted) load(function () { render(); focus(0); });
  nextPhoto();
});

addEventListener('resize', fit);
fit();
load(function () {
  render(); focus(0); tick(); setInterval(tick, 1000);
  nextPhoto(); setInterval(nextPhoto, CONFIG.photoSeconds * 1000);
  if (SERVER) setInterval(function () {
    api('POST', '/api/heartbeat', {}, function (r) { if (r && r.bench) bench(); });
  }, 5000);
});
$('help').classList.add('show');
setTimeout(function () { $('help').classList.remove('show'); }, 6000);
