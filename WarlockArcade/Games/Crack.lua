-- Crack the Opener: a hidden opener of four casts, from six spells (a spell can come more than once). Guess it in eight
-- tries; after each one, a gold mark for every spell in the right slot and a silver mark for every right spell in the
-- wrong slot. One opener a day (the same for everyone, like Warlockle) and practice openers.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local X = {}
A.CrackRules = X
X.SPELLS = { 'shadowBolt', 'immolate', 'corruption', 'baneOfAgony', 'lifeTap', 'soulFire' }
X.LEN, X.TRIES = 4, 8

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
function X.new(seed, daily)
  local rand = rng(seed)
  local code = {}
  for i = 1, X.LEN do code[i] = rand(#X.SPELLS) end
  return { code = code, tries = {}, done = false, won = false, daily = daily }
end
-- gold: right spell, right slot; silver: right spell, other slot (each spell of the code counted once)
function X.score(code, guess)
  local gold, silver = 0, 0
  local cc, gc = {}, {}
  for i = 1, X.LEN do
    if guess[i] == code[i] then gold = gold + 1
    else cc[code[i]] = (cc[code[i]] or 0) + 1; gc[guess[i]] = (gc[guess[i]] or 0) + 1 end
  end
  for k, n in pairs(gc) do silver = silver + min(n, cc[k] or 0) end
  return gold, silver
end
function X.guess(s, guess)
  if s.done then return nil, 'This opener is cracked or lost' end
  if #guess ~= X.LEN then return nil, 'Fill all four slots' end
  local g, sv = X.score(s.code, guess)
  local copy = {}
  for i = 1, X.LEN do copy[i] = guess[i] end
  s.tries[#s.tries + 1] = { guess = copy, gold = g, silver = sv }
  if g == X.LEN then s.done, s.won = true, true
  elseif #s.tries >= X.TRIES then s.done = true end
  return g, sv
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local RX, RY, RH = 250, -84, 50     -- the rows of tries
local SLOT = 42

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('crack')
  g.cur = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16)
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('A hidden opener of four casts. Gold: right spell, right slot. Silver: right spell, wrong slot.')
  self.dailyBtn = K.button(f, 110, 28, 'Daily', function() self:openDaily() end, 'normal', 13)
  self.dailyBtn:SetPoint('TOPRIGHT', -138, -18)
  self.practiceBtn = K.button(f, 110, 28, 'Practice', function() self:openPractice() end, 'normal', 13)
  self.practiceBtn:SetPoint('TOPRIGHT', -20, -18)
  -- the eight rows: four slots and the marks
  self.rows = {}
  for r = 1, X.TRIES do
    local row = K.box(f, 330, RH - 6, C.panel, C.line, 1)
    row:SetPoint('TOPLEFT', RX, RY - (r - 1) * RH)
    row.n = K.text(row, 11, C.faint, 'LEFT', K.FONT_NUM); row.n:SetPoint('LEFT', 10, 0); row.n:SetText(tostring(r))
    row.slots, row.marks = {}, {}
    for i = 1, X.LEN do
      local s = K.box(row, SLOT - 4, SLOT - 4, { 0.04, 0.03, 0.06 }, C.line, 1)
      s:SetPoint('LEFT', 30 + (i - 1) * SLOT, 0)
      s.icon = K.icon(s, SLOT - 10, nil); s.icon:SetPoint('CENTER')
      row.slots[i] = s
    end
    for i = 1, X.LEN do
      local m = K.shape(row, 'ARTWORK', 'circle'); m:SetSize(14, 14)
      m:SetPoint('LEFT', 30 + X.LEN * SLOT + 14 + ((i - 1) % 2) * 18, (i <= 2) and 8 or -8)
      row.marks[i] = m
    end
    self.rows[r] = row
  end
  -- the six spells to pick from
  self.pick = {}
  for i, key in ipairs(X.SPELLS) do
    local b = K.box(f, 64, 64, C.panel2, C.line, 1, 'Button')
    b:SetPoint('TOPLEFT', 620 + ((i - 1) % 3) * 74, -110 - floor((i - 1) / 3) * 74)
    b.icon = K.icon(b, 52, A.SPELLS[key].id); b.icon:SetPoint('CENTER')
    b.key = K.text(b, 11, C.text, 'RIGHT', K.FONT_NUM, 'OUTLINE'); b.key:SetPoint('BOTTOMRIGHT', -4, 4); b.key:SetText(tostring(i))
    b.hl = K.shape(b, 'HIGHLIGHT', 'rr6'); b.hl:SetAllPoints(); b.hl:SetVertexColor(1, 1, 1, 0.1)
    b.spell = i
    b:SetScript('OnClick', function(btn) self:add(btn.spell) end)
    b:SetScript('OnEnter', function(btn) K.showTip(btn, { { A.SPELLS[X.SPELLS[btn.spell]].name, { 1, 1, 1 } }, { 'Click (or press ' .. btn.spell .. ') to put it in the next slot', C.dim } }) end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    self.pick[i] = b
  end
  self.backBtn = K.button(f, 106, 32, 'Back', function() self:back() end, 'normal', 13)
  self.backBtn:SetPoint('TOPLEFT', 620, -270)
  self.goBtn = K.button(f, 106, 32, 'Guess', function() self:submit() end, 'orange', 14)
  self.goBtn:SetPoint('LEFT', self.backBtn, 'RIGHT', 10, 0)
  self.msg = K.text(f, 15, C.gold, 'LEFT'); self.msg:SetPoint('TOPLEFT', 620, -320); self.msg:SetWidth(320); self.msg:SetWordWrap(true)
  self.answer = {}
  for i = 1, X.LEN do
    local s = K.box(f, SLOT, SLOT, { 0.04, 0.03, 0.06 }, C.gold, 1)
    s:SetPoint('TOPLEFT', 620 + (i - 1) * (SLOT + 6), -372)
    s.icon = K.icon(s, SLOT - 8, nil); s.icon:SetPoint('CENTER')
    self.answer[i] = s
  end
  self.stats = K.text(f, 11, C.dim, 'LEFT'); self.stats:SetPoint('TOPLEFT', 620, -432); self.stats:SetWidth(320); self.stats:SetWordWrap(true)
  local legend = K.text(f, 11, C.faint, 'LEFT'); legend:SetPoint('TOPLEFT', 22, -84); legend:SetWidth(210); legend:SetWordWrap(true); legend:SetSpacing(2)
  legend:SetText('Pick four spells (1-6 on the keyboard), then Guess (Enter). Backspace takes the last one back.\n\nGold mark: a spell in the right slot.\nSilver mark: a right spell in the wrong slot.\n\nA spell can be in the opener more than once.')
end

function G:openDaily()
  local day = A.WarlockleRules.today()
  local d = self.db.daily
  if not (d and d.day == day and d.s) then d = { day = day, s = X.new(day * 977 + 5, true) }; self.db.daily = d end
  self.s, self.daily, self.day = d.s, true, day
  self.cur = {}
  self:refresh()
end
function G:openPractice()
  self.s, self.daily = X.new(math.random(1, 2000000000), false), false
  self.cur = {}
  A.sound('flip')
  self:refresh()
end
function G:Show() self.f:Show(); if not self.s then self:openDaily() else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:add(i)
  if self.s.done or #self.cur >= X.LEN then return end
  self.cur[#self.cur + 1] = i
  A.sound('place')
  self:refresh()
end
function G:back()
  if #self.cur == 0 then return end
  table.remove(self.cur)
  A.sound('flip')
  self:refresh()
end
function G:submit()
  local s = self.s
  local g, sv = X.guess(s, self.cur)
  if not g then self.msg:SetText(sv); A.sound('error'); return end
  self.cur = {}
  if s.won then A.sound('win') elseif s.done then A.sound('lose') else A.sound(g > 0 and 'good' or 'select') end
  if s.done and self.daily then self:record() end
  local row = self.rows[#s.tries]
  K.fadeIn(row, 0.25)
  self:refresh()
end
function G:record()
  local db, s = self.db, self.s
  if db.lastDay == self.day then return end
  db.lastDay = self.day
  db.played = (db.played or 0) + 1
  if s.won then db.won = (db.won or 0) + 1; db.streak = (db.streak or 0) + 1; db.bestStreak = max(db.bestStreak or 0, db.streak); db.best = min(db.best or 99, #s.tries)
  else db.streak = 0 end
end

function G:refresh()
  local s = self.s
  self.title:SetText(self.daily and ('Crack the Opener #' .. A.WarlockleRules.number(self.day)) or 'Crack the Opener - practice')
  self.dailyBtn:SetStyle(self.daily and 'gold' or 'normal')
  self.practiceBtn:SetStyle(self.daily and 'normal' or 'gold')
  for r, row in ipairs(self.rows) do
    local t = s.tries[r]
    local active = not s.done and r == #s.tries + 1
    row:SetBorderColor(active and C.accent[1] or C.line[1], active and C.accent[2] or C.line[2], active and C.accent[3] or C.line[3], 1)
    for i, slot in ipairs(row.slots) do
      local v = t and t.guess[i] or (active and self.cur[i])
      slot.icon:SetShown(v ~= nil)
      if v then slot.icon:SetTexture(K.spellTexture(A.SPELLS[X.SPELLS[v]].id)) end
    end
    for i, m in ipairs(row.marks) do
      if t and i <= t.gold then m:SetVertexColor(1, 0.8, 0.25, 1)
      elseif t and i <= t.gold + t.silver then m:SetVertexColor(0.85, 0.85, 0.92, 1)
      else m:SetVertexColor(0.2, 0.17, 0.26, 1) end
    end
  end
  for i, a in ipairs(self.answer) do
    a.icon:SetShown(s.done)
    if s.done then a.icon:SetTexture(K.spellTexture(A.SPELLS[X.SPELLS[s.code[i]]].id)) end
  end
  for _, b in ipairs(self.pick) do b:SetEnabled(not s.done); b:SetAlpha(s.done and 0.5 or 1) end
  self.goBtn:SetEnabled(not s.done and #self.cur == X.LEN)
  self.backBtn:SetEnabled(not s.done and #self.cur > 0)
  if s.done then self.msg:SetText(s.won and ('Cracked in ' .. #s.tries .. '!') or 'Out of tries - the opener was:')
  else self.msg:SetText((X.TRIES - #s.tries) .. ' tries left') end
  local db = self.db
  self.stats:SetText(self.daily and ('Daily: played ' .. (db.played or 0) .. ', cracked ' .. (db.won or 0) .. ', streak ' .. (db.streak or 0) .. (db.best and (', best ' .. db.best .. ' tries') or '')) or 'Practice openers do not count for the streak')
end

function G:OnKey(key)
  local i = tonumber(key)
  if i and X.SPELLS[i] and key == tostring(i) then self:add(i); return true end
  if key == 'BACKSPACE' then self:back(); return true end
  if key == 'ENTER' then self:submit(); return true end
  return false
end

A.RegisterGame({
  key = 'crack', name = 'Crack the Opener', order = 18, ready = true, kind = 'daily', icon = A.SPELLS.drainLife.id,
  tagline = 'A hidden opener of four casts. Crack it in eight tries.',
  bestLine = function()
    local db = A.db('crack')
    if db.daily and db.daily.day == A.WarlockleRules.today() and db.daily.s and db.daily.s.done then return db.daily.s.won and ('Today: in ' .. #db.daily.s.tries) or 'Today: missed' end
    return 'New opener today'
  end,
  help = {
    '|cffffd040Crack the hidden opener:|r four casts, from six spells - a spell can be in it more than once.',
    ' ',
    'Pick four spells (click them or press 1-6) and Guess (Enter). Every guess gets a gold mark for each spell in the right slot and a silver mark for each right spell in the wrong slot - not which ones.',
    ' ',
    'Eight tries. One opener a day, the same for everyone, and as many practice openers as you like.',
  },
  create = function(parent) return G.create(parent) end,
})
