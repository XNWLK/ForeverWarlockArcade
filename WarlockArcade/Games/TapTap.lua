-- Tap Tap DPS: the rotation is the song chart. A 120 s fight of the sim's standard character (Bane of Agony, Corruption
-- and Immolate kept up, Shadow Bolt as the filler, Life Tap when mana runs low - real cast times, durations, costs and
-- damage from A.CAST / A.CHARACTER) is played faster, as falling notes in four lanes. Spells with a cast time are hold
-- notes: let go early and the cast is interrupted - no damage, like the game. Life Tap is a Space note across all lanes.
-- The score is the DPS that fight would have done, and how much of a perfect run that is.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs, random = math.floor, math.min, math.max, math.abs, math.random

local T = {}
A.TapTapRules = T
T.FIGHT = 120
T.LANES = { 'corruption', 'baneOfAgony', 'immolate', 'shadowBolt' }
T.LANE_OF = { corruption = 1, baneOfAgony = 2, immolate = 3, shadowBolt = 4 }
T.KEYS = { 'D', 'F', 'J', 'K', 'SPACE' }   -- the default keys: four lanes, then Life Tap (players can change them)
-- a key's name as shown on screen ('SPACE' -> 'Space', 'NUMPAD1' -> 'Num 1', 'D' -> 'D')
local KEY_NAMES = { LSHIFT = 'Shift', RSHIFT = 'Right Shift', LCTRL = 'Ctrl', RCTRL = 'Right Ctrl', LALT = 'Alt', RALT = 'Right Alt' }
function T.keyLabel(k)
  if not k then return '-' end
  if KEY_NAMES[k] then return KEY_NAMES[k] end
  local n = k:match('^NUMPAD(.+)$')
  if n then return 'Num ' .. n end
  if #k > 1 and k:match('^%u+$') then return k:sub(1, 1) .. k:sub(2):lower() end
  return k
end
T.SPEEDS = { { name = 'Easy', x = 2 }, { name = 'Normal', x = 3 }, { name = 'Hard', x = 4 } }
T.PERFECT, T.GOOD = 0.06, 0.13     -- seconds of song time either side of the note
T.LEAD = 2                         -- seconds before the first note

-- the standard character's average damage of a cast (crits counted at their chance) - what a perfect hit deals
function T.castDamage(key)
  local c = A.CAST[key]
  local ch = A.CHARACTER
  local direct = (c.direct or 0) * (1 + ch.critPct / 100 * (ch.critMult - 1))
  return direct + (c.tick and c.tick * c.ticks or 0)
end

