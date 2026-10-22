-- Guess the DPS: five questions about the Forever Warlock Sim's published results - how much DPS a build does, how much
-- damage one spell deals in it over the fight, how often it is cast, how much DPS 1% of a stat is worth. Slide to your
-- guess and lock it in; the closer, the more points (out of 100 a question). One round a day (the same for everyone)
-- and practice rounds.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local RES = A.RESULTS

local Q = {}
A.GuessDpsRules = Q
Q.ROUND = 5
local STAT = { sp = '1 spell power', hitPct = '1% hit', critPct = '1% crit', hastePct = '1% haste' }
local function buildName(key) return RES.builds[key] and RES.builds[key].name or key end
local function buildIcon(key) local b = RES.builds[key]; return b and A.SPELLS[b.icon] and A.SPELLS[b.icon].id end

-- every question there can be, by kind; each kind's range sets how far off a guess may be
function Q.pool()
  if Q._pool then return Q._pool end
  local kinds = {
    dps = { label = 'DPS of the build', short = 'build DPS', unit = ' DPS', list = {} },
    dmg = { label = 'Damage over the fight', short = 'spell damage', unit = ' damage', list = {} },
    casts = { label = 'Casts in the fight', short = 'casts', unit = ' casts', list = {} },
    weight = { label = 'DPS for one more ...', short = 'stat worth', unit = ' DPS', list = {} },
  }
  for _, r in ipairs(RES.dps) do
    table.insert(kinds.dps.list, { title = buildName(r.build), sub = (r.race == 'no racial' and 'No racial' or r.race) .. ' - how much DPS?', icon = buildIcon(r.build), value = r.dps })
  end
  for _, r in ipairs(RES.spells) do
    if r.race == nil or r.race == 'Human' then
      local s = A.SPELLS[r.spell]
      local b = RES.builds[r.build]
      local icon = s and s.id or (b and b.pet and A.PETS[b.pet] and A.PETS[b.pet].spell)
      if r.dmg and r.dmg > 0 then table.insert(kinds.dmg.list, { title = r.name, sub = 'in ' .. buildName(r.build) .. ' - its damage over the fight?', icon = icon, value = r.dmg }) end
      if r.casts and r.casts >= 1 and s then table.insert(kinds.casts.list, { title = r.name, sub = 'in ' .. buildName(r.build) .. ' - how many casts?', icon = icon, value = r.casts }) end
    end
  end
  for bk, w in pairs(RES.weights) do
    for stat, label in pairs(STAT) do
      if w[stat] then table.insert(kinds.weight.list, { title = buildName(bk), sub = 'how much DPS is ' .. label .. ' worth?', icon = buildIcon(bk), value = w[stat] }) end
    end
  end
  local order = {}
  for _, key in ipairs({ 'dps', 'dmg', 'casts', 'weight' }) do
    local k = kinds[key]
    if #k.list > 0 then
      local lo, hi = math.huge, -math.huge
      for _, x in ipairs(k.list) do lo = min(lo, x.value); hi = max(hi, x.value) end
      -- the slider goes a bit past the lowest and highest answer
      local pad = (hi - lo) * 0.15 + (hi == lo and 1 or 0)
      k.lo, k.hi = max(0, lo - pad), hi + pad
      k.key = key
      order[#order + 1] = k
    end
  end
  Q._pool = order
  return order
end
-- points for a guess: 100 when spot on, 0 a quarter of the slider away
function Q.points(kind, guess, value)
  local span = kind.hi - kind.lo
  return floor(100 * max(0, 1 - 4 * abs(guess - value) / span) + 0.5)
end
local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
-- a round: five questions, a different kind each time where it can
function Q.newRound(seed, daily)
  local rand = rng(seed)
  local pool = Q.pool()
  local qs, used = {}, {}
  for i = 1, Q.ROUND do
    local kind = pool[((i - 1 + rand(#pool)) % #pool) + 1]
    local item
    for try = 1, 20 do
      item = kind.list[rand(#kind.list)]
      if not used[item] then break end
    end
    used[item] = true
    qs[i] = { kind = kind.key, item = item }
  end
  return { qs = qs, at = 1, guesses = {}, points = {}, total = 0, done = false, daily = daily }
end
function Q.kindOf(key) for _, k in ipairs(Q.pool()) do if k.key == key then return k end end end
function Q.answer(s, guess)
  if s.done then return nil end
  local q = s.qs[s.at]
  local kind = Q.kindOf(q.kind)
  local p = Q.points(kind, guess, q.item.value)
  s.guesses[s.at], s.points[s.at] = guess, p
  s.total = s.total + p
  return p
end
function Q.next(s)
  if s.at >= #s.qs then s.done = true else s.at = s.at + 1 end
end
function Q.format(kind, v)
  if kind.key == 'weight' then return K.dec(v, 2) .. kind.unit end
  if kind.key == 'casts' then return K.dec(v, 1) .. kind.unit end
  return K.num(v) .. kind.unit
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local SX, SW = 130, 700          -- the slider: left edge and width

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('guessdps')
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16)
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('Five questions about the sim\'s results. The closer your guess, the more points.')
  self.dailyBtn = K.button(f, 110, 28, 'Daily', function() self:openDaily() end, 'normal', 13)
  self.dailyBtn:SetPoint('TOPRIGHT', -138, -18)
  self.practiceBtn = K.button(f, 110, 28, 'Practice', function() self:openPractice() end, 'normal', 13)
  self.practiceBtn:SetPoint('TOPRIGHT', -20, -18)
  -- the five questions as dots along the top
  self.steps = {}
  for i = 1, Q.ROUND do
    local b = K.box(f, 150, 46, C.panel, C.line, 1)
    b:SetPoint('TOPLEFT', 90 + (i - 1) * 160, -80)
    b.n = K.text(b, 11, C.dim, 'LEFT'); b.n:SetPoint('TOPLEFT', 10, -8)
    b.p = K.text(b, 16, C.text, 'LEFT', K.FONT_NUM); b.p:SetPoint('BOTTOMLEFT', 10, 7)
    self.steps[i] = b
  end
  -- the question
  local card = K.box(f, 780, 150, C.panel2, C.line, 1)
  card:SetPoint('TOP', 0, -146)
  self.card = card
  self.qIcon = K.icon(card, 64, nil); self.qIcon:SetPoint('LEFT', 24, 0)
  self.qKind = K.text(card, 12, C.accent, 'LEFT'); self.qKind:SetPoint('TOPLEFT', 106, -24)
  self.qTitle = K.text(card, 22, C.gold, 'LEFT', K.FONT); self.qTitle:SetPoint('TOPLEFT', 106, -46)
  self.qSub = K.text(card, 14, C.text, 'LEFT'); self.qSub:SetPoint('TOPLEFT', 106, -80)
  self.qNote = K.text(card, 11, C.faint, 'LEFT'); self.qNote:SetPoint('TOPLEFT', 106, -112)
  self.qNote:SetText('From the Forever Warlock Sim: ' .. RES.fight .. ', standard gear, results of ' .. RES.generated .. '.')
  -- the slider
  self.track = K.box(f, SW, 16, { 0.05, 0.04, 0.08 }, C.line, 1, 'Button')
  self.track:SetPoint('TOPLEFT', SX, -340)
  self.fill = K.shape(self.track, 'ARTWORK', 'rr6'); self.fill:SetPoint('TOPLEFT', 1, -1); self.fill:SetPoint('BOTTOMLEFT', 1, 1)
  K.fill(self.fill, C.accent[1], C.accent[2], C.accent[3], 1)
  self.answerMark = K.rect(self.track, 'OVERLAY', C.good, 1); self.answerMark:SetSize(4, 34)
  self.knob = CreateFrame('Frame', nil, self.track)
  self.knob:SetSize(30, 30)
  self.knob:SetFrameLevel(self.track:GetFrameLevel() + 5)
  self.knob.glow = K.shape(self.knob, 'BACKGROUND', 'glow'); self.knob.glow:SetSize(60, 60); self.knob.glow:SetPoint('CENTER'); self.knob.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
  self.knob.dot = K.shape(self.knob, 'ARTWORK', 'circle'); self.knob.dot:SetAllPoints(); self.knob.dot:SetVertexColor(1, 1, 1, 1)
  self.track:SetScript('OnMouseDown', function() self.dragging = true end)
  self.track:SetScript('OnMouseUp', function() self.dragging = false end)
  self.loT = K.text(f, 11, C.faint, 'LEFT', K.FONT_NUM); self.loT:SetPoint('TOPLEFT', self.track, 'BOTTOMLEFT', 0, -10)
  self.hiT = K.text(f, 11, C.faint, 'RIGHT', K.FONT_NUM); self.hiT:SetPoint('TOPRIGHT', self.track, 'BOTTOMRIGHT', 0, -10)
  self.guessT = K.text(f, 30, C.text, 'CENTER', K.FONT_NUM); self.guessT:SetPoint('TOP', self.track, 'BOTTOM', 0, -24)
  self.minus = K.button(f, 40, 34, '-', function() self:nudge(-1) end, 'normal', 16)
  self.minus:SetPoint('RIGHT', self.track, 'LEFT', -16, 0)
  self.plus = K.button(f, 40, 34, '+', function() self:nudge(1) end, 'normal', 16)
  self.plus:SetPoint('LEFT', self.track, 'RIGHT', 16, 0)
  self.msg = K.text(f, 15, C.gold, 'CENTER'); self.msg:SetPoint('TOP', self.guessT, 'BOTTOM', 0, -14)
  self.lockBtn = K.button(f, 220, 40, 'Lock it in', function() self:lock() end, 'orange', 15)
  self.lockBtn:SetPoint('BOTTOM', 0, 46)
  self.stats = K.text(f, 11, C.dim, 'CENTER'); self.stats:SetPoint('BOTTOM', 0, 18)
end

function G:openDaily()
  local day = A.WarlockleRules.today()
  local d = self.db.daily
  if not (d and d.day == day and d.s) then d = { day = day, s = Q.newRound(day * 613 + 17, true) }; self.db.daily = d end
  self.s, self.daily, self.day = d.s, true, day
  self:startQuestion()
end
function G:openPractice()
  self.s, self.daily = Q.newRound(math.random(1, 2000000000), false), false
  A.sound('flip')
  self:startQuestion()
end
function G:Show() self.f:Show(); if not self.s then self:openDaily() else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide(); self.dragging = false end

function G:startQuestion()
  local s = self.s
  self.revealed = s.guesses[s.at] ~= nil
  local kind = Q.kindOf(s.qs[s.at].kind)
  self.guess = self.revealed and s.guesses[s.at] or (kind.lo + kind.hi) / 2
  K.fadeIn(self.card, 0.2)
  self:refresh()
end
function G:setFromCursor()
  local x = GetCursorPosition()
  local sc = self.track:GetEffectiveScale()
  local l = self.track:GetLeft()
  if not l then return end
  local f = max(0, min(1, (x / sc - l) / SW))
  local kind = Q.kindOf(self.s.qs[self.s.at].kind)
  self.guess = kind.lo + (kind.hi - kind.lo) * f
  self:refresh()
end
function G:nudge(d)
  if self.revealed or self.s.done then return end
  local kind = Q.kindOf(self.s.qs[self.s.at].kind)
  self.guess = max(kind.lo, min(kind.hi, self.guess + d * (kind.hi - kind.lo) / 100))
  A.sound('tick')
  self:refresh()
end
function G:lock()
  local s = self.s
  if s.done then self:openPractice(); return end
  if self.revealed then
    Q.next(s)
    if s.done then
      if self.daily then self:record() end
      self.db.best = max(self.db.best or 0, s.total)
      A.sound(s.total >= 300 and 'win' or 'levelup')
      self:refresh()
    else self:startQuestion(); A.sound('flip') end
    return
  end
  local p = Q.answer(s, self.guess)
  self.revealed = true
  A.sound(p >= 90 and 'perfect' or p >= 50 and 'good' or 'miss')
  self:refresh()
end
function G:record()
  local db = self.db
  if db.lastDay == self.day then return end
  db.lastDay = self.day
  db.played = (db.played or 0) + 1
  db.dailyTotal = (db.dailyTotal or 0) + self.s.total
  db.dailyBest = max(db.dailyBest or 0, self.s.total)
end

function G:refresh()
  local s = self.s
  local q = s.qs[s.at]
  local kind = Q.kindOf(q.kind)
  self.title:SetText(self.daily and ('Guess the DPS #' .. A.WarlockleRules.number(self.day)) or 'Guess the DPS - practice')
  self.dailyBtn:SetStyle(self.daily and 'gold' or 'normal')
  self.practiceBtn:SetStyle(self.daily and 'normal' or 'gold')
  for i, b in ipairs(self.steps) do
    local p = s.points[i]
    b.n:SetText(i .. ' - ' .. Q.kindOf(s.qs[i].kind).short)
    b.p:SetText(p and (p .. ' points') or (i == s.at and 'now' or '-'))
    local c = p and (p >= 90 and C.good or p >= 50 and C.flame or C.bad) or (i == s.at and C.accent or C.line)
    b:SetBorderColor(c[1], c[2], c[3], 1)
  end
  self.qIcon:SetTexture(K.spellTexture(q.item.icon))
  self.qKind:SetText(kind.label)
  self.qTitle:SetText(q.item.title)
  self.qSub:SetText(q.item.sub)
  local f = (self.guess - kind.lo) / (kind.hi - kind.lo)
  self.fill:SetWidth(max(1, (SW - 2) * f))
  self.knob:ClearAllPoints(); self.knob:SetPoint('CENTER', self.track, 'LEFT', SW * f, 0)
  self.loT:SetText(Q.format(kind, kind.lo)); self.hiT:SetText(Q.format(kind, kind.hi))
  self.guessT:SetText(Q.format(kind, self.guess))
  if self.revealed then
    local v = q.item.value
    self.answerMark:ClearAllPoints(); self.answerMark:SetPoint('CENTER', self.track, 'LEFT', SW * (v - kind.lo) / (kind.hi - kind.lo), 0)
    self.answerMark:Show()
    local p = s.points[s.at]
    self.msg:SetText('The sim says ' .. Q.format(kind, v) .. '  -  ' .. p .. ' points')
    self.msg:SetTextColor((p >= 90 and C.good or p >= 50 and C.flame or C.bad)[1], (p >= 90 and C.good or p >= 50 and C.flame or C.bad)[2], (p >= 90 and C.good or p >= 50 and C.flame or C.bad)[3])
  else
    self.answerMark:Hide()
    self.msg:SetText('Drag the slider (or Left / Right, + / -), then lock it in')
    self.msg:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end
  if s.done then
    self.msg:SetText('Round over: ' .. s.total .. ' of ' .. 100 * Q.ROUND .. ' points')
    self.msg:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    self.lockBtn:SetLabel(self.daily and 'Practice round' or 'Another round')
  else
    self.lockBtn:SetLabel(self.revealed and (s.at < #s.qs and 'Next question' or 'See the total') or 'Lock it in')
  end
  self.minus:SetEnabled(not self.revealed); self.plus:SetEnabled(not self.revealed)
  local db = self.db
  self.stats:SetText((self.daily and ('Daily: played ' .. (db.played or 0) .. ', best ' .. (db.dailyBest or 0) .. '  -  ') or '') .. 'Best round: ' .. (db.best or 0) .. ' points')
end

function G:OnUpdate()
  if self.dragging and not self.revealed and self.s and not self.s.done then self:setFromCursor() end
end
function G:OnKey(key)
  if key == 'LEFT' then self:nudge(-1); return true end
  if key == 'RIGHT' then self:nudge(1); return true end
  if key == 'ENTER' or key == 'SPACE' then self:lock(); return true end
  return false
end

A.RegisterGame({
  key = 'guessdps', name = 'Guess the DPS', order = 17, ready = true, kind = 'cards', icon = A.SPELLS.deathCoil.id,
  tagline = 'How much DPS does it do? Guess the sim\'s own numbers.',
  bestLine = function() local b = A.db('guessdps').best; return b and b > 0 and ('Best: ' .. b .. ' points') or 'Play' end,
  help = {
    '|cffffd040Guess the Forever Warlock Sim\'s numbers.|r Five questions: how much DPS a build does, how much damage one spell deals in it over the whole fight, how many times it is cast, how much DPS one more spell power or 1% of a stat is worth.',
    ' ',
    'Drag the slider - or Left / Right, + and - - and lock your guess in (Enter). Spot on is 100 points; a quarter of the slider away is 0.',
    ' ',
    'One daily round, the same for everyone, and as many practice rounds as you like. The numbers are the sim\'s published results (' .. RES.fight .. ', ' .. RES.gear .. ').',
  },
  create = function(parent) return G.create(parent) end,
})
