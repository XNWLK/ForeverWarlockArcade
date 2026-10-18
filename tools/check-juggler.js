// Plays DoT Juggler rounds with a simple bot (refresh whatever runs out soonest, Life Tap when low) through the game's
// own cast function, frame by frame. Fails on Lua errors, "nil" and raw long decimals on screen (timers show one
// decimal on purpose, so "15.0" is fine here); reports the DPS.
//   node tools/check-juggler.js [rounds=10]
const { boot } = require('./host.js');
const ROUNDS = +process.argv[2] || 10;
const host = boot();
host.run(`
local A = __ADDON_NS
local J = A.JugglerRules
function JBOT()
  local g = A.games.juggler.obj
  local s = g.s
  if not s or s.over or not J.ready(s) then return end
  if s.mana < 450 and s.health > A.CHARACTER.tapHealth then g:castOn('lifeTap'); return end
  local best, bestLeft, bestSlot
  for _, d in ipairs(s.dummies) do
    if d.alive and d.hp > 400 then
      for _, key in ipairs(J.SPELLS) do
        local dot = d.dots[key]
        local left = dot and (dot.ends - s.t) or -1
        if left < A.CAST[key].every * 0.9 and (not bestLeft or left < bestLeft) and s.mana >= A.CAST[key].cost then best, bestLeft, bestSlot = key, left, d.slot end
      end
    end
  end
  if best then g:castOn(best, bestSlot) end
end
function JRESULT() local s = A.games.juggler.obj.s; return string.format('%.0f %.0f %d %d %d %d', J.dps(s), s.damage, s.kills, s.clipped, s.fell, s.taps) end
`, '=jbot');
host.run('__ADDON_NS.open("juggler")');
const bad = new Set(), out = [];
for (let r = 0; r < ROUNDS && !host.errors.length; r++) {
  host.run('math.randomseed(' + (500 + r) + '); __ADDON_NS.games.juggler.obj:start()');
  for (let t = 0; t < 92 && !host.errors.length; t += 0.1) {
    host.run('JBOT()');
    host.advance(0.1, 0.05);
    if (Math.round(t * 10) % 25 === 0) for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && (/\d\.\d{4,}/.test(n.parsed.plain) || /\bnil\b/.test(n.parsed.plain))) bad.add(n.parsed.plain);
  }
  out.push(host.call('JRESULT').split(' ').map(Number));
}
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
const avg = i => out.reduce((a, r) => a + r[i], 0) / out.length;
console.log(out.length + ' rounds: bot DPS ' + avg(0).toFixed(0) + ' (damage ' + avg(1).toFixed(0) + ', destroyed ' + avg(2).toFixed(1) +
  ', clipped ticks ' + avg(3).toFixed(1) + ', fell off ' + avg(4).toFixed(1) + ', Life Taps ' + avg(5).toFixed(1) + ')');
if (bad.size) { console.log('FAIL: text the game would not show:\n  ' + [...bad].slice(0, 10).join('\n  ')); process.exit(1); }
console.log('OK');
