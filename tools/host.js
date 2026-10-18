// Runs the addon outside the game and outside the browser: web/wow-core.js + web/wow.lua in fengari under Node, the
// same code the web page runs, without drawing. For the checks in tools/.
const fs = require('fs'), path = require('path');
const fengari = require('fengari');
const { WowHost } = require('../web/wow-core.js');
const ROOT = path.join(__dirname, '..'), ADDON = 'WarlockArcade';

// rough text size: the web page measures with the real fonts; here ~0.52 of the size per letter (Friz Quadrata)
function measure(plain, font, wrapWidth) {
  const per = font.size * (/ARIALN/i.test(font.path) ? 0.46 : 0.55);
  const lines = [];
  String(plain).split('\n').forEach(par => {
    if (!wrapWidth) { lines.push(par.length * per); return; }
    let cur = 0;
    par.split(/\s+/).forEach(w => {
      const ww = w.length * per, sp = cur ? per : 0;
      if (cur && cur + sp + ww > wrapWidth) { lines.push(cur); cur = ww; } else cur += sp + ww;
    });
    lines.push(cur);
  });
  return { w: Math.ceil(Math.max(0, ...lines)), h: Math.ceil(lines.length * font.size * 1.15), lines: lines.length };
}

function toc() {
  const src = fs.readFileSync(path.join(ROOT, ADDON, ADDON + '.toc'), 'utf8').replace(/\r/g, '');
  const meta = {}, files = [];
  src.split('\n').forEach(l => {
    const m = /^##\s*([^:]+):\s*(.*)$/.exec(l);
    if (m) meta[m[1].trim()] = m[2].trim();
    else if (l.trim() && !l.startsWith('#')) files.push(l.trim());
  });
  return { meta, files };
}

// web: true = like the web page (WOW_WEB), false = like the game
function boot(opts) {
  opts = opts || {};
  let clock = 0;
  const store = opts.storage || {};
  const host = new WowHost({
    fengari, measure, now: () => clock,
    storage: { get: k => store[k] || null, set: (k, v) => { store[k] = v; } },
    onError: opts.quiet ? null : (m => console.log('LUA ERROR: ' + m)),
    meta: {},
  });
  host.resize(opts.width || 1365, 768);
  const t = toc();
  host.o.meta = t.meta;
  if (opts.web !== false) host.run('WOW_WEB = true', '=web');
  if (opts.prelude) host.run(opts.prelude, '=prelude');
  host.boot(ADDON, t.files, (t.meta.SavedVariables || '').split(',').map(s => s.trim()).filter(Boolean),
    p => fs.readFileSync(path.join(ROOT, p), 'utf8'));
  host.advance = (sec, step) => { step = step || 1 / 30; for (let t = 0; t < sec; t += step) { clock += step; host.tick(step); } };
  host.store = store;
  return host;
}
module.exports = { boot, measure, ROOT, ADDON };
