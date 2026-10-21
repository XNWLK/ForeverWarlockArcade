// Felsweeper: a logic bot plays many games at every size through the real squares (left and right clicks, like the
// mouse): it flags squares that must hide an Infernal, opens squares that must be safe (by clicking numbers whose
// sigils are all there) and guesses only when stuck. Checks: the first square is never an Infernal and opens an area,
// every number is right, a sure flag is never wrong, wins and losses end the game, best times are kept.
//   node tools/check-sweeper.js [games per size=12]
const { boot } = require('./host.js');
const GAMES = +process.argv[2] || 12;
const host = boot();
host.run(`
local A = __ADDON_NS
local S = A.SweeperRules
function CLICK(b, button)
  local top = __web.topAt(b.__id)
  if top ~= b.__id then error('square covered by another frame', 2) end
  b:Click(button)
end
local function view(g, r, c) return g.cells[(r - 1) * g.s.w + c] end
local function around(s, r, c)
  local out = {}
  for dr = -1, 1 do for dc = -1, 1 do local rr, cc = r + dr, c + dc
    if (dr ~= 0 or dc ~= 0) and rr >= 1 and rr <= s.h and cc >= 1 and cc <= s.w then out[#out + 1] = { rr, cc, s.cells[rr][cc] } end end end
  return out
end
function SPLAY(size)
  local g = A.games.sweeper.obj
  g.size = size
  g:newGame()
  local s = g.s
  -- the first click: the middle
  local r0, c0 = math.floor(s.h / 2), math.floor(s.w / 2)
  CLICK(view(g, r0, c0), 'LeftButton')
  local firstOk = not s.cells[r0][c0].mine and s.opened > 1
  local badCount, badFlag, guesses = 0, 0, 0
  for r = 1, s.h do for c = 1, s.w do
    local n = 0
    for _, p in ipairs(around(s, r, c)) do if p[3].mine then n = n + 1 end end
    if n ~= s.cells[r][c].count then badCount = badCount + 1 end
  end end
  local guard = 0
  while not s.done and guard < 2000 do
    guard = guard + 1
    local acted = false
    for r = 1, s.h do for c = 1, s.w do
      local x = s.cells[r][c]
      if x.open and x.count > 0 and not s.done then
        local closed, flags = {}, 0
        for _, p in ipairs(around(s, r, c)) do if p[3].flag then flags = flags + 1 elseif not p[3].open then closed[#closed + 1] = p end end
        if #closed > 0 and flags + #closed == x.count then
          for _, p in ipairs(closed) do CLICK(view(g, p[1], p[2]), 'RightButton'); if not p[3].mine then badFlag = badFlag + 1 end end
          acted = true
        elseif #closed > 0 and flags == x.count then
          CLICK(view(g, r, c), 'LeftButton'); acted = true
        end
      end
    end end
    if not acted and not s.done then
      -- stuck: open a random closed square
      local list = {}
      for r = 1, s.h do for c = 1, s.w do local x = s.cells[r][c]; if not x.open and not x.flag then list[#list + 1] = { r, c } end end end
      local p = list[math.random(1, #list)]
      guesses = guesses + 1
      CLICK(view(g, p[1], p[2]), 'LeftButton')
    end
    g:OnUpdate(0.5)
  end
  return string.format('%s %d %d %d %s %.1f %s', tostring(firstOk), badCount, badFlag, guesses, tostring(s.won), s.t, tostring(A.db('sweeper').best and A.db('sweeper').best[size] or 'none'))
end
`, '=sbot');
host.run('__ADDON_NS.open("sweeper")'); host.layout();
let fail = '';
for (let size = 1; size <= 3 && !host.errors.length; size++) {
  let wins = 0, guesses = 0, lastBest = 'none';
  for (let i = 1; i <= GAMES; i++) {
    host.run('math.randomseed(' + (size * 100 + i) + ')');
    const [first, badCount, badFlag, gs, won, t, best] = String(host.call('SPLAY', size)).split(' ');
    if (first !== 'true') fail += 'size ' + size + ' game ' + i + ': the first square was not safe or opened nothing\n';
    if (+badCount) fail += 'size ' + size + ' game ' + i + ': ' + badCount + ' wrong numbers\n';
    if (+badFlag) fail += 'size ' + size + ' game ' + i + ': ' + badFlag + ' sure flags were wrong\n';
    if (won === 'true') wins++;
    guesses += +gs; lastBest = best;
  }
  console.log('size ' + size + ': the bot won ' + wins + ' of ' + GAMES + ' (' + guesses + ' guesses), best time ' + lastBest);
  if (wins === 0) fail += 'size ' + size + ': the bot never won\n';
  if (lastBest === 'none') fail += 'size ' + size + ': no best time kept\n';
}
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
