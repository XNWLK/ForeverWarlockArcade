// Draws the arcade's icon (for CurseForge and the page): a glowing soul shard in a closing ring, on a dark violet
// field with a fel-green light and sparks - the look of the games. Writes art/icon-512.png and art/icon-400.png.
//   node tools/gen-icon.js
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const ROOT = path.join(__dirname, '..');
const clamp = v => Math.max(0, Math.min(1, v));
const hex = h => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
const mix = (a, b, f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];

// the drawing, in a 400 x 400 space
const SHARD = [[200, 96], [252, 184], [223, 304], [177, 304], [148, 184]];
const SHINE = [[200, 96], [213, 184], [200, 304], [187, 184]];
const SHADE = [[252, 184], [148, 184], [200, 204]];
function inside(poly, x, y) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
  }
  return c;
}
function edgeDist(poly, x, y) {
  let d = 1e9;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [ax, ay] = poly[j], [bx, by] = poly[i];
    const vx = bx - ax, vy = by - ay, t = clamp(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy));
    d = Math.min(d, Math.hypot(x - ax - t * vx, y - ay - t * vy));
  }
  return d;
}
function star(x, y, cx, cy, s) {
  const dx = Math.abs(x - cx) / s, dy = Math.abs(y - cy) / s;
  return clamp(Math.max(0, 1 - (Math.sqrt(dx) + Math.sqrt(dy)) / 1.05) * 2.4 + Math.max(0, 1 - Math.hypot(dx, dy) * 3) ** 2);
}
const SPARKS = [[316, 92, 30, '#8CFF6A'], [88, 300, 20, '#D58BFF'], [324, 316, 15, '#D58BFF'], [94, 104, 13, '#8CFF6A'], [276, 60, 9, '#FFFFFF']];

// one sample: layers painted from the back to the front
function sample(x, y) {
  // the field: dark violet, lighter at the top left
  let c = mix(hex('#2A1442'), hex('#06030B'), clamp((x + y) / 800));
  const over = (col, a) => { a = clamp(a); c = mix(c, col, a); };
  const d = Math.hypot(x - 200, y - 200);
  over(hex('#9B5CFF'), 0.5 * Math.max(0, 1 - d / 190) ** 2);                                  // violet light in the middle
  over(hex('#4CFF3A'), 0.22 * Math.max(0, 1 - Math.hypot(x - 370, y - 380) / 230) ** 2);       // fel light, bottom right
  // the closing ring (outer, faint) and the ring (bright, with a glow)
  over(hex('#B48CFF'), 0.35 * clamp(2.5 - Math.abs(d - 166) + 0.5));
  over(hex('#C9A2FF'), 0.45 * Math.exp(-(((d - 132) / 12) ** 2)));
  over(mix(hex('#E2CCFF'), hex('#8CFF6A'), clamp((y - 80) / 260) * 0.55), clamp(5 - Math.abs(d - 132) + 0.5));
  // the shard: a glow behind it, the crystal with a gradient, its facets and outline
  over(hex('#C050FF'), 0.6 * Math.max(0, 1 - Math.hypot(x - 200, y - 205) / 125) ** 1.6);
  if (inside(SHARD, x, y)) {
    const f = clamp(((x - 148) + (y - 96)) / 300);
    c = f < 0.45 ? mix(hex('#F4DCFF'), hex('#A855F0'), f / 0.45) : mix(hex('#A855F0'), hex('#3A0F66'), (f - 0.45) / 0.55);
    if (inside(SHINE, x, y)) over([1, 1, 1], 0.3);
    if (inside(SHADE, x, y)) over(hex('#1D0833'), 0.28);
  }
  const e = edgeDist(SHARD, x, y);
  over(hex('#1B0731'), clamp(3 - e + 0.5));
  // sparks
  for (const [sx, sy, s, col] of SPARKS) over(hex(col), star(x, y, sx, sy, s));
  return c;
}

function render(size) {
  const px = Buffer.alloc(size * size * 4), k = 400 / size, N = 4;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let r = 0, g = 0, b = 0;
    for (let sy = 0; sy < N; sy++) for (let sx = 0; sx < N; sx++) {
      const c = sample((x + (sx + 0.5) / N) * k, (y + (sy + 0.5) / N) * k);
      r += c[0]; g += c[1]; b += c[2];
    }
    const i = (y * size + x) * 4;
    px[i] = Math.round(255 * r / N / N); px[i + 1] = Math.round(255 * g / N / N); px[i + 2] = Math.round(255 * b / N / N); px[i + 3] = 255;
  }
  return px;
}
function crc32(buf) { let c, crc = 0xffffffff; for (let n = 0; n < buf.length; n++) { c = (crc ^ buf[n]) & 0xff; for (let j = 0; j < 8; j++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crc = (crc >>> 8) ^ c; } return (crc ^ 0xffffffff) >>> 0; }
function chunk(type, data) { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, crc]); }
function png(px, size) {
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) { raw[y * (size * 4 + 1)] = 0; px.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4); }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}
for (const size of [512, 400]) {
  const out = path.join(ROOT, 'art', 'icon-' + size + '.png');
  fs.writeFileSync(out, png(render(size), size));
  console.log('art/icon-' + size + '.png');
}
