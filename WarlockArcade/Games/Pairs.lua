-- Grimoire Pairs: the grimoire's pages lie face down. Turn two; the same icon twice stays open, else both turn back.
-- Find every pair in as few turns as you can. Three sizes; the fewest turns and the best time of each are kept.
-- The pictures are the arcade's spell, talent and demon icons (Iconle's answers, so no two look alike).
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local P = {}
A.PairsRules = P
P.SIZES = { { name = 'Small', cols = 4, rows = 4 }, { name = 'Medium', cols = 6, rows = 4 }, { name = 'Large', cols = 6, rows = 6 } }

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
function P.new(size, seed)
  local z = P.SIZES[size]
  local n = z.cols * z.rows / 2
  local rand = rng(seed or 1)
  local pics = {}
  for _, a in ipairs(A.IconleRules.answers()) do pics[#pics + 1] = a.icon end
  for i = #pics, 2, -1 do local j = rand(i); pics[i], pics[j] = pics[j], pics[i] end
  local cards = {}
  for i = 1, n do cards[#cards + 1] = { pic = pics[i] }; cards[#cards + 1] = { pic = pics[i] } end
  for i = #cards, 2, -1 do local j = rand(i); cards[i], cards[j] = cards[j], cards[i] end
  return { size = size, cards = cards, open = {}, found = 0, pairs = n, turns = 0, t = 0, started = false, done = false }
end
-- turns a card: 'first', 'match', 'miss' (two shown, they go back on the next turn), or nil
function P.flip(s, i)
  local c = s.cards[i]
  if s.done or not c or c.up or c.found then return nil end
  if #s.open == 2 then P.hide(s) end
  s.started = true
  c.up = true
  s.open[#s.open + 1] = i
  if #s.open == 1 then return 'first' end
  s.turns = s.turns + 1
  local a, b = s.cards[s.open[1]], s.cards[s.open[2]]
  if a.pic == b.pic then
    a.found, b.found = true, true
    s.open = {}
    s.found = s.found + 1
    if s.found == s.pairs then s.done = true end
    return 'match'
  end
  return 'miss'
end
-- the two shown cards of a miss go back
function P.hide(s)
  if #s.open == 2 then
    for _, i in ipairs(s.open) do s.cards[i].up = false end
    s.open = {}
  end
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local AW, AH = 600, 488

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('pairs')
  g.size = g.db.size or 1
  g.views = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.area = K.box(f, AW + 16, AH + 16, { 0.04, 0.03, 0.06 }, C.line, 2)
  self.area:SetPoint('TOPLEFT', 22, -14)
  local side = K.box(f, 290, AH + 16, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', self.area, 'TOPRIGHT', 16, 0)
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.pairsT = stat(-14, 'Pairs found', 26, C.gold)
  self.turnsT = stat(-70, 'Turns', 22)
  self.timeT = stat(-120, 'Time', 22)
  self.bestT = stat(-172, 'Best at this size (turns / time)', 15, C.dim)
  self.sizeBtns = {}
  for i, z in ipairs(P.SIZES) do
    local b = K.button(side, 84, 28, z.name, function() self.size = i; self.db.size = i; self:newGame() end, 'normal', 12)
    b:SetPoint('TOPLEFT', 14 + (i - 1) * 90, -226)
    self.sizeBtns[i] = b
  end
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -270); note:SetPoint('TOPRIGHT', -12, -270); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Turn two pages. The same icon twice stays open; else they turn back. Find every pair in as few turns as you can.')
  self.msg = K.text(side, 15, C.gold, 'CENTER'); self.msg:SetPoint('BOTTOM', 0, 72)
  self.newBtn = K.button(side, 262, 40, 'New game', function() self:newGame() end, 'orange', 15)
  self.newBtn:SetPoint('BOTTOMLEFT', 14, 14)
end

function G:cardView(i)
  local v = self.views[i]
  if not v then
    v = CreateFrame('Button', nil, self.area)
    v.back = K.shape(v, 'BACKGROUND', 'rr10'); v.back:SetAllPoints()
    v.line = K.shape(v, 'BORDER', 'rl10_1'); v.line:SetAllPoints()
    v.sigil = K.shape(v, 'ARTWORK', 'spark'); v.sigil:SetPoint('CENTER')
    v.icon = v:CreateTexture(nil, 'ARTWORK', nil, 1); v.icon:SetPoint('TOPLEFT', 6, -6); v.icon:SetPoint('BOTTOMRIGHT', -6, 6); v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v.hl = K.shape(v, 'HIGHLIGHT', 'rr10'); v.hl:SetAllPoints(); v.hl:SetVertexColor(1, 1, 1, 0.08)
    v:SetScript('OnClick', function(btn) self:flip(btn.i) end)
    self.views[i] = v
  end
  return v
end
function G:newGame()
  local z = P.SIZES[self.size]
  self.s = P.new(self.size, math.random(1, 2000000000))
  local cs = min(floor((AW - (z.cols - 1) * 10) / z.cols), floor((AH - (z.rows - 1) * 10) / z.rows))
  local x0 = 8 + (AW - (z.cols * cs + (z.cols - 1) * 10)) / 2
  local y0 = -8 - (AH - (z.rows * cs + (z.rows - 1) * 10)) / 2
  self.cs = cs
  for i = 1, z.cols * z.rows do
    local v = self:cardView(i)
    local col, row = (i - 1) % z.cols, floor((i - 1) / z.cols)
    v.i, v.x, v.y = i, x0 + col * (cs + 10), y0 - row * (cs + 10)
    v:SetSize(cs, cs)
    v:ClearAllPoints(); v:SetPoint('TOPLEFT', v.x, v.y)
    v.sigil:SetSize(cs * 0.55, cs * 0.55)
    v.shownUp = false
    v:Show()
    self:paint(v, false)
  end
  for i = z.cols * z.rows + 1, #self.views do self.views[i]:Hide() end
  self.msg:SetText('')
  A.sound('card')
  self:refresh()
end
function G:Show() self.f:Show(); if not self.s then self:newGame() else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:paint(v, up, found)
  if up then
    v.icon:SetTexture(K.spellTexture(self.s.cards[v.i].pic)); v.icon:Show(); v.sigil:Hide()
    K.fill(v.back, 0.16, 0.12, 0.22, 1)
    if found then v.line:SetVertexColor(C.good[1], C.good[2], C.good[3], 1) else v.line:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1) end
  else
    v.icon:Hide(); v.sigil:Show()
    K.fill(v.back, 0.3, 0.16, 0.48, 1)
    v.sigil:SetVertexColor(0.85, 0.65, 1, 0.55)
    v.line:SetVertexColor(0.6, 0.42, 0.9, 0.9)
  end
end
-- turns a card over: it narrows to nothing, changes face, widens again
function G:turn(v, up, found)
  local cs = self.cs
  v.shownUp = up
  K.tween(v, 0.2, function(_, raw)
    local w = raw < 0.5 and (1 - raw * 2) or (raw - 0.5) * 2
    if raw >= 0.5 and not v.turned then v.turned = true; self:paint(v, up, found) end
    v:SetWidth(max(1, cs * w)); v:ClearAllPoints(); v:SetPoint('TOPLEFT', v.x + cs * (1 - w) / 2, v.y)
  end, function() v.turned = nil; v:SetWidth(cs); v:ClearAllPoints(); v:SetPoint('TOPLEFT', v.x, v.y) end)
end
function G:flip(i)
  local s = self.s
  local before = {}
  for k, c in ipairs(s.cards) do before[k] = c.up end
  local res = P.flip(s, i)
  if not res then return end
  -- cards that went back because a new turn started
  for k, c in ipairs(s.cards) do if before[k] and not c.up then self:turn(self.views[k], false) end end
  self:turn(self.views[i], true, res == 'match')
  if res == 'match' then
    for k, c in ipairs(s.cards) do if c.found and c.pic == s.cards[i].pic and k ~= i then self:paint(self.views[k], true, true) end end
    A.sound(s.done and 'win' or 'combo')
    if s.done then self:finish() end
  elseif res == 'miss' then A.sound('flip'); self.backIn = 0.9
  else A.sound('flip') end
  self:refresh()
end
function G:finish()
  local s = self.s
  self.db.best = self.db.best or {}
  local b = self.db.best[s.size]
  local isNew = not b or s.turns < b.turns or (s.turns == b.turns and s.t < b.t)
  if isNew then self.db.best[s.size] = { turns = s.turns, t = s.t } end
  self.msg:SetText((isNew and 'New best! ' or 'All found! ') .. s.turns .. ' turns, ' .. K.dec(s.t, 1) .. ' s')
end

function G:refresh()
  local s = self.s
  self.pairsT:SetText(s.found .. ' / ' .. s.pairs)
  self.turnsT:SetText(tostring(s.turns))
  self.timeT:SetText(K.dec(s.t, 1) .. ' s')
  local b = self.db.best and self.db.best[self.size]
  self.bestT:SetText(b and (b.turns .. ' turns / ' .. K.dec(b.t, 1) .. ' s') or '-')
  for i, btn in ipairs(self.sizeBtns) do btn:SetStyle(i == self.size and 'gold' or 'normal') end
end

function G:OnUpdate(dt)
  local s = self.s
  if not s then return end
  if s.started and not s.done then
    s.t = s.t + dt
    self.tick = (self.tick or 0) + dt
    if self.tick > 0.1 then self.tick = 0; self.timeT:SetText(K.dec(s.t, 1) .. ' s') end
  end
  -- a miss turns back by itself after a moment
  if self.backIn then
    self.backIn = self.backIn - dt
    if self.backIn <= 0 then
      self.backIn = nil
      local open = s.open
      if #open == 2 then
        for _, k in ipairs(open) do self:turn(self.views[k], false) end
        P.hide(s)
      end
    end
  end
end
function G:OnKey(key)
  if key == 'N' then self:newGame(); return true end
  return false
end

A.RegisterGame({
  key = 'pairs', name = 'Grimoire Pairs', order = 21, ready = true, kind = 'puzzle', icon = A.SPELLS.baneOfHavoc.id,
  tagline = 'Turn the grimoire\'s pages two at a time. Find every pair.',
  bestLine = function() local b = A.db('pairs').best; local v = b and (b[3] or b[2] or b[1]); return v and ('Best: ' .. v.turns .. ' turns') or 'Play' end,
  help = {
    '|cffffd040Find every pair.|r Click a page to turn it, then another. The same icon twice stays open; two different ones turn back.',
    ' ',
    'Find them all in as few turns as you can. Three sizes - 8, 12 and 18 pairs; the fewest turns and the best time of each are kept. N starts a new game.',
  },
  create = function(parent) return G.create(parent) end,
})
