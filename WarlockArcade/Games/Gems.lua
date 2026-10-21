-- Spell Gems: swap two gems next to each other to line up three or more of a kind. Every gem is a spell: matching
-- three casts it once - its real damage for the sim's standard character - and chain reactions hit harder (x1.5, x2 ..).
-- Life Tap gems give moves instead. Four in a row makes a gem that clears its line, five makes Rain of Fire (clears
-- every gem of one kind), an L or T makes Hellfire (clears around it). Beat each Molten Core boss before the moves run out.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local M = {}
A.GemsRules = M
M.N = 8
M.TYPES = { 'shadowBolt', 'immolate', 'corruption', 'incinerate', 'conflagrate', 'lifeTap' }
M.TAP = 6
M.MOVES = 20
M.BOSSES = { 'Lucifron', 'Magmadar', 'Gehennas', 'Garr', 'Shazzrah', 'Baron Geddon', 'Golemagg', 'Sulfuron Harbinger', 'Majordomo Executus', 'Ragnaros' }
M.COLORS = { { 0.7, 0.42, 1 }, { 1, 0.5, 0.16 }, { 0.48, 0.9, 0.32 }, { 1, 0.3, 0.25 }, { 1, 0.78, 0.25 }, { 0.3, 0.6, 1 } }

-- a whole cast's damage for the standard character (crits at their chance); a gem is a third of it
function M.castDamage(key)
  local s, c, ch = A.SPELLS[key], A.CAST[key], A.CHARACTER
  local crit = 1 + ch.critPct / 100 * (ch.critMult - 1)
  local direct = c and c.direct or (s.base and (s.base + (s.coef or 0) * ch.sp)) or 0
  local dot = c and c.tick and c.tick * c.ticks or 0
  return direct * crit + dot
end
function M.gemDamage(t) return (t == M.TAP or not M.TYPES[t]) and 0 or M.castDamage(M.TYPES[t]) / 3 end   -- Rain of Fire gems (kind 0) deal nothing themselves
function M.bossHp(level) return floor(6000 * 1.4 ^ (level - 1) / 100 + 0.5) * 100 end

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
function M.new(seed)
  local s = { rand = rng(seed or 1), nextId = 0, level = 1, moves = M.MOVES, damage = 0, total = 0, taps = 0, done = false, best = 0 }
  s.hp = M.bossHp(1)
  M.fill(s)
  return s
