-- Drain Snake: your Drain Soul beam winds through the field. Steer it to the souls; every soul makes it longer and a
-- little faster. Now and then a soul shard shows up for a few seconds - worth five. Hitting the wall or the beam itself
-- ends the drain. Arrow keys or W A S D, or the buttons. Runs on fixed steps.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local S = {}
A.SnakeRules = S
S.W, S.H = 24, 18
S.DIRS = { UP = { 0, -1 }, DOWN = { 0, 1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
function S.new(seed)
  local s = { rand = rng(seed or 1), body = { { 6, 9 }, { 5, 9 }, { 4, 9 } }, dir = { 1, 0 }, queue = {}, grow = 0, score = 0, souls = 0,
    acc = 0, done = false, events = {}, t = 0 }
  S.placeSoul(s)
  return s
end
function S.free(s, x, y)
  for _, b in ipairs(s.body) do if b[1] == x and b[2] == y then return false end end
  if s.soul and s.soul[1] == x and s.soul[2] == y then return false end
  if s.shard and s.shard[1] == x and s.shard[2] == y then return false end
  return true
end
local function spot(s)
  for try = 1, 400 do
    local x, y = s.rand(S.W), s.rand(S.H)
    if S.free(s, x, y) then return { x, y } end
  end
end
function S.placeSoul(s) s.soul = spot(s) end
-- seconds per step: 0.14 at the start, down to 0.065
function S.step(s) return max(0.065, 0.14 - 0.003 * s.souls) end
-- a turn: queued, at most two ahead; never straight back
function S.turn(s, name)
  local d = S.DIRS[name]
  if not d or s.done then return end
  local last = s.queue[#s.queue] or s.dir
  if (d[1] == -last[1] and d[2] == -last[2]) or (d[1] == last[1] and d[2] == last[2]) then return end
  if #s.queue < 2 then s.queue[#s.queue + 1] = d end
end
local function move(s)
  if #s.queue > 0 then s.dir = table.remove(s.queue, 1) end
  local head = s.body[1]
  local x, y = head[1] + s.dir[1], head[2] + s.dir[2]
  if x < 1 or x > S.W or y < 1 or y > S.H then s.done = true; s.events[#s.events + 1] = { kind = 'wall' }; return end
  -- the tail moves away this step unless growing, so its square is free
  local last = s.grow > 0 and #s.body or #s.body - 1
  for i = 1, last do local b = s.body[i]; if b[1] == x and b[2] == y then s.done = true; s.events[#s.events + 1] = { kind = 'bite' }; return end end
  table.insert(s.body, 1, { x, y })
  if s.grow > 0 then s.grow = s.grow - 1 else table.remove(s.body) end
  if s.soul and x == s.soul[1] and y == s.soul[2] then
    s.score = s.score + 1; s.souls = s.souls + 1; s.grow = s.grow + 1
    s.events[#s.events + 1] = { kind = 'soul', x = x, y = y }
    S.placeSoul(s)
    if not s.shard and s.souls % 5 == 0 then s.shard = spot(s); s.shardLeft = 6 end
  elseif s.shard and x == s.shard[1] and y == s.shard[2] then
    s.score = s.score + 5; s.grow = s.grow + 2
    s.events[#s.events + 1] = { kind = 'shard', x = x, y = y }
    s.shard = nil
  end
end
function S.update(s, dt)
  if s.done then return end
  s.t = s.t + dt
  if s.shard then s.shardLeft = s.shardLeft - dt; if s.shardLeft <= 0 then s.shard = nil end end
  s.acc = s.acc + min(dt, 0.25)
  while s.acc >= S.step(s) and not s.done do s.acc = s.acc - S.step(s); move(s) end
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local CS = 24

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('snake')
  g.segs = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, S.W * CS + 16, S.H * CS + 16, { 0.04, 0.03, 0.06 }, C.line, 2)
  board:SetPoint('TOPLEFT', 22, -14)
  board:SetClipsChildren(true)
  self.board = board
  for x = 1, S.W do for y = 1, S.H do
    if (x + y) % 2 == 0 then local t = K.rect(board, 'BORDER', { 1, 1, 1 }, 0.02); t:SetSize(CS, CS); t:SetPoint('TOPLEFT', 8 + (x - 1) * CS, -8 - (y - 1) * CS) end
  end end
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.soul = K.shape(self.layer, 'ARTWORK', 'glow'); self.soul:SetSize(CS * 1.8, CS * 1.8)
  self.soulCore = K.shape(self.layer, 'ARTWORK', 'spark', 1); self.soulCore:SetSize(CS, CS)
  self.shard = K.shape(self.layer, 'ARTWORK', 'glow'); self.shard:SetSize(CS * 2, CS * 2); self.shard:SetVertexColor(1, 0.8, 0.3, 0.9)
  self.shardCore = K.shape(self.layer, 'ARTWORK', 'spark', 1); self.shardCore:SetSize(CS * 1.2, CS * 1.2); self.shardCore:SetVertexColor(1, 0.95, 0.6, 1)
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 20)
  self.pop = K.popups(self.top)
  self.idle = K.text(self.top, 16, C.text, 'CENTER'); self.idle:SetPoint('CENTER', 0, 30)
  self.idle2 = K.text(self.top, 12, C.dim, 'CENTER'); self.idle2:SetPoint('TOP', self.idle, 'BOTTOM', 0, -8)
  local side = K.box(f, 290, S.H * CS + 16, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.scoreT = stat(-14, 'Souls drained', 28, C.gold)
  self.lenT = stat(-70, 'Beam length', 18)
  self.bestT = stat(-116, 'Best', 18, C.dim)
  -- buttons for a touch screen
  local pad = { { 'UP', 0, 1 }, { 'LEFT', -1, 0 }, { 'DOWN', 0, 0 }, { 'RIGHT', 1, 0 } }
  for _, p in ipairs(pad) do
    local b = K.button(side, 56, 40, p[1] == 'UP' and 'Up' or p[1] == 'DOWN' and 'Down' or p[1] == 'LEFT' and 'Left' or 'Right', nil, 'normal', 12)
    b:SetPoint('TOP', side, 'TOP', p[2] * 62, -190 - (1 - p[3]) * 46)
    b:SetScript('OnMouseDown', function() self:steer(p[1]) end)
  end
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -300); note:SetPoint('TOPRIGHT', -12, -300); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Arrow keys or W A S D. Every soul makes the beam longer and a little faster; the gold soul shard is worth 5 but fades. Do not touch the wall or the beam.')
  self.start = K.button(side, 262, 40, 'Start', function() self:play() end, 'orange', 15)
  self.start:SetPoint('BOTTOMLEFT', 14, 14)
end

function G:seg(i)
  local v = self.segs[i]
  if not v then
    v = K.shape(self.layer, 'ARTWORK', 'rr6', -1)
    v:SetSize(CS - 2, CS - 2)
    self.segs[i] = v
  end
  return v
end
function G:cell(x, y) return 8 + (x - 0.5) * CS, -8 - (y - 0.5) * CS end
function G:play()
  self.s = S.new(math.random(1, 2000000000))
  self.pop:clear()
  self.idle:SetText(''); self.idle2:SetText('')
  A.sound('go')
  self:draw()
  self:refresh()
end
function G:steer(d)
  if not self.s or self.s.done then return end
  S.turn(self.s, d)
end
function G:Show() self.f:Show(); if not self.s then self.idle:SetText('Drain the souls'); self.idle2:SetText('Press Start, Enter or an arrow key') end; self:refresh() end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:draw()
  local s = self.s
  local n = #s.body
  for i, b in ipairs(s.body) do
    local v = self:seg(i)
    local x, y = self:cell(b[1], b[2])
    v:ClearAllPoints(); v:SetPoint('CENTER', self.board, 'TOPLEFT', x, y)
    -- the head bright, the beam fading towards its end
    local f = 1 - (i - 1) / max(1, n)
    if i == 1 then v:SetVertexColor(0.9, 0.7, 1, 1) else v:SetVertexColor(0.35 + 0.35 * f, 0.15 + 0.2 * f, 0.6 + 0.35 * f, 0.6 + 0.4 * f) end
    v:Show()
  end
  for i = n + 1, #self.segs do self.segs[i]:Hide() end
  local x, y = self:cell(s.soul[1], s.soul[2])
  local pulse = 0.75 + 0.25 * math.sin(s.t * 6)
  self.soul:ClearAllPoints(); self.soul:SetPoint('CENTER', self.board, 'TOPLEFT', x, y); self.soul:SetVertexColor(0.6, 1, 0.5, 0.7 * pulse)
  self.soulCore:ClearAllPoints(); self.soulCore:SetPoint('CENTER', self.board, 'TOPLEFT', x, y); self.soulCore:SetVertexColor(0.85, 1, 0.8, 1)
  self.shard:SetShown(s.shard ~= nil); self.shardCore:SetShown(s.shard ~= nil)
  if s.shard then
    local sx, sy = self:cell(s.shard[1], s.shard[2])
    self.shard:ClearAllPoints(); self.shard:SetPoint('CENTER', self.board, 'TOPLEFT', sx, sy)
    self.shardCore:ClearAllPoints(); self.shardCore:SetPoint('CENTER', self.board, 'TOPLEFT', sx, sy)
    self.shard:SetAlpha(min(1, s.shardLeft / 2))
  end
end
function G:refresh()
  local s = self.s
  self.scoreT:SetText(tostring(s and s.score or 0))
  self.lenT:SetText(tostring(s and #s.body or 3))
  self.bestT:SetText(tostring(self.db.best or 0))
  self.start:SetShown(not s or s.done)
  self.start:SetLabel(s and 'Again' or 'Start')
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if not s or s.done then return end
  S.update(s, dt)
  local changed = false
  for _, e in ipairs(s.events) do
    if e.kind == 'soul' then local x, y = self:cell(e.x, e.y); self.pop:show('+1', x, S.H * CS + 16 + y, C.fel, 13, 0.5); A.sound('pop'); changed = true
    elseif e.kind == 'shard' then local x, y = self:cell(e.x, e.y); self.pop:show('+5 soul shard', x, S.H * CS + 16 + y, C.gold, 15, 0.8); A.sound('coin'); changed = true
    else
      A.sound('crit'); A.sound('lose')
      local isNew = s.score > (self.db.best or 0)
      if isNew then self.db.best = s.score end
      self.idle:SetText((e.kind == 'wall' and 'Into the wall! ' or 'The beam bit itself! ') .. s.score .. ' souls')
      self.idle2:SetText(isNew and 'New best!' or ('Best: ' .. (self.db.best or 0)))
      changed = true
    end
  end
  s.events = {}
  self:draw()
  if changed then self:refresh() end
end
local KEYMAP = { UP = 'UP', DOWN = 'DOWN', LEFT = 'LEFT', RIGHT = 'RIGHT', W = 'UP', S = 'DOWN', A = 'LEFT', D = 'RIGHT' }
function G:OnKey(key)
  local d = KEYMAP[key]
  if d then
    if not self.s or self.s.done then self:play() end
    self:steer(d)
    return true
  end
  if (key == 'ENTER' or key == 'SPACE') and (not self.s or self.s.done) then self:play(); return true end
  return false
end

A.RegisterGame({
  key = 'snake', name = 'Drain Snake', order = 22, ready = true, kind = 'action', icon = A.SPELLS.baneOfAgony.id,
  tagline = 'Steer your Drain Soul beam to the souls. Do not bite yourself.',
  bestLine = function() local b = A.db('snake').best; return b and b > 0 and ('Best: ' .. b .. ' souls') or 'Play' end,
  help = {
    '|cffffd040Steer your Drain Soul beam to the souls.|r Arrow keys or W A S D (or the buttons). Every soul makes the beam longer and a little faster.',
    ' ',
    'Every fifth soul a gold soul shard shows up for a few seconds - worth five. Touching the wall or the beam itself ends the drain.',
  },
  create = function(parent) return G.create(parent) end,
})
