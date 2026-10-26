// demo.js - the demo list for TV Home: shown when the page is opened as a
// file or from server.js --demo. Simple stand-in icons; on the TV the real
// icons come from each app.
'use strict';

var DEMO_NAME = '';

var ICON = {
  netflix: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#000"/><text x="120" y="88" text-anchor="middle" font-family="Arial Black,Arial" font-weight="900" font-size="44" fill="#e50914" letter-spacing="2">NETFLIX</text></svg>',
  youtube: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#fff"/><rect x="40" y="50" width="62" height="44" rx="12" fill="#ff0033"/><path d="M64 61v22l19-11z" fill="#fff"/><text x="112" y="85" font-family="Arial" font-weight="700" font-size="30" fill="#0f0f0f" letter-spacing="-1">YouTube</text></svg>',
  disney: '<svg viewBox="0 0 240 144"><defs><linearGradient id="dg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0d1b4c"/><stop offset="1" stop-color="#1d4fa8"/></linearGradient></defs><rect width="240" height="144" fill="url(#dg)"/><text x="120" y="90" text-anchor="middle" font-family="Georgia,serif" font-style="italic" font-size="44" fill="#fff">Disney+</text></svg>',
  spotify: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#121212"/><circle cx="120" cy="72" r="40" fill="#1ed760"/><g fill="none" stroke="#121212" stroke-linecap="round"><path d="M96 62c16-5 34-4 49 4" stroke-width="7"/><path d="M99 75c13-4 28-3 40 4" stroke-width="6"/><path d="M102 87c10-3 21-2 30 3" stroke-width="5"/></g></svg>',
  emby: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#1c1c1c"/><path d="M120 34l38 38-38 38-38-38z" fill="#52b54b"/><path d="M112 58v28l22-14z" fill="#fff"/></svg>',
  livetv: '<svg viewBox="0 0 240 144"><defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff3b6b"/><stop offset="1" stop-color="#c2104c"/></linearGradient></defs><rect width="240" height="144" fill="url(#lg)"/><rect x="72" y="40" width="96" height="62" rx="10" fill="none" stroke="#fff" stroke-width="6"/><path d="M104 112h32" stroke="#fff" stroke-width="6" stroke-linecap="round"/><text x="120" y="80" text-anchor="middle" font-family="Arial" font-weight="800" font-size="20" fill="#fff">LIVE</text></svg>',
  pool: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#0b6b3a"/><circle cx="120" cy="72" r="40" fill="#111"/><circle cx="120" cy="72" r="17" fill="#fff"/><text x="120" y="81" text-anchor="middle" font-family="Arial" font-weight="800" font-size="24" fill="#111">8</text></svg>',
  browser: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#2f6fde"/><g fill="none" stroke="#fff" stroke-width="5"><circle cx="120" cy="72" r="38"/><ellipse cx="120" cy="72" rx="16" ry="38"/><path d="M82 72h76M88 52h64M88 92h64"/></g></svg>',
  media: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#7b4fd6"/><rect x="74" y="40" width="92" height="64" rx="10" fill="none" stroke="#fff" stroke-width="5"/><path d="M110 58v28l24-14z" fill="#fff"/></svg>',
  multiview: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#14a39a"/><rect x="62" y="46" width="56" height="52" rx="8" fill="#fff"/><rect x="124" y="46" width="56" height="52" rx="8" fill="none" stroke="#fff" stroke-width="5"/></svg>',
  store: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#38c06a"/><g fill="#fff"><rect x="88" y="40" width="28" height="28" rx="7"/><rect x="124" y="40" width="28" height="28" rx="7"/><rect x="88" y="76" width="28" height="28" rx="7"/><rect x="124" y="76" width="28" height="28" rx="7"/></g></svg>',
  homebrew: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#1f1f24"/><path d="M120 36l34 36-34 36-34-36z" fill="none" stroke="#ff9f1c" stroke-width="7"/><circle cx="120" cy="72" r="10" fill="#ff9f1c"/></svg>',
  settings: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#5b6270"/><circle cx="120" cy="72" r="30" fill="none" stroke="#fff" stroke-width="12" stroke-dasharray="9 7.7"/><circle cx="120" cy="72" r="22" fill="none" stroke="#fff" stroke-width="6"/><circle cx="120" cy="72" r="8" fill="#fff"/></svg>',
  ps5: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#0b1020"/><path d="M78 92c-8 0-12-8-9-20l5-15c3-8 9-12 17-12h58c8 0 14 4 17 12l5 15c3 12-1 20-9 20-6 0-9-4-13-10H91c-4 6-7 10-13 10z" fill="none" stroke="#fff" stroke-width="5"/><circle cx="148" cy="64" r="4" fill="#fff"/><circle cx="158" cy="72" r="4" fill="#fff"/><path d="M92 68h18M101 59v18" stroke="#fff" stroke-width="5" stroke-linecap="round"/></svg>',
  switch: '<svg viewBox="0 0 240 144"><rect width="240" height="144" fill="#e60012"/><rect x="86" y="34" width="30" height="76" rx="14" fill="none" stroke="#fff" stroke-width="6"/><rect x="124" y="34" width="30" height="76" rx="14" fill="#fff"/><circle cx="101" cy="56" r="6" fill="#fff"/><circle cx="139" cy="86" r="6" fill="#e60012"/></svg>'
};

var DEMO_TILES = [
  { id: 'netflix', name: 'Netflix', icon: 'netflix', color: '#e50914' },
  { id: 'youtube.leanback.v4', name: 'YouTube', icon: 'youtube', color: '#ff0033' },
  { id: 'com.disney.disneyplus-prod', name: 'Disney+', icon: 'disney', color: '#1d4fa8' },
  { id: 'spotify-beehive', name: 'Spotify', icon: 'spotify', color: '#1ed760' },
  { id: 'com.emby.app', name: 'Emby', icon: 'emby', color: '#52b54b' },
  { id: 'com.webos.app.livetv', name: 'Live TV', icon: 'livetv', color: '#ff3b6b' },
  { id: 'com.miniclip.eightballpool', name: '8 Ball Pool', icon: 'pool', color: '#0b6b3a' },
  { id: 'com.webos.app.browser', name: 'Web Browser', icon: 'browser', color: '#2f6fde' },
  { id: 'com.webos.app.mediadiscovery', name: 'Media Player', icon: 'media', color: '#7b4fd6' },
  { id: 'com.webos.app.multiviewsettings', name: 'Multi-view', icon: 'multiview', color: '#14a39a' },
  { id: 'com.webos.app.discovery', name: 'Apps', icon: 'store', color: '#38c06a' },
  { id: 'org.webosbrew.hbchannel', name: 'Homebrew Channel', icon: 'homebrew', color: '#ff9f1c' },
  { id: 'com.palm.app.settings', name: 'Settings', icon: 'settings', color: '#8a93a3' },
  { id: 'com.webos.app.hdmi3', name: 'PS5', sub: 'HDMI 3', icon: 'ps5', color: '#2d5bff', kind: 'input' },
  { id: 'com.webos.app.hdmi1', name: 'Switch 2', sub: 'HDMI 1', icon: 'switch', color: '#e60012', kind: 'input' }
].map(function (t) {
  // demo: store apps can be uninstalled, LG's own and inputs cannot
  var removable = !t.kind && !/^com\.(webos|palm)\./.test(t.id) && t.id !== 'org.webosbrew.hbchannel';
  return { key: t.id, id: t.id, name: t.name, sub: t.sub, kind: t.kind || 'app', color: t.color, svg: ICON[t.icon], params: null, removable: removable };
});