// Spell Lock!: a bot that always stops the most dangerous cast (late in it, when Spell Lock is ready) survives the fight;
// a player who does nothing goes down; locking with Spell Lock on cooldown does nothing; a lock late in a cast is worth
// more than an early one; casts that get through hit for the spell's real damage. Through the game's key handler.
//   node tools/check-spelllock.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local L = A.SpellLockRules
function LPLAY(bot)
  local g = A.games.spelllock.obj
  g:play()
  local s = g.s
  local guard = 0
  while not s.done and guard < 20000 do
    guard = guard + 1
    if bot and s.cd <= 0 then
      -- the cast that hurts most among those about to finish
      local pick, worst
      for i, f in ipairs(s.foes) do
        if f.key and f.at / f.len > 0.6 then local d = L.damage(f.key); if not worst or d > worst then pick, worst = i, d end end
      end
      if pick then g:OnKey(tostring(pick)) end
    end
    g:OnUpdate(1 / 30)
  end
  return string.format('%s %d %d %d %.0f %.1f', tostring(s.won), s.score, s.locks, s.hits, s.hp, s.t)
end
function LRULES()
  local out = {}
  local s = L.new(3)
  s.foes[1].key, s.foes[1].len, s.foes[1].at = 'shadowBolt', 3, 0.3
  s.foes[2].key, s.foes[2].len, s.foes[2].at = 'shadowBolt', 3, 2.7
  local early = L.lock(s, 1)
  local blocked = L.lock(s, 2)
  s.cd = 0
  local late = L.lock(s, 2)
  out[#out + 1] = (blocked == nil and late > early) and 'points ok' or ('points BAD ' .. tostring(early) .. ' ' .. tostring(late))
  local t = L.new(4)
  for i = 1, 4 do t.foes[i].wait = 99 end
  t.foes[1].key, t.foes[1].len, t.foes[1].at = 'soulFire', 6, 5.99
  local hp = t.hp
  L.update(t, 0.02)
  out[#out + 1] = (math.abs((hp - t.hp) - L.damage('soulFire')) < 0.01) and 'damage ok' or 'damage BAD'   -- at full health the healing adds nothing
  return table.concat(out, ' ')
end
`, '=lbot');
host.run('__ADDON_NS.open("spelllock")');
let fail = '';
const wins = [];
for (let i = 1; i <= 4 && !host.errors.length; i++) {
  host.run('math.randomseed(' + i + ')');
  const r = String(host.call('LPLAY', true)).split(' ');
  wins.push(r[0]);
  console.log('bot ' + i + ': ' + (r[0] === 'true' ? 'survived' : 'went down at ' + r[5] + ' s') + ', ' + r[1] + ' points, ' + r[2] + ' stopped, ' + r[3] + ' got through, health left ' + r[4]);
}
if (wins.filter(w => w === 'true').length < 2) fail += 'the bot went down too often\n';
const idle = String(host.call('LPLAY', false)).split(' ');
console.log('no locks: down at ' + idle[5] + ' s');
if (idle[0] !== 'false') fail += 'a player who does nothing survived\n';
const rules = String(host.call('LRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
