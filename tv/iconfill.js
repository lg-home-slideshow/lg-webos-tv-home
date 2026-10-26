// iconfill.js - does an app icon bring its own background (Emby's grey square,
// Spotify's black one)? Then the tile takes that colour and the icon fills the
// tile's height, so tile and icon read as one. Icons with a transparent
// background (LG's own) get null and keep the app's colour.
//
// A small PNG reader with Node's zlib only: the TV's Node has no image library.
'use strict';

var fs = require('fs');
var zlib = require('zlib');

// PNG -> { w, h, px(x, y) -> [r, g, b, a] }, or null for what it cannot read
// (interlaced, 16-bit).
function readPng(buf) {
  if (buf.length < 33 || buf.readUInt32BE(0) !== 0x89504e47) return null;
  var w, h, depth, type, interlace, plte = null, trns = null, idat = [];
  for (var o = 8; o + 8 <= buf.length;) {
    var len = buf.readUInt32BE(o), kind = buf.toString('latin1', o + 4, o + 8), d = buf.slice(o + 8, o + 8 + len);
    if (kind === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); depth = d[8]; type = d[9]; interlace = d[12]; }
    else if (kind === 'PLTE') plte = d;
    else if (kind === 'tRNS') trns = d;
    else if (kind === 'IDAT') idat.push(d);
    else if (kind === 'IEND') break;
    o += 12 + len;
  }
  if (!w || interlace || depth > 8 || (depth < 8 && type !== 3 && type !== 0)) return null;
  var chans = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
  if (!chans) return null;
  var raw = zlib.inflateSync(Buffer.concat(idat));
  var bpp = Math.max(1, chans * depth / 8), stride = Math.ceil(w * chans * depth / 8);
  var img = Buffer.alloc(stride * h), prev = Buffer.alloc(stride);
  for (var y = 0; y < h; y++) {
    var f = raw[y * (stride + 1)], line = raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)), cur = img.slice(y * stride, (y + 1) * stride);
    for (var i = 0; i < stride; i++) {
      var a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0, v = line[i];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { var p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      cur[i] = v & 255;
    }
    prev = cur;
  }
  function sample(x, y) {   // one channel value at bit depth < 8
    var bit = x * depth, byte = img[y * stride + (bit >> 3)];
    return (byte >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
  }
  return {
    w: w, h: h,
    px: function (x, y) {
      var i = y * stride + x * chans;
      if (type === 6) return [img[i], img[i + 1], img[i + 2], img[i + 3]];
      if (type === 2) return [img[i], img[i + 1], img[i + 2], trns && trns.readUInt16BE(0) === img[i] && trns.readUInt16BE(2) === img[i + 1] && trns.readUInt16BE(4) === img[i + 2] ? 0 : 255];
      if (type === 4) return [img[i], img[i], img[i], img[i + 1]];
      if (type === 0) { var g = depth < 8 ? sample(x, y) * 255 / ((1 << depth) - 1) : img[i]; return [g, g, g, 255]; }
      var k = depth < 8 ? sample(x, y) : img[i];   // palette
      return [plte[k * 3], plte[k * 3 + 1], plte[k * 3 + 2], trns && k < trns.length ? trns[k] : 255];
    }
  };
}

function hex(c) { return '#' + c.slice(0, 3).map(function (v) { return ('0' + Math.round(v).toString(16)).slice(-2); }).join(''); }

// The icon's own background: points along its border, a little inside so
// rounded corners don't count, all opaque and (nearly) one colour.
function fillColor(file) {
  try {
    var png = readPng(fs.readFileSync(file));
    if (!png) return null;
    var m = Math.max(1, Math.round(Math.min(png.w, png.h) * 0.04)), pts = [];
    for (var s = 0.15; s <= 0.851; s += 0.0875) {
      var x = Math.round(s * (png.w - 1)), y = Math.round(s * (png.h - 1));
      pts.push(png.px(x, m), png.px(x, png.h - 1 - m), png.px(m, y), png.px(png.w - 1 - m, y));
    }
    if (pts.some(function (p) { return p[3] < 245; })) return null;
    var avg = [0, 1, 2].map(function (k) { return pts.reduce(function (t, p) { return t + p[k]; }, 0) / pts.length; });
    var off = pts.filter(function (p) { return Math.abs(p[0] - avg[0]) + Math.abs(p[1] - avg[1]) + Math.abs(p[2] - avg[2]) > 24; });
    return off.length <= pts.length * 0.1 ? hex(avg) : null;
  } catch (e) { return null; }
}

var cache = {};
module.exports = function (file) {
  if (!(file in cache)) cache[file] = fillColor(file);
  return cache[file];
};
module.exports.readPng = readPng;
