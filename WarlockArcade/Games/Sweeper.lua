-- Felsweeper: Infernals are buried in the field. Open every safe square; a number tells how many Infernals touch it.
-- Right-click (or Flag mode) marks a square with a Banish sigil; clicking a number whose sigils are all placed opens
-- the squares around it. The first square is always safe and opens an area. Best times per size are kept.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local S = {}
A.SweeperRules = S
S.SIZES = { { name = 'Small', w = 9, h = 9, n = 10, cell = 44 }, { name = 'Medium', w = 16, h = 12, n = 30, cell = 34 }, { name = 'Large', w = 20, h = 15, n = 50, cell = 29 } }

function S.new(size)
  local z = S.SIZES[size]
  local s = { size = size, w = z.w, h = z.h, n = z.n, cells = {}, started = false, done = false, won = false, t = 0, opened = 0, flags = 0 }
  for r = 1, z.h do s.cells[r] = {}; for c = 1, z.w do s.cells[r][c] = { mine = false, open = false, flag = false, count = 0 } end end
  return s
end
local function around(s, r, c, fn)
  for dr = -1, 1 do for dc = -1, 1 do
    local rr, cc = r + dr, c + dc
    if (dr ~= 0 or dc ~= 0) and rr >= 1 and rr <= s.h and cc >= 1 and cc <= s.w then fn(rr, cc, s.cells[rr][cc]) end
  end end
