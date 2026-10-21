// Spell Gems: a bot plays whole games through the board (mouse clicks on cells, the way a player does), always taking
// the move that clears the most. Checks: boards start with no match and a move, a swap without a match is refused and
// costs nothing, damage is the gems' real numbers, specials get made and go off, no gem is ever lost (64 on the
// board after every step), bosses fall, games end, no Lua errors.
//   node tools/check-gems.js [games=6]
const { boot } = require('./host.js');
const GAMES = +process.argv[2] || 6;
const host = boot();
host.run(`
local A = __ADDON_NS
local M = A.GemsRules
local made = {}
function GSTART(seed)
  local s = M.new(seed)
  local runs = #M.runs(s.grid)
  local a = M.findMove(s)
  return runs .. ' ' .. (a and 'move' or 'none')
end
-- the move that clears most (tried on a copy), else the first one
local function best(s)
  local bestA, bestB, bestN
  for r = 1, M.N do for c = 1, M.N do
    for _, d in ipairs({ { 0, 1 }, { 1, 0 } }) do
      local a, b = { r, c }, { r + d[1], c + d[2] }
      if b[1] <= M.N and b[2] <= M.N and M.valid(s, a, b) then
        local g = s.grid
        local x, y = g[a[1]][a[2]], g[b[1]][b[2]]
        g[a[1]][a[2]], g[b[1]][b[2]] = y, x
        local n = 0
        for _, run in ipairs(M.runs(g)) do n = n + #run.cells end
        if x.sp == 'bomb' or y.sp == 'bomb' then n = n + 20 end
        g[a[1]][a[2]], g[b[1]][b[2]] = x, y
        if not bestN or n > bestN then bestA, bestB, bestN = a, b, n end
      end
    end
  end end
  return bestA, bestB
end
local function count(g) local n = 0; for r = 1, M.N do for c = 1, M.N do if g[r][c] then n = n + 1 end end end; return n end
function GCLICK(g, rc)
  local x, y = g:cellPos(rc[1], rc[2])
  local l, t = g.board:GetLeft(), g.board:GetTop()
  local sc = g.board:GetEffectiveScale()
  __webCursor((l + x) * sc, (t + y) * sc)
  g:down(); g:up()
end
function GPLAY()
  local g = A.games.gems.obj
  g:newGame()
  local s = g.s
  local moves, lost, refused, specials, fired = 0, 0, 0, {}, 0
  -- a swap that does nothing: find two neighbours that make no match
  for r = 1, M.N do for c = 1, M.N - 1 do
    if not M.valid(s, { r, c }, { r, c + 1 }) and refused == 0 then
      local before = s.moves
      GCLICK(g, { r, c }); GCLICK(g, { r, c + 1 })
      refused = (s.moves == before and not g.busy) and 1 or -1
    end
  end end
  local guard = 0
  while not s.done and guard < 400 do
    guard = guard + 1
    local a, b = best(s)
    if not a then break end
    local had = {}
    for r = 1, M.N do for c = 1, M.N do local x = s.grid[r][c]; if x.sp then had[x.id] = x.sp end end end
    GCLICK(g, a); GCLICK(g, b)
    moves = moves + 1
    for _, st in ipairs(g.queue) do
      if count(st.grid) ~= M.N * M.N then lost = lost + 1 end
      for _, sp in pairs(st.made or {}) do specials[sp] = (specials[sp] or 0) + 1 end
      for id in pairs(st.cleared or {}) do if had[id] then fired = fired + 1 end end
    end
    while g.busy do g:OnUpdate(0.05) end
  end
  local sp = {}
  for k, v in pairs(specials) do sp[#sp + 1] = k .. '=' .. v end
  table.sort(sp)
  return string.format('%d %d %d %d %.0f %d %s', moves, s.level, lost, refused, s.total, fired, table.concat(sp, ','))
end
function GDMG() return string.format('%.1f %.1f %d', M.castDamage('shadowBolt'), M.gemDamage(1) * 3, M.gemDamage(M.TAP)) end
`, '=gbot');
let fail = '';
// the bot points the cursor where it clicks
host.run(`function __webCursor(x, y) __CURX, __CURY = x, y end`);
host.run(`local old = GetCursorPosition; function GetCursorPosition() if __CURX then return __CURX, __CURY end; return old() end`);
for (let i = 1; i <= 30; i++) { const st = String(host.call('GSTART', i)); if (st !== '0 move') fail += 'board ' + i + ' starts with ' + st + '\n'; }
const [sb, three, tap] = String(host.call('GDMG')).split(' ').map(Number);
if (Math.abs(sb - three) > 0.1 || tap !== 0) fail += 'gem damage: ' + [sb, three, tap].join(' ') + '\n';
host.run('__ADDON_NS.open("gems")'); host.layout();
let specials = {}, bosses = 0, fired = 0;
for (let i = 1; i <= GAMES && !host.errors.length; i++) {
  host.run('math.randomseed(' + i + ')');
  const out = String(host.call('GPLAY')).split(' ');
  const [moves, level, lost, refused, total, f] = out.map(Number);
  for (const x of (out[6] || '').split(',').filter(Boolean)) { const [k, v] = x.split('='); specials[k] = (specials[k] || 0) + +v; }
  bosses += level - 1; fired += f;
  console.log('game ' + i + ': ' + moves + ' moves, reached boss ' + level + ', ' + Math.round(total) + ' damage');
  if (lost) fail += 'game ' + i + ': gems lost in ' + lost + ' steps\n';
  if (refused !== 1) fail += 'game ' + i + ': a swap without a match was not refused cleanly\n';
}
console.log('specials made: ' + JSON.stringify(specials) + ', set off: ' + fired + ', bosses beaten: ' + bosses);
if (!specials.row && !specials.col) fail += 'no line gem was ever made\n';
if (!fired) fail += 'no special ever went off\n';
if (!bosses) fail += 'the bot never beat a boss\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
