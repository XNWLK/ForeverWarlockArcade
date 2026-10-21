-- Iconle: a Warlock icon, zoomed far in. Guess whose it is - a spell, a talent or a demon - in six tries; every miss
-- zooms out a little (and the colour comes back after two). Icons that are the same picture count as one answer:
-- any of their names is right. One icon a day (the same for everyone, like Warlockle), and practice icons.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local I = {}
A.IconleRules = I
I.MAX = 6
I.ZOOM = { 0.16, 0.24, 0.35, 0.5, 0.7, 1 }   -- share of the icon shown, by guesses made
I.GREY = 2                                  -- the first two looks are grey
I.HINT_AFTER = 3
-- pictures that are the same icon (checked against web/icons.js by tools/check-iconle.js): one answer, any name
I.SAME = {
  { 'spell:shadowBolt', 'talent:improvedShadowBolt' }, { 'spell:searingPain', 'talent:agonizingFlames' },
  { 'spell:soulFire', 'talent:decimation' }, { 'spell:corruption', 'talent:improvedCorruption' },
  { 'spell:baneOfAgony', 'talent:improvedBaneOfAgony' }, { 'spell:drainLife', 'talent:soulSiphon' },
  { 'spell:drainSoul', 'talent:improvedDrains' }, { 'spell:lifeTap', 'talent:improvedLifeTap' },
  { 'pet:imp', 'talent:improvedImp' }, { 'pet:voidwalker', 'talent:improvedVoidwalker' }, { 'pet:felhunter', 'talent:improvedFelhunter' },
}

