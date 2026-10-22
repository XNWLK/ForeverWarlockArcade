// Shard Stack: a bot picks a place for each piece (height, holes, bumpiness, rows) and gets it there with the game's
// own keys (turn, move, drop); it must break many rows. Also: every piece turned four times is back where it was, the
// square turns in place, a turn by the wall kicks off it, rows broken together score the spell's damage x rows x level,
// a well filled without care ends the game.
//   node tools/check-stack.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local T = A.StackRules
local function evaluate(grid)
  local heights, holes, lines = {}, 0, 0
  for q = 1, T.W do
    heights[q] = 0
    local seen = false
    for r = 1, T.H do
      if grid[r][q] then if not seen then heights[q] = T.H - r + 1; seen = true end
      elseif seen then holes = holes + 1 end
    end
  end
  for r = 1, T.H do local n = 0; for q = 1, T.W do if grid[r][q] then n = n + 1 end end; if n == T.W then lines = lines + 1 end end
  local agg, bump = 0, 0
  for q = 1, T.W do agg = agg + heights[q]; if q > 1 then bump = bump + math.abs(heights[q] - heights[q - 1]) end end
  return -0.51 * agg + 0.76 * lines - 0.36 * holes - 0.18 * bump
end
local function best(s)
  local bestScore, bestRot, bestCol
  for rot = 0, 3 do
    for col = -2, T.W do
      if T.fits(s, s.kind, rot, s.row, col) then
        local r = s.row
        while T.fits(s, s.kind, rot, r + 1, col) do r = r + 1 end
        local grid = {}
        for i = 1, T.H do grid[i] = {}; for q = 1, T.W do grid[i][q] = s.grid[i][q] end end
        local ok = true
        for _, c in ipairs(T.cells(s.kind, rot, r, col)) do if c[1] < 1 then ok = false else grid[c[1]][c[2]] = 1 end end
        if ok then
          local v = evaluate(grid)
          if not bestScore or v > bestScore then bestScore, bestRot, bestCol = v, rot, col end
        end
      end
    end
  end
  return bestRot, bestCol
end
function TPLAY(pieces)
  local g = A.games.stack.obj
  g:play()
  local s = g.s
  local placed = 0
  local expected = 0
  local lvlBefore
  while not s.done and placed < pieces do
    local rot, col = best(s)
    if not rot then break end
    for i = 1, (rot - s.rot) % 4 do g:OnKey('UP') end
    local guard = 0
    while s.col ~= col and guard < 20 do guard = guard + 1; g:OnKey(s.col < col and 'RIGHT' or 'LEFT'); g:OnKeyUp('RIGHT'); g:OnKeyUp('LEFT') end
    local before, lv = s.score, s.level
    local rowsBefore = s.lines
    g:OnKey('SPACE')
    placed = placed + 1
    g:OnUpdate(0.01)
  end
  return string.format('%s %d %d %d %d', tostring(s.done), placed, s.lines, s.level, s.score)
end
function TRULES()
  local out = {}
  local s = T.new(5)
  local ok = true
  for kind = 1, #T.PIECES do
    local a = T.cells(kind, 0, 5, 4)
    local b = T.cells(kind, 4, 5, 4)
    for i = 1, 4 do if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then ok = false end end
  end
  out[#out + 1] = ok and 'four turns ok' or 'four turns BAD'
  local sq = {}
  for _, c in ipairs(T.cells(2, 0, 5, 4)) do sq[c[1] * 100 + c[2]] = true end
  local same = true
  for _, c in ipairs(T.cells(2, 1, 5, 4)) do if not sq[c[1] * 100 + c[2]] then same = false end end
  out[#out + 1] = same and 'square ok' or 'square BAD'
  -- the long piece standing at the right wall: turning it lies it down, kicked off the wall
  s.kind, s.rot, s.row, s.col = 1, 1, 5, T.W - 2
  local fitsBefore = T.fits(s, 1, 1, 5, T.W - 2)
  local turned = T.rotate(s, 1)
  out[#out + 1] = (fitsBefore and turned) and 'kick ok' or ('kick BAD ' .. tostring(fitsBefore) .. ' ' .. tostring(turned))
  -- four rows at once
  local t = T.new(6)
  for r = T.H - 3, T.H do for q = 1, T.W - 1 do t.grid[r][q] = 'shadowBolt' end end
  t.kind, t.rot, t.row, t.col = 1, 1, T.H - 4, T.W - 2
  local cells = T.cells(1, 1, T.H - 4, T.W - 2)
  local hole = true
  for _, c in ipairs(cells) do if c[2] ~= T.W then hole = false end end
  if not hole then t.col = t.col + (T.W - cells[1][2]) end
  local before = t.score
  T.drop(t)
  local gained = t.score - before
  local want = T.damage('rainOfFire') * 4
  out[#out + 1] = (t.lines == 4 and gained >= want and gained <= want + 2 * T.H) and 'tetra ok' or ('tetra BAD ' .. t.lines .. ' ' .. gained .. ' ' .. want)
  -- dropping every piece in the middle fills the well
  local u = T.new(7)
  for i = 1, 60 do if not u.done then T.drop(u) end end
  out[#out + 1] = u.done and 'over ok' or 'over BAD'
  return table.concat(out, ' ')
end
`, '=tbot');
host.run('__ADDON_NS.open("stack")');
let fail = '';
for (let i = 1; i <= 2 && !host.errors.length; i++) {
  host.run('math.randomseed(' + i + ')');
  const [done, placed, lines, level, score] = String(host.call('TPLAY', 300)).split(' ');
  console.log('bot ' + i + ': ' + placed + ' pieces, ' + lines + ' rows, level ' + level + ', ' + score + ' damage' + (done === 'true' ? ' (well full)' : ''));
  if (+lines < 60) fail += 'bot ' + i + ': only ' + lines + ' rows\n';
}
const rules = String(host.call('TRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
