-- Demon 2048: slide the tiles, two of a kind merge into the next demon. Soul Shard, Imp, Voidwalker, Succubus,
-- Felhunter ... up to the Demon Lord at 2048. Theme only (Xn: "theme-only for 2048 is fine").
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, max, min, random = math.floor, math.max, math.min, math.random

local M = {}
A.MergeRules = M
M.N = 4
M.TIERS = {
  { name = 'Soul Shard', color = { 0.45, 0.25, 0.7 } },
  { name = 'Imp', pet = 'imp', color = { 0.85, 0.45, 0.15 } },
  { name = 'Voidwalker', pet = 'voidwalker', color = { 0.3, 0.35, 0.8 } },
  { name = 'Succubus', pet = 'succubus', color = { 0.75, 0.25, 0.55 } },
  { name = 'Felhunter', pet = 'felhunter', color = { 0.35, 0.6, 0.25 } },
  { name = 'Felguard', color = { 0.25, 0.7, 0.3 } },
  { name = 'Infernal', color = { 0.9, 0.35, 0.1 } },
  { name = 'Doomguard', color = { 0.7, 0.15, 0.15 } },
  { name = 'Dreadlord', color = { 0.4, 0.15, 0.55 } },
  { name = 'Pit Lord', color = { 0.55, 0.3, 0.15 } },
  { name = 'Demon Lord', color = { 1, 0.75, 0.2 } },
}
M.WIN = 11           -- the Demon Lord (2048)
function M.value(tier) return 2 ^ tier end

function M.new(seed)
  if seed then math.randomseed(seed) end
  local s = { grid = {}, score = 0, moves = 0, over = false, won = false, keepGoing = false, nextId = 0, best = 1 }
  for r = 1, M.N do s.grid[r] = {} end
  M.spawn(s); M.spawn(s)
  return s