-- the rotation, in fight time: { key, t, cast }
function T.rotation()
  local ch = A.CHARACTER
  local t, mana, gcd = 0, ch.maxMana, ch.gcd
  local ends = { corruption = -1, baneOfAgony = -1, immolate = -1 }
  local casts = {}
  while t < T.FIGHT - 0.5 do
    local key
    if ends.baneOfAgony <= t then key = 'baneOfAgony'
    elseif ends.corruption <= t + A.CAST.corruption.cast then key = 'corruption'
    elseif ends.immolate <= t + A.CAST.immolate.cast then key = 'immolate'
    else key = 'shadowBolt' end
    -- no DoTs that would not finish ticking much before the fight ends
    if key ~= 'shadowBolt' and t + A.CAST[key].duration * 0.5 > T.FIGHT then key = 'shadowBolt' end
    if mana < A.CAST[key].cost then key = 'lifeTap' end
    local cast = key == 'lifeTap' and 0 or A.CAST[key].cast
    local busy = max(gcd, cast)
    if t + busy > T.FIGHT then break end
    casts[#casts + 1] = { key = key, t = t, cast = cast }
    if key == 'lifeTap' then mana = min(ch.maxMana, mana + ch.tapMana)
    else
      mana = mana - A.CAST[key].cost
      if ends[key] then ends[key] = t + cast + A.CAST[key].duration end
    end
    mana = min(ch.maxMana, mana + ch.mp5 / 5 * busy)
    t = t + busy
  end
  return casts
end

-- a song: notes in song time (fight time / speed)
function T.newSong(speedIndex)
  local sp = T.SPEEDS[speedIndex].x
  local notes, perfect = {}, 0
  for _, c in ipairs(T.rotation()) do
    local n = { key = c.key, lane = T.LANE_OF[c.key] or 0, t = T.LEAD + c.t / sp, len = c.cast / sp, dmg = c.key == 'lifeTap' and 0 or T.castDamage(c.key) }
    n.hold = n.len > 0.2
    notes[#notes + 1] = n
    perfect = perfect + n.dmg
  end
  local last = notes[#notes]
  return { notes = notes, speed = speedIndex, perfect = perfect, t = 0, damage = 0, combo = 0, maxCombo = 0,
    counts = { perfect = 0, good = 0, miss = 0, interrupted = 0 }, held = {}, events = {}, length = last.t + last.len + 1.5, done = false }
end

local function judge(s, n, dt)
  local d = abs(dt)
  local q = d <= T.PERFECT and 'perfect' or d <= T.GOOD and 'good' or nil
  return q
end
local function award(s, n, q)
  n.judged = q
  s.counts[q] = s.counts[q] + 1
  if q == 'perfect' or q == 'good' then
    s.combo = s.combo + 1
    s.maxCombo = max(s.maxCombo, s.combo)
    local dmg = n.dmg * (q == 'perfect' and 1 or 0.8)
    -- a cast's damage lands when the cast is done; an instant lands now
    if n.hold then n.pending = dmg else s.damage = s.damage + dmg end
    s.events[#s.events + 1] = { kind = q, lane = n.lane, dmg = not n.hold and dmg or nil }
  else
    s.combo = 0
    s.events[#s.events + 1] = { kind = q, lane = n.lane }
  end
end
-- a lane (1-4, or 0 for Life Tap) pressed / let go
function T.press(s, lane)
  if s.done then return end
  -- a cast still held in this lane: done if it was about to end, interrupted if not
  if s.held[lane] then T.release(s, lane) end
  local best, bestD
  for _, n in ipairs(s.notes) do
    if not n.judged and n.lane == lane then
      local d = s.t - n.t
      if abs(d) <= T.GOOD and (not bestD or abs(d) < abs(bestD)) then best, bestD = n, d end
      if n.t > s.t + T.GOOD then break end
    end
  end
  if not best then s.events[#s.events + 1] = { kind = 'empty', lane = lane }; return end
  award(s, best, judge(s, best, bestD))
  if best.hold then s.held[lane] = best end
end
function T.release(s, lane)
  local n = s.held[lane]
  if not n then return end
  s.held[lane] = nil
  local left = n.t + n.len - s.t
  if left > T.GOOD then
    n.interrupted = true
    s.counts.interrupted = s.counts.interrupted + 1
    s.combo = 0
    n.pending = nil
    s.events[#s.events + 1] = { kind = 'interrupted', lane = lane }
  else
    s.damage = s.damage + (n.pending or 0); n.pending = nil; n.finished = true
    s.events[#s.events + 1] = { kind = 'cast', lane = lane, dmg = n.dmg }
  end
end
function T.update(s, dt)
  if s.done then return end
  s.t = s.t + dt
  for _, n in ipairs(s.notes) do
    if n.t > s.t + 1 then break end
    if not n.judged and s.t - n.t > T.GOOD then award(s, n, 'miss') end
  end
  -- a held cast that reaches its end finishes by itself; if the next note of that lane starts right then, keep holding
  -- and it starts too (a chain of Shadow Bolts is one long hold)
  for lane, n in pairs(s.held) do
    if s.t >= n.t + n.len then
      s.held[lane] = nil; s.damage = s.damage + (n.pending or 0); n.pending = nil; n.finished = true
      s.events[#s.events + 1] = { kind = 'cast', lane = lane, dmg = n.dmg }
      for _, m in ipairs(s.notes) do
        if not m.judged and m.lane == lane and m.hold and abs(m.t - (n.t + n.len)) <= T.GOOD then award(s, m, 'perfect'); s.held[lane] = m; break end
        if m.t > n.t + n.len + T.GOOD then break end
      end
    end
  end
  if s.t >= s.length then s.done = true; s.events[#s.events + 1] = { kind = 'done' } end
end
function T.dps(s) return s.damage / T.FIGHT end
function T.perfectDps(s) return s.perfect / T.FIGHT end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local LW, BH = 104, 470          -- lane width, board height
local HIT_Y = 70                 -- the hit line, from the bottom of the board
local SCROLL = 330               -- pixels per second of song time
local COL = { { 0.45, 0.85, 0.3 }, { 0.7, 0.45, 1 }, { 1, 0.45, 0.15 }, { 0.8, 0.5, 1 } }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('taptap')
  g.speedIndex = g.db.speed or 2
  g:loadKeys()
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local bw = LW * 4
  local board = K.box(f, bw, BH, { 0.05, 0.04, 0.07 }, C.line, 2)
  board:SetPoint('TOP', f, 'TOP', -150, -14)
  self.board = board
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 3)
  self.lanes = {}
  for i = 1, 4 do
    local l = CreateFrame('Button', nil, board)
    l:SetSize(LW, BH)
    l:SetPoint('BOTTOMLEFT', (i - 1) * LW, 0)
    l:SetFrameLevel(board:GetFrameLevel() + 1)
    l.bg = K.rect(l, 'BACKGROUND', COL[i], 0.05); l.bg:SetAllPoints()
    if i > 1 then local sep = K.rect(l, 'BORDER', C.line, 0.6); sep:SetPoint('TOPLEFT'); sep:SetPoint('BOTTOMLEFT'); sep:SetWidth(1) end
    l.flash = K.rect(l, 'ARTWORK', COL[i], 0); l.flash:SetAllPoints()
    l.ring = l:CreateTexture(nil, 'ARTWORK', nil, 1); l.ring:SetTexture(K.MEDIA .. 'ring'); l.ring:SetSize(58, 58); l.ring:SetPoint('CENTER', l, 'BOTTOM', 0, HIT_Y); l.ring:SetVertexColor(COL[i][1], COL[i][2], COL[i][3], 0.9)
    l.key = K.text(l, 14, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); l.key:SetPoint('TOP', l.ring, 'BOTTOM', 0, -6); l.key:SetText(T.keyLabel(self.keys[i]))
    l.name = K.text(l, 10, C.dim, 'CENTER'); l.name:SetPoint('BOTTOM', 0, 6); l.name:SetText(A.SPELLS[T.LANES[i]].name)
    l.lane = i
    l:RegisterForClicks('LeftButtonUp')
    l:SetScript('OnMouseDown', function(b) self:press(b.lane) end)
    l:SetScript('OnMouseUp', function(b) self:release(b.lane) end)
    self.lanes[i] = l
  end
  local line = K.rect(self.layer, 'BORDER', { 1, 1, 1 }, 0.25); line:SetPoint('BOTTOMLEFT', 0, HIT_Y); line:SetPoint('BOTTOMRIGHT', 0, HIT_Y); line:SetHeight(2)
  self.notePool, self.used = {}, {}
  self.pop = K.popups(self.layer)
  -- Life Tap button (also Space)
  self.tapBtn = K.button(f, bw, 34, 'Life Tap', nil, 'normal', 13)
  self.tapBtn:SetPoint('TOP', board, 'BOTTOM', 0, -8)
  self.tapBtn:SetScript('OnMouseDown', function() self:press(0) end)
  -- side panel
  local side = K.box(f, 290, BH, C.panel, C.line, 1)
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
  self.countT = line2(-170, 'Perfect / good / miss / interrupted', 15, C.dim)
  self.speedT = line2(-218, 'Speed', 15)
  self.bestT = line2(-262, 'Best DPS at this speed', 15, C.dim)
  self.speedBtns = {}
  for i, sp in ipairs(T.SPEEDS) do
    local b = K.button(side, 84, 28, sp.name, function() self.speedIndex = i; self.db.speed = i; self:refreshSide() end, 'normal', 12)
    b:SetPoint('TOPLEFT', 14 + (i - 1) * 90, -320)
    self.speedBtns[i] = b
  end
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -360); note:SetPoint('TOPRIGHT', -12, -360); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('The chart is a ' .. T.FIGHT .. ' s fight of the sim\'s standard character, played faster. Hold the notes with a tail until they end - let go early and the cast is interrupted.')
  self.start = K.button(side, 262, 40, 'Play', function() self:play() end, 'orange', 16)
  self.start:SetPoint('BOTTOMLEFT', 14, 14)
  self.keysBtn = K.button(f, 290, 34, 'Change keys', function() self:openKeys() end, 'normal', 13)
  self.keysBtn:SetPoint('TOPLEFT', side, 'BOTTOMLEFT', 0, -8)
  self:buildKeys()
  self:refreshKeys()
  self:refreshSide()
end

-- the keys: self.keys[1..4] are the lanes, [5] Life Tap; saved in db.keys once changed
function G:loadKeys()
  self.keys = {}
  local saved = type(self.db.keys) == 'table' and self.db.keys or {}
  for i, k in ipairs(T.KEYS) do self.keys[i] = type(saved[i]) == 'string' and saved[i] or k end
end
-- the action (1-4 a lane, 5 Life Tap) a key does: the player's keys first, then 1 2 3 4 for the lanes when free
function G:actionOf(key)
  for i, k in ipairs(self.keys) do if k == key then return i end end
  local d = tonumber(key)
  if d and d >= 1 and d <= 4 and key == tostring(d) then return d end
end

local KEY_ROWS = { { 'Lane 1', 'corruption' }, { 'Lane 2', 'baneOfAgony' }, { 'Lane 3', 'immolate' }, { 'Lane 4', 'shadowBolt' }, { 'All lanes', 'lifeTap' } }
function G:buildKeys()
  local p = K.box(self.f, 290, BH, { 0.07, 0.05, 0.1, 0.98 }, C.line, 1)
  p:SetPoint('TOPLEFT', self.side, 'TOPLEFT')
  p:SetFrameLevel(self.side:GetFrameLevel() + 20)   -- before the children are made, so they sit on it
  p:EnableMouse(true)
  local title = K.text(p, 20, C.gold, 'CENTER', K.FONT_TITLE); title:SetPoint('TOP', 0, -12); title:SetText('Keys')
  local sub = K.text(p, 11, C.dim, 'LEFT'); sub:SetPoint('TOPLEFT', 14, -44); sub:SetPoint('TOPRIGHT', -12, -44); sub:SetWordWrap(true); sub:SetSpacing(2)
  sub:SetText('Click a key, then press the new one on your keyboard. Escape cancels. 1 2 3 4 also play the lanes while they are free.')
  p.rows = {}
  for i, r in ipairs(KEY_ROWS) do
    local y = -100 - (i - 1) * 52
    local icon = K.icon(p, 32, A.SPELLS[r[2]].id); icon:SetPoint('TOPLEFT', 14, y)
    local name = K.text(p, 13, C.text, 'LEFT'); name:SetPoint('TOPLEFT', icon, 'TOPRIGHT', 8, -1); name:SetText(A.SPELLS[r[2]].name)
    local lane = K.text(p, 10, C.dim, 'LEFT'); lane:SetPoint('TOPLEFT', name, 'BOTTOMLEFT', 0, -3); lane:SetText(r[1])
    local b = K.button(p, 104, 30, '', function() self:startBinding(i) end, 'normal', 13)
    b:SetPoint('TOPRIGHT', -14, y - 1)
    p.rows[i] = b
  end
  local def = K.button(p, 124, 32, 'Defaults', function() self.binding = nil; self.db.keys = nil; self:loadKeys(); self.keysPanel.msg:SetText(''); self:refreshKeys(); A.sound('select') end, 'normal', 13)
  def:SetPoint('BOTTOMLEFT', 14, 14)
  local done = K.button(p, 124, 32, 'Done', function() self:closeKeys() end, 'blue', 13)
  done:SetPoint('BOTTOMRIGHT', -14, 14)
  p.msg = K.text(p, 11, C.flame, 'CENTER'); p.msg:SetPoint('BOTTOMLEFT', 14, 56); p.msg:SetPoint('BOTTOMRIGHT', -14, 56); p.msg:SetWordWrap(true)
  p:Hide()
  self.keysPanel = p
end
function G:refreshKeys()
  for i, l in ipairs(self.lanes) do l.key:SetText(T.keyLabel(self.keys[i])) end
  self.tapBtn:SetLabel('Life Tap  (' .. T.keyLabel(self.keys[5]) .. ')')
  for i, b in ipairs(self.keysPanel.rows) do
    if self.binding == i then b:SetLabel('Press a key'); b:SetStyle('gold')
    else b:SetLabel(T.keyLabel(self.keys[i])); b:SetStyle('normal') end
  end
end
function G:openKeys()
  if self.s and not self.s.done then return end
  self.binding = nil
  self.keysPanel.msg:SetText('')
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
  self.keysPanel.msg:SetText('')
  self:refreshKeys()
  A.sound('select')
end
-- a key pressed while waiting for one: it becomes that action's key; an action that had it gets the old key instead
function G:bindKey(key)
  local i = self.binding
  self.binding = nil
  local msg = ''
  if key ~= 'ESCAPE' and key ~= self.keys[i] then
    local old = self.keys[i]
    for j, k in ipairs(self.keys) do
      if j ~= i and k == key then
        self.keys[j] = old
        msg = T.keyLabel(key) .. ' was on ' .. A.SPELLS[KEY_ROWS[j][2]].name .. ' - that one is now on ' .. T.keyLabel(old)
      end
    end
    self.keys[i] = key
    local db = {}
    for j, k in ipairs(self.keys) do db[j] = k end
    self.db.keys = db
    A.sound('select')
  end
  self.keysPanel.msg:SetText(msg)
  self:refreshKeys()
end

function G:noteFrame()
  local n = table.remove(self.notePool)
  if not n then
    n = {}
    n.tail = self.layer:CreateTexture(nil, 'BORDER'); n.tail:SetWidth(16)
    n.bg = self.layer:CreateTexture(nil, 'ARTWORK'); n.bg:SetTexture(K.MEDIA .. 'circle'); n.bg:SetSize(56, 56)
    n.icon = self.layer:CreateTexture(nil, 'ARTWORK', nil, 1); n.icon:SetSize(38, 38); n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    n.wide = self.layer:CreateTexture(nil, 'ARTWORK'); n.wide:SetHeight(18)
    n.wideText = K.text(self.layer, 12, { 1, 1, 1 }, 'CENTER', K.FONT, 'OUTLINE')
  end
  return n
end
function G:hideNote(v) v.tail:Hide(); v.bg:Hide(); v.icon:Hide(); v.wide:Hide(); v.wideText:Hide() end

function G:refreshSide()
  local s = self.s
  self.dpsT:SetText(K.num(s and T.dps(s) or 0))
  self.pctT:SetText(s and string.format('%.1f%%', 100 * s.damage / s.perfect) or '-')
  self.comboT:SetText((s and s.combo or 0) .. (s and s.maxCombo > 0 and ('  (best ' .. s.maxCombo .. ')') or ''))
  local c = s and s.counts or { perfect = 0, good = 0, miss = 0, interrupted = 0 }
  self.countT:SetText(c.perfect .. ' / ' .. c.good .. ' / ' .. c.miss .. ' / ' .. c.interrupted)
  local sp = T.SPEEDS[self.speedIndex]
  self.speedT:SetText(sp.name .. ' (' .. sp.x .. 'x the real fight)')
  local best = self.db.best and self.db.best[self.speedIndex]
  self.bestT:SetText(best and (K.num(best) .. ' DPS') or '-')
  local playing = s and not s.done
  for i, b in ipairs(self.speedBtns) do b:SetStyle(i == self.speedIndex and 'gold' or 'normal'); b:SetEnabled(not playing) end
  if self.keysBtn then self.keysBtn:SetEnabled(not playing) end
  self.start:SetShown(not playing)
  self.start:SetLabel(s and s.done and 'Play again' or 'Play')
end

function G:Show() self.f:Show(); self:refreshSide() end
function G:Hide() self.f:Hide(); GameTooltip:Hide(); if self.keysPanel then self:closeKeys() end end
function G:OnPause() end

function G:play()
  if self.keysPanel:IsShown() then self:closeKeys() end
  self.s = T.newSong(self.speedIndex)
  for _, v in pairs(self.used) do self:hideNote(v); self.notePool[#self.notePool + 1] = v end
  self.used = {}
  self.pop:clear()
  self.message = nil
  A.sound('open')
  self:refreshSide()
end
function G:press(lane)
  local s = self.s
  if not s or s.done then return end
  T.press(s, lane)
  local l = self.lanes[lane]
  if l then l.flashT = 0.12 end
end
function G:release(lane) if self.s then T.release(self.s, lane) end end

function G:finish()
  local s = self.s
  local dps = T.dps(s)
  self.db.best = self.db.best or {}
  local isNew = dps > (self.db.best[s.speed] or 0)
  if isNew then self.db.best[s.speed] = dps end
  self.pop:show((isNew and 'New best! ' or '') .. K.num(dps) .. ' DPS', 2 * LW, BH / 2, C.gold, 26, 3)
  A.sound('win')
  self:refreshSide()
end

local LABEL = { perfect = { 'Perfect', C.good }, good = { 'Good', C.flame }, miss = { 'Miss', C.bad }, interrupted = { 'Interrupted!', C.bad } }
function G:OnUpdate(dt)
  self.pop:update(dt)
  for _, l in ipairs(self.lanes) do
    if l.flashT then l.flashT = l.flashT - dt; l.flash:SetAlpha(max(0, l.flashT) * 2.5); if l.flashT <= 0 then l.flashT = nil; l.flash:SetAlpha(0) end end
  end
  local s = self.s
  if not s or s.done then return end
  T.update(s, dt)
  for _, e in ipairs(s.events) do
    local x = e.lane and e.lane > 0 and (e.lane - 0.5) * LW or 2 * LW
    if LABEL[e.kind] then self.pop:show(LABEL[e.kind][1], x, HIT_Y + 44, LABEL[e.kind][2], 15, 0.6) end
    if e.dmg and e.dmg > 0 then self.pop:show(K.num(e.dmg), x, HIT_Y + 66, C.gold, 13, 0.7) end
    if e.kind == 'done' then self:finish() end
  end
  if #s.events > 0 then self:refreshSide() end
  s.events = {}
  -- draw the notes in view
  local seen = {}
  for i, n in ipairs(s.notes) do
    local dy = (n.t - s.t) * SCROLL
    if dy > BH - HIT_Y - 28 then break end   -- not drawn above the top of the board
    local top = dy + n.len * SCROLL
    local gone = (n.judged == 'miss' and dy < -40) or (n.judged and n.judged ~= 'miss' and (not n.hold or n.interrupted or n.finished))
    if top > -60 and not gone then
      seen[i] = true
      local v = self.used[i]
      if not v then v = self:noteFrame(); self.used[i] = v end
      local y = HIT_Y + max(dy, (n.hold and s.held[n.lane] == n) and 0 or dy)
      if n.lane == 0 then
        v.wide:SetColorTexture(0.2, 0.55, 0.95, n.judged == 'miss' and 0.3 or 0.85)
        v.wide:ClearAllPoints(); v.wide:SetPoint('LEFT', self.board, 'BOTTOMLEFT', 4, HIT_Y + dy); v.wide:SetPoint('RIGHT', self.board, 'BOTTOMRIGHT', -4, HIT_Y + dy); v.wide:Show()
        v.wideText:ClearAllPoints(); v.wideText:SetPoint('CENTER', v.wide, 'CENTER'); v.wideText:SetText('Life Tap - ' .. T.keyLabel(self.keys[5])); v.wideText:Show()
      else
        local c = COL[n.lane]
        local cx = (n.lane - 0.5) * LW
        if n.hold then
          v.tail:SetColorTexture(c[1], c[2], c[3], n.judged == 'miss' and 0.2 or 0.55)
          v.tail:ClearAllPoints(); v.tail:SetPoint('BOTTOM', self.board, 'BOTTOMLEFT', cx, y); v.tail:SetHeight(max(1, min(BH - 4, HIT_Y + top) - y)); v.tail:Show()
        end
        v.bg:SetVertexColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, n.judged == 'miss' and 0.35 or 1)
        v.bg:ClearAllPoints(); v.bg:SetPoint('CENTER', self.board, 'BOTTOMLEFT', cx, y); v.bg:Show()
        v.icon:SetTexture(K.spellTexture(A.SPELLS[n.key].id)); v.icon:SetDesaturated(n.judged == 'miss')
        v.icon:ClearAllPoints(); v.icon:SetPoint('CENTER', v.bg, 'CENTER'); v.icon:Show()
      end
    end
  end
  for i, v in pairs(self.used) do if not seen[i] then self:hideNote(v); self.notePool[#self.notePool + 1] = v; self.used[i] = nil end end
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
  local a = self:actionOf(key)
  if a then self:press(a == 5 and 0 or a); return true end
  return false
end
function G:OnKeyUp(key)
  local a = self:actionOf(key)
  if a and a < 5 then self:release(a) end
end

A.RegisterGame({
  key = 'taptap', name = 'Tap Tap DPS', order = 7, ready = true, icon = A.SPELLS.rainOfFire.id,
  tagline = 'Your rotation is the song chart. Hit every note.',
  bestLine = function() local b = A.db('taptap').best; local v = b and (b[3] or b[2] or b[1]); return v and ('Best: ' .. K.num(v) .. ' DPS') or 'Play' end,
  help = {
    '|cffffd040Hit the notes as they reach the rings.|r Keys D F J K (or 1 2 3 4), or click / tap the lane. Space is Life Tap. Change keys (under the side panel) lets you pick your own.',
    ' ',
    'The chart is a real rotation: a ' .. T.FIGHT .. ' s fight of the Forever Warlock Sim\'s standard character - Bane of Agony, Corruption and Immolate kept up, Shadow Bolt in between, Life Tap when mana runs low - with the real cast times and durations, played 2, 3 or 4 times faster.',
    ' ',
    'Notes with a tail are casts: hold until the tail ends. Let go early and the cast is interrupted - no damage, just like in the game.',
    ' ',
    'Every note is worth the spell\'s real damage (Perfect: all of it, Good: 80%). Your score is the DPS that fight would have done.',
  },
  create = function(parent) return G.create(parent) end,
})
