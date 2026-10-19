-- Soul Circles: aim the rotation. The same 120 s fight of the sim's standard character as Tap Tap DPS (A.TapTapRules:
-- Bane of Agony, Corruption and Immolate kept up, Shadow Bolt as the filler, Life Tap when mana runs low), but every
-- cast is a circle somewhere on the board with a ring closing in on it: click it (or point at it and press one of two
-- keys) as the ring meets it. Instants are plain circles; spells with a cast time are sliders: hold and keep the cursor
-- on the ball - let go or lose the ball and the cast is interrupted, no damage. The score is the DPS of that fight.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs, sqrt, cos, sin, pi = math.floor, math.min, math.max, math.abs, math.sqrt, math.cos, math.sin, math.pi
local T = A.TapTapRules

local O = {}
A.CircleRules = O
O.W, O.H = 600, 470                -- the board, in its own pixels
O.SPEEDS = {
  { name = 'Easy', x = 2, approach = 1.2, r = 38 },
  { name = 'Normal', x = 3, approach = 0.95, r = 34 },
  { name = 'Hard', x = 4, approach = 0.75, r = 30 },
}
O.WINDOW = { perfect = 0.06, good = 0.12, meh = 0.17 }   -- seconds either side of the circle's time
O.MULT = { perfect = 1, good = 0.8, meh = 0.5 }          -- share of the spell's damage
O.FOLLOW = 2.4      -- the ball counts as followed this many radii away
O.GRACE = 0.1       -- seconds the cursor may be off the ball before the cast is interrupted
O.END_EARLY = 0.2   -- a slider is done this long before its end, so the next circle can be clicked in time
O.LEAD = 2          -- seconds before the first circle
O.KEYS = { 'Z', 'X' }

-- the same chart for everyone at a speed, so best scores compare
local function rng(seed)
  local s = seed
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end
local function inside(x, y, m) return x >= m and x <= O.W - m and y >= m and y <= O.H - m end