-- the answers: one per picture, with every name that picture has
function I.answers()
  if I._answers then return I._answers end
  local byRef, list, names = {}, {}, {}
  local function add(ref, name, icon, what, tree)
    local a = { refs = { ref }, names = { name }, icon = icon, what = what, tree = tree }
    byRef[ref] = a
    list[#list + 1] = a
  end
  for key, s in pairs(A.SPELLS) do add('spell:' .. key, s.name, s.id, 'Spell', s.tree) end
  for key, t in pairs(A.TALENTS) do add('talent:' .. key, t.name, t.spell, 'Talent', t.tree) end
  for key, p in pairs(A.PETS) do add('pet:' .. key, p.name, p.spell, 'Demon', nil) end
  for _, same in ipairs(I.SAME) do
    local keep = byRef[same[1]]
    for i = 2, #same do
      local other = byRef[same[i]]
      if keep and other and other ~= keep then
        for _, n in ipairs(other.names) do keep.names[#keep.names + 1] = n end
        keep.refs[#keep.refs + 1] = same[i]
        keep.what = keep.what .. ' / ' .. other.what
        for j, a in ipairs(list) do if a == other then table.remove(list, j); break end end
        byRef[same[i]] = keep
      end
    end
  end
  -- a spell and a talent of the same name are one picture too (Shadowburn, Conflagrate ...)
  local byName = {}
  for i = #list, 1, -1 do
    local a = list[i]
    local n = a.names[1]
    if byName[n] and byName[n] ~= a then
      local keep = byName[n]
      keep.what = keep.what .. ' / ' .. a.what
      for _, r in ipairs(a.refs) do keep.refs[#keep.refs + 1] = r end
      table.remove(list, i)
    else byName[n] = a end
  end
  table.sort(list, function(a, b) return a.names[1] < b.names[1] end)
  for _, a in ipairs(list) do for _, n in ipairs(a.names) do names[#names + 1] = n end end
  table.sort(names)
  -- remove repeated names (a spell and a talent named alike)
  local uniq = {}
  for _, n in ipairs(names) do if uniq[#uniq] ~= n then uniq[#uniq + 1] = n end end
  I._answers, I._names = list, uniq
  return list
end
function I.names() I.answers(); return I._names end

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end
function I.dailyIndex(day)
  local n = #I.answers()
  local step = 37
  while n % step == 0 do step = step + 2 end
  return ((day * step) % n) + 1
end
-- a puzzle: the answer and where the zoom looks (a point that stays the same while zooming out)
function I.new(index, seed, daily)
  local rand = rng(seed)
  return { answer = index, cx = 0.3 + rand() * 0.4, cy = 0.3 + rand() * 0.4, guesses = {}, done = false, won = false, daily = daily }
end
function I.answerOf(s) return I.answers()[s.answer] end
function I.isRight(s, name) for _, n in ipairs(I.answerOf(s).names) do if n == name then return true end end; return false end
function I.guess(s, name)
  if s.done then return nil, 'This one is finished' end
  for _, g in ipairs(s.guesses) do if g == name then return nil, 'Already guessed' end end
  s.guesses[#s.guesses + 1] = name
  if I.isRight(s, name) then s.done, s.won = true, true
  elseif #s.guesses >= I.MAX then s.done = true end
  return true
end
-- the part of the icon shown: texture coordinates inside the icon's own border (0.08 .. 0.92)
function I.view(s)
  local z = s.done and 1 or I.ZOOM[min(#I.ZOOM, #s.guesses + 1)]
  local half = z / 2
  local cx = max(half, min(1 - half, s.cx))
  local cy = max(half, min(1 - half, s.cy))
  local function m(v) return 0.08 + 0.84 * v end
  return m(cx - half), m(cx + half), m(cy - half), m(cy + half), z
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local LX, LY = 22, -84         -- the big icon
local BIG = 240
local NX, NY = 300, -84        -- the list of names
local NW, NH = 200, 19

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('iconle')
  g.search = ''
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16)
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('Whose icon is it? Six tries - every miss zooms out.')
  self.dailyBtn = K.button(f, 110, 28, 'Daily', function() self:openDaily() end, 'normal', 13)
  self.dailyBtn:SetPoint('TOPRIGHT', -138, -18)
  self.practiceBtn = K.button(f, 110, 28, 'Practice', function() self:openPractice() end, 'normal', 13)
  self.practiceBtn:SetPoint('TOPRIGHT', -20, -18)
  -- the big icon in a rounded frame
  local frame = K.box(f, BIG + 16, BIG + 16, { 0.02, 0.015, 0.03 }, C.line, 2)
  frame:SetPoint('TOPLEFT', LX, LY)
  self.frame = frame
  self.big = frame:CreateTexture(nil, 'ARTWORK')
  self.big:SetPoint('TOPLEFT', 8, -8); self.big:SetPoint('BOTTOMRIGHT', -8, 8)
  self.zoomT = K.text(frame, 11, C.dim, 'RIGHT', K.FONT_NUM, 'OUTLINE', 'OVERLAY'); self.zoomT:SetPoint('BOTTOMRIGHT', -14, 12)
  -- the guesses so far
  self.rows = {}
  for i = 1, I.MAX do
    local r = K.box(f, BIG + 16, 26, C.panel, C.line, 1)
    r:SetPoint('TOPLEFT', LX, LY - BIG - 26 - (i - 1) * 28)
    r.n = K.text(r, 11, C.faint, 'LEFT', K.FONT_NUM); r.n:SetPoint('LEFT', 10, 0); r.n:SetText(tostring(i))
    r.icon = K.icon(r, 18, nil); r.icon:SetPoint('LEFT', 28, 0)
    r.name = K.text(r, 12, C.text, 'LEFT'); r.name:SetPoint('LEFT', 52, 0); r.name:SetPoint('RIGHT', -40, 0)
    r.mark = K.text(r, 12, C.good, 'RIGHT'); r.mark:SetPoint('RIGHT', -10, 0)
    self.rows[i] = r
  end
  -- the names: A to Z in three columns; typing filters them
  self.searchBox = K.box(f, 3 * NW + 20, 28, C.panel2, C.line, 1)
  self.searchBox:SetPoint('TOPLEFT', NX, NY)
  self.searchT = K.text(self.searchBox, 12, C.text, 'LEFT'); self.searchT:SetPoint('LEFT', 10, 0); self.searchT:SetPoint('RIGHT', -10, 0)
  self.nameBtns = {}
  local names = I.names()
  self.perCol = math.ceil(#names / 3)
  for i, name in ipairs(names) do
    local b = K.box(f, NW, NH - 2, { 0.07, 0.055, 0.1 }, { 0.2, 0.16, 0.28 }, 1, 'Button')
    b:SetFrameLevel(f:GetFrameLevel() + 5)
    b.label = K.text(b, 11, C.text, 'LEFT'); b.label:SetPoint('LEFT', 6, 0); b.label:SetPoint('RIGHT', -4, 0); b.label:SetText(name)
    b.hl = K.shape(b, 'HIGHLIGHT', 'rr4'); b.hl:SetAllPoints(); b.hl:SetVertexColor(1, 1, 1, 0.08)
    b.itemName = name
    b:SetScript('OnClick', function(btn) self:guess(btn.itemName) end)
    self.nameBtns[i] = b
  end
  self.msg = K.text(f, 15, C.gold, 'CENTER'); self.msg:SetPoint('TOP', f, 'TOPLEFT', LX + (BIG + 16) / 2, LY - BIG - 26 - I.MAX * 28 - 4)
  self.msg2 = K.text(f, 11, C.dim, 'CENTER'); self.msg2:SetPoint('TOP', self.msg, 'BOTTOM', 0, -5); self.msg2:SetWidth(BIG + 16); self.msg2:SetWordWrap(true)
  self.stats = K.text(f, 10, C.faint, 'CENTER'); self.stats:SetPoint('TOP', self.msg2, 'BOTTOM', 0, -5); self.stats:SetWidth(BIG + 16); self.stats:SetWordWrap(true)
end

function G:openDaily()
  local day = A.WarlockleRules.today()
  local d = self.db.daily
  if not (d and d.day == day and d.s) then
    d = { day = day, s = I.new(I.dailyIndex(day), day * 131 + 7, true) }
    self.db.daily = d
  end
  self.s, self.daily, self.day = d.s, true, day
  self.search = ''
  self:refresh(true)
end
function G:openPractice()
  self.s, self.daily = I.new(math.random(1, #I.answers()), math.random(1, 2000000000), false), false
  self.search = ''
  self:refresh(true)
  A.sound('flip')
end
function G:Show() self.f:Show(); if not self.s then self:openDaily() else self:refresh(false) end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:guess(name)
  local s = self.s
  local ok, why = I.guess(s, name)
  if not ok then self.msg2:SetText(s.done and 'Finished - click Practice for another one' or (name .. ': ' .. why)); A.sound('error'); return end
  self.search = ''
  if s.won then A.sound('win') elseif s.done then A.sound('lose') else A.sound('whoosh') end
  if s.done and s.daily then self:record() end
  self:refresh(true)
end
function G:record()
  local db, s = self.db, self.s
  if db.lastDay == self.day then return end
  db.lastDay = self.day
  db.played = (db.played or 0) + 1
  if s.won then db.won = (db.won or 0) + 1; db.streak = (db.streak or 0) + 1; db.bestStreak = max(db.bestStreak or 0, db.streak)
  else db.streak = 0 end
end

function G:refresh(animate)
  local s = self.s
  local a = I.answerOf(s)
  self.title:SetText(self.daily and ('Iconle #' .. A.WarlockleRules.number(self.day)) or 'Iconle - practice')
  self.dailyBtn:SetStyle(self.daily and 'gold' or 'normal')
  self.practiceBtn:SetStyle(self.daily and 'normal' or 'gold')
  -- the icon: zoom out smoothly to the new view
  self.big:SetTexture(K.spellTexture(a.icon))
  self.big:SetDesaturated(not s.done and #s.guesses < I.GREY)
  local l, r, t, b, z = I.view(s)
  local from = self.view
  self.view = { l, r, t, b }
  if animate and from then
    K.tween(self.big, 0.35, function(f) self.big:SetTexCoord(K.lerp(from[1], l, f), K.lerp(from[2], r, f), K.lerp(from[3], t, f), K.lerp(from[4], b, f)) end)
  else self.big:SetTexCoord(l, r, t, b) end
  self.zoomT:SetText(s.done and '' or (floor(100 / z + 0.5) .. '% zoom'))
  for i, row in ipairs(self.rows) do
    local g = s.guesses[i]
    if g then
      local right = I.isRight(s, g)
      row.name:SetText(g)
      row.icon:SetTexture(K.spellTexture(self:iconOfName(g))); row.icon:Show()
      row.mark:SetText(right and 'Right!' or 'No'); row.mark:SetTextColor(right and C.good[1] or C.bad[1], right and C.good[2] or C.bad[2], right and C.good[3] or C.bad[3])
      row:SetBorderColor(right and C.good[1] or C.line[1], right and C.good[2] or C.line[2], right and C.good[3] or C.line[3], 1)
    else
      row.name:SetText(''); row.icon:Hide(); row.mark:SetText('')
      row:SetBorderColor(C.line[1], C.line[2], C.line[3], 1)
    end
  end
  -- the list, filtered by what was typed
  local q = self.search:lower()
  local n = 0
  for _, btn in ipairs(self.nameBtns) do
    local name = btn.itemName
    local show = q == '' or name:lower():find(q, 1, true) ~= nil
    btn:SetShown(show)
    if show then
      local col, row = floor(n / self.perCol), n % self.perCol
      btn:ClearAllPoints(); btn:SetPoint('TOPLEFT', self.f, 'TOPLEFT', NX + col * (NW + 10), NY - 36 - row * NH)
      local tried = false
      for _, x in ipairs(s.guesses) do if x == name then tried = true end end
      btn.label:SetTextColor(tried and C.faint[1] or C.text[1], tried and C.faint[2] or C.text[2], tried and C.faint[3] or C.text[3])
      btn:SetEnabled(not s.done and not tried)
      n = n + 1
    end
  end
  self.matches = n
  self.searchT:SetText(self.search == '' and K.paint(C.faint, 'Type to search the names...') or (self.search .. K.paint(C.gold, '_') .. K.paint(C.faint, '   ' .. n .. ' found' .. (n == 1 and ' - Enter guesses it' or ''))))
  -- messages
  if s.done then
    self.msg:SetText(s.won and ('Got it in ' .. #s.guesses .. '!') or ('It was ' .. a.names[1]))
    self.msg2:SetText(a.what .. (a.tree and (' - ' .. A.WarlockleRules.TREE_NAME[a.tree]) or '') .. (#a.names > 1 and ('  (also: ' .. table.concat(a.names, ', ', 2) .. ')') or ''))
  else
    self.msg:SetText((I.MAX - #s.guesses) .. ' guesses left')
    if #s.guesses >= I.HINT_AFTER then self.msg2:SetText('Hint: a ' .. (a.what:lower():gsub(' / ', ' and ')) .. (a.tree and (' of ' .. A.WarlockleRules.TREE_NAME[a.tree]) or ''))
    else self.msg2:SetText('') end
  end
  local db = self.db
  self.stats:SetText(self.daily and ('Daily: played ' .. (db.played or 0) .. ', solved ' .. (db.won or 0) .. ', streak ' .. (db.streak or 0) .. ', best ' .. (db.bestStreak or 0)) or 'Practice icons do not count for the streak')
end
function G:iconOfName(name)
  for _, a in ipairs(I.answers()) do for _, n in ipairs(a.names) do if n == name then return a.icon end end end
end

-- typing searches the list; Enter guesses when one name is left, Backspace and Escape edit the search
function G:OnKey(key)
  local s = self.s
  if not s or s.done then return false end
  if #key == 1 and key:match('[%a]') then self.search = self.search .. key:lower(); self:refresh(false); return true end
  if key == 'SPACE' and self.search ~= '' then self.search = self.search .. ' '; self:refresh(false); return true end
  if key == 'BACKSPACE' and self.search ~= '' then self.search = self.search:sub(1, -2); self:refresh(false); return true end
  if key == 'ESCAPE' and self.search ~= '' then self.search = ''; self:refresh(false); return true end
  if key == 'ENTER' and self.matches == 1 then
    for _, b in ipairs(self.nameBtns) do if b:IsShown() then self:guess(b.itemName); return true end end
  end
  return false
end

A.RegisterGame({
  key = 'iconle', name = 'Iconle', order = 11, ready = true, kind = 'daily', icon = A.SPELLS.wrack.id,
  tagline = 'A Warlock icon, zoomed far in. Whose is it?',
  bestLine = function()
    local db = A.db('iconle')
    if db.daily and db.daily.day == A.WarlockleRules.today() and db.daily.s and db.daily.s.done then return db.daily.s.won and ('Today: in ' .. #db.daily.s.guesses) or 'Today: missed' end
    return 'New icon today'
  end,
  help = {
    '|cffffd040Whose icon is it?|r A spell, a talent or a demon of the Forever Warlock Sim - zoomed far in. Click a name (or type to search and press Enter) to guess.',
    ' ',
    'Six tries. Every miss zooms out a little; the colour comes back after two misses, and after three you learn what it is (spell, talent or demon) and its tree.',
    ' ',
    'Some spells and talents share the very same icon (Shadow Bolt and Improved Shadow Bolt ...): any of their names counts.',
    ' ',
    'One daily icon - the same for everyone - and as many practice icons as you like.',
  },
  create = function(parent) return G.create(parent) end,
})