end
local function gem(s, t, sp) s.nextId = s.nextId + 1; return { id = s.nextId, t = t, sp = sp } end
-- a new board with no matches on it and at least one move
function M.fill(s)
  for guard = 1, 100 do
    s.grid = {}
    for r = 1, M.N do
      s.grid[r] = {}
      for c = 1, M.N do
        local t
        repeat
          t = s.rand(#M.TYPES)
          local row = c > 2 and s.grid[r][c - 1].t == t and s.grid[r][c - 2].t == t
          local col = r > 2 and s.grid[r - 1][c].t == t and s.grid[r - 2][c].t == t
        until not row and not col
        s.grid[r][c] = gem(s, t)
      end
    end
    if M.findMove(s) then return end
  end
end
function M.copyGrid(g)
  local out = {}
  for r = 1, M.N do out[r] = {}; for c = 1, M.N do local x = g[r][c]; out[r][c] = x and { id = x.id, t = x.t, sp = x.sp } or false end end
  return out
end

-- runs of three or more of a kind: list of { cells = {{r,c}..}, dir = 'h'|'v' }
function M.runs(g)
  local out = {}
  local function scan(get, dir)
    for a = 1, M.N do
      local b = 1
      while b <= M.N do
        local x = get(a, b)
        local e = b
        if x and x.t > 0 then
          while e + 1 <= M.N and get(a, e + 1) and get(a, e + 1).t == x.t do e = e + 1 end
        end
        if x and x.t > 0 and e - b + 1 >= 3 then
          local cells = {}
          for k = b, e do cells[#cells + 1] = dir == 'h' and { a, k } or { k, a } end
          out[#out + 1] = { cells = cells, dir = dir, t = x.t }
        end
        b = e + 1
      end
    end
  end
  scan(function(r, c) return g[r][c] end, 'h')
  scan(function(c, r) return g[r][c] end, 'v')
  return out
end
local function adjacent(a, b) return abs(a[1] - b[1]) + abs(a[2] - b[2]) == 1 end
-- would swapping these make a match (or is one of them Rain of Fire)?
function M.valid(s, a, b)
  if not adjacent(a, b) then return false end
  local g = s.grid
  local x, y = g[a[1]][a[2]], g[b[1]][b[2]]
  if x.sp == 'bomb' or y.sp == 'bomb' then return true end
  g[a[1]][a[2]], g[b[1]][b[2]] = y, x
  local ok = #M.runs(g) > 0
  g[a[1]][a[2]], g[b[1]][b[2]] = x, y
  return ok
end
function M.findMove(s)
  for r = 1, M.N do for c = 1, M.N do
    if c < M.N and M.valid(s, { r, c }, { r, c + 1 }) then return { r, c }, { r, c + 1 } end
    if r < M.N and M.valid(s, { r, c }, { r + 1, c }) then return { r, c }, { r + 1, c } end
  end end
end

-- clears a set of cells; specials caught in it go off too. Returns the gems cleared (with their cells)
local function blast(s, g, set, bombColor)
  local queue, cleared = {}, {}
  for key in pairs(set) do queue[#queue + 1] = key end
  local i = 1
  while i <= #queue do
    local key = queue[i]; i = i + 1
    local r, c = floor(key / 100), key % 100
    local x = g[r][c]
    if x and not cleared[key] then
      cleared[key] = { r = r, c = c, gem = x }
      local more = {}
      if x.sp == 'row' then for k = 1, M.N do more[#more + 1] = r * 100 + k end
      elseif x.sp == 'col' then for k = 1, M.N do more[#more + 1] = k * 100 + c end
      elseif x.sp == 'area' then for dr = -1, 1 do for dc = -1, 1 do local rr, cc = r + dr, c + dc; if rr >= 1 and rr <= M.N and cc >= 1 and cc <= M.N then more[#more + 1] = rr * 100 + cc end end end
      elseif x.sp == 'bomb' then
        local color = bombColor or s.rand(#M.TYPES)
        for rr = 1, M.N do for cc = 1, M.N do local y = g[rr][cc]; if y and y.t == color then more[#more + 1] = rr * 100 + cc end end end
      end
      for _, k in ipairs(more) do if not cleared[k] then queue[#queue + 1] = k end end
    end
  end
  return cleared
end

-- a swap and everything it sets off. Returns nil (and why) for a swap that does nothing, else a list of steps:
-- { grid = board after the step, cleared = {id = true}, damage, cascade, made = {id = special} }
function M.swap(s, a, b)
  if s.done then return nil, 'over' end
  if not M.valid(s, a, b) then return nil, 'no match' end
  local g = s.grid
  local x, y = g[a[1]][a[2]], g[b[1]][b[2]]
  g[a[1]][a[2]], g[b[1]][b[2]] = y, x
  s.moves = s.moves - 1
  local steps = { { grid = M.copyGrid(g), swap = true } }
  local cascade = 0
  -- Rain of Fire swapped with a gem: every gem of that kind
  local first
  if x.sp == 'bomb' or y.sp == 'bomb' then
    local bomb, other, bc = x.sp == 'bomb' and x or y, x.sp == 'bomb' and y or x, x.sp == 'bomb' and b or a
    local set = {}
    local color = other.t > 0 and other.t or s.rand(#M.TYPES)
    for r = 1, M.N do for c = 1, M.N do if g[r][c] == bomb or g[r][c].t == color then set[r * 100 + c] = true end end end
    first = blast(s, g, set, color)
  end
  while true do
    local cleared, made = first, {}
    first = nil
    if not cleared then
      local runs = M.runs(g)
      if #runs == 0 then break end
      local set, count = {}, {}
      for _, run in ipairs(runs) do for _, rc in ipairs(run.cells) do local k = rc[1] * 100 + rc[2]; set[k] = true; count[k] = (count[k] or 0) + 1 end end
      -- specials: 5+ in a line Rain of Fire, an L or T Hellfire, 4 a line gem; made where the swap was (or the middle)
      local keep = {}
      for _, run in ipairs(runs) do
        local n = #run.cells
        local at
        for _, rc in ipairs(run.cells) do
          if (rc[1] == a[1] and rc[2] == a[2]) or (rc[1] == b[1] and rc[2] == b[2]) then at = rc end
        end
        for _, rc in ipairs(run.cells) do if count[rc[1] * 100 + rc[2]] > 1 then at = at or rc; if n < 5 then keep[rc[1] * 100 + rc[2]] = 'area' end end end
        at = at or run.cells[floor((n + 1) / 2)]
        local k = at[1] * 100 + at[2]
        if n >= 5 then keep[k] = 'bomb' elseif n == 4 and not keep[k] then keep[k] = run.dir == 'h' and 'row' or 'col' end
      end
      for k in pairs(keep) do set[k] = nil end
      cleared = blast(s, g, set)
      for k, sp in pairs(keep) do
        local r, c = floor(k / 100), k % 100
        local old = g[r][c]
        if old then
          local ng = gem(s, sp == 'bomb' and 0 or old.t, sp)
          g[r][c] = ng
          made[ng.id] = sp
        end
      end
    end
    cascade = cascade + 1
    local mult = 1 + 0.5 * (cascade - 1)
    local dmg, taps, ids = 0, 0, {}
    for k, cl in pairs(cleared) do
      ids[cl.gem.id] = true
      if cl.gem.t == M.TAP then taps = taps + 1 else dmg = dmg + M.gemDamage(cl.gem.t) end
      g[cl.r][cl.c] = false
    end
    dmg = dmg * mult
    s.damage = s.damage + dmg
    s.total = s.total + dmg
    s.taps = s.taps + taps
    local extra = floor(s.taps / 3)
    s.taps = s.taps - extra * 3
    s.moves = s.moves + extra
    -- fall and refill
    for c = 1, M.N do
      local w = M.N
      for r = M.N, 1, -1 do if g[r][c] then local v = g[r][c]; g[r][c] = false; g[w][c] = v; w = w - 1 end end
      for r = w, 1, -1 do g[r][c] = gem(s, s.rand(#M.TYPES)) end
    end
    steps[#steps + 1] = { grid = M.copyGrid(g), cleared = ids, damage = dmg, cascade = cascade, mult = mult, made = made, moves = extra }
    if cascade > 30 then break end
  end
  -- the boss
  local result
  if s.damage >= s.hp then
    s.level = s.level + 1
    s.damage = 0
    s.hp = M.bossHp(s.level)
    s.moves = M.MOVES
    result = 'boss'
    if s.level > #M.BOSSES then s.done, s.won = true, true end
  elseif s.moves <= 0 then s.done = true; result = 'over' end
  if not s.done and not M.findMove(s) then M.fill(s); steps[#steps + 1] = { grid = M.copyGrid(s.grid), shuffled = true } end
  return steps, result
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local CS = 56                       -- cell size
local BX, BY = 30, -24              -- the board's top left
local BW = CS * M.N + 16

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('gems')
  g.views, g.pool = {}, {}
  g.queue = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, BW, BW, { 0.04, 0.03, 0.06 }, C.line, 2)
  board:SetPoint('TOPLEFT', BX, BY)
  board:SetClipsChildren(true)
  board:EnableMouse(true)
  self.board = board
  for r = 1, M.N do for c = 1, M.N do
    if (r + c) % 2 == 0 then local t = K.rect(board, 'BORDER', { 1, 1, 1 }, 0.025); t:SetSize(CS, CS); t:SetPoint('TOPLEFT', 8 + (c - 1) * CS, -8 - (r - 1) * CS) end
  end end
  board:SetScript('OnMouseDown', function() self:down() end)
  board:SetScript('OnMouseUp', function() self:up() end)
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.sel = K.shape(self.layer, 'OVERLAY', 'rl10_2'); self.sel:SetSize(CS, CS); self.sel:SetVertexColor(1, 0.85, 0.35, 1); self.sel:Hide()
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 30)
  self.pop = K.popups(self.top)
  -- side panel
  local side = K.box(f, 384, BW, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  self.side = side
  self.bossIcon = K.icon(side, 44, A.SPELLS.rainOfFire.id); self.bossIcon:SetPoint('TOPLEFT', 16, -16)
  self.bossT = K.text(side, 18, C.gold, 'LEFT', K.FONT); self.bossT:SetPoint('TOPLEFT', self.bossIcon, 'TOPRIGHT', 12, -2)
  self.levelT = K.text(side, 11, C.dim, 'LEFT'); self.levelT:SetPoint('TOPLEFT', self.bossT, 'BOTTOMLEFT', 0, -4)
  self.hpBar = K.box(side, 352, 22, { 0.06, 0.03, 0.04 }, C.line, 1)
  self.hpBar:SetPoint('TOPLEFT', 16, -74)
  self.hpFill = K.shape(self.hpBar, 'ARTWORK', 'rr4'); self.hpFill:SetPoint('TOPLEFT', 1, -1); self.hpFill:SetPoint('BOTTOMLEFT', 1, 1)
  K.fill(self.hpFill, 0.85, 0.2, 0.18, 1)
  self.hpT = K.text(self.hpBar, 12, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); self.hpT:SetPoint('CENTER')
  local function stat(x, y, label, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', x, y); a:SetText(label)
    local b = K.text(side, 24, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', x, y - 15)
    return b
  end
  self.movesT = stat(16, -110, 'Moves left', C.chips)
  self.totalT = stat(140, -110, 'Damage', C.gold)
  self.bestT = stat(264, -110, 'Best boss', C.dim)
  -- the gems: what each one is worth
  local y = -170
  local legend = K.text(side, 11, C.dim, 'LEFT'); legend:SetPoint('TOPLEFT', 16, y); legend:SetText('Three in a row cast the spell once:')
  for i, key in ipairs(M.TYPES) do
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    local ic = K.icon(side, 22, A.SPELLS[key].id); ic:SetPoint('TOPLEFT', 16 + col * 176, y - 20 - row * 28)
    local t = K.text(side, 11, C.text, 'LEFT'); t:SetPoint('LEFT', ic, 'RIGHT', 6, 0)
    t:SetText(A.SPELLS[key].name .. '  ' .. K.paint(C.gold, i == M.TAP and '+1 move' or K.num(M.castDamage(key))))
  end
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 16, y - 112); note:SetPoint('TOPRIGHT', -14, y - 112); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Chain reactions hit harder: x1.5, x2 ... Four in a row: a gem that clears its line. Five: Rain of Fire, clears one kind. An L or T: Hellfire. Every 3 Life Tap gems: +1 move.')
  self.msg = K.text(side, 14, C.gold, 'CENTER'); self.msg:SetPoint('BOTTOM', 0, 66)
  self.hintBtn = K.button(side, 110, 34, 'Hint', function() self:hint() end, 'normal', 13)
  self.hintBtn:SetPoint('BOTTOMLEFT', 16, 16)
  self.newBtn = K.button(side, 226, 34, 'New game', function() self:newGame() end, 'orange', 14)
  self.newBtn:SetPoint('BOTTOMRIGHT', -16, 16)
end

function G:cellPos(r, c) return 8 + (c - 1) * CS + CS / 2, -8 - (r - 1) * CS - CS / 2 end
function G:gemView(x)
  local v = table.remove(self.pool)
  if not v then
    v = CreateFrame('Frame', nil, self.layer)
    v:SetSize(CS - 6, CS - 6)
    v.bg = K.shape(v, 'BACKGROUND', 'rr10'); v.bg:SetAllPoints()
    v.line = K.shape(v, 'BORDER', 'rl10_1'); v.line:SetAllPoints()
    v.icon = v:CreateTexture(nil, 'ARTWORK'); v.icon:SetSize(34, 34); v.icon:SetPoint('CENTER'); v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v.stripe1 = K.rect(v, 'OVERLAY', { 1, 1, 1 }, 0.75); v.stripe2 = K.rect(v, 'OVERLAY', { 1, 1, 1 }, 0.75)
    v.spark = K.shape(v, 'OVERLAY', 'spark', 1); v.spark:SetSize(60, 60); v.spark:SetPoint('CENTER')
    v.ring = K.shape(v, 'OVERLAY', 'ring', 2); v.ring:SetSize(48, 48); v.ring:SetPoint('CENTER')
  end
  v.gid = x.id
  self:paintGem(v, x)
  v.t, v.sp = x.t, x.sp
  v:SetAlpha(1)
  v:Show()
  return v
end
function G:paintGem(v, x)
  local col = x.t > 0 and M.COLORS[x.t] or { 1, 0.6, 0.2 }
  K.fill(v.bg, col[1] * 0.45, col[2] * 0.45, col[3] * 0.45, 1)
  v.line:SetVertexColor(col[1], col[2], col[3], 0.9)
  v.icon:SetTexture(K.spellTexture(x.sp == 'bomb' and A.SPELLS.rainOfFire.id or A.SPELLS[M.TYPES[x.t]].id))
  v.stripe1:ClearAllPoints(); v.stripe2:ClearAllPoints()
  if x.sp == 'row' then
    v.stripe1:SetPoint('LEFT', 2, 6); v.stripe1:SetPoint('RIGHT', -2, 6); v.stripe1:SetHeight(3)
    v.stripe2:SetPoint('LEFT', 2, -6); v.stripe2:SetPoint('RIGHT', -2, -6); v.stripe2:SetHeight(3)
  elseif x.sp == 'col' then
    v.stripe1:SetPoint('TOP', 6, -2); v.stripe1:SetPoint('BOTTOM', 6, 2); v.stripe1:SetWidth(3)
    v.stripe2:SetPoint('TOP', -6, -2); v.stripe2:SetPoint('BOTTOM', -6, 2); v.stripe2:SetWidth(3)
  end
  v.stripe1:SetShown(x.sp == 'row' or x.sp == 'col'); v.stripe2:SetShown(x.sp == 'row' or x.sp == 'col')
  v.spark:SetShown(x.sp == 'bomb'); v.spark:SetVertexColor(1, 0.8, 0.4, 0.9)
  v.ring:SetShown(x.sp == 'area'); v.ring:SetVertexColor(1, 0.55, 0.2, 1)
end

-- draws a board: every gem moves (with a tween) to its cell; new ones drop in from above, gone ones shrink away
function G:showGrid(grid, made, dur)
  local seen = {}
  for r = 1, M.N do for c = 1, M.N do
    local x = grid[r][c]
    if x then
      seen[x.id] = true
      local v = self.views[x.id]
      local tx, ty = self:cellPos(r, c)
      if not v then
        v = self:gemView(x); self.views[x.id] = v
        -- a special made by a match appears where it was made; the rest drop in from above
        if made and made[x.id] then v.x, v.y = tx, ty; K.tween(v.spark, 0.3, function(f) v:SetAlpha(0.3 + 0.7 * f) end)
        else v.x, v.y = tx, ty + CS * (M.N - r + 1) * 0.6 + 40 end
      end
      if v.t ~= x.t or v.sp ~= x.sp then self:paintGem(v, x); v.t, v.sp = x.t, x.sp end
      local fx, fy = v.x, v.y
      v.x, v.y = tx, ty
      if dur and dur > 0 and (fx ~= tx or fy ~= ty) then
        K.tween(v, dur, function(f) v:SetPoint('CENTER', self.board, 'TOPLEFT', K.lerp(fx, tx, f), K.lerp(fy, ty, f)) end)
      else K.tweens[v] = nil; v:SetPoint('CENTER', self.board, 'TOPLEFT', tx, ty) end
    end
  end end
  for id, v in pairs(self.views) do
    if not seen[id] then
      self.views[id] = nil
      K.tween(v, 0.16, function(f) v:SetAlpha(1 - f); v:SetSize((CS - 6) * (1 + 0.4 * f), (CS - 6) * (1 + 0.4 * f)) end,
        function() v:Hide(); v:SetSize(CS - 6, CS - 6); self.pool[#self.pool + 1] = v end)
    end
  end
end

function G:newGame()
  self.s = M.new(math.random(1, 2000000000))
  self.queue, self.sel_ = {}, nil
  for id, v in pairs(self.views) do v:Hide(); self.pool[#self.pool + 1] = v; self.views[id] = nil end
  self.pop:clear()
  self:showGrid(self.s.grid, nil, 0.3)
  self.msg:SetText('')
  self:refreshSide()
  A.sound('open')
end
function G:Show() self.f:Show(); if not self.s then self:newGame() else self:refreshSide() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:refreshSide()
  local s = self.s
  local name = M.BOSSES[min(s.level, #M.BOSSES)]
  self.bossT:SetText(s.won and 'Molten Core cleared!' or name)
  self.levelT:SetText('Boss ' .. min(s.level, #M.BOSSES) .. ' of ' .. #M.BOSSES)
  local f = s.won and 0 or max(0, 1 - s.damage / s.hp)
  self.hpFill:SetWidth(max(1, 350 * f))
  self.hpT:SetText(s.won and 'Defeated' or (K.num(max(0, s.hp - s.damage)) .. ' / ' .. K.num(s.hp)))
  self.movesT:SetText(tostring(s.moves))
  self.totalT:SetText(K.num(s.total))
  self.bestT:SetText(tostring(self.db.best or 0))
  self.hintBtn:SetEnabled(not s.done)
end

-- input: click one gem then a neighbour, or drag a gem onto a neighbour
function G:cellAt()
  local x, y = GetCursorPosition()
  local sc = self.board:GetEffectiveScale()
  local l, t = self.board:GetLeft(), self.board:GetTop()
  if not l then return nil end
  local c = floor((x / sc - l - 8) / CS) + 1
  local r = floor((t - y / sc - 8) / CS) + 1
  if r < 1 or r > M.N or c < 1 or c > M.N then return nil end
  return { r, c }
end
function G:down() self.press = self:cellAt() end
function G:up()
  local a, b = self.press, self:cellAt()
  self.press = nil
  if not a or self.busy or self.s.done then return end
  if b and (b[1] ~= a[1] or b[2] ~= a[2]) then
    -- a drag: towards the neighbour it points at
    local dr, dc = b[1] - a[1], b[2] - a[2]
    if abs(dr) > abs(dc) then dr, dc = dr > 0 and 1 or -1, 0 else dr, dc = 0, dc > 0 and 1 or -1 end
    self:try(a, { a[1] + dr, a[2] + dc })
    return
  end
  local sel = self.sel_
  if sel and abs(sel[1] - a[1]) + abs(sel[2] - a[2]) == 1 then self:try(sel, a); return end
  if sel and sel[1] == a[1] and sel[2] == a[2] then self.sel_ = nil; self.sel:Hide(); return end
  self.sel_ = a
  local x, y = self:cellPos(a[1], a[2])
  self.sel:ClearAllPoints(); self.sel:SetPoint('CENTER', self.board, 'TOPLEFT', x, y); self.sel:Show()
  A.sound('pop')
end
function G:try(a, b)
  self.sel_ = nil; self.sel:Hide()
  local s = self.s
  local steps, result = M.swap(s, a, b)
  if not steps then
    A.sound('error')
    -- a little nudge both ways to show it does not work
    local x1, y1 = self:cellPos(a[1], a[2])
    local x2, y2 = self:cellPos(b[1], b[2])
    local va, vb = self:viewAt(a), self:viewAt(b)
    if va and vb then
      K.tween(va, 0.25, function(_, raw) local k = math.sin(raw * math.pi) * 0.35; va:SetPoint('CENTER', self.board, 'TOPLEFT', K.lerp(x1, x2, k), K.lerp(y1, y2, k)) end)
      K.tween(vb, 0.25, function(_, raw) local k = math.sin(raw * math.pi) * 0.35; vb:SetPoint('CENTER', self.board, 'TOPLEFT', K.lerp(x2, x1, k), K.lerp(y2, y1, k)) end)
    end
    return
  end
  self.queue = steps
  self.result = result
  self.busy = true
  self.wait = 0
end
function G:viewAt(rc)
  local x = self.s.grid[rc[1]][rc[2]]
  return x and self.views[x.id]
end
function G:hint()
  local a, b = M.findMove(self.s)
  if not a then return end
  for _, rc in ipairs({ a, b }) do
    local v = self:viewAt(rc)
    if v then K.tween(v, 0.8, function(_, raw) v:SetAlpha(0.45 + 0.55 * math.abs(math.cos(raw * math.pi * 3))) end, function() v:SetAlpha(1) end) end
  end
  A.sound('select')
end

-- plays the steps of a swap one after another: the swap, then each clear (damage pops) and fall
function G:OnUpdate(dt)
  self.pop:update(dt)
  if not self.busy then return end
  self.wait = self.wait - dt
  if self.wait > 0 then return end
  local step = table.remove(self.queue, 1)
  if not step then
    self.busy = false
    local s = self.s
    if self.result == 'boss' then
      self.msg:SetText(s.won and 'Ragnaros is down - Molten Core cleared!' or ('Boss down! Next: ' .. M.BOSSES[s.level]))
      self.db.best = max(self.db.best or 0, s.level - 1)
      A.sound(s.won and 'win' or 'levelup')
    elseif self.result == 'over' then
      self.msg:SetText('Out of moves - ' .. K.num(s.total) .. ' damage')
      self.db.best = max(self.db.best or 0, s.level - 1)
      A.sound('lose')
    end
    self:refreshSide()
    return
  end
  if step.swap then self:showGrid(step.grid, nil, 0.15); A.sound('flip'); self.wait = 0.17; return end
  if step.shuffled then self:showGrid(step.grid, nil, 0.3); self.msg:SetText('No moves left - new gems'); self.wait = 0.35; return end
  self:showGrid(step.grid, step.made, 0.2)
  if step.damage > 0 then
    self.pop:show(K.num(step.damage) .. (step.mult > 1 and ('  x' .. K.dec(step.mult, 1)) or ''), BW / 2, BW / 2 + 40 - step.cascade * 4, step.mult > 1 and C.flame or C.gold, 16 + min(10, step.cascade * 2), 0.9)
  end
  if step.moves and step.moves > 0 then self.pop:show('+' .. step.moves .. ' move' .. (step.moves > 1 and 's' or ''), BW / 2, BW / 2 - 10, C.chips, 16, 0.9) end
  A.sound(step.cascade > 1 and 'combo' or 'perfect')
  self.wait = 0.24
  self:refreshSide()
end

function G:OnKey(key)
  if key == 'H' and self.s and not self.s.done then self:hint(); return true end
  return false
end

A.RegisterGame({
  key = 'gems', name = 'Spell Gems', order = 13, ready = true, kind = 'puzzle', icon = A.SPELLS.conflagrate.id,
  tagline = 'Match three spells to cast them. Chain reactions hit harder.',
  bestLine = function() local b = A.db('gems').best; return b and b > 0 and ('Best: ' .. b .. (b == 1 and ' boss' or ' bosses')) or 'Play' end,
  help = {
    '|cffffd040Swap two gems next to each other to line up three or more of a kind.|r Click a gem then its neighbour, or drag it.',
    ' ',
    'Every gem is a spell: three of them cast it once for its real damage (the Forever Warlock Sim\'s standard character). Chain reactions hit harder: x1.5, x2 and so on. |cff4fa3ffLife Tap|r gems give a move for every three.',
    ' ',
    'Four in a row: a gem that clears its whole line. Five: Rain of Fire, which clears every gem of one kind. An L or a T: Hellfire, which clears around it.',
    ' ',
    'Beat each Molten Core boss in ' .. M.MOVES .. ' moves - Ragnaros is the last one. H shows a move.',
  },
  create = function(parent) return G.create(parent) end,
})