function O.newSong(speedIndex)
  local sp = O.SPEEDS[speedIndex]
  local r = sp.r
  local rand = rng(7919 * speedIndex)
  local m = r + 16
  local objs, perfect = {}, 0
  local px, py, a = O.W / 2, O.H / 2, rand() * 2 * pi
  local prevEnd, num = nil, 0
  for i, c in ipairs(T.rotation()) do
    local o = { i = i, key = c.key, t = O.LEAD + c.t / sp.x, len = c.cast / sp.x, dmg = c.key == 'lifeTap' and 0 or T.castDamage(c.key) }
    o.slider = o.len > 0.2
    -- where: a jump from the last circle (or slider end), longer after a longer gap
    if prevEnd then
      local d = max(100, min(230, 60 + (o.t - prevEnd) * 240))
      for try = 1, 30 do
        local b = try == 1 and a + (rand() - 0.5) * 2.2 or rand() * 2 * pi
        local x, y = px + d * cos(b), py + d * sin(b)
        if inside(x, y, m) then o.x, o.y, a = x, y, b; break end
        if try > 12 then d = max(100, d * 0.9) end
      end
      if not o.x then o.x, o.y = m + rand() * (O.W - 2 * m), m + rand() * (O.H - 2 * m) end
    else
      o.x, o.y = O.W / 2, O.H / 2
    end
    if o.slider then
      local L = max(70, min(190, o.len * 300))
      for try = 1, 30 do
        local b = try == 1 and a + (rand() - 0.5) * 1.6 or rand() * 2 * pi
        local x, y = o.x + L * cos(b), o.y + L * sin(b)
        if inside(x, y, m) then o.ex, o.ey, a = x, y, b; break end
      end
      if not o.ex then   -- toward the middle, which always fits
        local dx, dy = O.W / 2 - o.x, O.H / 2 - o.y
        local dl = sqrt(dx * dx + dy * dy)
        if dl < 1 then dx, dy, dl = 1, 0, 1 end
        o.ex, o.ey = o.x + dx / dl * 70, o.y + dy / dl * 70
      end
      o.need = max(0.1, o.len - O.END_EARLY)
      px, py = o.ex, o.ey
    else
      px, py = o.x, o.y
    end
    prevEnd = o.t + o.len
    -- the numbers start again after each Life Tap
    num = (objs[#objs] and objs[#objs].key == 'lifeTap') and 1 or num + 1
    o.num = num
    objs[#objs + 1] = o
    perfect = perfect + o.dmg
  end
  local last = objs[#objs]
  return { objs = objs, speed = speedIndex, r = r, approach = sp.approach, perfect = perfect, t = 0, damage = 0, combo = 0,
    maxCombo = 0, counts = { perfect = 0, good = 0, meh = 0, miss = 0, interrupted = 0 }, down = 0, cx = -999, cy = -999,
    events = {}, length = last.t + last.len + 1.5, done = false, first = 1, out = 0 }
end

function O.ball(o, t)
  local f = max(0, min(1, (t - o.t) / o.len))
  return o.x + (o.ex - o.x) * f, o.y + (o.ey - o.y) * f
end
local function endSlider(s, o, ok)
  s.active = nil
  o.endAt = s.t
  if ok then
    o.finished = true
    s.damage = s.damage + o.pending
    s.events[#s.events + 1] = { kind = 'cast', x = o.ex, y = o.ey, dmg = o.pending }
  else
    o.interrupted = true
    s.counts.interrupted = s.counts.interrupted + 1
    s.combo = 0
    local bx, by = O.ball(o, s.t)
    s.events[#s.events + 1] = { kind = 'interrupted', x = bx, y = by }
  end
end
local function judge(s, o, q)
  o.judged = q
  o.hitAt = s.t
  s.counts[q] = s.counts[q] + 1
  if O.MULT[q] then
    s.combo = s.combo + 1
    s.maxCombo = max(s.maxCombo, s.combo)
    local dmg = o.dmg * O.MULT[q]
    if o.slider then
      if s.active then endSlider(s, s.active, s.t >= s.active.t + s.active.need) end
      o.pending = dmg; s.active = o; s.out = 0
    else s.damage = s.damage + dmg end
    s.events[#s.events + 1] = { kind = q, x = o.x, y = o.y, dmg = not o.slider and dmg > 0 and dmg or nil }
  else
    s.combo = 0
    s.events[#s.events + 1] = { kind = q, x = o.x, y = o.y }
  end
end

-- a click or key: hits the first open circle under the cursor
function O.press(s, x, y)
  if s.done then return end
  s.down = s.down + 1
  if x then s.cx, s.cy = x, y end
  local r2 = s.r * s.r
  for i = s.first, #s.objs do
    local o = s.objs[i]
    if o.t > s.t + O.WINDOW.meh then break end
    if not o.judged then
      local dx, dy = s.cx - o.x, s.cy - o.y
      if dx * dx + dy * dy <= r2 then
        local d = abs(s.t - o.t)
        judge(s, o, d <= O.WINDOW.perfect and 'perfect' or d <= O.WINDOW.good and 'good' or 'meh')
        return o
      end
    end
  end
end
function O.release(s)
  s.down = max(0, s.down - 1)
  if s.down == 0 and s.active and not s.done then endSlider(s, s.active, s.t >= s.active.t + s.active.need) end
end

function O.update(s, dt, x, y)
  if s.done then return end
  s.t = s.t + dt
  if x then s.cx, s.cy = x, y end
  local o = s.active
  if o then
    if s.t >= o.t + o.need then endSlider(s, o, true)
    else
      local bx, by = O.ball(o, s.t)
      local dx, dy = s.cx - bx, s.cy - by
      local f = O.FOLLOW * s.r
      if dx * dx + dy * dy > f * f then
        s.out = s.out + dt
        if s.out > O.GRACE then endSlider(s, o, false) end
      else s.out = 0 end
    end
  end
  for i = s.first, #s.objs do
    local m = s.objs[i]
    if m.t > s.t then break end
    if not m.judged and s.t > m.t + O.WINDOW.meh then judge(s, m, 'miss') end
  end
  while s.objs[s.first] and s.objs[s.first].judged do s.first = s.first + 1 end
  if s.t >= s.length then
    if s.active then endSlider(s, s.active, true) end
    s.done = true
    s.events[#s.events + 1] = { kind = 'done' }
  end
end
function O.dps(s) return s.damage / T.FIGHT end
function O.pct(s) return s.perfect > 0 and 100 * s.damage / s.perfect or 0 end
function O.rank(pct) return pct >= 99.95 and 'SS' or pct >= 95 and 'S' or pct >= 90 and 'A' or pct >= 80 and 'B' or pct >= 65 and 'C' or 'D' end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local SW = 290                   -- side panel width
local DOTS = 26                  -- circles that draw a slider's track
local COL = { corruption = { 0.45, 0.85, 0.3 }, baneOfAgony = { 0.7, 0.45, 1 }, immolate = { 1, 0.45, 0.15 },
  shadowBolt = { 0.95, 0.35, 0.75 }, lifeTap = { 0.3, 0.6, 1 } }
local LABEL = { perfect = { 'Perfect', C.good }, good = { 'Good', C.flame }, meh = { 'Meh', C.fire }, miss = { 'Miss', C.bad }, interrupted = { 'Interrupted!', C.bad } }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('circles')
  g.speedIndex = g.db.speed or 2
  g.held = {}
  g:loadKeys()
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, O.W, O.H, { 0.05, 0.04, 0.07 }, C.line, 2)
  board:SetPoint('TOP', f, 'TOP', -(SW + 16) / 2, -14)
  board:SetClipsChildren(true)   -- the closing rings of circles near the edge stay on the board
  board:EnableMouse(true)
  board:SetScript('OnMouseDown', function() self:press('MOUSE') end)
  board:SetScript('OnMouseUp', function() self:release('MOUSE') end)
  self.board = board
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.top = CreateFrame('Frame', nil, board)   -- above every circle (they sit at layer + 1..250)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 300)
  self.pop = K.popups(self.top)
  self.idle = K.text(self.top, 16, C.dim, 'CENTER')
  self.idle:SetPoint('CENTER')
  self.views, self.pool = {}, {}
  self.hint = K.text(f, 12, C.dim, 'CENTER')
  self.hint:SetPoint('TOPLEFT', board, 'BOTTOMLEFT', 0, -12); self.hint:SetPoint('TOPRIGHT', board, 'BOTTOMRIGHT', 0, -12)
  self.hint:SetWordWrap(true)
  -- side panel
  local side = K.box(f, SW, O.H, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  self.side = side
  local function line2(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 20, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.dpsT = line2(-14, 'DPS so far (of a ' .. T.FIGHT .. ' s fight)', 26, C.gold)
  self.pctT = line2(-70, 'Of a perfect rotation', 20)
  self.comboT = line2(-120, 'Combo', 20, C.chips)
  self.countT = line2(-170, 'Perfect / good / meh / miss / interrupted', 15, C.dim)
  self.speedT = line2(-218, 'Speed', 15)
  self.bestT = line2(-262, 'Best DPS at this speed', 15, C.dim)
  self.speedBtns = {}
  for i, sp in ipairs(O.SPEEDS) do
    local b = K.button(side, 84, 28, sp.name, function() self.speedIndex = i; self.db.speed = i; self:refreshSide() end, 'normal', 12)
    b:SetPoint('TOPLEFT', 14 + (i - 1) * 90, -320)
    self.speedBtns[i] = b
  end
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -360); note:SetPoint('TOPRIGHT', -12, -360); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('The same ' .. T.FIGHT .. ' s fight as Tap Tap DPS, now with aim. Casts are sliders: hold and follow the ball.')
  self.start = K.button(side, 262, 40, 'Play', function() self:play() end, 'orange', 16)
  self.start:SetPoint('BOTTOMLEFT', 14, 14)
  self.keysBtn = K.button(f, SW, 30, 'Change keys', function() self:openKeys() end, 'normal', 13)
  self.keysBtn:SetPoint('TOPLEFT', side, 'BOTTOMLEFT', 0, -8)
  self:buildKeys()
  self:refreshKeys()
  self:refreshSide()
end

-- keys: two, so one can be held through a cast while the other taps the next circle; saved in db.keys once changed
function G:loadKeys()
  self.keys = {}
  local saved = type(self.db.keys) == 'table' and self.db.keys or {}
  for i, k in ipairs(O.KEYS) do self.keys[i] = type(saved[i]) == 'string' and saved[i] or k end
end
function G:buildKeys()
  local p = K.box(self.f, SW, O.H, { 0.07, 0.05, 0.1, 0.98 }, C.line, 1)
  p:SetPoint('TOPLEFT', self.side, 'TOPLEFT')
  p:SetFrameLevel(self.side:GetFrameLevel() + 20)   -- before the children are made, so they sit on it
  p:EnableMouse(true)
  local title = K.text(p, 20, C.gold, 'CENTER', K.FONT_TITLE); title:SetPoint('TOP', 0, -12); title:SetText('Keys')
  local sub = K.text(p, 11, C.dim, 'LEFT'); sub:SetPoint('TOPLEFT', 14, -44); sub:SetPoint('TOPRIGHT', -12, -44); sub:SetWordWrap(true); sub:SetSpacing(2)
  sub:SetText('Point at a circle and press one of these instead of clicking. With two you can hold one through a cast and tap the next circle with the other.\n\nClick a key, then press the new one on your keyboard. Escape cancels.')
  p.rows = {}
  for i = 1, 2 do
    local y = -150 - (i - 1) * 50
    local name = K.text(p, 14, C.text, 'LEFT'); name:SetPoint('TOPLEFT', 14, y - 8); name:SetText('Key ' .. i)
    local b = K.button(p, 120, 30, '', function() self:startBinding(i) end, 'normal', 13)
    b:SetPoint('TOPRIGHT', -14, y)
    p.rows[i] = b
  end
  local def = K.button(p, 124, 32, 'Defaults', function() self.binding = nil; self.db.keys = nil; self:loadKeys(); self:refreshKeys(); A.sound('select') end, 'normal', 13)
  def:SetPoint('BOTTOMLEFT', 14, 14)
  local done = K.button(p, 124, 32, 'Done', function() self:closeKeys() end, 'blue', 13)
  done:SetPoint('BOTTOMRIGHT', -14, 14)
  p:Hide()
  self.keysPanel = p
end
function G:refreshKeys()
  for i, b in ipairs(self.keysPanel.rows) do
    if self.binding == i then b:SetLabel('Press a key'); b:SetStyle('gold')
    else b:SetLabel(T.keyLabel(self.keys[i])); b:SetStyle('normal') end
  end
  self.hint:SetText('Click the circles as the rings close in, or point and press ' .. T.keyLabel(self.keys[1]) .. ' / ' .. T.keyLabel(self.keys[2]) .. '. Hold the casts to the end.')
end
function G:openKeys()
  if self.s and not self.s.done then return end
  self.binding = nil
  self.keysPanel:Show()
  self:refreshKeys()
  A.sound('open')
end
function G:closeKeys()
  self.binding = nil
  self.keysPanel:Hide()
  self:refreshKeys()
end
function G:startBinding(i)
  if self.binding == i then self.binding = nil else self.binding = i end
  self:refreshKeys()
  A.sound('select')
end
function G:bindKey(key)
  local i = self.binding
  self.binding = nil
  if key ~= 'ESCAPE' and key ~= self.keys[i] then
    local other = 3 - i
    if self.keys[other] == key then self.keys[other] = self.keys[i] end   -- taken by the other one: they swap
    self.keys[i] = key
    self.db.keys = { self.keys[1], self.keys[2] }
    A.sound('select')
  end
  self:refreshKeys()
end

function G:refreshSide()
  local s = self.s
  self.dpsT:SetText(K.num(s and O.dps(s) or 0))
  self.pctT:SetText(s and string.format('%.1f%%', O.pct(s)) or '-')
  self.comboT:SetText((s and s.combo or 0) .. (s and s.maxCombo > 0 and ('  (best ' .. s.maxCombo .. ')') or ''))
  local c = s and s.counts or { perfect = 0, good = 0, meh = 0, miss = 0, interrupted = 0 }
  self.countT:SetText(c.perfect .. ' / ' .. c.good .. ' / ' .. c.meh .. ' / ' .. c.miss .. ' / ' .. c.interrupted)
  local sp = O.SPEEDS[self.speedIndex]
  self.speedT:SetText(sp.name .. ' (' .. sp.x .. 'x the real fight)')
  local best = self.db.best and self.db.best[self.speedIndex]
  self.bestT:SetText(best and (K.num(best) .. ' DPS') or '-')
  local playing = s and not s.done
  for i, b in ipairs(self.speedBtns) do b:SetStyle(i == self.speedIndex and 'gold' or 'normal'); b:SetEnabled(not playing) end
  self.keysBtn:SetEnabled(not playing)
  self.start:SetShown(not playing)
  self.start:SetLabel(s and s.done and 'Play again' or 'Play')
  if playing then self.idle:SetText('')
  elseif s and s.done then self.idle:SetText('')
  else self.idle:SetText('Press Play - the first circle shows up in the middle') end
end

function G:Show() self.f:Show(); self:refreshSide() end
function G:Hide() self.f:Hide(); GameTooltip:Hide(); self:releaseAll(); self:closeKeys() end
function G:OnPause() self:releaseAll() end

function G:cursorOnBoard()
  local x, y = GetCursorPosition()
  local sc = self.board:GetEffectiveScale()
  local l, b = self.board:GetLeft(), self.board:GetBottom()
  if not l then return nil end
  return x / sc - l, y / sc - b
end

function G:clearViews()
  for o, v in pairs(self.views) do v:Hide(); self.pool[#self.pool + 1] = v; self.views[o] = nil end
end
function G:play()
  if self.keysPanel:IsShown() then self:closeKeys() end
  self:clearViews()
  self.s = O.newSong(self.speedIndex)
  self.held = {}
  self.drawFrom = 1
  self.pop:clear()
  A.sound('open')
  self:refreshSide()
end
-- src: 'MOUSE' or a key; each one counts once while it is down
function G:press(src)
  local s = self.s
  if not s or s.done or self.held[src] then return end
  self.held[src] = true
  local x, y = self:cursorOnBoard()
  O.press(s, x, y)
end
function G:release(src)
  if not self.held[src] then return end
  self.held[src] = nil
  if self.s then O.release(self.s) end
end
function G:releaseAll() for src in pairs(self.held) do self:release(src) end end

function G:finish()
  local s = self.s
  local dps = O.dps(s)
  self.db.best = self.db.best or {}
  local isNew = dps > (self.db.best[s.speed] or 0)
  if isNew then self.db.best[s.speed] = dps end
  self:clearViews()
  self.pop:show('Rank ' .. O.rank(O.pct(s)), O.W / 2, O.H / 2 + 30, C.gold, 34, 4)
  self.pop:show((isNew and 'New best! ' or '') .. K.num(dps) .. ' DPS', O.W / 2, O.H / 2 - 20, C.text, 22, 4)
  A.sound('win')
  self.held = {}
  self:refreshSide()
end

-- one circle (or slider) on the board: a frame of its own so that earlier circles draw on top of later ones
function G:view(o)
  local v = table.remove(self.pool)
  if not v then
    v = CreateFrame('Frame', nil, self.layer)
    v:SetAllPoints(self.layer)
    v.dots = {}
    for d = 1, DOTS do local t = v:CreateTexture(nil, 'BACKGROUND'); t:SetTexture(K.MEDIA .. 'circle'); v.dots[d] = t end
    v.tail = v:CreateTexture(nil, 'BORDER'); v.tail:SetTexture(K.MEDIA .. 'ring')
    v.bg = v:CreateTexture(nil, 'ARTWORK'); v.bg:SetTexture(K.MEDIA .. 'circle')
    v.icon = v:CreateTexture(nil, 'ARTWORK', nil, 1); v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v.edge = v:CreateTexture(nil, 'ARTWORK', nil, 2); v.edge:SetTexture(K.MEDIA .. 'ring')
    v.num = K.text(v, 13, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE')
    v.ball = v:CreateTexture(nil, 'OVERLAY'); v.ball:SetTexture(K.MEDIA .. 'glow')
    v.follow = v:CreateTexture(nil, 'OVERLAY', nil, 1); v.follow:SetTexture(K.MEDIA .. 'ring')
    v.approach = v:CreateTexture(nil, 'OVERLAY', nil, 2); v.approach:SetTexture(K.MEDIA .. 'ring')
  end
  local s, r, c = self.s, self.s.r, COL[o.key]
  v:SetFrameLevel(self.layer:GetFrameLevel() + 1 + max(0, 250 - o.i))
  for d, t in ipairs(v.dots) do
    if o.slider then
      local f = (d - 1) / (DOTS - 1)
      t:SetSize(r * 1.84, r * 1.84)
      t:SetVertexColor(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 1)
      t:ClearAllPoints(); t:SetPoint('CENTER', v, 'BOTTOMLEFT', o.x + (o.ex - o.x) * f, o.y + (o.ey - o.y) * f)
      t:Show()
    else t:Hide() end
  end
  if o.slider then
    v.tail:SetSize(r * 1.84, r * 1.84); v.tail:SetVertexColor(c[1], c[2], c[3], 0.8)
    v.tail:ClearAllPoints(); v.tail:SetPoint('CENTER', v, 'BOTTOMLEFT', o.ex, o.ey); v.tail:Show()
  else v.tail:Hide() end
  v.bg:SetVertexColor(c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1)
  v.bg:ClearAllPoints(); v.bg:SetPoint('CENTER', v, 'BOTTOMLEFT', o.x, o.y)
  v.icon:SetTexture(K.spellTexture(A.SPELLS[o.key].id)); v.icon:SetDesaturated(false)
  v.icon:ClearAllPoints(); v.icon:SetPoint('CENTER', v.bg, 'CENTER')
  v.edge:SetVertexColor(1, 1, 1, 0.9)
  v.edge:ClearAllPoints(); v.edge:SetPoint('CENTER', v.bg, 'CENTER')
  v.num:ClearAllPoints(); v.num:SetPoint('CENTER', v.bg, 'CENTER', r * 0.62, -r * 0.62); v.num:SetText(tostring(o.num))
  v.approach:SetVertexColor(c[1], c[2], c[3], 1)
  v.approach:ClearAllPoints(); v.approach:SetPoint('CENTER', v.bg, 'CENTER')
  v.ball:SetSize(r * 1.5, r * 1.5); v.ball:SetVertexColor(c[1], c[2], c[3], 1)
  v.follow:SetSize(r * 2.6, r * 2.6); v.follow:SetVertexColor(1, 1, 1, 0.7)
  v.ball:Hide(); v.follow:Hide()
  v:Show()
  return v
end

-- how a circle looks now: nil once it is gone
local FADE = 0.22
local function look(s, o)
  local t = s.t
  if t < o.t - s.approach then return nil end
  local fin = o.endAt or (o.judged and (o.judged == 'miss' or not o.slider) and o.hitAt)
  local fade = fin and (t - fin) / FADE or 0
  if fade >= 1 then return nil end
  return min(1, (t - (o.t - s.approach)) / (s.approach * 0.4)) * (1 - fade), fade
end

function G:draw()
  local s = self.s
  local r = s.r
  while s.objs[self.drawFrom] and s.objs[self.drawFrom].t + s.objs[self.drawFrom].len + 1 < s.t and not look(s, s.objs[self.drawFrom]) do self.drawFrom = self.drawFrom + 1 end
  local seen = {}
  for i = self.drawFrom, #s.objs do
    local o = s.objs[i]
    if o.t - s.approach > s.t then break end
    local a, fade = look(s, o)
    if a then
      seen[o] = true
      local v = self.views[o] or self:view(o)
      self.views[o] = v
      v:SetAlpha(a)
      local hitCircle = o.judged and o.judged ~= 'miss'
      -- the head: grows and fades when hit; a slider's head goes once it is hit
      local grow = (hitCircle and not o.slider) and (1 + 0.45 * fade) or 1
      local showHead = not (hitCircle and o.slider)
      v.bg:SetShown(showHead); v.icon:SetShown(showHead); v.edge:SetShown(showHead)
      v.bg:SetSize(r * 2 * grow, r * 2 * grow); v.edge:SetSize(r * 2 * grow, r * 2 * grow); v.icon:SetSize(r * 1.2 * grow, r * 1.2 * grow)
      v.icon:SetDesaturated(o.judged == 'miss')
      v.num:SetShown(not o.judged)
      if not o.judged then
        local k = 1 + 2.2 * max(0, (o.t - s.t) / s.approach)
        v.approach:SetSize(r * 2 * k, r * 2 * k); v.approach:Show()
      else v.approach:Hide() end
      if o.slider and (s.active == o or (o.judged and o.judged ~= 'miss')) then
        local bx, by = O.ball(o, s.t)
        v.ball:ClearAllPoints(); v.ball:SetPoint('CENTER', v, 'BOTTOMLEFT', bx, by); v.ball:Show()
        v.follow:ClearAllPoints(); v.follow:SetPoint('CENTER', v, 'BOTTOMLEFT', bx, by)
        v.follow:SetShown(s.active == o and s.out == 0)
      else v.ball:Hide(); v.follow:Hide() end
    end
  end
  for o, v in pairs(self.views) do if not seen[o] then v:Hide(); self.pool[#self.pool + 1] = v; self.views[o] = nil end end
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if not s or s.done then return end
  local x, y = self:cursorOnBoard()
  O.update(s, dt, x, y)
  for _, e in ipairs(s.events) do
    if LABEL[e.kind] then self.pop:show(LABEL[e.kind][1], e.x, e.y + s.r + 12, LABEL[e.kind][2], 15, 0.6) end
    if e.dmg and e.dmg > 0 then self.pop:show(K.num(e.dmg), e.x, e.y - s.r - 10, C.gold, 13, 0.7) end
  end
  local events = s.events
  s.events = {}
  if #events > 0 then self:refreshSide() end
  if s.done then self:finish() else self:draw() end
end

function G:OnKey(key)
  if self.binding then self:bindKey(key); return true end
  local s = self.s
  local playing = s and not s.done
  if not playing then
    if self.keysPanel:IsShown() then
      if key == 'ESCAPE' or key == 'ENTER' then self:closeKeys(); return true end
      return false
    end
    if key == 'ENTER' then self:play(); return true end
    return false
  end
  if key == self.keys[1] or key == self.keys[2] then self:press(key); return true end
  return false
end
function G:OnKeyUp(key) self:release(key) end

A.RegisterGame({
  key = 'circles', name = 'Soul Circles', order = 9, ready = true, icon = A.SPELLS.hellfire.id,
  tagline = 'Click the spells as the rings close in, follow your casts. Your aim is your DPS.',
  bestLine = function() local b = A.db('circles').best; local v = b and (b[3] or b[2] or b[1]); return v and ('Best: ' .. K.num(v) .. ' DPS') or 'Play' end,
  help = {
    '|cffffd040Click each circle as its ring closes in on it.|r Or point at it and press Z or X (Change keys picks others). The numbers show the order.',
    ' ',
    'Circles are your instant spells: Bane of Agony and Life Tap. |cffffd040Sliders are casts|r (Shadow Bolt, Corruption, Immolate): click the start, keep the button or key down and stay on the ball to the end. Let go early or lose the ball and the cast is interrupted - no damage.',
    ' ',
    'The chart is the same real rotation as Tap Tap DPS: a ' .. T.FIGHT .. ' s fight of the Forever Warlock Sim\'s standard character, played 2, 3 or 4 times faster. Every circle is worth the spell\'s real damage (Perfect: all of it, Good: 80%, Meh: 50%). Your score is the DPS that fight would have done, and a rank from D to SS.',
  },
  create = function(parent) return G.create(parent) end,
})
