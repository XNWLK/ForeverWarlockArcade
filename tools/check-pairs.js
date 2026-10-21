// Grimoire Pairs: every board holds each picture exactly twice (no two pictures alike); a player who knows where every
// pair is finishes in exactly as many turns as there are pairs; a player with a perfect memory (turns unknown cards,
// remembers them) finishes every size; a miss turns back by itself; the best is kept. Clicks the real cards.
//   node tools/check-pairs.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local P = A.PairsRules
function CLICK(b) local top = __web.topAt(b.__id); if top ~= b.__id then error('card covered', 2) end; b:Click() end
function PBOARD()
  local bad = 0
  for size = 1, 3 do for seed = 1, 30 do
    local s = P.new(size, seed)
    local count = {}
    for _, c in ipairs(s.cards) do count[c.pic] = (count[c.pic] or 0) + 1 end
    for _, n in pairs(count) do if n ~= 2 then bad = bad + 1 end end
  end end
  return bad
end
function PPLAY(size, cheat)
  local g = A.games.pairs.obj
  g.size = size
  g:newGame()
  local s = g.s
  local seen, missBack = {}, 'none'
  local guard = 0
  local function wait(t) for i = 1, math.floor(t * 30) do g:OnUpdate(1 / 30); __ADDON_NS.Kit.tick(1 / 30) end end
  while not s.done and guard < 500 do
    guard = guard + 1
    local first, second
    if cheat then
      for i, c in ipairs(s.cards) do if not c.found then first = i; break end end
      for i, c in ipairs(s.cards) do if i ~= first and c.pic == s.cards[first].pic then second = i end end
    else
      -- a known pair not found yet; else the first unknown card, and its partner if known
      for i, c in ipairs(s.cards) do
        if not c.found and seen[i] then for j, d in ipairs(s.cards) do if j ~= i and not d.found and seen[j] and d.pic == c.pic then first, second = i, j end end end
        if first then break end
      end
      if not first then
        for i, c in ipairs(s.cards) do if not c.found and not seen[i] then first = i; break end end
      end
    end
    CLICK(g.views[first]); seen[first] = true
    if not second then
      for j, d in ipairs(s.cards) do if j ~= first and not d.found and seen[j] and d.pic == s.cards[first].pic then second = j end end
      if not second then for j, d in ipairs(s.cards) do if j ~= first and not d.found and not seen[j] then second = j; break end end end
    end
    CLICK(g.views[second]); seen[second] = true
    if #s.open == 2 and missBack == 'none' then wait(1.2); missBack = (#s.open == 0) and 'ok' or 'stuck' end
    wait(0.3)
  end
  local b = A.db('pairs').best and A.db('pairs').best[size]
  return string.format('%s %d %d %s %s', tostring(s.done), s.turns, s.pairs, missBack, b and tostring(b.turns) or 'none')
end
`, '=pbot');
host.run('__ADDON_NS.open("pairs")'); host.layout();
let fail = '';
const bad = +host.call('PBOARD');
if (bad) fail += bad + ' pictures not exactly twice\n';
for (let size = 1; size <= 3 && !host.errors.length; size++) {
  const c = String(host.call('PPLAY', size, true)).split(' ');
  if (c[0] !== 'true' || c[1] !== c[2]) fail += 'size ' + size + ': knowing every pair took ' + c[1] + ' turns for ' + c[2] + ' pairs\n';
  host.run('math.randomseed(' + size + ')');
  const m = String(host.call('PPLAY', size, false)).split(' ');
  console.log('size ' + size + ': ' + m[2] + ' pairs, perfect memory ' + m[1] + ' turns, a miss turned back: ' + m[3] + ', best kept: ' + m[4]);
  if (m[0] !== 'true') fail += 'size ' + size + ': the memory bot did not finish\n';
  if (m[3] !== 'ok') fail += 'size ' + size + ': a miss did not turn back (' + m[3] + ')\n';
  if (m[4] !== c[1]) fail += 'size ' + size + ': best should be the fewest turns (' + c[1] + '), is ' + m[4] + '\n';
}
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
