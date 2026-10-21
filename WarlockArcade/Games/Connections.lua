-- Warlock Connections: sixteen Warlock things - spells, talents, demons, consumables - hide four groups of four
-- ("Fire spells", "Talents with 5 ranks", "Soul in the name" ...). Pick four that belong together and submit; four
-- mistakes and the puzzle is lost. Every thing on the board fits exactly one of the four groups shown. One puzzle a
-- day (the same for everyone, by the server's date, like Warlockle), and practice puzzles.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local R = {}
A.ConnectionsRules = R
R.MISTAKES = 4
R.COLORS = { { 0.96, 0.8, 0.3 }, { 0.45, 0.85, 0.42 }, { 0.42, 0.64, 1 }, { 0.74, 0.48, 1 } }   -- by difficulty
R.LEVEL = { 'Easy', 'Medium', 'Hard', 'Tricky' }

-- every thing that can be on the board, by its name (a spell and a talent of the same name are one thing)
function R.items()
  if R._items then return R._items end
  local list, byName = {}, {}
  local function add(name, field, key, icon, item)
    local it = byName[name]
    if not it then it = { name = name }; byName[name] = it; list[#list + 1] = it end
    it[field] = key
    if not it.icon then it.icon, it.item = icon, item end
  end
  for key, s in pairs(A.SPELLS) do add(s.name, 'spell', key, s.id) end
  for key, t in pairs(A.TALENTS) do add(t.name, 'talent', key, t.spell) end
  for key, p in pairs(A.PETS) do add(p.name, 'pet', key, p.spell) end
  for key, c in pairs(A.CONSUMABLES) do add(c.name, 'cons', key, c.spell or c.item, not c.spell) end
  table.sort(list, function(a, b) return a.name < b.name end)
  R._items, R._byName = list, byName
  return list
end

local function sp(it) return it.spell and A.SPELLS[it.spell] end
local function tal(it) return it.talent and A.TALENTS[it.talent] end
local MANA = { lifeTap = true, improvedLifeTap = true, demonicRune = true, majorManaPotion = true }
-- the groups: id, what the group is called, difficulty 1-4, which things belong
R.CATS = {
  { 'affTal', 'Affliction talents', 1, function(it) local t = tal(it); return t and t.tree == 'affliction' end },
  { 'demoTal', 'Demonology talents', 1, function(it) local t = tal(it); return t and t.tree == 'demonology' end },
  { 'destTal', 'Destruction talents', 1, function(it) local t = tal(it); return t and t.tree == 'destruction' end },
  { 'demons', 'Demons you can summon', 1, function(it) return it.pet ~= nil end },
  { 'cons', 'Raid consumables', 1, function(it) return it.cons ~= nil end },
  { 'fire', 'Fire spells', 1, function(it) local s = sp(it); return s and s.school == 'fire' end },
  { 'dots', 'Spells that tick on the target', 2, function(it) local s = sp(it); return s and (s.kind == 'dot' or s.kind == 'hybrid') end },
  { 'channel', 'Channelled spells', 2, function(it) local s = sp(it); return s and s.kind == 'channel' end },
  { 'mana', 'They give you mana', 2, function(it) return MANA[it.spell or ''] or MANA[it.talent or ''] or MANA[it.cons or ''] or false end },
  { 'improved', 'Called "Improved ..."', 2, function(it) return it.name:find('^Improved ') ~= nil end },
  { 'demonic', 'Called "Demonic ..."', 2, function(it) return it.name:find('^Demonic ') ~= nil end },
  { 'cooldown', 'Spells with a cooldown', 3, function(it) local s = sp(it); return s and (s.cd or 0) > 0 end },
  { 'rank5', 'Talents with 5 ranks', 3, function(it) local t = tal(it); return t and t.ranks == 5 end },
  { 'rank1', 'Talents with a single rank', 3, function(it) local t = tal(it); return t and t.ranks == 1 end },
  { 'tier1', 'First-row talents', 3, function(it) local t = tal(it); return t and t.row == 0 end },
  { 'deep', 'The last two rows of a tree', 3, function(it) local t = tal(it); return t and t.row >= 5 end },
  { 'needs', 'Talents that need another talent first', 4, function(it) local t = tal(it); return t and t.req ~= nil end },
  { 'soul', '"Soul" in the name', 4, function(it) return it.name:find('Soul') ~= nil end },
  { 'fel', '"Fel" in the name', 4, function(it) return it.name:find('Fel') ~= nil end },
  { 'shadowName', '"Shadow" in the name', 4, function(it) return it.name:find('Shadow') ~= nil end },
  { 'fireName', '"Fire" in the name', 4, function(it) return it.name:lower():find('fire') ~= nil end },
  { 'baneName', '"Bane" in the name', 4, function(it) return it.name:find('Bane') ~= nil end },
}

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return n and (s % n) + 1 or s / 2147483647 end
end

-- a puzzle from a seed: four groups (one of each difficulty when it can), four things each that fit no other group
function R.newPuzzle(seed)
  local items = R.items()
  local rand = rng(seed)
  local byDiff = {}
  for _, c in ipairs(R.CATS) do byDiff[c[3]] = byDiff[c[3]] or {}; table.insert(byDiff[c[3]], c) end
  for attempt = 1, 400 do
    local cats, used = {}, {}
    for d = 1, 4 do
      local pool = attempt < 200 and byDiff[d] or R.CATS
      local c = pool[rand(#pool)]
      if used[c[1]] then break end
      used[c[1]] = true
      cats[#cats + 1] = c
    end
    if #cats == 4 then
      local groups, ok = {}, true
      for i, c in ipairs(cats) do
        local cand = {}
        for _, it in ipairs(items) do
          if c[4](it) then
            local other = false
            for j, o in ipairs(cats) do if j ~= i and o[4](it) then other = true; break end end
            if not other then cand[#cand + 1] = it.name end
          end
        end
        if #cand < 4 then ok = false; break end
        for j = #cand, 2, -1 do local k = rand(j); cand[j], cand[k] = cand[k], cand[j] end
        groups[i] = { cat = c[1], label = c[2], diff = c[3], items = { cand[1], cand[2], cand[3], cand[4] } }
      end
      if ok then
        table.sort(groups, function(a, b) return a.diff < b.diff end)
        local board = {}
        for _, g in ipairs(groups) do for _, n in ipairs(g.items) do board[#board + 1] = n end end
        for j = #board, 2, -1 do local k = rand(j); board[j], board[k] = board[k], board[j] end
        return { seed = seed, groups = groups, board = board, solved = {}, mistakes = 0, tries = {}, done = false, won = false }
      end
    end
  end
end
function R.dailySeed(day) return day * 7919 + 1301 end
function R.groupOf(s, name) for i, g in ipairs(s.groups) do for _, n in ipairs(g.items) do if n == name then return i end end end end
function R.isSolved(s, gi) for _, x in ipairs(s.solved) do if x == gi then return true end end; return false end

-- a guess of four names: 'right' (and which group), 'oneAway', 'wrong', or nil and why not
function R.guess(s, names)
  if s.done then return nil, 'This puzzle is finished' end
  if #names ~= 4 then return nil, 'Pick four' end
  local sorted = {}
  for i, n in ipairs(names) do sorted[i] = n end
  table.sort(sorted)
  local key = table.concat(sorted, '|')
  for _, t in ipairs(s.tries) do if t == key then return nil, 'Already tried' end end
  s.tries[#s.tries + 1] = key
  local count = {}
  for _, n in ipairs(names) do local g = R.groupOf(s, n); count[g] = (count[g] or 0) + 1 end
  for gi, c in pairs(count) do
    if c == 4 then
      s.solved[#s.solved + 1] = gi
      if #s.solved == 4 then s.done, s.won = true, true end
      return 'right', gi
    end
  end
  s.mistakes = s.mistakes + 1
  if s.mistakes >= R.MISTAKES then s.done = true end
  for _, c in pairs(count) do if c == 3 then return 'oneAway' end end
  return 'wrong'
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local TW, TH, GAP = 206, 80, 10
local GX = (960 - (4 * TW + 3 * GAP)) / 2
local GY = -84

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('connections')
  g.picked = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16)
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('Find four groups of four. Every thing fits exactly one group. Four mistakes allowed.')
  self.dailyBtn = K.button(f, 110, 28, 'Daily', function() self:openDaily() end, 'normal', 13)
  self.dailyBtn:SetPoint('TOPRIGHT', -138, -18)
  self.practiceBtn = K.button(f, 110, 28, 'Practice', function() self:openPractice() end, 'normal', 13)
  self.practiceBtn:SetPoint('TOPRIGHT', -20, -18)
  -- the solved groups: bars across the board, in the order they were found
  self.bars = {}
  for i = 1, 4 do
    local b = K.box(f, 4 * TW + 3 * GAP, TH, R.COLORS[1], { 1, 1, 1, 0.25 }, 1)
    b:SetPoint('TOPLEFT', GX, GY - (i - 1) * (TH + GAP))
    b:SetFrameLevel(f:GetFrameLevel() + 8)
    b.label = K.text(b, 15, { 0.06, 0.04, 0.08 }, 'CENTER', K.FONT); b.label:SetPoint('TOP', 0, -16)
    b.names = K.text(b, 12, { 0.1, 0.07, 0.12 }, 'CENTER'); b.names:SetPoint('TOPLEFT', 16, -40); b.names:SetPoint('TOPRIGHT', -16, -40); b.names:SetWordWrap(true)
    b.level = K.text(b, 10, { 0.1, 0.07, 0.12, 0.7 }, 'RIGHT'); b.level:SetPoint('TOPRIGHT', -12, -10)
    b:Hide()
    self.bars[i] = b
  end
  -- the sixteen tiles
  self.tiles = {}
  for i = 1, 16 do
    local t = K.box(f, TW, TH, C.panel2, C.line, 1, 'Button')
    t:SetFrameLevel(f:GetFrameLevel() + 4)
    t.icon = K.icon(t, 28, nil); t.icon:SetPoint('TOP', 0, -10)
    t.name = K.text(t, 12, C.text, 'CENTER'); t.name:SetPoint('TOPLEFT', 8, -44); t.name:SetPoint('TOPRIGHT', -8, -44); t.name:SetWordWrap(true)
    t:SetScript('OnClick', function(btn) self:toggle(btn.itemName) end)
    t:SetScript('OnEnter', function(btn) btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3], 1); K.showTip(btn, self:tipOf(btn.itemName)) end)
    t:SetScript('OnLeave', function(btn) self:paintTile(btn); GameTooltip:Hide() end)
    self.tiles[i] = t
  end
  local cy = GY - 4 * (TH + GAP) - 8
  self.dotsLabel = K.text(f, 12, C.dim, 'LEFT'); self.dotsLabel:SetPoint('TOPLEFT', GX, cy - 8); self.dotsLabel:SetText('Mistakes left')
  self.dots = {}
  for i = 1, R.MISTAKES do
    local d = K.shape(f, 'ARTWORK', 'circle'); d:SetSize(14, 14)
    d:SetPoint('LEFT', self.dotsLabel, 'RIGHT', 10 + (i - 1) * 20, 0)
    self.dots[i] = d
  end
  self.shuffleBtn = K.button(f, 110, 34, 'Shuffle', function() self:shuffle() end, 'normal', 13)
  self.clearBtn = K.button(f, 110, 34, 'Deselect', function() self.picked = {}; self:refresh() end, 'normal', 13)
  self.submitBtn = K.button(f, 140, 34, 'Submit', function() self:submit() end, 'orange', 14)
  self.submitBtn:SetPoint('TOPRIGHT', f, 'TOPLEFT', GX + 4 * TW + 3 * GAP, cy)
  self.clearBtn:SetPoint('RIGHT', self.submitBtn, 'LEFT', -10, 0)
  self.shuffleBtn:SetPoint('RIGHT', self.clearBtn, 'LEFT', -10, 0)
  self.msg = K.text(f, 15, C.gold, 'CENTER'); self.msg:SetPoint('TOP', f, 'TOP', 0, cy - 50)
  self.stats = K.text(f, 12, C.dim, 'CENTER'); self.stats:SetPoint('TOP', self.msg, 'BOTTOM', 0, -8)
end

function G:tipOf(name)
  R.items()
  local it = R._byName[name]
  if not it then return nil end
  local lines = { { name, { 1, 1, 1 } } }
  if it.spell then lines[#lines + 1] = { 'Spell', C.gold } end
  if it.talent then lines[#lines + 1] = { 'Talent', C.gold } end
  if it.pet then lines[#lines + 1] = { 'Demon', C.gold } end
  if it.cons then lines[#lines + 1] = { 'Consumable', C.gold } end
  lines[#lines + 1] = { self:picked_(name) and 'Click to take it back' or 'Click to pick it', C.dim }
  return lines
end
function G:picked_(name) for _, n in ipairs(self.picked) do if n == name then return true end end; return false end

function G:openDaily()
  local day = A.WarlockleRules.today()
  local d = self.db.daily
  if not (d and d.day == day and d.s) then
    d = { day = day, s = R.newPuzzle(R.dailySeed(day)) }
    self.db.daily = d
  end
  self.s, self.daily, self.day = d.s, true, day
  self.picked = {}
  self:layout(true)
end
function G:openPractice()
  self.s, self.daily = R.newPuzzle(math.random(1, 2000000000)), false
  self.picked = {}
  self:layout(true)
  A.sound('flip')
end
function G:Show()
  self.f:Show()
  if not self.s then self:openDaily() else self:layout(false) end
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:toggle(name)
  local s = self.s
  if not s or s.done or R.isSolved(s, R.groupOf(s, name)) then return end
  for i, n in ipairs(self.picked) do
    if n == name then table.remove(self.picked, i); A.sound('flip'); self:refresh(); return end
  end
  if #self.picked >= 4 then self.msg:SetText('Four picked - submit them, or take one back'); A.sound('error'); return end
  self.picked[#self.picked + 1] = name
  A.sound('pop')
  self:refresh()
end
function G:shuffle()
  local s = self.s
  if not s then return end
  K.shuffle(s.board)
  self:layout(true)
  A.sound('card')
end

function G:submit()
  local s = self.s
  if not s or s.done then return end
  local res, gi = R.guess(s, self.picked)
  if not res then self.msg:SetText(gi or ''); A.sound('error'); return end
  if res == 'right' then
    self.picked = {}
    self.msg:SetText(s.won and 'Solved!' or 'That\'s a group!')
    A.sound(s.won and 'win' or 'combo')
  else
    self.msg:SetText(res == 'oneAway' and 'One away...' or 'Not a group')
    A.sound(s.done and 'lose' or 'error')
    -- a little shake of the picked tiles
    for _, t in ipairs(self.tiles) do
      if self:picked_(t.itemName) then
        local x, y = t.baseX, t.baseY
        K.tween(t, 0.35, function(_, raw) t:SetPoint('TOPLEFT', x + math.sin(raw * 18) * 7 * (1 - raw), y) end)
      end
    end
    if s.done then self.picked = {} end
  end
  if s.done and self.daily then self:record() end
  self:layout(res == 'right')
end
function G:record()
  local db, s = self.db, self.s
  if db.lastDay == self.day then return end
  db.lastDay = self.day
  db.played = (db.played or 0) + 1
  if s.won then
    db.won = (db.won or 0) + 1
    db.streak = (db.streak or 0) + 1
    db.bestStreak = max(db.bestStreak or 0, db.streak)
  else db.streak = 0 end
end

-- the board: solved bars at the top, the rest of the tiles below them
function G:layout(animate)
  local s = self.s
  if not s then return end
  R.items()   -- a daily puzzle read back from the saved variables needs the list of things too
  self.title:SetText(self.daily and ('Warlock Connections #' .. A.WarlockleRules.number(self.day)) or 'Warlock Connections - practice')
  self.dailyBtn:SetStyle(self.daily and 'gold' or 'normal')
  self.practiceBtn:SetStyle(self.daily and 'normal' or 'gold')
  -- when the puzzle is lost, every group is shown
  local shown = {}
  for _, gi in ipairs(s.solved) do shown[#shown + 1] = gi end
  if s.done and not s.won then for gi = 1, 4 do if not R.isSolved(s, gi) then shown[#shown + 1] = gi end end end
  for i, b in ipairs(self.bars) do
    local gi = shown[i]
    if gi then
      local g = s.groups[gi]
      local c = R.COLORS[g.diff]
      b:SetFill(c[1], c[2], c[3], R.isSolved(s, gi) and 1 or 0.55)
      b.label:SetText(g.label)
      b.names:SetText(table.concat(g.items, '  -  '))
      b.level:SetText(R.LEVEL[g.diff])
      if not b:IsShown() then b:Show(); if animate then K.fadeIn(b, 0.25) end end
    else b:Hide() end
  end
  local n = 0
  local rest = {}
  for _, name in ipairs(s.board) do
    local gi = R.groupOf(s, name)
    local isShown = false
    for _, x in ipairs(shown) do if x == gi then isShown = true end end
    if not isShown then rest[#rest + 1] = name end
  end
  for i, t in ipairs(self.tiles) do
    local name = rest[i]
    if name then
      local row = #shown + floor(n / 4)
      local col = n % 4
      t.baseX, t.baseY = GX + col * (TW + GAP), GY - row * (TH + GAP)
      t:ClearAllPoints(); t:SetPoint('TOPLEFT', t.baseX, t.baseY)
      t.itemName = name
      local it = R._byName[name]
      t.icon:SetTexture(it.item and K.itemTexture(it.icon) or K.spellTexture(it.icon))
      t.name:SetText(name)
      self:paintTile(t)
      t:Show()
      if animate then local d = n * 0.015; K.tween(t, 0.18 + d, function(_, raw) t:SetAlpha(max(0, min(1, (raw * (0.18 + d) - d) / 0.18))) end) end
      n = n + 1
    else t:Hide() end
  end
  self:refresh()
end
function G:paintTile(t)
  local on = self:picked_(t.itemName)
  if on then
    t:SetFill(0.32, 0.22, 0.48, 1); t:SetBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
    t.name:SetTextColor(1, 1, 1)
  else
    t:SetFill(C.panel2[1], C.panel2[2], C.panel2[3], 1); t:SetBorderColor(C.line[1], C.line[2], C.line[3], 1)
    t.name:SetTextColor(C.text[1], C.text[2], C.text[3])
  end
end
function G:refresh()
  local s = self.s
  for _, t in ipairs(self.tiles) do if t:IsShown() then self:paintTile(t) end end
  local left = R.MISTAKES - s.mistakes
  for i, d in ipairs(self.dots) do
    if i <= left then d:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1) else d:SetVertexColor(0.25, 0.22, 0.3, 1) end
  end
  self.submitBtn:SetEnabled(not s.done and #self.picked == 4)
  self.clearBtn:SetEnabled(not s.done and #self.picked > 0)
  self.shuffleBtn:SetEnabled(not s.done)
  if s.done then
    self.msg:SetText(s.won and ('Solved with ' .. s.mistakes .. (s.mistakes == 1 and ' mistake' or ' mistakes')) or 'Out of mistakes - here are the groups')
  end
  local db = self.db
  if self.daily then
    self.stats:SetText('Daily: played ' .. (db.played or 0) .. ', solved ' .. (db.won or 0) .. ', streak ' .. (db.streak or 0) .. ', best streak ' .. (db.bestStreak or 0)
      .. (s.done and '  -  a new puzzle tomorrow, or try Practice' or ''))
  else self.stats:SetText(s.done and 'Click Practice for another one' or 'Practice puzzles do not count for the daily streak') end
end

function G:OnKey(key)
  if key == 'ENTER' and self.s and not self.s.done and #self.picked == 4 then self:submit(); return true end
  return false
end

A.RegisterGame({
  key = 'connections', name = 'Warlock Connections', order = 10, ready = true, kind = 'daily', icon = A.SPELLS.drainSoul.id,
  tagline = 'Sixteen Warlock things, four hidden groups. A new one daily.',
  bestLine = function()
    local db = A.db('connections')
    if db.daily and db.daily.day == A.WarlockleRules.today() and db.daily.s and db.daily.s.done then return db.daily.s.won and 'Today: solved' or 'Today: missed' end
    return 'New puzzle today'
  end,
  help = {
    '|cffffd040Find the four groups of four.|r Click four things that belong together, then Submit (or press Enter).',
    ' ',
    'The things are spells, talents, demons and raid consumables of the Forever Warlock Sim. A group can be what they are (Fire spells, Demonology talents), a number about them (Talents with 5 ranks, Spells with a cooldown) or just their names ("Soul" in the name). Every thing on the board fits exactly one of the four groups.',
    ' ',
    'Three of four right says |cffffd040One away|r. Four mistakes and the puzzle is over. The colours go from easy (yellow) to tricky (purple).',
    ' ',
    'One daily puzzle - the same for everyone - and as many practice puzzles as you like.',
  },
  create = function(parent) return G.create(parent) end,
})
