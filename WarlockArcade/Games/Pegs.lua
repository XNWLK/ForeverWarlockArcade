-- Shadow Pegs: aim, shoot a Shadow Bolt, bounce it through the pegs. Clear every orange soul shard peg with 10 bolts.
-- Purple pegs are worth a Corruption tick, orange ones a Shadow Bolt hit, green ones an Immolate hit and they rain fire
-- on the pegs around them - the standard character's damage from the sim (A.CAST). More shards cleared = a bigger
-- multiplier. A bolt that lands in the moving bucket comes back.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, sqrt, sin, cos, abs, random = math.floor, math.min, math.max, math.sqrt, math.sin, math.cos, math.abs, math.random

local P = {}
A.PegsRules = P
P.W, P.H = 700, 500            -- the board
P.BALL_R, P.PEG_R = 8, 9
P.GRAVITY = 520
P.SPEED = 520                  -- launch speed
P.BOUNCE = 0.72
P.BALLS = 10
P.ORANGE = 16
P.GREEN = 2
P.RAIN_R = 85                  -- Rain of Fire: pegs within this distance light up
P.BUCKET_W, P.BUCKET_Y = 90, 18
P.VALUE = { purple = A.CAST.corruption.tick, orange = A.CAST.shadowBolt.direct, green = A.CAST.immolate.direct }
P.MULT_AT = { 8, 12, 15 }      -- shards cleared for x2, x3, x5
function P.mult(orangeHit) if orangeHit >= P.MULT_AT[3] then return 5 elseif orangeHit >= P.MULT_AT[2] then return 3 elseif orangeHit >= P.MULT_AT[1] then return 2 end; return 1 end

