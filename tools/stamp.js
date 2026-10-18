// Writes web/build.txt: a fingerprint of every file the web page loads (web/*.js, web/wow.lua, the addon). The page
// reads it fresh on every visit and adds it to each file it asks for, so a browser never mixes an old cached file
// with new ones after an update. Run before every commit that changes the page or the addon (check-all.js checks it).
//   node tools/stamp.js          writes it
//   node tools/stamp.js --check  only says whether it is up to date (exit 1 if not)
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const ROOT = path.join(__dirname, '..');
function files(dir) {
  return fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true }).flatMap(e => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? files(p) : [p];
  });
}
const list = files('web').filter(f => !/build\.txt$/.test(f)).concat(files('WarlockArcade')).sort();
const h = crypto.createHash('sha1');
list.forEach(f => { h.update(f.replace(/\\/g, '/')); h.update(fs.readFileSync(path.join(ROOT, f))); });
const stamp = h.digest('hex').slice(0, 12);
const file = path.join(ROOT, 'web', 'build.txt');
const old = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').trim() : '';
if (process.argv.includes('--check')) {
  if (old !== stamp) { console.log('FAIL: web/build.txt is out of date (' + old + ' vs ' + stamp + ') - run node tools/stamp.js'); process.exit(1); }
  console.log('OK: web/build.txt = ' + stamp);
} else {
  fs.writeFileSync(file, stamp + '\n');
  console.log('web/build.txt = ' + stamp + ' (' + list.length + ' files)');
}
