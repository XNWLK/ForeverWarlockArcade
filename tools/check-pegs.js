// Plays Shadow Pegs with a bot that aims at a random orange peg, through the game's own shoot function, frame by frame.
// Fails on Lua errors, a bolt that never comes down (stuck for 30 s), "nil" on screen; reports the damage.
//   node tools/check-pegs.js [games=6]
const { boot } = require('./host.js');
const GAMES = +process.argv[2] || 6;
const host = boot();
host.run(`
local A = __ADDON_NS
local P = A.PegsRules
function PBOT()
  local g = A.games.pegs.obj
  if g.overlay:IsShown() then g.overlay.go:Click(); return 'overlay' end
  local s = g.s
  if s.ball then return 'flying' end
  local targets = {}
  for _, p in ipairs(s.pegs) do if p.kind == 'orange' and not p.gone then targets[#targets + 1] = p end end
  local p = targets[math.random(1, math.max(1, #targets))] or s.pegs[1]
  P.aimAt(s, p.x + (math.random() - 0.5) * 30, p.y)
  g:shoot()
  return 'shot'
end
function PINFO() local s = A.games.pegs.obj.s; return string.format('%.0f %d %d %s %d %d', s.score, s.level, s.balls, tostring(s.over), s.orangeHit, #s.pegs) end
`, '=pbot');
host.run('__ADDON_NS.open("pegs")');
const out = [], bad = new Set();
for (let i = 0; i < GAMES && !host.errors.length; i++) {
  host.run('math.randomseed(' + (40 + i) + ')');
  let flying = 0, overlays = 0;
  for (let t = 0; t < 2000 && !host.errors.length; t += 0.05) {
    const w = host.call('PBOT');
    if (w === 'overlay') { overlays++; if (overlays > 1 && host.call('PINFO').endsWith('false') === false) {} }
    flying = w === 'flying' ? flying + 0.05 : 0;
    if (flying > 30) { host.errors.push('a bolt was in the air for 30 s: ' + host.call('PINFO')); break; }
    host.advance(0.05, 0.025);
    if (Math.round(t * 20) % 100 === 0) for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) bad.add(n.parsed.plain);
    const info = String(host.call('PINFO')).split(' ');
    if (info[3] === 'true' && info[2] === '0' && overlays >= 1) { out.push(info); break; }
  }
}
if (host.errors.length) { console.log('FAIL: ' + host.errors.join('\n')); process.exit(1); }
if (bad.size) { console.log('FAIL: text the game would not show:\n  ' + [...bad].join('\n  ')); process.exit(1); }
console.log(out.length + ' games: bot damage ' + (out.reduce((a, r) => a + +r[0], 0) / Math.max(1, out.length)).toFixed(0) + ', level reached ' + (out.reduce((a, r) => a + +r[1], 0) / Math.max(1, out.length)).toFixed(1) + ', orange pegs hit ' + out.map(r => r[4] + '/16 of ' + r[5]).join(' '));
console.log('OK');