-- layouts: lists of peg positions
local LAYOUTS = {}
LAYOUTS[1] = function()   -- staggered rows
  local t = {}
  for r = 0, 6 do for c = 0, 11 do local x = 60 + c * 53 + (r % 2) * 26; if x < P.W - 40 then t[#t + 1] = { x, 380 - r * 46 } end end end
  return t
end
LAYOUTS[2] = function()   -- rings
  local t = {}
  for ring, rad in ipairs({ 70, 130, 190 }) do
    local n = ring * 9 + 3
    for i = 0, n - 1 do local a = i / n * 6.2832; t[#t + 1] = { P.W / 2 + cos(a) * rad * 1.35, 215 + sin(a) * rad * 0.82 } end
  end
  return t
end
LAYOUTS[3] = function()   -- a V and two arcs
  local t = {}
  for i = 0, 11 do t[#t + 1] = { 70 + i * 24, 390 - i * 24 }; t[#t + 1] = { P.W - 70 - i * 24, 390 - i * 24 } end
  for i = 0, 14 do local a = 3.1416 + i / 14 * 3.1416; t[#t + 1] = { P.W / 2 + cos(a) * 260, 200 + sin(a) * -90 + 20 } end
  for i = 0, 9 do t[#t + 1] = { 160 + i * 42, 110 + (i % 2) * 18 } end
  return t
end
LAYOUTS[4] = function()   -- scattered, never too close
  local t = {}
  for _ = 1, 600 do
    if #t >= 72 then break end
    local x, y = 40 + random() * (P.W - 80), 70 + random() * 330
    local ok = true
    for _, p in ipairs(t) do if (p[1] - x) ^ 2 + (p[2] - y) ^ 2 < 42 ^ 2 then ok = false; break end end
    if ok then t[#t + 1] = { x, y } end
  end
  return t
end
P.LAYOUT_COUNT = #LAYOUTS

function P.newLevel(s, which)
  s.level = (s.level or 0) + 1
  local pts = LAYOUTS[which or ((s.level - 1) % #LAYOUTS) + 1]()
  s.pegs = {}
  for i, p in ipairs(pts) do
    if p[1] > 20 and p[1] < P.W - 20 and p[2] > 40 and p[2] < P.H - 70 then s.pegs[#s.pegs + 1] = { x = p[1], y = p[2], kind = 'purple', id = i } end
  end
  local idx = {}
  for i = 1, #s.pegs do idx[i] = i end
  A.Kit.shuffle(idx)
  for i = 1, min(P.ORANGE, #idx) do s.pegs[idx[i]].kind = 'orange' end
  for i = P.ORANGE + 1, min(P.ORANGE + P.GREEN, #idx) do s.pegs[idx[i]].kind = 'green' end
  s.balls, s.orangeHit, s.ball, s.over, s.won = P.BALLS, 0, nil, false, false
  s.orangeTotal = min(P.ORANGE, #s.pegs)
end
function P.new(seed)
  if seed then math.randomseed(seed) end
  local s = { score = 0, levelScore = 0, aim = -1.5708, bucketX = P.W / 2, bucketDir = 1, events = {} }
  P.newLevel(s)
  return s
end
function P.launch(s)
  if s.ball or s.over or s.balls <= 0 then return false end
  s.balls = s.balls - 1
  s.ball = { x = P.W / 2, y = P.H - 28, vx = cos(s.aim) * P.SPEED, vy = sin(s.aim) * P.SPEED, slow = 0, lit = 0 }
  s.shotScore = 0
  return true
end
-- aim at a point on the board (angles point down: launcher at the top)
function P.aimAt(s, x, y)
  local a = math.atan2 and math.atan2(y - (P.H - 28), x - P.W / 2) or math.atan(y - (P.H - 28), x - P.W / 2)
  s.aim = max(-3.05, min(-0.09, a))
end
local function light(s, p)
  if p.lit then return end
  p.lit = true
  local m = P.mult(s.orangeHit)
  local v = floor(P.VALUE[p.kind] * m + 0.5)
  if p.kind == 'orange' then s.orangeHit = s.orangeHit + 1 end
  s.score = s.score + v
  s.shotScore = (s.shotScore or 0) + v
  s.events[#s.events + 1] = { kind = 'hit', peg = p, value = v }
  if p.kind == 'green' then
    s.events[#s.events + 1] = { kind = 'rain', peg = p }
    for _, q in ipairs(s.pegs) do if not q.lit and not q.gone and (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 < P.RAIN_R ^ 2 then light(s, q) end end
  end
end
-- the lit pegs disappear (end of a shot, or a stuck bolt)
local function clearLit(s)
  for _, p in ipairs(s.pegs) do if p.lit and not p.gone then p.gone = true end end
end
function P.update(s, dt)
  -- the bucket moves all the time
  s.bucketX = s.bucketX + s.bucketDir * 120 * dt
  if s.bucketX > P.W - P.BUCKET_W / 2 then s.bucketX = P.W - P.BUCKET_W / 2; s.bucketDir = -1 elseif s.bucketX < P.BUCKET_W / 2 then s.bucketX = P.BUCKET_W / 2; s.bucketDir = 1 end
  local b = s.ball
  if not b then return end
  local steps = 6
  local h = min(dt, 0.05) / steps
  for _ = 1, steps do
    b.vy = b.vy - P.GRAVITY * h
    b.x, b.y = b.x + b.vx * h, b.y + b.vy * h
    if b.x < P.BALL_R then b.x = P.BALL_R; b.vx = abs(b.vx) * 0.9 elseif b.x > P.W - P.BALL_R then b.x = P.W - P.BALL_R; b.vx = -abs(b.vx) * 0.9 end
    if b.y > P.H - P.BALL_R then b.y = P.H - P.BALL_R; b.vy = -abs(b.vy) * 0.5 end
    local rr = P.BALL_R + P.PEG_R
    for _, p in ipairs(s.pegs) do
      if not p.gone then
        local dx, dy = b.x - p.x, b.y - p.y
        local d2 = dx * dx + dy * dy
        if d2 < rr * rr then
          local d = sqrt(d2)
          if d < 0.001 then dx, dy, d = 0, 1, 1 end
          local nx, ny = dx / d, dy / d
          b.x, b.y = p.x + nx * (rr + 0.01), p.y + ny * (rr + 0.01)
          local vn = b.vx * nx + b.vy * ny
          if vn < 0 then b.vx, b.vy = b.vx - (1 + P.BOUNCE) * vn * nx, b.vy - (1 + P.BOUNCE) * vn * ny end
          if not p.lit then light(s, p); s.events[#s.events + 1] = { kind = 'bounce' } end
        end
      end
    end
    -- the bucket
    if b.y < P.BUCKET_Y + 6 and b.y > 0 and abs(b.x - s.bucketX) < P.BUCKET_W / 2 - 4 and b.vy < 0 then
      s.balls = s.balls + 1
      s.events[#s.events + 1] = { kind = 'bucket' }
      b.y = -100
    end
    if b.y < -P.BALL_R then break end
  end
  -- stuck: barely moving for a while -> the lit pegs go, so it falls on
  local speed2 = b.vx * b.vx + b.vy * b.vy
  if speed2 < 40 * 40 then b.slow = b.slow + dt else b.slow = 0 end
  if b.slow > 1.5 then clearLit(s); b.slow = 0; b.vy = b.vy - 60 end
  if b.y < -P.BALL_R then
    s.ball = nil
    clearLit(s)
    s.events[#s.events + 1] = { kind = 'shotEnd', score = s.shotScore }
    if s.orangeHit >= s.orangeTotal then
      s.over, s.won = true, true
      local bonus = s.balls * P.VALUE.orange
      s.score = s.score + bonus
      s.events[#s.events + 1] = { kind = 'cleared', bonus = bonus }
    elseif s.balls <= 0 then
      s.over = true
      s.events[#s.events + 1] = { kind = 'out' }
    end
  end
end
-- where the bolt would go, until it first touches a peg (the aiming guide)
function P.preview(s, n)
  local pts = {}
  local x, y, vx, vy = P.W / 2, P.H - 28, cos(s.aim) * P.SPEED, sin(s.aim) * P.SPEED
  local h = 0.012
  for i = 1, 120 do
    vy = vy - P.GRAVITY * h
    x, y = x + vx * h, y + vy * h
    if x < P.BALL_R or x > P.W - P.BALL_R then vx = -vx; x = max(P.BALL_R, min(P.W - P.BALL_R, x)) end
    if i % 4 == 0 then pts[#pts + 1] = { x, y } end
    if #pts >= n then break end
    local hit = false
    for _, p in ipairs(s.pegs) do if not p.gone and (x - p.x) ^ 2 + (y - p.y) ^ 2 < (P.BALL_R + P.PEG_R) ^ 2 then hit = true; break end end
    if hit or y < 0 then break end
  end
  return pts
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local COLOR = { purple = { 0.55, 0.35, 0.95 }, orange = { 1, 0.55, 0.12 }, green = { 0.35, 0.9, 0.3 } }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('pegs')
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  -- side panel
  local side = K.box(f, 210, 560, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', 10, -12)
  self.side = side
  local function line(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 12, y); a:SetText(label)
    local b = K.text(side, size or 20, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 12, y - 15)
    return b
  end
  self.scoreT = line(-12, 'Damage', 22, C.gold)
  self.levelT = line(-62, 'Level')
  self.ballsT = line(-112, 'Shadow Bolts left', 20, C.shadow)
  self.orangeT = line(-162, 'Soul shard pegs left', 20, COLOR.orange)
  self.multT = line(-212, 'Multiplier', 20, C.mult)
  self.bestT = line(-262, 'Best', 16, C.dim)
  local legend = K.text(side, 11, C.dim, 'LEFT'); legend:SetPoint('TOPLEFT', 12, -320); legend:SetPoint('TOPRIGHT', -10, -320); legend:SetWordWrap(true); legend:SetSpacing(3)
  legend:SetText('|cff8c59f2Purple|r peg: ' .. K.num(P.VALUE.purple) .. ' (a Corruption tick)|n|cffff8c1fOrange|r soul shard: ' .. K.num(P.VALUE.orange) .. ' (a Shadow Bolt)|n|cff59e64dGreen|r Rain of Fire: ' .. K.num(P.VALUE.green) .. ', lights the pegs around it|n|nAim with the mouse, click to shoot. Or Left / Right and Space.')
  -- the board
  local board = K.box(f, P.W, P.H, { 0.06, 0.045, 0.08 }, C.line, 2)
  board:SetPoint('TOPLEFT', 232, -12)
  board:EnableMouse(true)
  board:SetScript('OnMouseDown', function() self:shoot() end)
  self.board = board
  local layer = CreateFrame('Frame', nil, board)
  layer:SetAllPoints()
  layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.layer = layer
  self.pegTex = {}
  self.dots = {}
  for i = 1, 14 do
    local d = layer:CreateTexture(nil, 'ARTWORK'); d:SetTexture(K.MEDIA .. 'circle'); d:SetSize(5, 5); d:SetVertexColor(1, 1, 1, 0.55); d:Hide()
    self.dots[i] = d
  end
  self.launcher = layer:CreateTexture(nil, 'ARTWORK'); self.launcher:SetTexture(K.MEDIA .. 'circle'); self.launcher:SetSize(30, 30); self.launcher:SetVertexColor(0.45, 0.25, 0.7, 1)
  self.launcher:SetPoint('CENTER', board, 'BOTTOMLEFT', P.W / 2, P.H - 28)
  self.ballGlow = layer:CreateTexture(nil, 'OVERLAY'); self.ballGlow:SetTexture(K.MEDIA .. 'glow'); self.ballGlow:SetSize(44, 44); self.ballGlow:SetVertexColor(0.75, 0.3, 1, 0.9); self.ballGlow:SetBlendMode('ADD')
  self.ball = layer:CreateTexture(nil, 'OVERLAY', nil, 1); self.ball:SetTexture(K.MEDIA .. 'circle'); self.ball:SetSize(P.BALL_R * 2, P.BALL_R * 2); self.ball:SetVertexColor(0.85, 0.6, 1, 1)
  self.bucket = layer:CreateTexture(nil, 'ARTWORK'); self.bucket:SetColorTexture(0.4, 0.3, 0.55, 1); self.bucket:SetSize(P.BUCKET_W, 10)
  self.bucket:SetPoint('CENTER', board, 'BOTTOMLEFT', P.W / 2, P.BUCKET_Y)
  self.bucketL = K.text(layer, 10, C.dim, 'CENTER'); self.bucketL:SetPoint('BOTTOM', self.bucket, 'TOP', 0, 2); self.bucketL:SetText('free bolt')
  self.pop = K.popups(layer)
  local o = K.box(f, 460, 270, { 0.07, 0.05, 0.1, 0.97 }, C.gold, 2)
  o:SetPoint('CENTER', board, 'CENTER')
  o:SetFrameLevel(f:GetFrameLevel() + 30)
  o:EnableMouse(true)
  o.title = K.text(o, 26, C.gold, 'CENTER', K.FONT_TITLE); o.title:SetPoint('TOP', 0, -18)
  o.body = K.text(o, 14, C.text, 'CENTER'); o.body:SetPoint('TOPLEFT', 24, -64); o.body:SetPoint('TOPRIGHT', -24, -64); o.body:SetWordWrap(true); o.body:SetSpacing(4)
  o.go = K.button(o, 180, 42, 'Start', function() self:overlayGo() end, 'orange', 16)
  o.go:SetPoint('BOTTOM', 0, 18)
  self.overlay = o
end

function G:pegTexture(i)
  local t = self.pegTex[i]
  if not t then
    t = self.layer:CreateTexture(nil, 'ARTWORK', nil, 1); t:SetTexture(K.MEDIA .. 'circle'); t:SetSize(P.PEG_R * 2, P.PEG_R * 2)
    t.glow = self.layer:CreateTexture(nil, 'ARTWORK', nil, 0); t.glow:SetTexture(K.MEDIA .. 'glow'); t.glow:SetSize(40, 40); t.glow:SetBlendMode('ADD')
    self.pegTex[i] = t
  end
  return t
end

function G:drawPegs()
  local s = self.s
  for i, p in ipairs(s.pegs) do
    local t = self:pegTexture(i)
    if p.gone then t:Hide(); t.glow:Hide()
    else
      local c = COLOR[p.kind]
      local k = p.lit and 1 or 0.7
      t:SetVertexColor(min(1, c[1] * k + (p.lit and 0.3 or 0)), min(1, c[2] * k + (p.lit and 0.3 or 0)), min(1, c[3] * k + (p.lit and 0.3 or 0)), 1)
      t:ClearAllPoints(); t:SetPoint('CENTER', self.board, 'BOTTOMLEFT', p.x, p.y); t:Show()
      t.glow:ClearAllPoints(); t.glow:SetPoint('CENTER', t, 'CENTER'); t.glow:SetVertexColor(c[1], c[2], c[3], 0.8); t.glow:SetShown(p.lit and true or false)
    end
  end
  for i = #s.pegs + 1, #self.pegTex do self.pegTex[i]:Hide(); self.pegTex[i].glow:Hide() end
end

function G:refreshSide()
  local s = self.s
  self.scoreT:SetText(K.num(s and s.score or 0))
  self.levelT:SetText(s and s.level or 1)
  self.ballsT:SetText(s and s.balls or P.BALLS)
  self.orangeT:SetText(s and (s.orangeTotal - s.orangeHit) or P.ORANGE)
  self.multT:SetText('x' .. (s and P.mult(s.orangeHit) or 1))
  self.bestT:SetText(K.num(self.db.best or 0))
end

function G:Show()
  self.f:Show()
  if not self.s then self:showOverlay('start') end
  self:refreshSide()
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:showOverlay(kind)
  local o, s = self.overlay, self.s
  self.overlayKind = kind
  if kind == 'start' then
    o.title:SetText('Shadow Pegs')
    o.body:SetText('Aim with the mouse and click to shoot a Shadow Bolt. Light up every |cffff8c1forange soul shard|r peg with ' .. P.BALLS .. ' bolts.|n|nThe more shards you clear, the bigger the multiplier. Catch the bolt in the moving bucket to get it back.')
    o.go:SetLabel('Start')
  elseif kind == 'cleared' then
    o.title:SetText('Level ' .. s.level .. ' cleared!')
    o.body:SetText('All soul shards collected.|nBolts left: ' .. s.balls .. ' (+' .. K.num(s.balls * P.VALUE.orange) .. ')|n|nDamage so far: |cffffd040' .. K.num(s.score) .. '|r')
    o.go:SetLabel('Next level')
  else
    local isNew = s.score > (self.db.best or 0)
    if isNew then self.db.best = s.score end
    o.title:SetText('Out of Shadow Bolts')
    o.body:SetText('Soul shards left: ' .. (s.orangeTotal - s.orangeHit) .. '|nReached level ' .. s.level .. '|n|nDamage: |cffffd040' .. K.num(s.score) .. '|r' .. (isNew and '  |cff60ff60new best!|r' or ''))
    o.go:SetLabel('Again')
  end
  o:Show()
end
function G:overlayGo()
  local kind = self.overlayKind
  self.overlay:Hide()
  if kind == 'cleared' then P.newLevel(self.s)
  else self.s = P.new() end
  self.pop:clear()
  A.sound('open')
  self:drawPegs()
  self:refreshSide()
end

function G:shoot()
  local s = self.s
  if not s or self.overlay:IsShown() then return end
  if P.launch(s) then A.sound('click') end
end

function G:cursorOnBoard()
  local x, y = GetCursorPosition()
  local sc = self.board:GetEffectiveScale()
  local l, b = self.board:GetLeft(), self.board:GetBottom()
  if not l then return nil end
  return x / sc - l, y / sc - b
end

function G:OnUpdate(dt)
  local s = self.s
  self.pop:update(dt)
  if not s then return end
  if not s.ball and not s.over and not self.overlay:IsShown() and self.board:IsMouseOver() then
    local x, y = self:cursorOnBoard()
    if x then P.aimAt(s, x, y) end
  end
  if self.keyAim then s.aim = max(-3.05, min(-0.09, s.aim + self.keyAim * dt * 1.4)) end
  P.update(s, dt)
  local changed = false
  for _, e in ipairs(s.events) do
    changed = true
    if e.kind == 'hit' then
      self.pop:show(K.num(e.value), e.peg.x, e.peg.y + 14, COLOR[e.peg.kind], e.peg.kind == 'orange' and 15 or 12, 0.7)
      if e.peg.kind == 'orange' then A.sound('select') end
    elseif e.kind == 'rain' then self.pop:show('Rain of Fire!', e.peg.x, e.peg.y + 30, COLOR.green, 16, 1); A.sound('crit')
    elseif e.kind == 'bucket' then self.pop:show('Free bolt!', s.bucketX, P.BUCKET_Y + 30, C.gold, 18, 1.1); A.sound('coin')
    elseif e.kind == 'shotEnd' and e.score and e.score > 0 then self.pop:show(K.num(e.score) .. ' this shot', P.W / 2, P.H - 70, C.gold, 16, 1.2)
    elseif e.kind == 'cleared' then A.sound('win'); self:showOverlay('cleared')
    elseif e.kind == 'out' then A.sound('lose'); self:showOverlay('over')
    end
  end
  s.events = {}
  if changed then self:drawPegs(); self:refreshSide() end
  -- the bolt, the bucket, the aiming guide
  local b = s.ball
  if b then
    self.ball:ClearAllPoints(); self.ball:SetPoint('CENTER', self.board, 'BOTTOMLEFT', b.x, b.y); self.ball:Show()
    self.ballGlow:ClearAllPoints(); self.ballGlow:SetPoint('CENTER', self.ball, 'CENTER'); self.ballGlow:Show()
  else self.ball:Hide(); self.ballGlow:Hide() end
  self.bucket:ClearAllPoints(); self.bucket:SetPoint('CENTER', self.board, 'BOTTOMLEFT', s.bucketX, P.BUCKET_Y)
  local pts = (not b and not s.over and not self.overlay:IsShown()) and P.preview(s, #self.dots) or {}
  for i, d in ipairs(self.dots) do
    local p = pts[i]
    if p then d:ClearAllPoints(); d:SetPoint('CENTER', self.board, 'BOTTOMLEFT', p[1], p[2]); d:Show() else d:Hide() end
  end
end

function G:OnKey(key)
  if self.overlay:IsShown() then
    if key == 'ENTER' or key == 'SPACE' then self:overlayGo(); return true end
    return false
  end
  if key == 'SPACE' or key == 'ENTER' then self:shoot(); return true end
  if key == 'LEFT' or key == 'RIGHT' then
    if self.s then self.s.aim = max(-3.05, min(-0.09, self.s.aim + (key == 'LEFT' and -0.06 or 0.06))) end
    return true
  end
  return false
end

A.RegisterGame({
  key = 'pegs', name = 'Shadow Pegs', order = 6, ready = true, icon = A.SPELLS.shadowBolt.id,
  tagline = 'Bounce a Shadow Bolt through the pegs and light up every soul shard.',
  bestLine = function() local b = A.db('pegs').best; return b and ('Best: ' .. K.num(b) .. ' damage') or 'Play' end,
  help = {
    '|cffffd040Clear every orange soul shard peg with ' .. P.BALLS .. ' Shadow Bolts.|r Aim with the mouse, click to shoot (or Left / Right and Space).',
    ' ',
    'Every peg the bolt touches lights up and deals damage - the standard character\'s numbers from the Forever Warlock Sim: purple ' .. K.num(P.VALUE.purple) .. ' (a Corruption tick), orange ' .. K.num(P.VALUE.orange) .. ' (a Shadow Bolt), green ' .. K.num(P.VALUE.green) .. ' (an Immolate hit). Lit pegs vanish when the bolt is gone.',
    ' ',
    'Green pegs are Rain of Fire: they light every peg around them. The multiplier grows as the shards fall: x2 from ' .. P.MULT_AT[1] .. ', x3 from ' .. P.MULT_AT[2] .. ', x5 from ' .. P.MULT_AT[3] .. '.',
    ' ',
    'Land the bolt in the moving bucket to get it back. Clear a level and every bolt you have left adds a Shadow Bolt of damage.',
  },
  create = function(parent) return G.create(parent) end,
})
