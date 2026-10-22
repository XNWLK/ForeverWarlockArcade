-- Pentagram Push: push every soul shard onto a pentagram. You can push one shard at a time and never pull. Eight
-- hand-made rituals; each one's fewest moves (found by a solver, tools/check-push.js) is its three-star mark.
-- Arrow keys or W A S D to walk, Backspace or U to undo, R to start the ritual again.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local P = {}
A.PushRules = P
-- # wall, . pentagram, $ soul shard, * shard on a pentagram, @ you, + you on a pentagram
P.LEVELS = {
  { name = 'First shard', par = 2, rows = { '#######', '#     #', '# @$ .#', '#     #', '#######' } },
  { name = 'Two by two', par = 7, rows = { '#######', '#  .  #', '#  $  #', '#  @  #', '# $ . #', '#     #', '#######' } },
  { name = 'The bend', par = 11, rows = { '  #####', '###   #', '# $   #', '# ##  #', '#  @ .#', '#######' } },
  { name = 'Side by side', par = 20, rows = { '########', '#      #', '# $$ ..#', '#      #', '#  @   #', '########' } },
  { name = 'The pillar', par = 15, rows = { '#######', '#.    #', '# ##$ #', '# #@  #', '# $  .#', '#     #', '#######' } },
  { name = 'Three shards', par = 25, rows = { '########', '#  .   #', '# $#$  #', '#  @ . #', '# $#.  #', '#      #', '########' } },
  { name = 'Narrow hall', par = 12, rows = { '#########', '#   #   #', '# $   $ #', '##.# #.##', ' #  @  # ', ' ####### ' } },
  { name = 'The circle', par = 16, rows = { '  #####  ', '###   ###', '#  $.$  #', '#  .@.  #', '#  $.$  #', '###   ###', '  #####  ' } },
}
P.DIRS = { UP = { 0, -1 }, DOWN = { 0, 1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

function P.load(n)
  local lv = P.LEVELS[n]
  local s = { level = n, w = 0, h = #lv.rows, wall = {}, goal = {}, boxes = {}, moves = 0, pushes = 0, history = {}, done = false }
  for y, row in ipairs(lv.rows) do
    s.w = max(s.w, #row)
    for x = 1, #row do
      local ch = row:sub(x, x)
      local k = y * 100 + x
      if ch == '#' then s.wall[k] = true end
      if ch == '.' or ch == '*' or ch == '+' then s.goal[k] = true end
      if ch == '$' or ch == '*' then s.boxes[k] = true end
      if ch == '@' or ch == '+' then s.px, s.py = x, y end
    end
  end
  return s
end
function P.solved(s)
  for k in pairs(s.boxes) do if not s.goal[k] then return false end end
  return true
end
-- one step: walks, or pushes the shard in front if the square behind it is free. 'walk', 'push' or nil
function P.move(s, name)
  local d = P.DIRS[name]
  if not d or s.done then return nil end
  local nx, ny = s.px + d[1], s.py + d[2]
  local k = ny * 100 + nx
  if s.wall[k] then return nil end
  local pushed
  if s.boxes[k] then
    local bk = (ny + d[2]) * 100 + nx + d[1]
    if s.wall[bk] or s.boxes[bk] then return nil end
    s.boxes[k] = nil
    s.boxes[bk] = true
    pushed = { from = k, to = bk }
    s.pushes = s.pushes + 1
  end
  s.history[#s.history + 1] = { px = s.px, py = s.py, push = pushed }
  s.px, s.py = nx, ny
  s.moves = s.moves + 1
  if P.solved(s) then s.done = true end
  return pushed and 'push' or 'walk'
end
function P.undo(s)
  local h = table.remove(s.history)
  if not h then return false end
  s.px, s.py = h.px, h.py
  if h.push then s.boxes[h.push.to] = nil; s.boxes[h.push.from] = true; s.pushes = s.pushes - 1 end
  s.moves = s.moves - 1
  s.done = false
  return true
end
function P.stars(level, moves)
  local par = P.LEVELS[level].par
  return moves <= par and 3 or moves <= floor(par * 1.5 + 0.5) and 2 or 1
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local AW, AH = 600, 430

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('push')
  g.tiles, g.shards = {}, {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16)
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('Push every soul shard onto a pentagram. One at a time - and you cannot pull.')
  self.area = K.box(f, AW + 16, AH + 16, { 0.04, 0.03, 0.06 }, C.line, 2)
  self.area:SetPoint('TOPLEFT', 22, -70)
  self.layer = CreateFrame('Frame', nil, self.area)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(self.area:GetFrameLevel() + 2)
  self.me = CreateFrame('Frame', nil, self.layer)
  self.me:SetFrameLevel(self.layer:GetFrameLevel() + 10)
  self.me.glow = K.shape(self.me, 'BACKGROUND', 'glow'); self.me.glow:SetPoint('TOPLEFT', -14, 14); self.me.glow:SetPoint('BOTTOMRIGHT', 14, -14); self.me.glow:SetVertexColor(0.6, 1, 0.4, 0.4)
  self.me.icon = self.me:CreateTexture(nil, 'ARTWORK'); self.me.icon:SetPoint('TOPLEFT', 4, -4); self.me.icon:SetPoint('BOTTOMRIGHT', -4, 4)
  self.me.icon:SetTexture(K.spellTexture(A.TALENTS.masterDemonologist.spell)); self.me.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self.me.line = K.shape(self.me, 'OVERLAY', 'rl6_2'); self.me.line:SetAllPoints(); self.me.line:SetVertexColor(0.6, 1, 0.4, 1)
  self.top = CreateFrame('Frame', nil, self.area)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(self.area:GetFrameLevel() + 30)
  self.done = K.text(self.top, 22, C.gold, 'CENTER', K.FONT_TITLE, 'OUTLINE'); self.done:SetPoint('TOP', 0, -14)
  -- the side: levels, numbers, buttons
  local side = K.box(f, 290, AH + 16, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', self.area, 'TOPRIGHT', 16, 0)
  self.levelBtns = {}
  for i = 1, #P.LEVELS do
    local b = K.button(side, 60, 30, tostring(i), function() self:open(i) end, 'normal', 12)
    b:SetPoint('TOPLEFT', 14 + ((i - 1) % 4) * 66, -14 - floor((i - 1) / 4) * 36)
    b.tipFn = function() local best = self.db.best and self.db.best[i]; return { P.LEVELS[i].name, 'Fewest moves found: ' .. P.LEVELS[i].par, best and ('Your best: ' .. best .. ' moves') or 'Not done yet' } end
    self.levelBtns[i] = b
  end
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.movesT = stat(-100, 'Moves / pushes', 22, C.gold)
  self.parT = stat(-150, 'Three stars at', 16)
  self.bestT = stat(-194, 'Your best', 16, C.dim)
  local pad = { { 'UP', 0, 1 }, { 'LEFT', -1, 0 }, { 'DOWN', 0, 0 }, { 'RIGHT', 1, 0 } }
  for _, p in ipairs(pad) do
    local b = K.button(side, 56, 36, p[1] == 'UP' and 'Up' or p[1] == 'DOWN' and 'Down' or p[1] == 'LEFT' and 'Left' or 'Right', function() self:step(p[1]) end, 'normal', 12)
    b:SetPoint('TOP', side, 'TOP', p[2] * 62, -250 - (1 - p[3]) * 42)
  end
  self.undoBtn = K.button(side, 126, 34, 'Undo', function() self:undo() end, 'normal', 13)
  self.undoBtn:SetPoint('BOTTOMLEFT', 14, 58)
  self.restartBtn = K.button(side, 126, 34, 'Start again', function() self:open(self.s.level) end, 'normal', 13)
  self.restartBtn:SetPoint('BOTTOMRIGHT', -14, 58)
  self.nextBtn = K.button(side, 262, 36, 'Next ritual', function() self:open(min(#P.LEVELS, self.s.level + 1)) end, 'orange', 14)
  self.nextBtn:SetPoint('BOTTOMLEFT', 14, 14)
end

function G:open(n)
  self.s = P.load(n)
  self.db.level = n
  local s = self.s
  self.cs = min(64, floor(AW / s.w), floor(AH / s.h))
  self.x0 = 8 + (AW - s.w * self.cs) / 2
  self.y0 = -8 - (AH - s.h * self.cs) / 2
  for _, t in ipairs(self.tiles) do t:Hide() end
  local n2 = 0
  local function tile(layer, shape, x, y, inset, r, g, b, a)
    n2 = n2 + 1
    local t = self.tiles[n2]
    if not t then t = self.layer:CreateTexture(nil, layer); self.tiles[n2] = t end
    t:SetDrawLayer(layer)
    t:SetTexture(K.MEDIA .. shape)
    local m = shape == 'shadow' and 24 or tonumber(shape:match('^r[rl](%d+)'))
    if m then t:SetTextureSliceMargins(m, m, m, m) end
    t:SetSize(self.cs - inset * 2, self.cs - inset * 2)
    t:ClearAllPoints(); t:SetPoint('TOPLEFT', self.area, 'TOPLEFT', self.x0 + (x - 1) * self.cs + inset, self.y0 - (y - 1) * self.cs - inset)
    t:SetVertexColor(r, g, b, a)
    t:Show()
  end
  -- the floor is what can be reached from you (outside squares stay empty)
  local floorSet, stack = {}, { { s.px, s.py } }
  while #stack > 0 do
    local p = table.remove(stack)
    local k = p[2] * 100 + p[1]
    if not floorSet[k] and not s.wall[k] and p[1] >= 1 and p[1] <= s.w and p[2] >= 1 and p[2] <= s.h then
      floorSet[k] = true
      for _, d in pairs(P.DIRS) do stack[#stack + 1] = { p[1] + d[1], p[2] + d[2] } end
    end
  end
  for y = 1, s.h do for x = 1, s.w do
    local k = y * 100 + x
    if s.wall[k] then tile('BORDER', 'rr6', x, y, 1, 0.28, 0.2, 0.36, 1)
    elseif floorSet[k] then tile('BACKGROUND', 'rr4', x, y, 1, 0.1, 0.08, 0.14, 1) end
    if s.goal[k] then
      tile('ARTWORK', 'glow', x, y, -6, 0.75, 0.35, 1, 0.55)
      tile('ARTWORK', 'spark', x, y, 6, 0.85, 0.6, 1, 0.9)
    end
  end end
  self.me:SetSize(self.cs - 8, self.cs - 8)
  self:placeAll(false)
  self.done:SetText('')
  A.sound('open')
  self:refresh()
end
-- the shards: one frame each, so a push can slide
function G:shardView(i)
  local v = self.shards[i]
  if not v then
    v = CreateFrame('Frame', nil, self.layer)
    v:SetFrameLevel(self.layer:GetFrameLevel() + 5)
    v.glow = K.shape(v, 'BACKGROUND', 'glow'); v.glow:SetPoint('TOPLEFT', -10, 10); v.glow:SetPoint('BOTTOMRIGHT', 10, -10)
    v.bg = K.shape(v, 'BORDER', 'rr10'); v.bg:SetAllPoints()
    v.gem = K.shape(v, 'ARTWORK', 'spark'); v.gem:SetPoint('TOPLEFT', 4, -4); v.gem:SetPoint('BOTTOMRIGHT', -4, 4)
    v.line = K.shape(v, 'OVERLAY', 'rl10_1'); v.line:SetAllPoints()
    self.shards[i] = v
  end
  return v
end
function G:pos(x, y) return self.x0 + (x - 0.5) * self.cs, self.y0 - (y - 0.5) * self.cs end
function G:placeAll(slide)
  local s = self.s
  local i = 0
  local list = {}
  for k in pairs(s.boxes) do list[#list + 1] = k end
  table.sort(list)
  for _, k in ipairs(list) do
    i = i + 1
    local v = self:shardView(i)
    v:SetSize(self.cs - 10, self.cs - 10)
    local x, y = k % 100, floor(k / 100)
    local onGoal = s.goal[k]
    K.fill(v.bg, onGoal and 0.6 or 0.35, onGoal and 0.45 or 0.15, onGoal and 0.15 or 0.55, 1)
    v.gem:SetVertexColor(onGoal and 1 or 0.9, onGoal and 0.9 or 0.65, onGoal and 0.5 or 1, 1)
    v.line:SetVertexColor(onGoal and C.gold[1] or 0.7, onGoal and C.gold[2] or 0.5, onGoal and C.gold[3] or 1, 1)
    v.glow:SetVertexColor(onGoal and 1 or 0.6, onGoal and 0.8 or 0.35, onGoal and 0.3 or 1, onGoal and 0.7 or 0.3)
    local px, py = self:pos(x, y)
    v:ClearAllPoints(); v:SetPoint('CENTER', self.area, 'TOPLEFT', px, py)
    v:Show()
  end
  for j = i + 1, #self.shards do self.shards[j]:Hide() end
  local tx, ty = self:pos(s.px, s.py)
  if slide and self.meX then
    local fx, fy = self.meX, self.meY
    K.tween(self.me, 0.08, function(f) self.me:ClearAllPoints(); self.me:SetPoint('CENTER', self.area, 'TOPLEFT', K.lerp(fx, tx, f), K.lerp(fy, ty, f)) end)
  else self.me:ClearAllPoints(); self.me:SetPoint('CENTER', self.area, 'TOPLEFT', tx, ty) end
  self.meX, self.meY = tx, ty
end
function G:Show() self.f:Show(); if not self.s then self:open(self.db.level or 1) else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:step(dir)
  local s = self.s
  local r = P.move(s, dir)
  if not r then return end
  A.sound(r == 'push' and 'place' or 'tick')
  self:placeAll(true)
  if s.done then self:finish() end
  self:refresh()
end
function G:undo()
  if P.undo(self.s) then A.sound('flip'); self.done:SetText(''); self:placeAll(false); self:refresh() end
end
function G:finish()
  local s = self.s
  local stars = P.stars(s.level, s.moves)
  self.db.best = self.db.best or {}
  self.db.stars = self.db.stars or {}
  self.db.best[s.level] = min(self.db.best[s.level] or 9999, s.moves)
  self.db.stars[s.level] = max(self.db.stars[s.level] or 0, stars)
  self.done:SetText('Ritual complete! ' .. string.rep('*', stars) .. '  (' .. s.moves .. ' moves)')
  A.sound(stars == 3 and 'win' or 'levelup')
end

function G:refresh()
  local s = self.s
  local lv = P.LEVELS[s.level]
  self.title:SetText('Pentagram Push ' .. s.level .. ': ' .. lv.name)
  for i, b in ipairs(self.levelBtns) do
    local st = self.db.stars and self.db.stars[i] or 0
    b:SetLabel(i .. (st > 0 and (' ' .. string.rep('*', st)) or ''))
    b:SetStyle(i == s.level and 'gold' or 'normal')
  end
  self.movesT:SetText(s.moves .. ' / ' .. s.pushes)
  self.parT:SetText(lv.par .. ' moves (two stars at ' .. floor(lv.par * 1.5 + 0.5) .. ')')
  local best = self.db.best and self.db.best[s.level]
  self.bestT:SetText(best and (best .. ' moves') or '-')
  self.undoBtn:SetEnabled(#s.history > 0)
  self.nextBtn:SetEnabled(s.done and s.level < #P.LEVELS)
end

local KEYMAP = { UP = 'UP', DOWN = 'DOWN', LEFT = 'LEFT', RIGHT = 'RIGHT', W = 'UP', S = 'DOWN', A = 'LEFT', D = 'RIGHT' }
function G:OnKey(key)
  if KEYMAP[key] then self:step(KEYMAP[key]); return true end
  if key == 'BACKSPACE' or key == 'U' then self:undo(); return true end
  if key == 'R' then self:open(self.s.level); return true end
  if key == 'ENTER' and self.s.done and self.s.level < #P.LEVELS then self:open(self.s.level + 1); return true end
  return false
end

A.RegisterGame({
  key = 'push', name = 'Pentagram Push', order = 25, ready = true, kind = 'puzzle', icon = A.TALENTS.masterDemonologist.spell,
  tagline = 'Push every soul shard onto a pentagram. Never pull.',
  bestLine = function()
    local st = A.db('push').stars
    local n = 0
    if st then for _, v in pairs(st) do n = n + v end end
    return n > 0 and (n .. ' of ' .. 3 * #P.LEVELS .. ' stars') or 'Play'
  end,
  help = {
    '|cffffd040Push every soul shard onto a pentagram.|r Arrow keys or W A S D to walk; walking into a shard pushes it - one at a time, and you cannot pull it back.',
    ' ',
    'Backspace or U undoes a step, R starts the ritual again. Eight rituals; finishing one in the fewest moves found gives three stars, within half as many again two.',
  },
  create = function(parent) return G.create(parent) end,
})
