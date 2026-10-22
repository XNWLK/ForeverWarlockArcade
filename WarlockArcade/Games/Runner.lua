-- Fel Runner: run through Molten Core as far as you can. Jump over fire and Core Hounds (Space, Up, W or a click; a
-- short tap jumps lower), duck under the fire bats (Down or S). Souls float along the way. It gets faster the further
-- you run. Fixed steps, so the same keys always give the same run.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local R = {}
A.RunnerRules = R
R.W, R.H, R.GROUND = 600, 470, 64
R.X, R.SIZE = 120, 36             -- the runner: place and size (ducking: half as tall)
R.GRAVITY, R.JUMP, R.CUT = -2700, 920, 0.45
R.SPEED, R.ACCEL, R.TOP = 330, 7, 720
R.STEP = 1 / 120
R.KINDS = {
  fire = { w = 46, h = 26, fly = false },
  hound = { w = 54, h = 44, fly = false },
  bat = { w = 44, h = 26, fly = true },
}

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end
function R.new(seed)
  return { rand = rng(seed or 1), y = 0, vy = 0, duck = false, hold = false, speed = R.SPEED, dist = 0, souls = 0, things = {},
    next = 500, t = 0, acc = 0, started = false, done = false, events = {} }
end
function R.onGround(s) return s.y <= 0.001 end
function R.jump(s)
  if s.done then return end
  s.started = true
  s.hold = true
  if R.onGround(s) and not s.duck then s.vy = R.JUMP; s.events[#s.events + 1] = { kind = 'jump' } end
end
-- letting go early cuts the jump short
function R.release(s) s.hold = false; if s.vy > 0 then s.vy = s.vy * R.CUT end end
function R.setDuck(s, on) if s.done then return end; s.started = s.started or on; s.duck = on and true or false end
function R.box(s)
  local h = (s.duck and R.onGround(s)) and R.SIZE / 2 or R.SIZE
  return R.X - R.SIZE / 2 + 4, s.y, R.SIZE - 8, h - 2
end
local function spawn(s, x)
  local r = s.rand()
  local kind = r < 0.42 and 'fire' or r < 0.72 and 'hound' or 'bat'
  local k = R.KINDS[kind]
  local th = { kind = kind, x = x, w = k.w + (kind == 'fire' and floor(s.rand() * 30) or 0), h = k.h, y = k.fly and 30 or 0 }
  s.things[#s.things + 1] = th
  -- now and then a soul above it
  if s.rand() < 0.35 then s.things[#s.things + 1] = { kind = 'soul', x = x + th.w / 2 - 10, y = k.fly and 110 or 120, w = 20, h = 20 } end
  -- the gap to the next: shorter at speed, but never too short to land and jump again
  local gap = 300 + s.rand() * 260
  s.next = x + gap * (0.8 + 0.4 * s.speed / R.TOP)
end
local function hit(ax, ay, aw, ah, b) return ax < b.x + b.w and ax + aw > b.x and ay < b.y + b.h and ay + ah > b.y end
local function step(s, dt)
  s.t = s.t + dt
  if not s.started then return end
  s.speed = min(R.TOP, s.speed + R.ACCEL * dt)
  local v = s.speed * dt
  s.dist = s.dist + v
  s.vy = s.vy + R.GRAVITY * dt * (s.vy < 0 and 1.15 or 1)
  s.y = max(0, s.y + s.vy * dt)
  if s.y <= 0 then s.vy = 0 end
  for _, th in ipairs(s.things) do th.x = th.x - v end
  s.next = s.next - v
  if s.next <= R.W + 60 then spawn(s, s.next + 0) end
  while s.things[1] and s.things[1].x + s.things[1].w < -20 do table.remove(s.things, 1) end
  local bx, by, bw, bh = R.box(s)
  for i = #s.things, 1, -1 do
    local th = s.things[i]
    if hit(bx, by, bw, bh, th) then
      if th.kind == 'soul' then
        table.remove(s.things, i); s.souls = s.souls + 1; s.events[#s.events + 1] = { kind = 'soul' }
      else
        s.done = true; s.events[#s.events + 1] = { kind = 'crash', what = th.kind }; return
      end
    end
  end
end
function R.update(s, dt)
  if s.done then return end
  s.acc = s.acc + min(dt, 0.25)
  while s.acc >= R.STEP and not s.done do s.acc = s.acc - R.STEP; step(s, R.STEP) end
end
-- the score: metres run plus 50 a soul
function R.score(s) return floor(s.dist / 10) + 50 * s.souls end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('runner')
  g.views = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, R.W, R.H, { 0.06, 0.025, 0.03 }, C.line, 2, 'Button')
  board:SetPoint('TOPLEFT', 22, -14)
  board:SetClipsChildren(true)
  board:SetScript('OnMouseDown', function() self:jump() end)
  board:SetScript('OnMouseUp', function() if self.s then R.release(self.s) end end)
  self.board = board
  board.sky = K.rect(board, 'BACKGROUND', { 1, 1, 1 }, 1, 1)
  board.sky:SetPoint('TOPLEFT', 2, -2); board.sky:SetPoint('BOTTOMRIGHT', -2, 2)
  board.sky:SetGradient('VERTICAL', CreateColor(0.28, 0.07, 0.05, 1), CreateColor(0.05, 0.02, 0.06, 1))
  -- far rocks (slow) and embers
  self.rocks = {}
  for i = 1, 6 do
    local r = K.shape(board, 'BORDER', 'rr14'); r:SetSize(120 + (i * 37) % 90, 60 + (i * 23) % 70)
    r:SetVertexColor(0.12, 0.05, 0.06, 1); r.x = (i - 1) * 120; self.rocks[i] = r
  end
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.ground = K.rect(self.layer, 'ARTWORK', { 1, 1, 1 }, 1)
  self.ground:SetPoint('BOTTOMLEFT', 2, 2); self.ground:SetPoint('BOTTOMRIGHT', -2, 2); self.ground:SetHeight(R.GROUND)
  self.ground:SetGradient('VERTICAL', CreateColor(0.12, 0.05, 0.04, 1), CreateColor(0.32, 0.12, 0.06, 1))
  self.edge = K.rect(self.layer, 'ARTWORK', C.fire, 0.9, 1)
  self.edge:SetPoint('BOTTOMLEFT', 2, R.GROUND); self.edge:SetPoint('BOTTOMRIGHT', -2, R.GROUND); self.edge:SetHeight(2)
  self.marks = {}
  for i = 1, 8 do local m = K.rect(self.layer, 'ARTWORK', { 1, 0.5, 0.2 }, 0.25, 2); m:SetSize(26, 3); m.x = i * 80; self.marks[i] = m end
  -- the runner
  self.me = CreateFrame('Frame', nil, self.layer)
  self.me:SetFrameLevel(self.layer:GetFrameLevel() + 20)
  self.me.glow = K.shape(self.me, 'BACKGROUND', 'glow'); self.me.glow:SetSize(80, 80); self.me.glow:SetPoint('CENTER'); self.me.glow:SetVertexColor(0.6, 1, 0.35, 0.45)
  self.me.bg = K.shape(self.me, 'BORDER', 'rr6'); self.me.bg:SetAllPoints(); self.me.bg:SetVertexColor(0.1, 0.06, 0.12, 1)
  self.me.icon = self.me:CreateTexture(nil, 'ARTWORK'); self.me.icon:SetPoint('TOPLEFT', 3, -3); self.me.icon:SetPoint('BOTTOMRIGHT', -3, 3)
  self.me.icon:SetTexture(K.spellTexture(A.TALENTS.felDomination.spell)); self.me.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self.me.line = K.shape(self.me, 'OVERLAY', 'rl6_1'); self.me.line:SetAllPoints(); self.me.line:SetVertexColor(0.6, 1, 0.4, 1)
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 40)
  self.pop = K.popups(self.top)
  self.scoreT = K.text(self.top, 30, { 1, 1, 1 }, 'RIGHT', K.FONT_NUM, 'OUTLINE'); self.scoreT:SetPoint('TOPRIGHT', -16, -12)
  self.idle = K.text(self.top, 16, C.text, 'CENTER'); self.idle:SetPoint('CENTER', 0, 40)
  self.idle2 = K.text(self.top, 12, C.dim, 'CENTER'); self.idle2:SetPoint('TOP', self.idle, 'BOTTOM', 0, -8)
  local side = K.box(f, 290, R.H, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.distT = stat(-14, 'Distance', 26, C.gold)
  self.soulT = stat(-70, 'Souls', 20, C.fel)
  self.speedT = stat(-118, 'Speed', 16)
  self.bestT = stat(-164, 'Best score', 18, C.dim)
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -220); note:SetPoint('TOPRIGHT', -12, -220); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Space, Up, W or a click to jump - tap for a small jump, hold for a big one. Down or S to duck under the fire bats. Jump the fire and the Core Hounds. Souls: +50.')
  self.duckBtn = K.button(side, 126, 40, 'Duck', nil, 'normal', 13)
  self.duckBtn:SetPoint('BOTTOMLEFT', 14, 64)
  self.duckBtn:SetScript('OnMouseDown', function() if self.s then R.setDuck(self.s, true) end end)
  self.duckBtn:SetScript('OnMouseUp', function() if self.s then R.setDuck(self.s, false) end end)
  self.jumpBtn = K.button(side, 126, 40, 'Jump', nil, 'normal', 13)
  self.jumpBtn:SetPoint('BOTTOMRIGHT', -14, 64)
  self.jumpBtn:SetScript('OnMouseDown', function() self:jump() end)
  self.jumpBtn:SetScript('OnMouseUp', function() if self.s then R.release(self.s) end end)
  self.start = K.button(side, 262, 40, 'Run', function() self:play() end, 'orange', 16)
  self.start:SetPoint('BOTTOMLEFT', 14, 14)
  self:play(true)
end

function G:thingView(th)
  local v = self.views[th]
  if v then return v end
  v = CreateFrame('Frame', nil, self.layer)
  v:SetSize(th.w, th.h)
  v.glow = K.shape(v, 'BACKGROUND', 'glow'); v.glow:SetPoint('CENTER'); v.glow:SetSize(th.w * 2, th.h * 2.6)
  v.body = K.shape(v, 'ARTWORK', th.kind == 'soul' and 'spark' or 'rr6'); v.body:SetAllPoints()
  if th.kind == 'fire' then v.glow:SetVertexColor(1, 0.5, 0.1, 0.7); K.fill(v.body, 1, 0.42, 0.08, 1)
  elseif th.kind == 'hound' then
    v.glow:SetVertexColor(1, 0.3, 0.1, 0.4); K.fill(v.body, 0.45, 0.12, 0.08, 1)
    v.icon = v:CreateTexture(nil, 'ARTWORK', nil, 1); v.icon:SetSize(30, 30); v.icon:SetPoint('CENTER'); v.icon:SetTexture(K.spellTexture(A.SPELLS.immolate.id)); v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  elseif th.kind == 'bat' then v.glow:SetVertexColor(1, 0.6, 0.2, 0.6); K.fill(v.body, 0.8, 0.3, 0.1, 1)
    v.wing = K.shape(v, 'ARTWORK', 'spark', 1); v.wing:SetSize(th.w * 1.3, th.h * 1.6); v.wing:SetPoint('CENTER'); v.wing:SetVertexColor(1, 0.8, 0.4, 0.9)
  else v.glow:SetVertexColor(0.5, 1, 0.4, 0.8); v.body:SetVertexColor(0.85, 1, 0.8, 1) end
  self.views[th] = v
  return v
end
function G:play(quiet)
  for th, v in pairs(self.views) do v:Hide(); self.views[th] = nil end
  self.s = R.new(math.random(1, 2000000000))
  self.pop:clear()
  self.idle:SetText('Space, Up or a click to start running'); self.idle2:SetText('Best: ' .. (self.db.best or 0))
  if not quiet then A.sound('open') end
  self:draw()
  self:refresh()
end
function G:jump()
  local s = self.s
  if s.done then return end
  if not s.started then self.idle:SetText(''); self.idle2:SetText('') end
  R.jump(s)
end
function G:Show() self.f:Show(); self:refresh() end
function G:Hide() self.f:Hide(); GameTooltip:Hide(); if self.s then R.release(self.s); R.setDuck(self.s, false) end end

function G:draw()
  local s = self.s
  local bx, by, bw, bh = R.box(s)
  self.me:SetSize(R.SIZE, (s.duck and R.onGround(s)) and R.SIZE / 2 or R.SIZE)
  self.me:ClearAllPoints(); self.me:SetPoint('BOTTOM', self.board, 'BOTTOMLEFT', R.X, R.GROUND + s.y)
  for _, r in ipairs(self.rocks) do
    r:ClearAllPoints(); r:SetPoint('BOTTOMLEFT', self.board, 'BOTTOMLEFT', r.x, R.GROUND)
  end
  for _, m in ipairs(self.marks) do m:ClearAllPoints(); m:SetPoint('BOTTOMLEFT', self.board, 'BOTTOMLEFT', m.x, R.GROUND - 18) end
  local seen = {}
  for _, th in ipairs(s.things) do
    seen[th] = true
    local v = self:thingView(th)
    v:ClearAllPoints(); v:SetPoint('BOTTOMLEFT', self.board, 'BOTTOMLEFT', th.x, R.GROUND + th.y)
    v:Show()
  end
  for th, v in pairs(self.views) do if not seen[th] then v:Hide(); self.views[th] = nil end end
  self.scoreT:SetText(s.started and tostring(R.score(s)) or '')
end
function G:refresh()
  local s = self.s
  self.distT:SetText(floor(s.dist / 10) .. ' m')
  self.soulT:SetText(tostring(s.souls))
  self.speedT:SetText(floor(s.speed / 10) .. ' m/s')
  self.bestT:SetText(tostring(self.db.best or 0))
  self.start:SetShown(s.done)
  self.start:SetLabel('Run again')
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if s.done then return end
  local before = s.dist
  R.update(s, dt)
  local v = s.dist - before
  for _, r in ipairs(self.rocks) do r.x = r.x - v * 0.25; if r.x < -220 then r.x = r.x + 6 * 120 end end
  for _, m in ipairs(self.marks) do m.x = m.x - v; if m.x < -30 then m.x = m.x + 8 * 80 end end
  for _, e in ipairs(s.events) do
    if e.kind == 'jump' then A.sound('jump')
    elseif e.kind == 'soul' then self.pop:show('+50', R.X, R.GROUND + s.y + 60, C.fel, 15, 0.6); A.sound('coin')
    elseif e.kind == 'crash' then
      A.sound('crit')
      local score = R.score(s)
      local isNew = score > (self.db.best or 0)
      if isNew then self.db.best = score end
      self.idle:SetText((e.what == 'fire' and 'Burned! ' or e.what == 'hound' and 'A Core Hound got you! ' or 'A fire bat got you! ') .. score .. ' points')
      self.idle2:SetText(isNew and 'New best!' or ('Best: ' .. self.db.best))
      self:refresh()
    end
  end
  s.events = {}
  self:draw()
  self.tick = (self.tick or 0) + dt
  if self.tick > 0.2 then self.tick = 0; self:refresh() end
end
function G:OnKey(key)
  if key == 'SPACE' or key == 'UP' or key == 'W' then
    if self.s.done then self:play() else self:jump() end
    return true
  end
  if key == 'DOWN' or key == 'S' then R.setDuck(self.s, true); return true end
  if key == 'ENTER' and self.s.done then self:play(); return true end
  return false
end
function G:OnKeyUp(key)
  if key == 'SPACE' or key == 'UP' or key == 'W' then R.release(self.s) end
  if key == 'DOWN' or key == 'S' then R.setDuck(self.s, false) end
end

A.RegisterGame({
  key = 'runner', name = 'Fel Runner', order = 23, ready = true, kind = 'action', icon = A.TALENTS.felDomination.spell,
  tagline = 'Run through Molten Core. Jump the fire, duck the bats.',
  bestLine = function() local b = A.db('runner').best; return b and b > 0 and ('Best: ' .. b) or 'Play' end,
  help = {
    '|cffffd040Run as far as you can.|r Space, Up, W or a click to jump - a short tap jumps lower, holding jumps higher. Down or S to duck.',
    ' ',
    'Jump over the fire and the Core Hounds; duck under the fire bats. Souls float along the way: 50 points each. It gets faster the further you run.',
  },
  create = function(parent) return G.create(parent) end,
})
