// Type to Cast: a bot types the falling words (lowest first, a letter every 0.1 s) at every speed; then an idle
// player (three words reach the ground: the fight ends early), wrong letters, running out of mana (the spell fizzles),
// and damage-over-time spells being worth less late in the fight. Through the game's own key handler.
//   node tools/check-typing.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local Y = A.TypingRules
function TPLAY(speed, every)
  local g = A.games.typing.obj
  g.speedIndex = speed
  g:play()
  local s = g.s
  local step, acc, guard = 1 / 60, 0, 0
  while not s.done and guard < 20000 do
    guard = guard + 1
    acc = acc + step
    if every and acc >= every then
      acc = 0
      local w = s.target
      if not w then for _, x in ipairs(s.words) do if not w or x.y < w.y then w = x end end end
      if w then g:OnKey(w.letters:sub(w.pos + 1, w.pos + 1)) end
    end
    g:OnUpdate(step)
  end
  return string.format('%.0f %d %d %d %.1f %d', s.damage, s.cast, s.lives, s.wrong, s.t, s.maxCombo)
end
function TRULES()
  local out = {}
  out[#out + 1] = (Y.damage('corruption', 60) > Y.damage('corruption', 5)) and 'dot ok' or 'dot BAD'
  out[#out + 1] = (math.abs(Y.damage('shadowBolt', 1) - Y.damage('shadowBolt', 60)) < 0.01) and 'direct ok' or 'direct BAD'
  local s = Y.new(2, 5)
  local w = Y.spawn(s)
  s.mana = 0
  for c in w.letters:gmatch('.') do Y.type(s, c) end
  out[#out + 1] = (w.key == 'lifeTap' and s.mana > 0 or s.damage == 0) and 'oom ok' or 'oom BAD'
  Y.type(s, 'Q'); Y.type(s, 'Q')
  out[#out + 1] = s.wrong == 2 and 'wrong ok' or ('wrong BAD ' .. s.wrong)
  return table.concat(out, ' ')
end
`, '=tbot');
host.run('__ADDON_NS.open("typing")');
let fail = '';
for (let sp = 1; sp <= 3 && !host.errors.length; sp++) {
  host.run('math.randomseed(' + sp + ')');
  const [dmg, cast, lives, wrong, t, combo] = String(host.call('TPLAY', sp, 0.1)).split(' ').map(Number);
  console.log('speed ' + sp + ': typist ' + Math.round(dmg / 60) + ' DPS, ' + cast + ' spells, lives left ' + lives + ', wrong ' + wrong + ', best combo ' + combo);
  if (!(dmg > 0 && cast > 10 && t >= 60 && wrong === 0)) fail += 'speed ' + sp + ': typist ' + [dmg, cast, lives, wrong, t].join(' ') + '\n';
}
const idle = String(host.call('TPLAY', 2, null)).split(' ').map(Number);
console.log('idle: lives ' + idle[2] + ', the fight ended at ' + idle[4] + ' s');
if (!(idle[2] === 0 && idle[4] < 60)) fail += 'idle player: ' + idle.join(' ') + '\n';
const rules = String(host.call('TRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += 'rules: ' + rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
