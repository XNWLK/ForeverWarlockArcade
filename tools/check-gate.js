// Demon Gate: a bot builds towers on the squares that cover the most road (clicking the board like the mouse), upgrades
// with spare gold and starts every wave; it must hold at least ten waves. Also: gold never below zero, no tower on the
// road, selling gives 60% back, enemies stay on the road, a champion at the gate costs five lives, towers hit with the
// spells' real damage.
//   node tools/check-gate.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local D = A.GateRules
local old = GetCursorPosition
function GetCursorPosition() if __CURX then return __CURX, __CURY end; return old() end
local function clickCell(g, c, r, button)
  local sc = g.board:GetEffectiveScale()
  __CURX, __CURY = (g.board:GetLeft() + 8 + (c + 0.5) * D.CELL) * sc, (g.board:GetTop() - 8 - (r + 0.5) * D.CELL) * sc
  g:click(button or 'LeftButton')
end
-- every free square, by how many road squares its tower would reach
local function spots(s, range)
  local road, list = D.roadCells(), {}
  for r = 0, D.ROWS - 1 do for c = 0, D.COLS - 1 do
    if not road[r * 100 + c] and not D.towerAt(s, c, r) then
      local n = 0
      for k in pairs(road) do local rc, rr = k % 100, math.floor(k / 100); if (rc - c) ^ 2 + (rr - r) ^ 2 <= range * range then n = n + 1 end end
      list[#list + 1] = { c, r, n }
    end
  end end
  table.sort(list, function(a, b) return a[3] > b[3] end)
  return list
end
function GPLAY()
  local g = A.games.gate.obj
  g:newGame()
  local s = g.s
  local minGold, offRoad, plan = 0, 0, { 1, 1, 2, 3, 4, 1, 5, 6, 2, 4, 5, 2, 3, 5, 2, 4, 5, 5 }
  local built = 0
  local guard = 0
  while not s.done and guard < 100 do
    guard = guard + 1
    -- spend: the next tower of the plan on its best square, else upgrade the cheapest
    for k = 1, 6 do
      local kind = plan[(built % #plan) + 1]
      if s.gold >= D.TOWERS[kind].cost then
        local sp = spots(s, D.TOWERS[kind].range)[1]
        if sp then g.pick = kind; clickCell(g, sp[1], sp[2]); built = built + 1 end
      else
        local best
        for _, t in ipairs(s.towers) do local c = D.upgradeCost(t); if c and s.gold >= c + 60 and (not best or c < D.upgradeCost(best)) then best = t end end
        if best then g.sel = best; g:upgrade() end
      end
    end
    g:OnKey('SPACE')
    local inner = 0
    while s.running and not s.done and inner < 40000 do
      inner = inner + 1
      g:OnUpdate(1 / 30)
      if s.gold < minGold then minGold = s.gold end
      for _, e in ipairs(s.enemies) do local x, y = D.at(e.d); if x < -D.CELL or x > D.COLS * D.CELL + D.CELL or y < 0 or y > D.ROWS * D.CELL then offRoad = offRoad + 1 end end
    end
  end
  return string.format('%s %d %d %d %d %.0f %d', tostring(s.won), s.wave, s.lives, #s.towers, minGold, s.dealt, offRoad)
end
function GRULES()
  local out = {}
  local s = D.new()
  local road = D.ROAD[2]
  out[#out + 1] = (D.build(s, 1, road[1], road[2]) == nil) and 'road ok' or 'road BAD'
  local t = D.build(s, 2, 0, 0)
  local gold = s.gold
  local back = D.sell(s, t)
  out[#out + 1] = (back == math.floor(D.TOWERS[2].cost * 0.6) and s.gold == gold + back) and 'sell ok' or 'sell BAD'
  local u = D.new()
  u.wave = 5
  u.enemies = { { id = 1, kind = 'champion', d = D.TOTAL - 1, hp = 100, max = 100, dots = {} } }
  D.update(u, 0.1)
  out[#out + 1] = (u.lives == D.LIVES - 5) and 'champion ok' or ('champion BAD ' .. u.lives)
  -- a Shadow Bolt tower hits for Shadow Bolt's real damage
  local v = D.new()
  v.wave = 1
  local sb = D.build(v, 2, 3, 1)
  v.enemies = { { id = 1, kind = 'footman', d = 90, hp = 5000, max = 5000, dots = {} } }
  D.update(v, 0.01)
  local want = A.CAST.shadowBolt.direct * (1 + A.CHARACTER.critPct / 100 * (A.CHARACTER.critMult - 1))
  out[#out + 1] = (math.abs((5000 - v.enemies[1].hp) - want) < 0.5) and 'damage ok' or ('damage BAD ' .. (5000 - v.enemies[1].hp) .. ' ' .. want)
  return table.concat(out, ' ')
end
`, '=gbot');
host.run('__ADDON_NS.open("gate")'); host.layout();
let fail = '';
for (let i = 1; i <= 2 && !host.errors.length; i++) {
  host.run('math.randomseed(' + i + ')');
  const [won, wave, lives, towers, minGold, dealt, off] = String(host.call('GPLAY')).split(' ');
  console.log('bot ' + i + ': ' + (won === 'true' ? 'held all 15 waves' : 'fell in wave ' + wave) + ', ' + lives + ' lives left, ' + towers + ' towers, ' + dealt + ' damage');
  if (won !== 'true' && +wave < 10) fail += 'bot ' + i + ': fell in wave ' + wave + '\n';
  if (+minGold < 0) fail += 'gold went below zero\n';
  if (+off) fail += off + ' times an enemy was off the road\n';
}
const rules = String(host.call('GRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
