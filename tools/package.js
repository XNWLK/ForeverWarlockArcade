// Packs the addon for the game: dist/WarlockArcade-<version>.zip with one folder, WarlockArcade/, inside (what the
// AddOns folder and CurseForge expect). Only the files the addon needs: the .toc, the files it lists, the media.
// Then reads the zip back and checks every file against the original.
//   node tools/package.js
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const ROOT = path.join(__dirname, '..'), ADDON = 'WarlockArcade';
const tocText = fs.readFileSync(path.join(ROOT, ADDON, ADDON + '.toc'), 'utf8');
const version = (/^## Version:\s*(\S+)/m.exec(tocText) || [])[1];
if (!version) throw new Error('no ## Version in the .toc');
const listed = tocText.replace(/\r/g, '').split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('#')).map(l => l.replace(/\\/g, '/'));
const media = fs.readdirSync(path.join(ROOT, ADDON, 'Media')).filter(f => /\.tga$/i.test(f)).map(f => 'Media/' + f);
const files = [ADDON + '.toc', ...listed, ...media];
for (const f of files) if (!fs.existsSync(path.join(ROOT, ADDON, f))) throw new Error('missing: ' + f);
// files in the folder that would not be shipped (a sign something is left out or left over)
const all = [];
(function walk(d, rel) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const r = rel ? rel + '/' + e.name : e.name; if (e.isDirectory()) walk(path.join(d, e.name), r); else all.push(r); } })(path.join(ROOT, ADDON), '');
const extra = all.filter(f => !files.includes(f));
if (extra.length) console.log('not packed (not in the .toc): ' + extra.join(', '));

const CRC = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc32 = b => { let c = -1; for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8); return (c ^ -1) >>> 0; };
// DOS time of the newest file (zips have no time zones; good enough for an archive date)
const when = new Date(Math.max(...files.map(f => fs.statSync(path.join(ROOT, ADDON, f)).mtimeMs)));
const dosTime = (when.getHours() << 11) | (when.getMinutes() << 5) | (when.getSeconds() >> 1);
const dosDate = ((when.getFullYear() - 1980) << 9) | ((when.getMonth() + 1) << 5) | when.getDate();
const parts = [], central = [];
let offset = 0;
const entries = [ADDON + '/', ...files.map(f => ADDON + '/' + f)];
// the folders too, so every unzip tool makes them
const dirs = new Set([ADDON + '/']);
for (const f of files) { const p = f.split('/'); for (let i = 1; i < p.length; i++) dirs.add(ADDON + '/' + p.slice(0, i).join('/') + '/'); }
for (const name of [...dirs, ...files.map(f => ADDON + '/' + f)]) {
  const isDir = name.endsWith('/');
  const data = isDir ? Buffer.alloc(0) : fs.readFileSync(path.join(ROOT, name));
  const packed = isDir ? data : zlib.deflateRawSync(data, { level: 9 });
  const method = isDir ? 0 : 8;
  const crc = crc32(data);
  const nameBuf = Buffer.from(name, 'utf8');
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0x0800, 6); local.writeUInt16LE(method, 8);
  local.writeUInt16LE(dosTime, 10); local.writeUInt16LE(dosDate, 12); local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(packed.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(nameBuf.length, 26); local.writeUInt16LE(0, 28);
  parts.push(local, nameBuf, packed);
  const cen = Buffer.alloc(46);
  cen.writeUInt32LE(0x02014b50, 0); cen.writeUInt16LE(20, 4); cen.writeUInt16LE(20, 6); cen.writeUInt16LE(0x0800, 8); cen.writeUInt16LE(method, 10);
  cen.writeUInt16LE(dosTime, 12); cen.writeUInt16LE(dosDate, 14); cen.writeUInt32LE(crc, 16); cen.writeUInt32LE(packed.length, 20);
  cen.writeUInt32LE(data.length, 24); cen.writeUInt16LE(nameBuf.length, 28); cen.writeUInt32LE(isDir ? 0x10 : 0, 38); cen.writeUInt32LE(offset, 42);
  central.push(cen, nameBuf);
  offset += 30 + nameBuf.length + packed.length;
}
const cenBuf = Buffer.concat(central);
const end = Buffer.alloc(22);
const count = dirs.size + files.length;
end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(count, 8); end.writeUInt16LE(count, 10); end.writeUInt32LE(cenBuf.length, 12); end.writeUInt32LE(offset, 16);
const zip = Buffer.concat([...parts, cenBuf, end]);
fs.mkdirSync(path.join(ROOT, 'dist'), { recursive: true });
const out = path.join(ROOT, 'dist', ADDON + '-' + version + '.zip');
fs.writeFileSync(out, zip);

// read it back: every entry unpacks to the very same bytes
const z = fs.readFileSync(out);
let at = z.readUInt32LE(z.length - 22 + 16), n = z.readUInt16LE(z.length - 22 + 10), ok = 0;
for (let i = 0; i < n; i++) {
  const name = z.toString('utf8', at + 46, at + 46 + z.readUInt16LE(at + 28));
  const lo = z.readUInt32LE(at + 42), size = z.readUInt32LE(at + 20), method = z.readUInt16LE(at + 10);
  const start = lo + 30 + z.readUInt16LE(lo + 26) + z.readUInt16LE(lo + 28);
  const raw = z.slice(start, start + size);
  const data = method === 8 ? zlib.inflateRawSync(raw) : raw;
  if (!name.endsWith('/')) {
    const orig = fs.readFileSync(path.join(ROOT, name));
    if (!orig.equals(data)) throw new Error('the zip differs for ' + name);
  }
  ok++;
  at += 46 + z.readUInt16LE(at + 28) + z.readUInt16LE(at + 30) + z.readUInt16LE(at + 32);
}
console.log('dist/' + path.basename(out) + ': ' + files.length + ' files (' + Math.round(zip.length / 1024) + ' KB), all ' + ok + ' entries read back the same');
