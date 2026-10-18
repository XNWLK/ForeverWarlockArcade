-- Warlockle: guess the talent of the day. Pick talents from the three real talent trees; every guess shows how close
-- it is (tree, tier, column, ranks, whether it needs another talent first). After a few misses the talent's own text
-- is shown with its name hidden. One puzzle a day (the same for everyone, by the server's date), and a practice mode.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, abs = math.floor, math.abs

local W = {}
A.WarlockleRules = W
W.MAX = 6
W.HINT_AFTER = 3
W.FIRST_DAY = 20744      -- 2026-10-18 (days since 1970-01-01) = puzzle #1
W.TREE_NAME = { affliction = 'Affliction', demonology = 'Demonology', destruction = 'Destruction' }
W.TREE_ORDER = { 'affliction', 'demonology', 'destruction' }

function W.today() return floor(GetServerTime() / 86400) end
function W.number(day) return day - W.FIRST_DAY + 1 end
-- walks through every talent once before repeating (37 shares no factor with the talent count)
function W.targetOf(day)
  local list = A.TALENT_ORDER
  return list[((day * 37) % #list) + 1]
end
function W.new(target, daily) return { target = target, guesses = {}, daily = daily, done = false, won = false } end
function W.compare(guessKey, targetKey)
  local g, t = A.TALENTS[guessKey], A.TALENTS[targetKey]
  local function num(a, b) if a == b then return 'same' elseif abs(a - b) == 1 then return a < b and 'nearMore' or 'nearLess' end; return a < b and 'more' or 'less' end
  return {
    tree = g.tree == t.tree and 'same' or 'other',
    row = num(g.row, t.row), col = num(g.col, t.col), ranks = num(g.ranks, t.ranks),
    req = ((g.req ~= nil) == (t.req ~= nil)) and 'same' or 'other',
  }
end
function W.guess(s, key)
  if s.done then return nil, 'This puzzle is finished' end
  for _, k in ipairs(s.guesses) do if k == key then return nil, 'Already guessed' end end
  s.guesses[#s.guesses + 1] = key
  if key == s.target then s.done, s.won = true, true
  elseif #s.guesses >= W.MAX then s.done = true end
  return true
end
-- the talent's text with its name hidden
function W.hint(target)
  local t = A.TALENTS[target]
  local text = t.text or ''
  local i, j = text:find(t.name, 1, true)
  while i do text = text:sub(1, i - 1) .. '?????' .. text:sub(j + 1); i, j = text:find(t.name, 1, true) end
  return text
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local TX, TY = 16, -96               -- where the list of talents starts
local COLS = { { 'Talent', 132 }, { 'Tree', 64 }, { 'Tier', 58 }, { 'Column', 58 }, { 'Ranks', 52 }, { 'Needs one', 54 } }
local GX, GY, ROWH = 530, -96, 50    -- the guess table

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('warlockle')
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 18, -16)
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 18, -46)
  self.dailyBtn = K.button(f, 110, 28, 'Daily', function() self:openDaily() end, 'normal', 13)
  self.dailyBtn:SetPoint('TOPRIGHT', -132, -18)
  self.practiceBtn = K.button(f, 110, 28, 'Practice', function() self:openPractice() end, 'normal', 13)
  self.practiceBtn:SetPoint('TOPRIGHT', -14, -18)
  -- every talent by name, A to Z: where it sits in the trees is the puzzle
  self.icons = {}
  local keys = {}
  for _, key in ipairs(A.TALENT_ORDER) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return A.TALENTS[a].name < A.TALENTS[b].name end)
  local perCol = math.ceil(#keys / 3)
  local box = K.box(f, 3 * 166 + 8, perCol * 22 + 12, C.panel, C.line, 1)
  box:SetPoint('TOPLEFT', TX - 4, TY + 4)
  for i, key in ipairs(keys) do
    local t = A.TALENTS[key]
    local col, row = floor((i - 1) / perCol), (i - 1) % perCol
    local b = K.box(f, 162, 20, { 0.07, 0.055, 0.09 }, { 0.2, 0.16, 0.26 }, 1, 'Button')
    b:SetPoint('TOPLEFT', TX + col * 166, TY - 2 - row * 22)
    b:SetFrameLevel(f:GetFrameLevel() + 5)
    b.key = key
    b.icon = K.icon(b, 16, t.spell); b.icon:SetPoint('LEFT', 2, 0)
    b.name = K.text(b, 11, C.text, 'LEFT'); b.name:SetPoint('LEFT', 22, 0); b.name:SetPoint('RIGHT', -2, 0); b.name:SetText(t.name)
    b.veil = K.rect(b, 'OVERLAY', { 0, 0, 0 }, 0.55, 1); b.veil:SetAllPoints(); b.veil:Hide()
    b.hl = K.rect(b, 'HIGHLIGHT', { 1, 1, 1 }, 0.08); b.hl:SetAllPoints()
    b:SetScript('OnClick', function(btn) self:guess(btn.key) end)
    b:SetScript('OnEnter', function(btn)
      local done = self.s and self:guessed(btn.key)
      local over = self.s and self.s.done
      K.showTip(btn, { { A.TALENTS[btn.key].name, { 1, 1, 1 } }, { over and 'Puzzle finished - try Practice' or done and 'Already guessed' or 'Click to guess', (done or over) and C.faint or C.gold } }, 'ANCHOR_RIGHT')
    end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    self.icons[key] = b
  end
  -- the guess table
  local x = GX
  self.head = {}
  for i, col in ipairs(COLS) do
    local h = K.text(f, 11, C.dim, i == 1 and 'LEFT' or 'CENTER'); h:SetPoint('TOPLEFT', x, GY); h:SetWidth(col[2]); h:SetText(col[1])
    x = x + col[2] + 2
  end
  self.rows = {}
  for r = 1, W.MAX do
    local row = { cells = {} }
    local cx = GX
    for i, col in ipairs(COLS) do
      local c = K.box(f, col[2], ROWH - 4, { 0.09, 0.07, 0.12 }, C.line, 1)
      c:SetPoint('TOPLEFT', cx, GY - 18 - (r - 1) * ROWH)
      c.a = K.text(c, i == 1 and 12 or 13, C.text, i == 1 and 'LEFT' or 'CENTER')
      if i == 1 then c.a:SetPoint('LEFT', 34, 6); c.a:SetPoint('RIGHT', -3, 6); c.a:SetWordWrap(true)
        c.icon = K.icon(c, 26, nil); c.icon:SetPoint('LEFT', 4, 0)
      else c.a:SetPoint('TOP', 0, -8) end
      c.b = K.text(c, 10, C.dim, 'CENTER'); c.b:SetPoint('BOTTOM', 0, 5)
      if i == 1 then c.b:ClearAllPoints(); c.b:SetPoint('BOTTOMLEFT', 34, 5) end
      row.cells[i] = c
      cx = cx + col[2] + 2
    end
    self.rows[r] = row
  end
  self.hintBox = K.box(f, 414, 92, C.panel, C.line, 1)
  self.hintBox:SetPoint('TOPLEFT', GX, GY - 18 - W.MAX * ROWH - 6)
  self.hintTitle = K.text(self.hintBox, 11, C.dim, 'LEFT'); self.hintTitle:SetPoint('TOPLEFT', 10, -7)
  self.hint = K.text(self.hintBox, 12, C.text, 'LEFT'); self.hint:SetPoint('TOPLEFT', 10, -24); self.hint:SetPoint('TOPRIGHT', -10, -24)
  self.hint:SetWordWrap(true); self.hint:SetJustifyV('TOP')
  self.msg = K.text(f, 15, C.gold, 'CENTER'); self.msg:SetPoint('TOP', f, 'TOPLEFT', GX + 207, GY - 18 - W.MAX * ROWH - 112)
  self.msg2 = K.text(f, 12, C.dim, 'CENTER'); self.msg2:SetPoint('TOP', self.msg, 'BOTTOM', 0, -6)
  self.stats = K.text(f, 12, C.dim, 'CENTER'); self.stats:SetPoint('TOP', self.msg2, 'BOTTOM', 0, -6)
end

function G:guessed(key) for _, k in ipairs(self.s.guesses) do if k == key then return true end end; return false end

local function paintCell(c, state, text, sub)
  local col = (state == 'same') and { 0.16, 0.45, 0.16 } or (state == 'nearMore' or state == 'nearLess') and { 0.55, 0.45, 0.08 } or { 0.12, 0.1, 0.15 }
  c:SetFill(col[1], col[2], col[3], 1)
  c.a:SetText(text or '')
  c.b:SetText(sub or '')
end
local MORE = { row = 'lower down', col = 'more right', ranks = 'more' }
local LESS = { row = 'higher up', col = 'more left', ranks = 'fewer' }

function G:refresh()
  local s = self.s
  local daily = s and s.daily
  self.dailyBtn:SetStyle(daily and 'gold' or 'normal')
  self.practiceBtn:SetStyle((s and not daily) and 'gold' or 'normal')
  self.title:SetText(daily and ('Warlockle #' .. W.number(s.day)) or 'Warlockle - practice')
  self.sub:SetText('Guess the talent in ' .. W.MAX .. ' tries. Green = right, yellow = one off.')
  for key, b in pairs(self.icons) do
    local g = s and self:guessed(key)
    b.icon:SetDesaturated(g); b.veil:SetShown(g)
    local right = s and s.done and key == s.target
    local bc = right and C.gold or C.line
    b:SetBorderColor(bc[1], bc[2], bc[3], 1)
  end
  for r, row in ipairs(self.rows) do
    local key = s and s.guesses[r]
    local cells = row.cells
    if not key then
      for _, c in ipairs(cells) do paintCell(c, 'none', '', '') end
      cells[1].icon:Hide()
    else
      local t, cmp = A.TALENTS[key], W.compare(key, s.target)
      cells[1].icon:Show(); cells[1].icon:SetTexture(K.spellTexture(t.spell))
      paintCell(cells[1], key == s.target and 'same' or 'none', t.name, '')
      paintCell(cells[2], cmp.tree, W.TREE_NAME[t.tree]:sub(1, 5) .. (W.TREE_NAME[t.tree]:len() > 5 and '.' or ''), '')
      local function arrow(field, state) if state == 'same' then return '' end; return (state == 'more' or state == 'nearMore') and MORE[field] or LESS[field] end
      paintCell(cells[3], cmp.row, tostring(t.row + 1), arrow('row', cmp.row))
      paintCell(cells[4], cmp.col, tostring(t.col + 1), arrow('col', cmp.col))
      paintCell(cells[5], cmp.ranks, tostring(t.ranks), arrow('ranks', cmp.ranks))
      paintCell(cells[6], cmp.req, t.req and 'Yes' or 'No', '')
    end
  end
  local misses = s and #s.guesses - (s.won and 1 or 0) or 0
  if s and (misses >= W.HINT_AFTER or s.done) then
    self.hintTitle:SetText(s.done and 'The talent says:' or 'Hint - the talent says:')
    self.hint:SetText(s.done and (A.TALENTS[s.target].text or '') or W.hint(s.target))
  else
    self.hintTitle:SetText('Hint')
    self.hint:SetText('After ' .. W.HINT_AFTER .. ' misses you get the talent\'s own text, its name hidden.')
  end
  if s and s.done then
    local t = A.TALENTS[s.target]
    self.msg:SetText(s.won and ('Got it in ' .. #s.guesses .. '!') or ('It was ' .. t.name))
    self.msg:SetTextColor(s.won and C.good[1] or C.bad[1], s.won and C.good[2] or C.bad[2], s.won and C.good[3] or C.bad[3])
    if s.daily then
      local left = 86400 - (GetServerTime() % 86400)
      self.msg2:SetText(string.format('Next talent in %d h %02d min', floor(left / 3600), floor((left % 3600) / 60)))
    else self.msg2:SetText('') end
  else
    self.msg:SetText(s and (W.MAX - #s.guesses .. (W.MAX - #s.guesses == 1 and ' guess left' or ' guesses left')) or '')
    self.msg:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    self.msg2:SetText('')
  end
  local st = self.db.stats or {}
  self.stats:SetText('Daily: played ' .. (st.played or 0) .. ', solved ' .. (st.won or 0) .. ', streak ' .. (st.streak or 0) .. ', best streak ' .. (st.best or 0))
end

function G:openDaily()
  local day = W.today()
  local d = self.db.daily
  if not d or d.day ~= day then d = W.new(W.targetOf(day), true); d.day = day; self.db.daily = d end
  d.target = W.targetOf(day)    -- the talent list may have changed since it was saved
  self.s = d
  self:refresh()
end
function G:openPractice()
  local day = W.today()
  local key
  repeat key = A.TALENT_ORDER[math.random(1, #A.TALENT_ORDER)] until key ~= W.targetOf(day)
  self.s = W.new(key, false)
  self:refresh()
end

function G:guess(key)
  local s = self.s
  if not s then return end
  local ok, why = W.guess(s, key)
  if not ok then
    -- say why nothing happened, so the list never seems dead
    if s.done then
      self.msg2:SetText(s.daily and 'Today\'s talent is done - click Practice for another one' or 'This one is done - click Practice for a new one')
      self.practiceBtn:SetStyle('orange')
    else self.msg2:SetText(A.TALENTS[key].name .. ': ' .. (why or 'already guessed')) end
    A.sound('select')
    return
  end
  A.sound(s.won and 'win' or s.done and 'lose' or 'click')
  if s.done and s.daily and not s.counted then
    s.counted = true
    local st = self.db.stats or {}
    st.played = (st.played or 0) + 1
    if s.won then
      st.won = (st.won or 0) + 1
      st.streak = (st.lastWon == s.day - 1) and (st.streak or 0) + 1 or 1
      st.lastWon = s.day
      st.best = math.max(st.best or 0, st.streak)
      st.dist = st.dist or {}
      st.dist[#s.guesses] = (st.dist[#s.guesses] or 0) + 1
    else st.streak = 0 end
    self.db.stats = st
  end
  self:refresh()
end

function G:Show() self.f:Show(); if not self.s then self:openDaily() else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end
function G:OnUpdate() end

A.RegisterGame({
  key = 'warlockle', name = 'Warlockle', order = 4, ready = true, icon = A.SPELLS.curseOfElements.id,
  tagline = 'The talent of the day: guess it in six tries from its tree, tier, column and ranks.',
  bestLine = function()
    local db = A.db('warlockle')
    local d = db.daily
    if d and d.day == W.today() and d.done then return d.won and ('Today: solved in ' .. #d.guesses) or 'Today: missed' end
    return 'Today\'s talent is waiting'
  end,
  help = {
    '|cffffd040Guess the talent of the day in ' .. W.MAX .. ' tries.|r Click a talent in the trees to guess it.',
    ' ',
    'Each guess shows how close it is: the same tree (green), its tier and column in the tree and its number of ranks (green = right, yellow = one off, with which way to go), and whether it needs another talent first.',
    ' ',
    'After ' .. W.HINT_AFTER .. ' misses you see the talent\'s own text with its name hidden.',
    ' ',
    'There is one talent a day for everyone - in the browser and in the game. Practice gives you a random one any time.',
  },
  create = function(parent) return G.create(parent) end,
})
