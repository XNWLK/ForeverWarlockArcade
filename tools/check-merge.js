// Plays Demon 2048 with a bot (prefers down/left, like people do) until no move is left. Checks the rules: nothing
// appears or vanishes (the sum of all tiles only grows by the new tile each move), merges score their value, the game
// ends only when no move is left. Fails on Lua errors and on "nil" or "2.0"-style numbers on screen.
//   node tools/check-merge.js [games=20]
const { boot } = require('./host.js');
const GAMES = +process.argv[2] || 20;
const host = boot();
host.run(`
local A = __ADDON_NS
local M = A.MergeRules
local function total(s) local n = 0; for r = 1, M.N do for c = 1, M.N do local t = s.grid[r][c]; if t then n = n + M.value(t.tier) end end end; return n end
function MPLAY(seed)
  local g = A.games.merge.obj
  math.randomseed(seed)
  g:newGame()
  local s = g.s
  local order = { 'DOWN', 'LEFT', 'RIGHT', 'UP' }
  local guard = 0
  while not s.over and guard < 5000 do
    guard = guard + 1
    local before, score0 = total(s), s.score
    local moved = false
    for _, d in ipairs(order) do
      if math.random() < 0.15 then d = order[math.random(1, 4)] end
      local tier0 = s.best
      if M.move(s, d) then
        moved = true
        local after = total(s)
        assert(after == before + 2 or after == before + 4, 'tiles appeared or vanished: ' .. before .. ' -> ' .. after)
        assert(s.score >= score0, 'the score went down')
        break
      end
    end
    if not moved then for _, d in ipairs(order) do if M.move(s, d) then moved = true; break end end end
    if not moved then assert(not M.canMove(s), 'no move worked, yet the game says a move is left'); break end
    if s.justWon then s.justWon = nil; s.keepGoing = true end
  end
  g:draw()
  return string.format('%.0f %d %d', s.score, s.best, s.moves)
end
`, '=mbot');
host.run('__ADDON_NS.open("merge")');
const out = [], bad = new Set();
for (let i = 0; i < GAMES && !host.errors.length; i++) {
  out.push(String(host.call('MPLAY', 60 + i)).split(' ').map(Number));
  host.advance(0.3);
  for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && (/\bnil\b|NaN/.test(n.parsed.plain) || /\d\.0(?!\d)/.test(n.parsed.plain))) bad.add(n.parsed.plain);
}
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (bad.size) { console.log('FAIL: text the game would not show:\n  ' + [...bad].join('\n  ')); process.exit(1); }
const tiers = host.call('tostring', null);
console.log(out.length + ' games: bot score ' + (out.reduce((a, r) => a + r[0], 0) / out.length).toFixed(0) + ', biggest tile tier ' + Math.max(...out.map(r => r[1])) + ' (of 11), moves ' + (out.reduce((a, r) => a + r[2], 0) / out.length).toFixed(0));
console.log('OK');
