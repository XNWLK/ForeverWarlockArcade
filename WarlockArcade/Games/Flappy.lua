-- Flappy Imp: the Imp flies through Molten Core. Click, tap or press Space to flap; get through the gaps between the
-- lava pillars without touching them or the lava below. Soul shards float in some gaps. The pillars come a little
-- faster as you go. Runs on a fixed step, so the same flaps always give the same flight.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local F = {}
A.FlappyRules = F
F.W, F.H = 600, 470
F.LAVA = 30                 -- the lava at the bottom
F.X, F.R = 150, 15          -- the Imp's place and size
F.GRAVITY, F.FLAP = -1250, 400
F.PW, F.GAP, F.SPACING = 66, 150, 240
F.SPEED, F.SPEEDUP = 170, 2.2   -- pixels per second, and more per pillar passed
F.STEP = 1 / 120

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end
function F.new(seed)
  local s = { rand = rng(seed or 1), y = F.H * 0.55, vy = 0, pillars = {}, score = 0, shards = 0, t = 0, acc = 0, started = false, done = false, events = {}, next = F.W + 80 }
  return s
end
function F.speed(s) return F.SPEED + F.SPEEDUP * min(60, s.score) end
local function addPillar(s, x)
  local lo = F.LAVA + 50 + F.GAP / 2
  local hi = F.H - 40 - F.GAP / 2
  local prev = s.pillars[#s.pillars]
  local mid = lo + s.rand() * (hi - lo)
  if prev then mid = max(lo, min(hi, prev.mid + (mid - prev.mid) * 0.75)) end   -- not too far from the last gap
  s.pillars[#s.pillars + 1] = { x = x, mid = mid, passed = false, shard = s.rand() < 0.35 }
end
function F.flap(s)
  if s.done then return end
  s.started = true
  s.vy = F.FLAP
  s.events[#s.events + 1] = { kind = 'flap' }
end
local function hits(s, p)
  -- the Imp (a circle) against the two pillar boxes
  local cx = max(p.x, min(F.X, p.x + F.PW))
  if abs(F.X - cx) > F.R then return false end
  local dx = F.X - cx
  local top, bottom = p.mid + F.GAP / 2, p.mid - F.GAP / 2
  local function boxHit(y0, y1)
    local cy = max(y0, min(s.y, y1))
    return dx * dx + (s.y - cy) * (s.y - cy) < F.R * F.R
  end
  return boxHit(top, F.H + 100) or boxHit(-100, bottom)
end
local function step(s, dt)
  s.t = s.t + dt
  if not s.started then s.y = F.H * 0.55 + math.sin(s.t * 3) * 8; return end
  s.vy = s.vy + F.GRAVITY * dt
  s.y = min(F.H - F.R, s.y + s.vy * dt)
  if s.y >= F.H - F.R and s.vy > 0 then s.vy = 0 end
  local v = F.speed(s) * dt
  for _, p in ipairs(s.pillars) do p.x = p.x - v end
  s.next = s.next - v
  if s.next <= F.W + 40 then addPillar(s, s.next); s.next = s.next + F.SPACING end
  while s.pillars[1] and s.pillars[1].x < -F.PW - 10 do table.remove(s.pillars, 1) end
  for _, p in ipairs(s.pillars) do
    if not p.passed and p.x + F.PW < F.X - F.R then p.passed = true; s.score = s.score + 1; s.events[#s.events + 1] = { kind = 'pass' } end
    if p.shard and abs(p.x + F.PW / 2 - F.X) < F.R + 10 and abs(p.mid - s.y) < F.R + 10 then p.shard = false; s.shards = s.shards + 1; s.events[#s.events + 1] = { kind = 'shard', y = p.mid } end
    if hits(s, p) then s.done = true; s.events[#s.events + 1] = { kind = 'crash' }; return end
  end
  if s.y - F.R <= F.LAVA then s.y = F.LAVA + F.R; s.done = true; s.events[#s.events + 1] = { kind = 'lava' } end
end
function F.update(s, dt)
  if s.done then return end
  s.acc = s.acc + min(dt, 0.25)
  while s.acc >= F.STEP and not s.done do s.acc = s.acc - F.STEP; step(s, F.STEP) end
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local BX, BY = 22, -14

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('flappy')
  g.views = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, F.W, F.H, { 0.06, 0.025, 0.03 }, C.line, 2, 'Button')
  board:SetPoint('TOPLEFT', BX, BY)
  board:SetClipsChildren(true)
  board:SetScript('OnMouseDown', function() self:flap() end)
  self.board = board
  -- the cavern: a warm light from below, slow embers drifting left
  board.sky = K.rect(board, 'BACKGROUND', { 1, 1, 1 }, 1, 1)
  board.sky:SetPoint('TOPLEFT', 2, -2); board.sky:SetPoint('BOTTOMRIGHT', -2, 2)
  board.sky:SetGradient('VERTICAL', CreateColor(0.32, 0.08, 0.04, 1), CreateColor(0.05, 0.02, 0.05, 1))
  self.motes = {}
  for i = 1, 18 do
    local m = K.shape(board, 'BORDER', 'glow')
    m.size = 3 + (i * 5) % 9
    m:SetSize(m.size, m.size)
    m.x, m.y, m.v = (i * 97) % F.W, 40 + (i * 61) % (F.H - 60), 12 + (i * 7) % 30
    m:SetVertexColor(1, 0.55 + (i % 3) * 0.1, 0.2, 0.25 + (i % 4) * 0.08)
    self.motes[i] = m
  end
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  -- the lava
  self.lava = K.rect(self.layer, 'ARTWORK', { 1, 1, 1 }, 1)
  self.lava:SetPoint('BOTTOMLEFT', 2, 2); self.lava:SetPoint('BOTTOMRIGHT', -2, 2); self.lava:SetHeight(F.LAVA)
  self.lava:SetGradient('VERTICAL', CreateColor(1, 0.4, 0.05, 1), CreateColor(1, 0.75, 0.2, 1))
  self.lavaGlow = K.rect(self.layer, 'ARTWORK', { 1, 1, 1 }, 1, -1)
  self.lavaGlow:SetPoint('BOTTOMLEFT', 2, F.LAVA); self.lavaGlow:SetPoint('BOTTOMRIGHT', -2, F.LAVA); self.lavaGlow:SetHeight(40)
  self.lavaGlow:SetGradient('VERTICAL', CreateColor(1, 0.45, 0.1, 0.35), CreateColor(1, 0.4, 0.1, 0))
  -- the Imp
  self.imp = CreateFrame('Frame', nil, self.layer)
  self.imp:SetSize(F.R * 2 + 12, F.R * 2 + 12)
  self.imp:SetFrameLevel(self.layer:GetFrameLevel() + 20)
  self.imp.glow = K.shape(self.imp, 'BACKGROUND', 'glow'); self.imp.glow:SetSize(70, 70); self.imp.glow:SetPoint('CENTER'); self.imp.glow:SetVertexColor(1, 0.6, 0.2, 0.55)
  self.imp.ring = K.shape(self.imp, 'BORDER', 'circle'); self.imp.ring:SetAllPoints(); self.imp.ring:SetVertexColor(0.15, 0.06, 0.04, 1)
  self.imp.icon = self.imp:CreateTexture(nil, 'ARTWORK'); self.imp.icon:SetPoint('TOPLEFT', 4, -4); self.imp.icon:SetPoint('BOTTOMRIGHT', -4, 4)
  self.imp.icon:SetTexture(K.spellTexture(A.PETS.imp.spell)); self.imp.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self.imp.edge = K.shape(self.imp, 'OVERLAY', 'ring'); self.imp.edge:SetAllPoints(); self.imp.edge:SetVertexColor(1, 0.7, 0.3, 1)
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 40)
  self.pop = K.popups(self.top)
  self.scoreT = K.text(self.top, 44, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); self.scoreT:SetPoint('TOP', 0, -18)
  self.idle = K.text(self.top, 16, C.text, 'CENTER'); self.idle:SetPoint('CENTER', 0, -60)
  self.idle2 = K.text(self.top, 12, C.dim, 'CENTER'); self.idle2:SetPoint('TOP', self.idle, 'BOTTOM', 0, -8)
  -- side panel
  local side = K.box(f, 290, F.H, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.passT = stat(-14, 'Pillars passed', 28, C.gold)
  self.shardT = stat(-72, 'Soul shards', 22, C.shadow)
  self.bestT = stat(-124, 'Best', 22, C.dim)
  self.shardBestT = stat(-176, 'Most soul shards in one flight', 15, C.dim)
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -232); note:SetPoint('TOPRIGHT', -12, -232); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Click the cavern, tap it or press Space to flap. Fly through the gaps; the lava and the pillars are deadly. The pillars come a little faster every time.')
  self.start = K.button(side, 262, 40, 'Fly', function() self:play() end, 'orange', 16)
  self.start:SetPoint('BOTTOMLEFT', 14, 14)
  self:play(true)
end

function G:pillarView(p)
  local v = self.views[p]
  if v then return v end
  v = CreateFrame('Frame', nil, self.layer)
  v:SetWidth(F.PW)
  v:SetPoint('TOP', self.board, 'TOP'); v:SetPoint('BOTTOM', self.board, 'BOTTOM')
  local function column()
    local t = K.shape(v, 'ARTWORK', 'rr6')
    K.fill(t, 0.3, 0.1, 0.07, 1)
    local cap = K.shape(v, 'ARTWORK', 'rr4', 1)
    cap:SetHeight(14)
    K.fill(cap, 1, 0.45, 0.12, 1)
    return t, cap
  end
  v.topCol, v.topCap = column()
  v.botCol, v.botCap = column()
  v.shard = K.shape(v, 'OVERLAY', 'glow'); v.shard:SetSize(34, 34); v.shard:SetVertexColor(0.8, 0.4, 1, 1)
  v.shardIcon = K.shape(v, 'OVERLAY', 'spark', 1); v.shardIcon:SetSize(26, 26); v.shardIcon:SetVertexColor(1, 0.8, 1, 1)
  self.views[p] = v
  return v
end
function G:place(v, p)
  local top, bottom = p.mid + F.GAP / 2, p.mid - F.GAP / 2
  v:SetPoint('TOP', self.board, 'TOPLEFT', p.x + F.PW / 2, 0); v:SetPoint('BOTTOM', self.board, 'BOTTOMLEFT', p.x + F.PW / 2, 0)
  v.topCol:ClearAllPoints(); v.topCol:SetPoint('BOTTOMLEFT', v, 'BOTTOMLEFT', 4, top); v.topCol:SetPoint('TOPRIGHT', v, 'TOPRIGHT', -4, 10)
  v.topCap:ClearAllPoints(); v.topCap:SetPoint('BOTTOMLEFT', v, 'BOTTOMLEFT', 0, top); v.topCap:SetPoint('BOTTOMRIGHT', v, 'BOTTOMRIGHT', 0, top)
  v.botCol:ClearAllPoints(); v.botCol:SetPoint('TOPLEFT', v, 'BOTTOMLEFT', 4, bottom); v.botCol:SetPoint('BOTTOMRIGHT', v, 'BOTTOMRIGHT', -4, -10)
  v.botCap:ClearAllPoints(); v.botCap:SetPoint('TOPLEFT', v, 'BOTTOMLEFT', 0, bottom); v.botCap:SetPoint('TOPRIGHT', v, 'BOTTOMRIGHT', 0, bottom)
  v.shard:SetShown(p.shard); v.shardIcon:SetShown(p.shard)
  if p.shard then
    v.shard:ClearAllPoints(); v.shard:SetPoint('CENTER', v, 'BOTTOM', 0, p.mid)
    v.shardIcon:ClearAllPoints(); v.shardIcon:SetPoint('CENTER', v, 'BOTTOM', 0, p.mid)
  end
end

function G:play(quiet)
  for p, v in pairs(self.views) do v:Hide(); self.views[p] = nil end
  self.s = F.new(math.random(1, 2000000000))
  self.pop:clear()
  self.idle:SetText('Click, tap or press Space to flap')
  self.idle2:SetText('Best: ' .. (self.db.best or 0))
  if not quiet then A.sound('open') end
  self:refreshSide()
end
function G:flap()
  local s = self.s
  if s.done then return end
  if not s.started then self.idle:SetText(''); self.idle2:SetText('') end
  F.flap(s)
end

function G:refreshSide()
  local s = self.s
  self.passT:SetText(tostring(s.score))
  self.shardT:SetText(tostring(s.shards))
  self.bestT:SetText(tostring(self.db.best or 0))
  self.shardBestT:SetText(tostring(self.db.bestShards or 0))
  self.scoreT:SetText(s.started and tostring(s.score) or '')
  self.start:SetShown(s.done)
  self.start:SetLabel('Fly again')
end
function G:Show() self.f:Show(); self:refreshSide() end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  -- embers drift left whatever happens
  for _, m in ipairs(self.motes) do
    m.x = m.x - m.v * dt * (s.started and not s.done and 2 or 1)
    if m.x < -10 then m.x = F.W + 10 end
    m:SetPoint('CENTER', self.board, 'BOTTOMLEFT', m.x, m.y)
  end
  if s.done then return end
  F.update(s, dt)
  local changed = false
  for _, e in ipairs(s.events) do
    if e.kind == 'pass' then A.sound('tick'); changed = true
    elseif e.kind == 'shard' then self.pop:show('+1 soul shard', F.X + 40, e.y + 20, C.shadow, 14, 0.8); A.sound('coin'); changed = true
    elseif e.kind == 'flap' then A.sound('whoosh')
    elseif e.kind == 'crash' or e.kind == 'lava' then
      A.sound('crit')
      local isNew = s.score > (self.db.best or 0)
      self.db.best = max(self.db.best or 0, s.score)
      self.db.bestShards = max(self.db.bestShards or 0, s.shards)
      self.idle:SetText((e.kind == 'lava' and 'Into the lava! ' or 'Crashed! ') .. s.score .. (s.score == 1 and ' pillar' or ' pillars'))
      self.idle2:SetText(isNew and 'New best!' or ('Best: ' .. self.db.best))
      changed = true
    end
  end
  s.events = {}
  -- draw
  self.imp:SetPoint('CENTER', self.board, 'BOTTOMLEFT', F.X, s.y)
  self.imp.icon:SetRotation(max(-0.7, min(0.5, s.vy / 900)))
  local seen = {}
  for _, p in ipairs(s.pillars) do
    seen[p] = true
    local v = self:pillarView(p)
    self:place(v, p)
    v:Show()
  end
  for p, v in pairs(self.views) do if not seen[p] then v:Hide(); self.views[p] = nil end end
  if changed then self:refreshSide() end
end

function G:OnKey(key)
  if key == 'SPACE' or key == 'UP' or key == 'W' then
    if self.s.done then self:play() else self:flap() end
    return true
  end
  if key == 'ENTER' and self.s.done then self:play(); return true end
  return false
end

A.RegisterGame({
  key = 'flappy', name = 'Flappy Imp', order = 15, ready = true, kind = 'action', icon = A.PETS.imp.spell,
  tagline = 'Flap the Imp through the lava pillars of Molten Core.',
  bestLine = function() local b = A.db('flappy').best; return b and b > 0 and ('Best: ' .. b .. ' pillars') or 'Play' end,
  help = {
    '|cffffd040Keep the Imp flying.|r Click or tap the cavern, or press Space, to flap.',
    ' ',
    'Fly through the gaps between the lava pillars. Touching a pillar or the lava below ends the flight. Soul shards float in some of the gaps - collect them on the way.',
    ' ',
    'The pillars come a little faster every time you pass one. Your best flight and your most soul shards are kept.',
  },
  create = function(parent) return G.create(parent) end,
})
