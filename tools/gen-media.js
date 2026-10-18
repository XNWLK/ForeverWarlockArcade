// Makes the addon's shape textures twice: WarlockArcade/Media/<name>.tga for the game (uncompressed 32-bit TGA, the
// size a power of two) and web/media/<name>.png for the web page. White shapes on transparent: the code tints them.
//   node tools/gen-media.js
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const ROOT = path.join(__dirname, '..');
const S = 64;
// alpha 0..1 for each pixel, from a distance function with 1 px of soft edge
const SHAPES = {
  circle: (x, y) => { const d = Math.hypot(x - S / 2, y - S / 2); return clamp(S / 2 - 1 - d + 0.5); },
  ring: (x, y) => { const d = Math.hypot(x - S / 2, y - S / 2); return Math.min(clamp(S / 2 - 1 - d + 0.5), clamp(d - (S / 2 - 7) + 0.5)); },
  glow: (x, y) => { const d = Math.hypot(x - S / 2, y - S / 2) / (S / 2); return Math.max(0, 1 - d) ** 2; },
};
function clamp(v) { return Math.max(0, Math.min(1, v)); }
function pixels(fn) {
  const px = Buffer.alloc(S * S * 4);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    // 4x4 samples per pixel for smooth edges
    let a = 0;
    for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) a += fn(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4);
    const i = (y * S + x) * 4;
    px[i] = 255; px[i + 1] = 255; px[i + 2] = 255; px[i + 3] = Math.round(255 * a / 16);
  }
  return px;
}
function tga(px) {
  const h = Buffer.alloc(18);
  h[2] = 2; h.writeUInt16LE(S, 12); h.writeUInt16LE(S, 14); h[16] = 32; h[17] = 0x28;   // true colour, top-left origin, 8 alpha bits
  const body = Buffer.alloc(S * S * 4);
  for (let i = 0; i < S * S; i++) { body[i * 4] = px[i * 4 + 2]; body[i * 4 + 1] = px[i * 4 + 1]; body[i * 4 + 2] = px[i * 4]; body[i * 4 + 3] = px[i * 4 + 3]; }
  return Buffer.concat([h, body]);
}
function crc32(buf) { let c, crc = 0xffffffff; for (let n = 0; n < buf.length; n++) { c = (crc ^ buf[n]) & 0xff; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crc = (crc >>> 8) ^ c; } return (crc ^ 0xffffffff) >>> 0; }
function chunk(type, data) { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, crc]); }
function png(px) {
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4); ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc(S * (S * 4 + 1));
  for (let y = 0; y < S; y++) { raw[y * (S * 4 + 1)] = 0; px.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4); }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
fs.mkdirSync(path.join(ROOT, 'WarlockArcade', 'Media'), { recursive: true });
fs.mkdirSync(path.join(ROOT, 'web', 'media'), { recursive: true });
Object.keys(SHAPES).forEach(name => {
  const px = pixels(SHAPES[name]);
  fs.writeFileSync(path.join(ROOT, 'WarlockArcade', 'Media', name + '.tga'), tga(px));
  fs.writeFileSync(path.join(ROOT, 'web', 'media', name + '.png'), png(px));
});
console.log('Media: ' + Object.keys(SHAPES).join(', ') + ' (' + S + 'x' + S + ', .tga for the game, .png for the web)');
