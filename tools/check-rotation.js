// Perfect Rotation: for every puzzle, the search's target must beat a simple priority rotation and thousands of
// random orders (if random play beats the search, the search is too weak); DoT ticks after the fight and clipped
// ticks must not count. Then plays the target order through the real spell buttons (3 stars), checks Undo, a spell
// refused for lack of mana, and nothing added after the fight is over. Times the search.
//   node tools/check-rotation.js [random tries per puzzle=3000]
const { boot } = require('./host.js');
const TRIES = +process.argv[2] || 3000;
const host = boot();
host.run(`
local A = __ADDON_NS
local P = A.RotationRules
function RBEST(level)
  local t0 = os.clock()
  local d, seq = P.best(level)
  local seqS = {}
  for k in P.PUZZLES[level].best:gmatch('%a+') do seqS[#seqS + 1] = k end
  local s = P.run(level, seqS)
  return string.format('%.1f %.2f %d %.1f %s', d, os.clock() - t0, #seq, s.dmg, tostring(P.over(s)))
end
-- a priority rotation: Agony, Corruption, Immolate when they are off, Shadow Bolt, Life Tap when short of mana
function RGREEDY(level)
  local s = P.start(level)
  local up = {}
  while not P.over(s) do
    local pick
    for _, k in ipairs({ 'baneOfAgony', 'corruption', 'immolate' }) do
      local l = s.ticks[k]
      local last = l and l[#l] or -1
      if not pick and last <= s.t and P.can(s, k) and s.len - s.t > 6 then pick = k end
    end
    if not pick then pick = P.can(s, 'shadowBolt') and 'shadowBolt' or 'lifeTap' end
    s = P.cast(s, pick)
  end
  return string.format('%.1f', s.dmg)
end
function RRANDOM(level, n)
  local best = 0
  for i = 1, n do
    local s = P.start(level)
    while not P.over(s) do
      local k = P.SPELLS[math.random(1, #P.SPELLS)]
      local x = P.cast(s, k)
      if x then s = x end
    end
    if s.dmg > best then best = s.dmg end
  end
  return string.format('%.1f', best)
end
function RRULES()
  local out = {}
  -- Corruption cast 2 s before the end of a 12 s fight at 10 s: no tick lands
  local s = P.start(1)
  for i = 1, 6 do s = P.cast(s, 'lifeTap') end
  local before = s.dmg
  s = P.cast(s, 'corruption')
  out[#out + 1] = (s and s.dmg == before) and 'late dot ok' or 'late dot BAD'
  -- Agony twice in a row: the first one's ticks after the second are lost
  local a = P.cast(P.start(4), 'baneOfAgony')
  local b = P.cast(a, 'baneOfAgony')
  out[#out + 1] = (b.clipped > 0 and b.dmg < a.dmg + 12 * A.CAST.baneOfAgony.tick) and 'clip ok' or 'clip BAD'
  -- 300 mana: no Shadow Bolt
  out[#out + 1] = (not P.can(P.start(5), 'shadowBolt')) and 'mana ok' or 'mana BAD'
  return table.concat(out, ' ')
end
function CLICK(b)
  local top = __web.topAt(b.__id)
  if top ~= b.__id then error('button covered by another frame', 2) end
  b:Click()
end
function RPLAY(level)
  local g = A.games.rotation.obj
  g:open(level)
  local t = g:target()
  local function btn(key) for _, b in ipairs(g.spellBtns) do if b.key == key then return b end end end
  -- one wrong spell and Undo first
  CLICK(btn('lifeTap')); CLICK(g.undoBtn)
  local undoOk = #g.seq == 0
  for _, k in ipairs(t.seq) do CLICK(btn(k)) end
  local n = #g.seq
  CLICK(btn('lifeTap'))
  local after = #g.seq == n
  return string.format('%s %s %d %s %.1f %.1f', tostring(undoOk), tostring(after), (A.db('rotation').stars or {})[level] or 0, g.msg:GetText(), g.s.dmg, t.dmg)
end
`, '=rbot');
host.run('__ADDON_NS.open("rotation")'); host.layout();
let fail = '';
const P = 6;
for (let lv = 1; lv <= P && !host.errors.length; lv++) {
  const [target, secs, casts, stored, storedOver] = String(host.call('RBEST', lv)).split(' ');
  if (storedOver !== 'true' || Math.abs(+stored - +target) > 0.5) fail += 'puzzle ' + lv + ': the stored best order (' + stored + ') is not what the search finds now (' + target + ') - store the new one\n';
  const greedy = +host.call('RGREEDY', lv);
  host.run('math.randomseed(' + lv + ')');
  const rnd = +host.call('RRANDOM', lv, TRIES);
  console.log('puzzle ' + lv + ': target ' + Math.round(target) + ' (' + casts + ' casts, searched in ' + (+secs).toFixed(2) + ' s; stored ' + Math.round(stored) + '), priority rotation ' + Math.round(greedy) + ' (' + (100 * greedy / target).toFixed(1) + '%), best of ' + TRIES + ' random ' + Math.round(rnd) + ' (' + (100 * rnd / target).toFixed(1) + '%)');
  if (greedy > target + 0.5) fail += 'puzzle ' + lv + ': the priority rotation beats the search\n';
  if (rnd > target + 0.5) fail += 'puzzle ' + lv + ': random play beats the search\n';
  const play = String(host.call('RPLAY', lv)).split(' ');
  if (play[0] !== 'true') fail += 'puzzle ' + lv + ': Undo did not take the spell back\n';
  if (play[1] !== 'true') fail += 'puzzle ' + lv + ': a spell was added after the fight\n';
  if (play[2] !== '3') fail += 'puzzle ' + lv + ': playing the target order gave ' + play[2] + ' stars: ' + play.slice(3).join(' ') + '\n';
}
const rules = String(host.call('RRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += 'rules: ' + rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