end
function M.empty(s)
  local t = {}
  for r = 1, M.N do for c = 1, M.N do if not s.grid[r][c] then t[#t + 1] = { r, c } end end end
  return t
end
function M.spawn(s)
  local e = M.empty(s)
  if #e == 0 then return nil end
  local p = e[random(1, #e)]
  s.nextId = s.nextId + 1
  local tile = { tier = random() < 0.9 and 1 or 2, id = s.nextId, new = true }
  s.grid[p[1]][p[2]] = tile
  return tile
end
-- slide one line (a list of tiles or nil, in the direction of the move); returns the new line and the points
local function slide(line)
  local tiles = {}
  for _, t in ipairs(line) do if t then tiles[#tiles + 1] = t end end
  local out, pts, i = {}, 0, 1
  while i <= #tiles do
    local a, b = tiles[i], tiles[i + 1]
    if b and a.tier == b.tier and a.tier < #M.TIERS then
      out[#out + 1] = { tier = a.tier + 1, id = a.id, merged = true }
      pts = pts + M.value(a.tier + 1)
      i = i + 2
    else out[#out + 1] = a; i = i + 1 end
  end
  return out, pts
end
-- dir: 'LEFT', 'RIGHT', 'UP', 'DOWN'. Returns true if anything moved.
function M.move(s, dir)
  if s.over then return false end
  local N, g = M.N, s.grid
  for r = 1, N do for c = 1, N do local t = g[r][c]; if t then t.new, t.merged = nil, nil end end end
  local moved, gained = false, 0
  for k = 1, N do
    local cells = {}
    for i = 1, N do
      if dir == 'LEFT' then cells[i] = { k, i } elseif dir == 'RIGHT' then cells[i] = { k, N + 1 - i }
      elseif dir == 'UP' then cells[i] = { i, k } else cells[i] = { N + 1 - i, k } end
    end
    local line = {}
    for i, p in ipairs(cells) do line[i] = g[p[1]][p[2]] or false end
    local out, pts = slide(line)
    gained = gained + pts
    for i, p in ipairs(cells) do
      local before, after = g[p[1]][p[2]], out[i]
      if (before and before.id) ~= (after and after.id) or (after and after.merged) then moved = true end
      g[p[1]][p[2]] = after
    end
  end
  if not moved then return false end
  s.score = s.score + gained
  s.moves = s.moves + 1
  M.spawn(s)
  for r = 1, N do for c = 1, N do local t = g[r][c]; if t then s.best = max(s.best, t.tier); if t.tier >= M.WIN and not s.won then s.won = true; s.justWon = true end end end end
  if not M.canMove(s) then s.over = true end
  return true
end
function M.canMove(s)
  local N, g = M.N, s.grid
  for r = 1, N do for c = 1, N do
    local t = g[r][c]
    if not t then return true end
    local can = t.tier < #M.TIERS   -- two Demon Lords cannot merge: there is nothing above
    if can and c < N and g[r][c + 1] and g[r][c + 1].tier == t.tier then return true end
    if can and r < N and g[r + 1][c] and g[r + 1][c].tier == t.tier then return true end
  end end
  return false
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local TS, GAPX = 112, 10       -- tile size and gap
local BS = M.N * TS + (M.N + 1) * GAPX

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('merge')
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, BS, BS, { 0.1, 0.075, 0.13 }, C.line, 2)
  board:SetPoint('TOPLEFT', 60, -40)
  board:EnableMouse(true)
  board:SetScript('OnMouseDown', function() self.down = { GetCursorPosition() } end)
  board:SetScript('OnMouseUp', function() self:swipe() end)
  self.board = board
  self.cells = {}
  for r = 1, M.N do
    self.cells[r] = {}
    for c = 1, M.N do
      local bg = K.rect(board, 'BORDER', { 0.16, 0.12, 0.2 }, 1, 1)
      bg:SetSize(TS, TS); bg:SetPoint('TOPLEFT', GAPX + (c - 1) * (TS + GAPX), -GAPX - (r - 1) * (TS + GAPX))
      local t = CreateFrame('Frame', nil, board)
      t:SetSize(TS, TS); t:SetPoint('CENTER', bg, 'CENTER')
      t:SetFrameLevel(board:GetFrameLevel() + 2)
      t.fill = K.rect(t, 'BACKGROUND', { 0.5, 0.3, 0.7 }, 1); t.fill:SetAllPoints()
      t.icon = t:CreateTexture(nil, 'ARTWORK'); t.icon:SetSize(54, 54); t.icon:SetPoint('TOP', 0, -12); t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      t.big = K.text(t, 30, { 1, 1, 1 }, 'CENTER', K.FONT_TITLE, 'OUTLINE'); t.big:SetPoint('CENTER', 0, 10)
      t.name = K.text(t, 13, { 1, 1, 1 }, 'CENTER', K.FONT, 'OUTLINE'); t.name:SetPoint('BOTTOM', 0, 22)
      t.value = K.text(t, 11, { 1, 1, 1, 0.8 }, 'CENTER', K.FONT_NUM); t.value:SetPoint('BOTTOM', 0, 7)
      t:Hide()
      self.cells[r][c] = t
    end
  end
  -- side
  local side = K.box(f, 330, BS, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 24, 0)
  local title = K.text(side, 24, C.gold, 'CENTER', K.FONT_TITLE); title:SetPoint('TOP', 0, -16); title:SetText('Demon 2048')
  local function stat(y, label, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 20, y); a:SetText(label)
    local b = K.text(side, 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 20, y - 15)
    return b
  end
  self.scoreT = stat(-60, 'Score', C.gold)
  self.bestT = stat(-110, 'Best score', C.dim)
  self.topT = stat(-160, 'Biggest demon', C.shadow)
  self.ladder = K.text(side, 11, C.dim, 'LEFT'); self.ladder:SetPoint('TOPLEFT', 20, -214); self.ladder:SetPoint('TOPRIGHT', -14, -214)
  self.ladder:SetWordWrap(true); self.ladder:SetSpacing(2)
  local arrows = { { 'UP', 0, 1 }, { 'LEFT', -1, 0 }, { 'DOWN', 0, 0 }, { 'RIGHT', 1, 0 } }
  for _, a in ipairs(arrows) do
    local b = K.button(side, 56, 40, a[1] == 'UP' and 'Up' or a[1] == 'DOWN' and 'Down' or a[1] == 'LEFT' and 'Left' or 'Right', function() self:move(a[1]) end, 'normal', 12)
    b:SetPoint('BOTTOM', side, 'BOTTOM', a[2] * 62, 66 + a[3] * 46)
  end
  self.newBtn = K.button(side, 140, 32, 'New game', function() self:newGame() end, 'ghost', 12)
  self.newBtn:SetPoint('BOTTOM', 0, 16)
  self.msg = K.text(f, 16, C.gold, 'CENTER'); self.msg:SetPoint('TOP', board, 'BOTTOM', 0, -14)
  local o = K.box(f, 420, 220, { 0.07, 0.05, 0.1, 0.97 }, C.gold, 2)
  o:SetPoint('CENTER', board, 'CENTER')
  o:SetFrameLevel(f:GetFrameLevel() + 30)
  o:EnableMouse(true)
  o.title = K.text(o, 24, C.gold, 'CENTER', K.FONT_TITLE); o.title:SetPoint('TOP', 0, -18)
  o.body = K.text(o, 14, C.text, 'CENTER'); o.body:SetPoint('TOPLEFT', 20, -60); o.body:SetPoint('TOPRIGHT', -20, -60); o.body:SetWordWrap(true)
  o.go = K.button(o, 170, 40, 'New game', function() self:overlayGo() end, 'orange', 15)
  o.go:SetPoint('BOTTOM', 0, 16)
  o:Hide()
  self.overlay = o
  local lines = {}
  for i, t in ipairs(M.TIERS) do lines[i] = K.hex(t.color) .. K.num(M.value(i)) .. '|r ' .. t.name end
  self.ladder:SetText(table.concat(lines, '|n'))
end

function G:draw()
  local s = self.s
  for r = 1, M.N do for c = 1, M.N do
    local t, v = s.grid[r][c], self.cells[r][c]
    if not t then v:Hide()
    else
      local tier = M.TIERS[t.tier]
      v.fill:SetColorTexture(tier.color[1], tier.color[2], tier.color[3], 1)
      local pet = tier.pet and A.PETS[tier.pet]
      v.icon:SetShown(pet ~= nil)
      if pet then v.icon:SetTexture(K.spellTexture(pet.spell)) end
      v.big:SetText(pet and '' or (t.tier == 1 and 'Shard' or tier.name:sub(1, 1)))
      v.name:SetText(t.tier == 1 and '' or tier.name)
      v.value:SetText(K.num(M.value(t.tier)))
      v.pop = (t.new or t.merged) and 0.18 or nil
      v:SetAlpha(t.new and 0.3 or 1)
      v:Show()
    end
  end end
  self.scoreT:SetText(K.num(s.score))
  self.bestT:SetText(K.num(math.max(self.db.best or 0, s.score)))
  self.topT:SetText(M.TIERS[s.best].name)
end

function G:newGame()
  self.s = M.new()
  self.overlay:Hide()
  self.msg:SetText('Arrow keys, W A S D, swipe, or the buttons')
  self:draw()
end
function G:Show()
  self.f:Show()
  if not self.s then self.s = self.db.game; if self.s then self.msg:SetText('') end end
  if not self.s then self:newGame() else self:draw() end
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:move(dir)
  local s = self.s
  if not s or self.overlay:IsShown() then return end
  if M.move(s, dir) then
    A.sound('card')
    self.msg:SetText('')
    if s.score > (self.db.best or 0) then self.db.best = s.score end
    self.db.game = s
    self:draw()
    if s.justWon and not s.keepGoing then
      s.justWon = nil
      A.sound('win')
      self:showOverlay('won')
    elseif s.over then
      A.sound('lose')
      self.db.game = nil
      self:showOverlay('over')
    end
  end
end
function G:showOverlay(kind)
  local o, s = self.overlay, self.s
  self.overlayKind = kind
  if kind == 'won' then
    o.title:SetText('The Demon Lord is summoned!')
    o.body:SetText('You merged your way to 2048. Score: ' .. K.num(s.score) .. '|n|nKeep going for a bigger score?')
    o.go:SetLabel('Keep going')
  else
    o.title:SetText('No moves left')
    o.body:SetText('Score: |cffffd040' .. K.num(s.score) .. '|r|nBiggest demon: ' .. M.TIERS[s.best].name)
    o.go:SetLabel('New game')
  end
  o:Show()
end
function G:overlayGo()
  if self.overlayKind == 'won' then self.s.keepGoing = true; self.overlay:Hide() else self:newGame() end
end
function G:swipe()
  if not self.down then return end
  local x, y = GetCursorPosition()
  local dx, dy = x - self.down[1], y - self.down[2]
  self.down = nil
  local sc = self.board:GetEffectiveScale()
  dx, dy = dx / sc, dy / sc
  if math.abs(dx) < 24 and math.abs(dy) < 24 then return end
  if math.abs(dx) > math.abs(dy) then self:move(dx > 0 and 'RIGHT' or 'LEFT') else self:move(dy > 0 and 'UP' or 'DOWN') end
end

function G:OnUpdate(dt)
  for r = 1, M.N do for c = 1, M.N do
    local v = self.cells[r][c]
    if v.pop then
      v.pop = v.pop - dt
      local k = v.pop > 0 and (1 + 0.5 * v.pop) or 1
      v:SetSize(TS * min(k, 1.09), TS * min(k, 1.09))
      v:SetAlpha(min(1, v:GetAlpha() + dt * 6))
      if v.pop <= 0 then v.pop = nil; v:SetSize(TS, TS); v:SetAlpha(1) end
    end
  end end
end

local KEYMAP = { UP = 'UP', DOWN = 'DOWN', LEFT = 'LEFT', RIGHT = 'RIGHT', W = 'UP', S = 'DOWN', A = 'LEFT', D = 'RIGHT' }
function G:OnKey(key)
  if self.overlay:IsShown() then
    if key == 'ENTER' or key == 'SPACE' then self:overlayGo(); return true end
    return false
  end
  if KEYMAP[key] then self:move(KEYMAP[key]); return true end
  return false
end

A.RegisterGame({
  key = 'merge', name = 'Demon 2048', order = 8, ready = true, icon = A.PETS.imp.spell,
  tagline = 'Merge soul shards into ever bigger demons.',
  bestLine = function() local b = A.db('merge').best; return b and b > 0 and ('Best: ' .. K.num(b)) or 'Play' end,
  help = {
    '|cffffd040Slide all tiles at once.|r Two of the same demon that bump into each other merge into the next one.',
    ' ',
    'Soul Shard (2), Imp (4), Voidwalker (8), Succubus (16), Felhunter (32), Felguard, Infernal, Doomguard, Dreadlord, Pit Lord - and the Demon Lord at 2048.',
    ' ',
    'Arrow keys or W A S D, swipe on the board, or the buttons. The game is saved as you play.',
  },
  create = function(parent) return G.create(parent) end,
})
