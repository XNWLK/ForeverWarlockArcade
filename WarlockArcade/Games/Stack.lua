-- Shard Stack: soul shard pieces fall into the well. Move and turn them to fill whole rows; a full row breaks. Rows
-- broken together cast a spell once for each row - one Shadow Bolt, two Immolates, three Soul Fires, four Rains of
-- Fire - for its real damage (the sim's standard character) times the level. Every ten rows the level goes up and the pieces fall faster.
-- Left / Right move (held keys repeat), Up or X turns, Z turns back, Down drops faster, Space drops at once.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local T = {}
A.StackRules = T
T.W, T.H = 10, 20
-- the seven pieces: cells in a 4x4 box (row, col), their spell (colour) and name
T.PIECES = {
  { cells = { { 2, 1 }, { 2, 2 }, { 2, 3 }, { 2, 4 } }, spell = 'shadowBolt', size = 4 },
  { cells = { { 1, 1 }, { 1, 2 }, { 2, 1 }, { 2, 2 } }, spell = 'lifeTap', size = 2 },   -- the square turns in place
  { cells = { { 1, 2 }, { 2, 1 }, { 2, 2 }, { 2, 3 } }, spell = 'baneOfAgony', size = 3 },
  { cells = { { 1, 2 }, { 1, 3 }, { 2, 1 }, { 2, 2 } }, spell = 'corruption', size = 3 },
  { cells = { { 1, 1 }, { 1, 2 }, { 2, 2 }, { 2, 3 } }, spell = 'incinerate', size = 3 },
  { cells = { { 1, 1 }, { 2, 1 }, { 2, 2 }, { 2, 3 } }, spell = 'immolate', size = 3 },
  { cells = { { 1, 3 }, { 2, 1 }, { 2, 2 }, { 2, 3 } }, spell = 'soulFire', size = 3 },
}
T.CLEARS = { 'shadowBolt', 'immolate', 'soulFire', 'rainOfFire' }
T.COLORS = { shadowBolt = { 0.75, 0.45, 1 }, lifeTap = { 0.35, 0.6, 1 }, baneOfAgony = { 0.65, 0.35, 0.9 }, corruption = { 0.45, 0.9, 0.35 },
  incinerate = { 1, 0.35, 0.25 }, immolate = { 1, 0.55, 0.15 }, soulFire = { 1, 0.82, 0.3 } }

function T.damage(key)
  local s, c, ch = A.SPELLS[key], A.CAST[key], A.CHARACTER
  local crit = 1 + ch.critPct / 100 * (ch.critMult - 1)
  local direct = c and c.direct or (s.base and (s.base + (s.coef or 0) * ch.sp)) or 0
  local tick = c and c.tick or (s.tickBase and (s.tickBase + (s.tickCoef or 0) * ch.sp)) or 0
  local ticks = c and c.ticks or (s.duration and s.tickEvery and floor(s.duration / s.tickEvery + 0.5)) or 0
  return floor(direct * crit + tick * ticks)
end
local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
function T.new(seed)
  local s = { rand = rng(seed or 1), grid = {}, bag = {}, score = 0, lines = 0, level = 1, fall = 0, lock = 0, done = false, events = {} }
  for r = 1, T.H do s.grid[r] = {} end
  s.nextKind = T.draw(s)
  T.spawn(s)
  return s
end
-- a bag of all seven, in a random order, then the next bag
function T.draw(s)
  if #s.bag == 0 then
    for i = 1, #T.PIECES do s.bag[i] = i end
    for i = #s.bag, 2, -1 do local j = s.rand(i); s.bag[i], s.bag[j] = s.bag[j], s.bag[i] end
  end
  return table.remove(s.bag)
end
-- the cells of the falling piece on the board, for its kind, turn (0-3), row and col
function T.cells(kind, rot, row, col)
  local p = T.PIECES[kind]
  local out = {}
  for i, c in ipairs(p.cells) do
    local r, q = c[1], c[2]
    for _ = 1, rot % 4 do r, q = q, p.size + 1 - r end
    out[i] = { row + r - 1, col + q - 1 }
  end
  return out
end
function T.fits(s, kind, rot, row, col)
  for _, c in ipairs(T.cells(kind, rot, row, col)) do
    local r, q = c[1], c[2]
    if q < 1 or q > T.W or r > T.H then return false end
    if r >= 1 and s.grid[r][q] then return false end
  end
  return true
end
function T.spawn(s)
  s.kind, s.rot, s.row, s.col = s.nextKind, 0, 0, 4
  s.nextKind = T.draw(s)
  s.lock = 0
  if not T.fits(s, s.kind, s.rot, s.row, s.col) then s.done = true; s.events[#s.events + 1] = { kind = 'over' } end
end
function T.move(s, d)
  if s.done then return false end
  if T.fits(s, s.kind, s.rot, s.row, s.col + d) then s.col = s.col + d; s.lock = 0; return true end
  return false
end
-- turning: if it does not fit, try a step to the side (or two, or up one)
function T.rotate(s, d)
  if s.done then return false end
  local rot = (s.rot + (d or 1)) % 4
  for _, k in ipairs({ { 0, 0 }, { 0, -1 }, { 0, 1 }, { 0, -2 }, { 0, 2 }, { -1, 0 } }) do
    if T.fits(s, s.kind, rot, s.row + k[1], s.col + k[2]) then s.rot, s.row, s.col = rot, s.row + k[1], s.col + k[2]; s.lock = 0; return true end
  end
  return false
end
local function place(s)
  for _, c in ipairs(T.cells(s.kind, s.rot, s.row, s.col)) do
    if c[1] < 1 then s.done = true; s.events[#s.events + 1] = { kind = 'over' }; return end
    s.grid[c[1]][c[2]] = T.PIECES[s.kind].spell
  end
  local full = {}
  for r = 1, T.H do
    local n = 0
    for q = 1, T.W do if s.grid[r][q] then n = n + 1 end end
    if n == T.W then full[#full + 1] = r end
  end
  if #full > 0 then
    for i = #full, 1, -1 do table.remove(s.grid, full[i]) end
    for i = 1, #full do table.insert(s.grid, 1, {}) end
    local spell = T.CLEARS[min(4, #full)]
    local dmg = T.damage(spell) * #full * s.level
    s.score = s.score + dmg
    s.lines = s.lines + #full
    s.events[#s.events + 1] = { kind = 'clear', rows = full, spell = spell, dmg = dmg }
    local lvl = floor(s.lines / 10) + 1
    if lvl > s.level then s.level = lvl; s.events[#s.events + 1] = { kind = 'level' } end
  end
  s.events[#s.events + 1] = { kind = 'place' }
  T.spawn(s)
end
function T.drop(s)
  if s.done then return end
  local n = 0
  while T.fits(s, s.kind, s.rot, s.row + 1, s.col) do s.row = s.row + 1; n = n + 1 end
  s.score = s.score + 2 * n
  place(s)
end
function T.speed(s) return max(0.06, 0.8 * 0.82 ^ (s.level - 1)) end
function T.update(s, dt, soft)
  if s.done then return end
  s.fall = s.fall + dt * (soft and 12 or 1)
  local sp = T.speed(s)
  while s.fall >= sp and not s.done do
    s.fall = s.fall - sp
    if T.fits(s, s.kind, s.rot, s.row + 1, s.col) then s.row = s.row + 1; if soft then s.score = s.score + 1 end
    else s.fall = 0; break end
  end
  -- on the floor: a moment to slide it, then it locks
  if not s.done and not T.fits(s, s.kind, s.rot, s.row + 1, s.col) then
    s.lock = s.lock + dt
    if s.lock >= 0.5 then place(s) end
  end
end
function T.ghostRow(s)
  local r = s.row
  while T.fits(s, s.kind, s.rot, r + 1, s.col) do r = r + 1 end
  return r
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local CS = 22
local BW, BH = T.W * CS + 16, T.H * CS + 16
local REPEAT_FIRST, REPEAT = 0.17, 0.05

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('stack')
  g.held = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, BW, BH, { 0.035, 0.028, 0.05 }, C.line, 2)
  board:SetPoint('TOP', f, 'TOP', -150, -14)
  board:SetClipsChildren(true)
  self.board = board
  for q = 1, T.W - 1 do local l = K.rect(board, 'BORDER', { 1, 1, 1 }, 0.03); l:SetWidth(1); l:SetPoint('TOPLEFT', 8 + q * CS, -8); l:SetPoint('BOTTOMLEFT', 8 + q * CS, 8) end
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.cells = {}
  for r = 1, T.H do
    self.cells[r] = {}
    for q = 1, T.W do
      local t = K.shape(self.layer, 'ARTWORK', 'rr4')
      t:SetSize(CS - 2, CS - 2)
      t:SetPoint('TOPLEFT', 9 + (q - 1) * CS, -9 - (r - 1) * CS)
      t:Hide()
      self.cells[r][q] = t
    end
  end
  self.pieceT, self.ghostT = {}, {}
  for i = 1, 4 do
    local p = K.shape(self.layer, 'OVERLAY', 'rr4'); p:SetSize(CS - 2, CS - 2); self.pieceT[i] = p
    local g = K.shape(self.layer, 'BORDER', 'rl4_1'); g:SetSize(CS - 2, CS - 2); self.ghostT[i] = g
  end
  self.flash = K.rect(self.layer, 'OVERLAY', { 1, 1, 1 }, 0, 2); self.flash:SetPoint('TOPLEFT', 8, -8); self.flash:SetPoint('BOTTOMRIGHT', -8, 8)
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 20)
  self.pop = K.popups(self.top)
  self.idle = K.text(self.top, 15, C.text, 'CENTER'); self.idle:SetPoint('CENTER', 0, 20); self.idle:SetWidth(BW - 20); self.idle:SetWordWrap(true)
  -- the side: next piece, numbers, buttons
  local side = K.box(f, 300, BH, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  local nl = K.text(side, 11, C.dim, 'LEFT'); nl:SetPoint('TOPLEFT', 14, -14); nl:SetText('Next')
  self.nextT = {}
  for i = 1, 4 do local p = K.shape(side, 'ARTWORK', 'rr4'); p:SetSize(CS - 2, CS - 2); self.nextT[i] = p end
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.scoreT = stat(-90, 'Damage dealt', 24, C.gold)
  self.linesT = stat(-138, 'Rows broken / level', 16)
  self.bestT = stat(-180, 'Best', 15, C.dim)
  local legend = K.text(side, 11, C.dim, 'LEFT'); legend:SetPoint('TOPLEFT', 14, -222); legend:SetPoint('TOPRIGHT', -12, -222); legend:SetWordWrap(true); legend:SetSpacing(2)
  local parts = {}
  for i, key in ipairs(T.CLEARS) do parts[i] = i .. ' row' .. (i > 1 and 's' or '') .. ': ' .. A.SPELLS[key].name .. ' ' .. K.paint(C.gold, K.num(T.damage(key))) end
  legend:SetText('Rows broken together cast a spell once per row, times the level:\n' .. table.concat(parts, '\n'))
  local pad = { { 'Left', -1, 0, function() self:press('LEFT') end }, { 'Turn', 0, 0, function() self:press('UP') end }, { 'Right', 1, 0, function() self:press('RIGHT') end },
    { 'Down', -0.5, 1, function() self:press('DOWN') end }, { 'Drop', 0.5, 1, function() self:press('SPACE') end } }
  for _, p in ipairs(pad) do
    local b = K.button(side, 80, 34, p[1], nil, 'normal', 12)
    b:SetPoint('BOTTOM', side, 'BOTTOM', p[2] * 88, 104 - p[3] * 40)
    b:SetScript('OnMouseDown', p[4])
    b:SetScript('OnMouseUp', function() self.held = {} end)
  end
  self.start = K.button(side, 272, 40, 'Play', function() self:play() end, 'orange', 15)
  self.start:SetPoint('BOTTOM', 0, 14)
end

function G:play()
  self.s = T.new(math.random(1, 2000000000))
  self.held = {}
  self.pop:clear()
  self.idle:SetText('')
  A.sound('go')
  self:draw()
  self:refresh()
end
function G:Show() self.f:Show(); if not self.s then self.idle:SetText('Press Play or Enter'); self:refresh() else self:draw(); self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide(); self.held = {} end

-- one press: does the move now and, for Left / Right / Down, keeps repeating while held
function G:press(key)
  local s = self.s
  if not s or s.done then return end
  if key == 'LEFT' or key == 'A' then if T.move(s, -1) then A.sound('tick') end; self.held.LEFT = REPEAT_FIRST
  elseif key == 'RIGHT' or key == 'D' then if T.move(s, 1) then A.sound('tick') end; self.held.RIGHT = REPEAT_FIRST
  elseif key == 'UP' or key == 'X' or key == 'W' then if T.rotate(s, 1) then A.sound('flip') end
  elseif key == 'Z' then if T.rotate(s, -1) then A.sound('flip') end
  elseif key == 'DOWN' or key == 'S' then self.held.DOWN = 0
  elseif key == 'SPACE' then T.drop(s); A.sound('place') end
  self:handle()
  self:draw()
end
function G:handle()
  local s = self.s
  for _, e in ipairs(s.events) do
    if e.kind == 'clear' then
      self.pop:show(A.SPELLS[e.spell].name .. '!  ' .. K.num(e.dmg), BW / 2, BH / 2 + 40, C.gold, 15 + #e.rows * 2, 1)
      A.sound(#e.rows >= 4 and 'win' or #e.rows >= 2 and 'combo' or 'perfect')
      K.tween(self.flash, 0.25, function(f) self.flash:SetAlpha(0.25 * (1 - f)) end)
    elseif e.kind == 'level' then self.pop:show('Level ' .. s.level, BW / 2, BH / 2, C.fel, 18, 1.2); A.sound('levelup')
    elseif e.kind == 'over' then self:finish() end
  end
  if #s.events > 0 then self:refresh() end
  s.events = {}
end
function G:finish()
  local s = self.s
  local isNew = s.score > (self.db.best or 0)
  if isNew then self.db.best = s.score end
  self.idle:SetText((isNew and 'New best! ' or 'The well is full! ') .. K.num(s.score) .. ' damage, ' .. s.lines .. ' rows')
  A.sound('lose')
  self.held = {}
end

function G:draw()
  local s = self.s
  for r = 1, T.H do for q = 1, T.W do
    local t, v = self.cells[r][q], s.grid[r][q]
    if v then local c = T.COLORS[v]; K.fill(t, c[1] * 0.75, c[2] * 0.75, c[3] * 0.75, 1); t:Show() else t:Hide() end
  end end
  local col = T.COLORS[T.PIECES[s.kind].spell]
  local gr = T.ghostRow(s)
  for i, c in ipairs(T.cells(s.kind, s.rot, s.row, s.col)) do
    local p, g = self.pieceT[i], self.ghostT[i]
    p:ClearAllPoints(); p:SetPoint('TOPLEFT', 9 + (c[2] - 1) * CS, -9 - (c[1] - 1) * CS)
    K.fill(p, col[1], col[2], col[3], 1); p:SetShown(not s.done and c[1] >= 1)
    local gc = T.cells(s.kind, s.rot, gr, s.col)[i]
    g:ClearAllPoints(); g:SetPoint('TOPLEFT', 9 + (gc[2] - 1) * CS, -9 - (gc[1] - 1) * CS)
    g:SetVertexColor(col[1], col[2], col[3], 0.5); g:SetShown(not s.done and gc[1] >= 1)
  end
  local nc = T.COLORS[T.PIECES[s.nextKind].spell]
  for i, c in ipairs(T.cells(s.nextKind, 0, 1, 1)) do
    local p = self.nextT[i]
    p:ClearAllPoints(); p:SetPoint('TOPLEFT', 14 + (c[2] - 1) * CS, -32 - (c[1] - 1) * CS)
    K.fill(p, nc[1], nc[2], nc[3], 1)
  end
end
function G:refresh()
  local s = self.s
  self.scoreT:SetText(K.num(s and s.score or 0))
  self.linesT:SetText((s and s.lines or 0) .. ' / ' .. (s and s.level or 1))
  self.bestT:SetText(K.num(self.db.best or 0))
  self.start:SetShown(not s or s.done)
  self.start:SetLabel(s and 'Again' or 'Play')
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if not s or s.done then return end
  -- held keys repeat
  for k, left in pairs(self.held) do
    if k ~= 'DOWN' then
      left = left - dt
      if left <= 0 then T.move(s, k == 'LEFT' and -1 or 1); left = REPEAT end
      self.held[k] = left
    end
  end
  T.update(s, dt, self.held.DOWN ~= nil)
  self:handle()
  self:draw()
end
local KEYS = { LEFT = true, RIGHT = true, UP = true, DOWN = true, SPACE = true, A = true, D = true, W = true, S = true, X = true, Z = true }
function G:OnKey(key)
  if KEYS[key] then
    if not self.s or self.s.done then if key == 'SPACE' then self:play() end; return true end
    self:press(key)
    return true
  end
  if key == 'ENTER' and (not self.s or self.s.done) then self:play(); return true end
  return false
end
function G:OnKeyUp(key)
  if key == 'LEFT' or key == 'A' then self.held.LEFT = nil end
  if key == 'RIGHT' or key == 'D' then self.held.RIGHT = nil end
  if key == 'DOWN' or key == 'S' then self.held.DOWN = nil end
end

A.RegisterGame({
  key = 'stack', name = 'Shard Stack', order = 24, ready = true, kind = 'puzzle', icon = A.SPELLS.immolate.id,
  tagline = 'Fill whole rows with the falling shards. Rows cast spells.',
  bestLine = function() local b = A.db('stack').best; return b and b > 0 and ('Best: ' .. K.num(b)) or 'Play' end,
  help = {
    '|cffffd040Fill whole rows with the falling pieces;|r a full row breaks. Left / Right move (hold to keep moving), Up or X turns, Z turns back, Down drops faster, Space drops at once. The outline shows where it will land.',
    ' ',
    'Rows broken together cast a spell once for every row, for its real damage (the Forever Warlock Sim\'s standard character) times the level: one row a Shadow Bolt, two Immolates, three Soul Fires, four Rains of Fire.',
    ' ',
    'Every ten rows the level goes up and the pieces fall faster. When there is no room for the next piece, the game is over.',
  },
  create = function(parent) return G.create(parent) end,
})