end
-- the Infernals go in after the first click, never in the 3x3 around it
function S.place(s, r0, c0, rand)
  rand = rand or math.random
  local spots = {}
  for r = 1, s.h do for c = 1, s.w do if math.abs(r - r0) > 1 or math.abs(c - c0) > 1 then spots[#spots + 1] = { r, c } end end end
  for i = 1, s.n do
    local j = rand(i, #spots)
    spots[i], spots[j] = spots[j], spots[i]
    s.cells[spots[i][1]][spots[i][2]].mine = true
  end
  for r = 1, s.h do for c = 1, s.w do
    local n = 0
    around(s, r, c, function(_, _, x) if x.mine then n = n + 1 end end)
    s.cells[r][c].count = n
  end end
  s.started = true
end
-- opens a square (and the area around a zero). Returns 'boom', 'won', or nil
function S.open(s, r, c, rand)
  if s.done then return end
  local x = s.cells[r][c]
  if x.open or x.flag then return end
  if not s.started then S.place(s, r, c, rand) end
  if x.mine then
    x.open, x.boom = true, true
    s.done = true
    for rr = 1, s.h do for cc = 1, s.w do local y = s.cells[rr][cc]; if y.mine then y.open = true end end end
    return 'boom'
  end
  local stack = { { r, c } }
  while #stack > 0 do
    local p = table.remove(stack)
    local y = s.cells[p[1]][p[2]]
    if not y.open and not y.flag and not y.mine then
      y.open = true
      s.opened = s.opened + 1
      if y.count == 0 then around(s, p[1], p[2], function(rr, cc, z) if not z.open then stack[#stack + 1] = { rr, cc } end end) end
    end
  end
  if s.opened >= s.w * s.h - s.n then
    s.done, s.won = true, true
    for rr = 1, s.h do for cc = 1, s.w do local y = s.cells[rr][cc]; if y.mine and not y.flag then y.flag = true; s.flags = s.flags + 1 end end end
    return 'won'
  end
end
function S.flag(s, r, c)
  if s.done then return end
  local x = s.cells[r][c]
  if x.open then return end
  x.flag = not x.flag
  s.flags = s.flags + (x.flag and 1 or -1)
  return x.flag
end
-- a number with as many sigils around it as it says: opens the rest around it
function S.chord(s, r, c)
  local x = s.cells[r][c]
  if s.done or not x.open or x.count == 0 then return end
  local flags = 0
  around(s, r, c, function(_, _, y) if y.flag then flags = flags + 1 end end)
  if flags ~= x.count then return end
  local result
  around(s, r, c, function(rr, cc, y) if not y.open and not y.flag then result = S.open(s, rr, cc) or result end end)
  return result or 'opened'
end
function S.update(s, dt) if s.started and not s.done then s.t = s.t + dt end end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local AW, AH = 600, 470             -- the field's area
local NUM = { { 0.45, 0.65, 1 }, { 0.45, 0.9, 0.45 }, { 1, 0.45, 0.4 }, { 0.75, 0.5, 1 }, { 1, 0.65, 0.25 }, { 0.35, 0.9, 0.9 }, { 1, 1, 1 }, { 0.7, 0.7, 0.75 } }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('sweeper')
  g.size = g.db.size or 1
  g.cells = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.area = K.box(f, AW + 16, AH + 16, { 0.04, 0.03, 0.06 }, C.line, 2)
  self.area:SetPoint('TOPLEFT', 22, -14)
  -- side panel
  local side = K.box(f, 290, AH + 16, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', self.area, 'TOPRIGHT', 16, 0)
  local function stat(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.leftT = stat(-14, 'Infernals left', 28, C.fire)
  self.timeT = stat(-72, 'Time', 22, C.gold)
  self.bestT = stat(-124, 'Best time at this size', 15, C.dim)
  self.sizeBtns = {}
  for i, z in ipairs(S.SIZES) do
    local b = K.button(side, 84, 28, z.name, function() self.size = i; self.db.size = i; self:newGame() end, 'normal', 12)
    b:SetPoint('TOPLEFT', 14 + (i - 1) * 90, -178)
    self.sizeBtns[i] = b
  end
  self.flagBtn = K.button(side, 262, 32, '', function() self.flagMode = not self.flagMode; self:refreshSide() end, 'normal', 13)
  self.flagBtn:SetPoint('TOPLEFT', 14, -220)
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -266); note:SetPoint('TOPRIGHT', -12, -266); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Left-click opens a square, right-click (or Flag mode) puts a Banish sigil on it. Click a number with all its sigils placed to open the rest around it. The first square is always safe.')
  self.msg = K.text(side, 15, C.gold, 'CENTER'); self.msg:SetPoint('BOTTOM', 0, 72)
  self.newBtn = K.button(side, 262, 40, 'New game', function() self:newGame() end, 'orange', 15)
  self.newBtn:SetPoint('BOTTOMLEFT', 14, 14)
end

function G:cellView(i)
  local v = self.cells[i]
  if not v then
    v = CreateFrame('Button', nil, self.area)
    v:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    v.bg = K.shape(v, 'BACKGROUND', 'rr4'); v.bg:SetPoint('TOPLEFT', 1, -1); v.bg:SetPoint('BOTTOMRIGHT', -1, 1)
    v.hl = K.shape(v, 'HIGHLIGHT', 'rr4'); v.hl:SetPoint('TOPLEFT', 1, -1); v.hl:SetPoint('BOTTOMRIGHT', -1, 1); v.hl:SetVertexColor(1, 1, 1, 0.12)
    v.num = K.text(v, 14, C.text, 'CENTER', K.FONT_NUM, 'OUTLINE'); v.num:SetPoint('CENTER', 0, 0)
    v.icon = v:CreateTexture(nil, 'ARTWORK'); v.icon:SetPoint('CENTER'); v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v:SetScript('OnClick', function(btn, button) self:click(btn.r, btn.c, button) end)
    self.cells[i] = v
  end
  return v
end

function G:newGame()
  local z = S.SIZES[self.size]
  self.s = S.new(self.size)
  local cs = z.cell
  local x0, y0 = 8 + (AW - z.w * cs) / 2, -8 - (AH - z.h * cs) / 2
  local i = 0
  for r = 1, z.h do for c = 1, z.w do
    i = i + 1
    local v = self:cellView(i)
    v.r, v.c = r, c
    v:SetSize(cs, cs)
    v:ClearAllPoints(); v:SetPoint('TOPLEFT', x0 + (c - 1) * cs, y0 - (r - 1) * cs)
    v.num:SetFont(K.FONT_NUM, floor(cs * 0.5), 'OUTLINE')
    v.icon:SetSize(cs - 10, cs - 10)
    v:Show()
  end end
  for j = i + 1, #self.cells do self.cells[j]:Hide() end
  self.msg:SetText('')
  self:paint()
  self:refreshSide()
end
function G:Show() self.f:Show(); if not self.s then self:newGame() else self:refreshSide() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:click(r, c, button)
  local s = self.s
  if s.done then return end
  local x = s.cells[r][c]
  local flagging = button == 'RightButton' or self.flagMode or IsShiftKeyDown()
  local result
  if x.open then
    result = S.chord(s, r, c)
    if not result then return end
  elseif flagging then
    local on = S.flag(s, r, c)
    A.sound(on and 'place' or 'flip')
    self:paint(); self:refreshSide()
    return
  else
    if x.flag then return end
    result = S.open(s, r, c)
  end
  if result == 'boom' then
    self.msg:SetText('An Infernal! Try again')
    A.sound('crit'); A.sound('lose')
  elseif result == 'won' then
    local best = self.db.best and self.db.best[self.size]
    local isNew = not best or s.t < best
    if isNew then self.db.best = self.db.best or {}; self.db.best[self.size] = s.t end
    self.msg:SetText((isNew and 'New best! ' or 'Cleared! ') .. K.dec(s.t, 1) .. ' s')
    A.sound('win')
  else A.sound('pop') end
  self:paint()
  self:refreshSide()
end

function G:paint()
  local s = self.s
  local i = 0
  for r = 1, s.h do for c = 1, s.w do
    i = i + 1
    local v, x = self.cells[i], s.cells[r][c]
    if x.open then
      if x.mine then
        K.fill(v.bg, x.boom and 0.7 or 0.3, x.boom and 0.15 or 0.08, 0.06, 1)
        v.icon:SetTexture(K.spellTexture(A.SPELLS.rainOfFire.id)); v.icon:SetDesaturated(false); v.icon:Show(); v.num:SetText('')
      else
        v.bg:SetGradient('VERTICAL', CreateColor(0.08, 0.065, 0.11, 1), CreateColor(0.1, 0.08, 0.14, 1))
        v.icon:Hide()
        local n = x.count
        v.num:SetText(n > 0 and tostring(n) or '')
        if n > 0 then v.num:SetTextColor(NUM[n][1], NUM[n][2], NUM[n][3]) end
      end
    else
      v.num:SetText('')
      K.fill(v.bg, 0.24, 0.18, 0.36, 1)
      if x.flag then
        v.icon:SetTexture(K.spellTexture(A.SPELLS.baneOfHavoc.id))
        v.icon:SetDesaturated(s.done and not s.won and not x.mine)   -- a wrong sigil, shown grey at the end
        v.icon:Show()
      else v.icon:Hide() end
    end
  end end
end

function G:refreshSide()
  local s = self.s
  self.leftT:SetText(tostring(s.n - s.flags))
  self.timeT:SetText(K.dec(s.t, 1) .. ' s')
  local best = self.db.best and self.db.best[self.size]
  self.bestT:SetText(best and (K.dec(best, 1) .. ' s') or '-')
  for i, b in ipairs(self.sizeBtns) do b:SetStyle(i == self.size and 'gold' or 'normal') end
  self.flagBtn:SetLabel(self.flagMode and 'Flag mode: on (clicks place sigils)' or 'Flag mode: off')
  self.flagBtn:SetStyle(self.flagMode and 'blue' or 'normal')
end

function G:OnUpdate(dt)
  local s = self.s
  if s and s.started and not s.done then
    S.update(s, dt)
    self.tick = (self.tick or 0) + dt
    if self.tick > 0.1 then self.tick = 0; self.timeT:SetText(K.dec(s.t, 1) .. ' s') end
  end
end
function G:OnKey(key)
  if key == 'F' then self.flagMode = not self.flagMode; self:refreshSide(); return true end
  if key == 'N' then self:newGame(); return true end
  return false
end

A.RegisterGame({
  key = 'sweeper', name = 'Felsweeper', order = 14, ready = true, kind = 'puzzle', icon = A.SPELLS.shadowburn.id,
  tagline = 'Infernals are buried in the field. Find every safe square.',
  bestLine = function() local b = A.db('sweeper').best; local v = b and (b[3] or b[2] or b[1]); return v and ('Best: ' .. K.dec(v, 1) .. ' s') or 'Play' end,
  help = {
    '|cffffd040Open every square without an Infernal under it.|r A number says how many Infernals touch that square (the eight around it).',
    ' ',
    'Left-click opens a square. Right-click - or Flag mode (F), or Shift-click - puts a Banish sigil on a square you think hides an Infernal. Click a number whose sigils are all placed to open the rest around it.',
    ' ',
    'The first square is always safe and opens an area. Three sizes; the best time of each is kept. N starts a new game.',
  },
  create = function(parent) return G.create(parent) end,
})
