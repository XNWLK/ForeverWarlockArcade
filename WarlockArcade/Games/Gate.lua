-- Demon Gate: the crusade marches on your gate. Build spell towers beside the road: each one is a Warlock spell with its
-- real numbers (the sim's standard character) - Searing Pain and Shadow Bolt hit with their real damage at their real
-- cast times, Corruption and Immolate put their real ticks on the target, Hellfire burns everything close, Curse of the
-- Elements makes the enemies near it take 10% more. Gold for every enemy; upgrade towers (level 2 and 3) or sell them.
-- Fifteen waves, a champion every fifth. An enemy that reaches the gate costs a life; twenty lives.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt

local D = {}
A.GateRules = D
D.COLS, D.ROWS, D.CELL = 15, 11, 40
D.WAVES, D.LIVES, D.GOLD = 15, 20, 260
-- the road, as corners in cells (col, row from the top left, 0-based); enemies come in from the left
D.ROAD = { { -1, 2 }, { 4, 2 }, { 4, 8 }, { 9, 8 }, { 9, 3 }, { 13, 3 }, { 13, 9 }, { 15, 9 } }
D.LEVEL = { 1, 1.5, 2.1 }            -- damage at tower level 1, 2, 3
D.UPCOST = { 0, 0.8, 1.2 }           -- upgrade cost, as a share of the tower's price

local ch = A.CHARACTER
local crit = 1 + ch.critPct / 100 * (ch.critMult - 1)
local function direct(key) local s, c = A.SPELLS[key], A.CAST[key]; return (c and c.direct or (s.base and (s.base + (s.coef or 0) * ch.sp)) or 0) * crit end
local function tick(key) local s, c = A.SPELLS[key], A.CAST[key]; return c and c.tick or (s.tickBase and (s.tickBase + (s.tickCoef or 0) * ch.sp)) or 0 end
D.TOWERS = {
  { key = 'searingPain', cost = 60, range = 2.4, every = A.SPELLS.searingPain.cast, hit = direct('searingPain'), note = 'Quick hits on one enemy' },
  { key = 'shadowBolt', cost = 110, range = 3.4, every = A.SPELLS.shadowBolt.cast, hit = direct('shadowBolt'), note = 'Big hits on one enemy, slow' },
  { key = 'corruption', cost = 90, range = 3, every = 1.5, dot = { tick = tick('corruption'), ticks = 6, every = 3 }, note = 'Puts Corruption on an enemy without it' },
  { key = 'immolate', cost = 100, range = 3, every = 2, hit = direct('immolate'), dot = { tick = tick('immolate'), ticks = 5, every = 3 }, note = 'A hit, then Immolate ticks' },
  { key = 'hellfire', cost = 160, range = 1.6, every = 1, aoe = tick('hellfire'), note = 'Burns every enemy close to it, every second' },
  { key = 'curseOfElements', cost = 120, range = 2.6, curse = 0.1, note = 'Enemies near it take 10% more damage' },
}
D.KINDS = {
  footman = { hp = 1, speed = 52, size = 14, color = { 0.85, 0.82, 0.75 }, name = 'Footman' },
  runner = { hp = 0.55, speed = 92, size = 11, color = { 1, 0.85, 0.35 }, name = 'Runner' },
  knight = { hp = 2.6, speed = 38, size = 17, color = { 0.6, 0.75, 1 }, name = 'Knight' },
  champion = { hp = 14, speed = 30, size = 22, color = { 1, 0.35, 0.3 }, name = 'Champion' },
}

-- the road in pixels: corners, and the length to each one
local function roadPoints()
  local pts, len = {}, { 0 }
  for i, p in ipairs(D.ROAD) do pts[i] = { (p[1] + 0.5) * D.CELL, (p[2] + 0.5) * D.CELL } end
  for i = 2, #pts do len[i] = len[i - 1] + abs(pts[i][1] - pts[i - 1][1]) + abs(pts[i][2] - pts[i - 1][2]) end
  return pts, len
end
D.PTS, D.LEN = roadPoints()
D.TOTAL = D.LEN[#D.LEN]
function D.at(d)
  for i = 2, #D.PTS do
    if d <= D.LEN[i] then
      local f = (d - D.LEN[i - 1]) / max(1, D.LEN[i] - D.LEN[i - 1])
      local a, b = D.PTS[i - 1], D.PTS[i]
      return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
    end
  end
  return D.PTS[#D.PTS][1], D.PTS[#D.PTS][2]
end
-- which cells are road
function D.roadCells()
  if D._road then return D._road end
  local road = {}
  for i = 2, #D.ROAD do
    local a, b = D.ROAD[i - 1], D.ROAD[i]
    local dx, dy = b[1] > a[1] and 1 or b[1] < a[1] and -1 or 0, b[2] > a[2] and 1 or b[2] < a[2] and -1 or 0
    local x, y = a[1], a[2]
    while true do
      road[y * 100 + x] = true
      if x == b[1] and y == b[2] then break end
      x, y = x + dx, y + dy
    end
  end
  D._road = road
  return road
end
function D.waveSize(w) return 8 + 2 * w end
function D.hpBase(w) return floor(380 * 1.27 ^ (w - 1)) end

function D.new()
  return { gold = D.GOLD, lives = D.LIVES, wave = 0, towers = {}, enemies = {}, spawnQueue = {}, t = 0, nextId = 0, running = false,
    done = false, won = false, events = {}, dealt = 0, kills = 0 }
end
function D.towerAt(s, c, r) for _, t in ipairs(s.towers) do if t.c == c and t.r == r then return t end end end
function D.canBuild(s, kind, c, r)
  if c < 0 or c >= D.COLS or r < 0 or r >= D.ROWS then return false, 'Outside the field' end
  if D.roadCells()[r * 100 + c] then return false, 'That is the road' end
  if D.towerAt(s, c, r) then return false, 'A tower stands there' end
  if s.gold < D.TOWERS[kind].cost then return false, 'Not enough gold' end
  return true
end
function D.build(s, kind, c, r)
  local ok, why = D.canBuild(s, kind, c, r)
  if not ok then return nil, why end
  s.gold = s.gold - D.TOWERS[kind].cost
  s.nextId = s.nextId + 1
  local t = { id = s.nextId, kind = kind, c = c, r = r, level = 1, spent = D.TOWERS[kind].cost, cd = 0 }
  s.towers[#s.towers + 1] = t
  return t
end
function D.upgradeCost(t) return t.level < 3 and floor(D.TOWERS[t.kind].cost * D.UPCOST[t.level + 1]) or nil end
function D.upgrade(s, t)
  local cost = D.upgradeCost(t)
  if not cost then return nil, 'Already at level 3' end
  if s.gold < cost then return nil, 'Not enough gold' end
  s.gold = s.gold - cost
  t.spent = t.spent + cost
  t.level = t.level + 1
  return true
end
function D.sell(s, t)
  for i, x in ipairs(s.towers) do if x == t then table.remove(s.towers, i); break end end
  local back = floor(t.spent * 0.6)
  s.gold = s.gold + back
  return back
end
-- a wave: footmen, with runners and knights mixed in later, a champion every fifth wave
function D.startWave(s)
  if s.running or s.done or s.wave >= D.WAVES then return false end
  s.wave = s.wave + 1
  s.running = true
  local w = s.wave
  local q = {}
  for i = 1, D.waveSize(w) do
    local kind = 'footman'
    if w >= 3 and i % 3 == 0 then kind = 'runner' end
    if w >= 5 and i % 5 == 0 then kind = 'knight' end
    q[#q + 1] = { kind = kind, at = (i - 1) * 0.75 }
  end
  if w % 5 == 0 then q[#q + 1] = { kind = 'champion', at = D.waveSize(w) * 0.75 + 1 } end
  s.spawnQueue, s.waveT = q, 0
  s.events[#s.events + 1] = { kind = 'wave' }
  return true
end
local function spawn(s, kind)
  local k = D.KINDS[kind]
  s.nextId = s.nextId + 1
  local hp = D.hpBase(s.wave) * k.hp
  s.enemies[#s.enemies + 1] = { id = s.nextId, kind = kind, d = 0, hp = hp, max = hp, dots = {} }
end
local function curseOn(s, e)
  local best = 0
  local x, y = D.at(e.d)
  for _, t in ipairs(s.towers) do
    local T = D.TOWERS[t.kind]
    if T.curse then
      local tx, ty = (t.c + 0.5) * D.CELL, (t.r + 0.5) * D.CELL
      if (tx - x) ^ 2 + (ty - y) ^ 2 <= (T.range * D.CELL) ^ 2 then best = max(best, T.curse * D.LEVEL[t.level]) end
    end
  end
  return 1 + best
end
local function hurt(s, e, amount)
  local dmg = amount * curseOn(s, e)
  e.hp = e.hp - dmg
  s.dealt = s.dealt + dmg
  return dmg
end
function D.update(s, dt)
  if s.done then return end
  s.t = s.t + dt
  if s.running then
    s.waveT = s.waveT + dt
    while s.spawnQueue[1] and s.spawnQueue[1].at <= s.waveT do spawn(s, table.remove(s.spawnQueue, 1).kind) end
  end
  -- the enemies walk; DoTs tick
  for i = #s.enemies, 1, -1 do
    local e = s.enemies[i]
    e.d = e.d + D.KINDS[e.kind].speed * dt
    for key, dot in pairs(e.dots) do
      dot.next = dot.next - dt
      if dot.next <= 0 then
        hurt(s, e, dot.tick); dot.left = dot.left - 1; dot.next = dot.next + dot.every
        if dot.left <= 0 then e.dots[key] = nil end
      end
    end
    if e.d >= D.TOTAL then
      table.remove(s.enemies, i)
      s.lives = s.lives - (e.kind == 'champion' and 5 or 1)
      s.events[#s.events + 1] = { kind = 'leak' }
      if s.lives <= 0 then s.lives = 0; s.done = true; s.events[#s.events + 1] = { kind = 'lost' }; return end
    end
  end
  -- the towers
  for _, t in ipairs(s.towers) do
    local T = D.TOWERS[t.kind]
    if not T.curse then
      t.cd = t.cd - dt
      if t.cd <= 0 then
        local tx, ty = (t.c + 0.5) * D.CELL, (t.r + 0.5) * D.CELL
        local r2 = (T.range * D.CELL) ^ 2
        local lv = D.LEVEL[t.level]
        if T.aoe then
          local any = false
          for _, e in ipairs(s.enemies) do
            local x, y = D.at(e.d)
            if (tx - x) ^ 2 + (ty - y) ^ 2 <= r2 then hurt(s, e, T.aoe * lv); any = true end
          end
          if any then t.cd = T.every; s.events[#s.events + 1] = { kind = 'burn', tower = t } end
        else
          -- the enemy furthest along the road in range (for a DoT tower: one without that DoT)
          local target
          for _, e in ipairs(s.enemies) do
            local x, y = D.at(e.d)
            if (tx - x) ^ 2 + (ty - y) ^ 2 <= r2 and not (T.dot and e.dots[T.key]) and (not target or e.d > target.d) then target = e end
          end
          if target then
            t.cd = T.every
            local dmg = T.hit and hurt(s, target, T.hit * lv) or 0
            if T.dot then target.dots[T.key] = { tick = T.dot.tick * lv, left = T.dot.ticks, every = T.dot.every, next = T.dot.every } end
            s.events[#s.events + 1] = { kind = 'shot', tower = t, target = target, dmg = dmg }
          end
        end
      end
    end
  end
  -- the dead
  for i = #s.enemies, 1, -1 do
    local e = s.enemies[i]
    if e.hp <= 0 then
      table.remove(s.enemies, i)
      local bounty = (e.kind == 'champion' and 60 or 6) + s.wave
      s.gold = s.gold + bounty
      s.kills = s.kills + 1
      s.events[#s.events + 1] = { kind = 'kill', enemy = e, gold = bounty }
    end
  end
  if s.running and #s.spawnQueue == 0 and #s.enemies == 0 then
    s.running = false
    local bonus = 30 + 5 * s.wave
    s.gold = s.gold + bonus
    s.events[#s.events + 1] = { kind = 'waveDone', gold = bonus }
    if s.wave >= D.WAVES then s.done, s.won = true, true; s.events[#s.events + 1] = { kind = 'won' } end
  end
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local BX, BY = 22, -14
local BW, BH = D.COLS * D.CELL, D.ROWS * D.CELL

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('gate')
  g.pick = 1
  g.speed = 1
  g.tviews, g.eviews, g.bolts = {}, {}, {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, BW + 16, BH + 16, { 0.05, 0.06, 0.045 }, C.line, 2, 'Button')
  board:SetPoint('TOPLEFT', BX, BY)
  board:SetClipsChildren(true)
  board:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  board:SetScript('OnClick', function(_, button) self:click(button) end)
  self.board = board
  -- the field: faint cells, the road
  local road = D.roadCells()
  for r = 0, D.ROWS - 1 do for c = 0, D.COLS - 1 do
    local t
    if road[r * 100 + c] then
      t = K.shape(board, 'BORDER', 'rr4'); K.fill(t, 0.32, 0.24, 0.17, 1)
    elseif (r + c) % 2 == 0 then t = K.rect(board, 'BORDER', { 1, 1, 1 }, 0.025) end
    if t then t:SetSize(D.CELL - 2, D.CELL - 2); t:SetPoint('TOPLEFT', 9 + c * D.CELL, -9 - r * D.CELL) end
  end end
  -- the gate at the end of the road
  self.gate = K.shape(board, 'ARTWORK', 'glow'); self.gate:SetSize(90, 90); self.gate:SetPoint('CENTER', board, 'TOPLEFT', 8 + D.PTS[#D.PTS][1] - 14, -8 - D.PTS[#D.PTS][2])
  self.gate:SetVertexColor(0.7, 0.35, 1, 0.8)
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.range = K.shape(self.layer, 'OVERLAY', 'ring', 2); self.range:Hide()
  self.rangeFill = K.shape(self.layer, 'BACKGROUND', 'circle', -2); self.rangeFill:Hide()
  self.hover = K.shape(self.layer, 'OVERLAY', 'rl6_2', 3); self.hover:SetSize(D.CELL - 2, D.CELL - 2); self.hover:Hide()
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 40)
  self.pop = K.popups(self.top)
  self.banner = K.text(self.top, 20, C.gold, 'CENTER', K.FONT_TITLE, 'OUTLINE'); self.banner:SetPoint('TOP', 0, -14)
  -- the side
  local side = K.box(f, 300, BH + 16, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 14, 0)
  self.side = side
  self.goldT = K.text(side, 22, C.gold, 'LEFT', K.FONT_NUM); self.goldT:SetPoint('TOPLEFT', 14, -12)
  self.livesT = K.text(side, 16, C.bad, 'LEFT', K.FONT_NUM); self.livesT:SetPoint('TOPLEFT', 150, -16)
  self.waveT = K.text(side, 12, C.dim, 'LEFT'); self.waveT:SetPoint('TOPLEFT', 14, -42)
  self.waveBtn = K.button(side, 180, 32, 'Start wave 1', function() self:nextWave() end, 'orange', 13)
  self.waveBtn:SetPoint('TOPLEFT', 14, -62)
  self.speedBtn = K.button(side, 84, 32, 'Speed x1', function() self.speed = self.speed == 1 and 2 or 1; self:refresh() end, 'normal', 12)
  self.speedBtn:SetPoint('TOPRIGHT', -14, -62)
  -- the towers to build
  self.pickBtns = {}
  for i, T in ipairs(D.TOWERS) do
    local b = K.box(side, 132, 52, C.panel2, C.line, 1, 'Button')
    b:SetPoint('TOPLEFT', 14 + ((i - 1) % 2) * 140, -104 - floor((i - 1) / 2) * 58)
    b.icon = K.icon(b, 34, A.SPELLS[T.key].id); b.icon:SetPoint('LEFT', 8, 0)
    b.name = K.text(b, 11, C.text, 'LEFT'); b.name:SetPoint('TOPLEFT', 48, -9); b.name:SetText((A.SPELLS[T.key].name:gsub('Curse of the Elements', 'Curse of El.')))
    b.cost = K.text(b, 11, C.gold, 'LEFT', K.FONT_NUM); b.cost:SetPoint('TOPLEFT', 48, -26); b.cost:SetText(T.cost .. ' gold')
    b.hl = K.shape(b, 'HIGHLIGHT', 'rr6'); b.hl:SetAllPoints(); b.hl:SetVertexColor(1, 1, 1, 0.07)
    b.i = i
    b:SetScript('OnClick', function(btn) self.pick = btn.i; self.sel = nil; A.sound('select'); self:refresh() end)
    b:SetScript('OnEnter', function(btn) K.showTip(btn, self:towerTip(btn.i)) end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    self.pickBtns[i] = b
  end
  -- the chosen tower
  self.info = K.text(side, 12, C.text, 'LEFT'); self.info:SetPoint('TOPLEFT', 14, -286); self.info:SetPoint('TOPRIGHT', -14, -286); self.info:SetWordWrap(true); self.info:SetSpacing(2)
  self.upBtn = K.button(side, 132, 32, 'Upgrade', function() self:upgrade() end, 'blue', 12)
  self.upBtn:SetPoint('BOTTOMLEFT', 14, 62)
  self.sellBtn = K.button(side, 132, 32, 'Sell', function() self:sell() end, 'red', 12)
  self.sellBtn:SetPoint('BOTTOMRIGHT', -14, 62)
  self.newBtn = K.button(side, 272, 36, 'New game', function() self:newGame() end, 'normal', 13)
  self.newBtn:SetPoint('BOTTOM', 0, 16)
end

function G:towerTip(i)
  local T = D.TOWERS[i]
  local lines = { { A.SPELLS[T.key].name .. ' tower - ' .. T.cost .. ' gold', { 1, 1, 1 } }, { T.note, C.gold } }
  if T.hit then lines[#lines + 1] = { K.num(T.hit) .. ' damage every ' .. K.dec(T.every, 1) .. ' s (the spell\'s real damage and cast time)', C.text } end
  if T.dot then lines[#lines + 1] = { T.dot.ticks .. ' ticks of ' .. K.num(T.dot.tick) .. ', one every ' .. T.dot.every .. ' s', C.text } end
  if T.aoe then lines[#lines + 1] = { K.num(T.aoe) .. ' damage a second to all close by (Hellfire\'s real tick)', C.text } end
  if T.curse then lines[#lines + 1] = { '+10% damage taken (level 2: 15%, level 3: 21%)', C.text } end
  lines[#lines + 1] = { 'Range ' .. K.dec(T.range, 1) .. ' squares. Levels 2 and 3: x1.5 and x2.1.', C.dim }
  return lines
end
function G:newGame()
  self.s = D.new()
  self.sel = nil
  for _, v in pairs(self.tviews) do v:Hide() end
  for id, v in pairs(self.eviews) do v:Hide(); self.eviews[id] = nil end
  self.tviews = {}
  self.pop:clear()
  self.banner:SetText('Build towers beside the road, then start the wave')
  self:refresh()
end
function G:Show() self.f:Show(); if not self.s then self:newGame() else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:cellUnderCursor()
  local x, y = GetCursorPosition()
  local sc = self.board:GetEffectiveScale()
  local l, t = self.board:GetLeft(), self.board:GetTop()
  if not l then return nil end
  return floor((x / sc - l - 8) / D.CELL), floor((t - y / sc - 8) / D.CELL)
end
function G:click(button)
  local s = self.s
  if s.done then return end
  local c, r = self:cellUnderCursor()
  if not c then return end
  local t = D.towerAt(s, c, r)
  if t then
    if button == 'RightButton' then self.sel = t; self:sell(); return end
    self.sel = t; A.sound('select'); self:refresh(); return
  end
  local built, why = D.build(s, self.pick, c, r)
  if built then self.sel = built; A.sound('place'); K.fadeIn(self:towerView(built), 0.2)
  else self.banner:SetText(why); A.sound('error') end
  self:refresh()
end
function G:upgrade()
  local t = self.sel
  if not t then return end
  local ok, why = D.upgrade(self.s, t)
  if ok then A.sound('levelup') else self.banner:SetText(why); A.sound('error') end
  self:refresh()
end
function G:sell()
  local t = self.sel
  if not t then return end
  local back = D.sell(self.s, t)
  local v = self.tviews[t]
  if v then v:Hide(); self.tviews[t] = nil end
  self.sel = nil
  self.pop:show('+' .. back .. ' gold', 8 + (t.c + 0.5) * D.CELL, BH + 8 - (t.r + 0.5) * D.CELL, C.gold, 14, 0.8)
  A.sound('coin')
  self:refresh()
end
function G:nextWave()
  if D.startWave(self.s) then self.banner:SetText(''); A.sound('go') end
  self:refresh()
end

function G:towerView(t)
  local v = self.tviews[t]
  if not v then
    v = CreateFrame('Frame', nil, self.layer)
    v:SetSize(D.CELL - 4, D.CELL - 4)
    v:SetFrameLevel(self.layer:GetFrameLevel() + 3)
    v.glow = K.shape(v, 'BACKGROUND', 'glow'); v.glow:SetSize(D.CELL * 2, D.CELL * 2); v.glow:SetPoint('CENTER'); v.glow:SetVertexColor(1, 0.5, 0.15, 0)
    v.bg = K.shape(v, 'BORDER', 'rr6'); v.bg:SetAllPoints(); K.fill(v.bg, 0.16, 0.12, 0.22, 1)
    v.icon = v:CreateTexture(nil, 'ARTWORK'); v.icon:SetPoint('TOPLEFT', 3, -3); v.icon:SetPoint('BOTTOMRIGHT', -3, 3); v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v.line = K.shape(v, 'OVERLAY', 'rl6_1'); v.line:SetAllPoints()
    v.pips = {}
    for i = 1, 3 do local p = K.shape(v, 'OVERLAY', 'circle', 1); p:SetSize(6, 6); p:SetPoint('BOTTOMLEFT', 3 + (i - 1) * 8, 3); v.pips[i] = p end
    self.tviews[t] = v
  end
  v.icon:SetTexture(K.spellTexture(A.SPELLS[D.TOWERS[t.kind].key].id))
  v:ClearAllPoints(); v:SetPoint('TOPLEFT', self.board, 'TOPLEFT', 10 + t.c * D.CELL, -10 - t.r * D.CELL)
  for i, p in ipairs(v.pips) do if i <= t.level then p:SetVertexColor(1, 0.85, 0.3, 1) else p:SetVertexColor(0.2, 0.18, 0.25, 1) end end
  v.line:SetVertexColor(self.sel == t and C.gold[1] or 0.5, self.sel == t and C.gold[2] or 0.4, self.sel == t and C.gold[3] or 0.65, 1)
  v:Show()
  return v
end
function G:enemyView(e)
  local v = self.eviews[e.id]
  if not v then
    local k = D.KINDS[e.kind]
    v = CreateFrame('Frame', nil, self.layer)
    v:SetSize(k.size * 2, k.size * 2)
    v:SetFrameLevel(self.layer:GetFrameLevel() + 8)
    v.body = K.shape(v, 'ARTWORK', 'circle'); v.body:SetAllPoints(); v.body:SetVertexColor(k.color[1], k.color[2], k.color[3], 1)
    v.rim = K.shape(v, 'OVERLAY', 'ring'); v.rim:SetAllPoints(); v.rim:SetVertexColor(0, 0, 0, 0.6)
    v.hpBg = K.rect(v, 'OVERLAY', { 0, 0, 0 }, 0.7, 1); v.hpBg:SetSize(k.size * 2, 4); v.hpBg:SetPoint('BOTTOM', v, 'TOP', 0, 3)
    v.hp = K.rect(v, 'OVERLAY', { 0.3, 1, 0.3 }, 1, 2); v.hp:SetHeight(4); v.hp:SetPoint('LEFT', v.hpBg, 'LEFT')
    v.dot = K.shape(v, 'OVERLAY', 'glow', 3); v.dot:SetAllPoints(); v.dot:SetVertexColor(0.5, 1, 0.3, 0)
    v.w = k.size * 2
    self.eviews[e.id] = v
  end
  return v
end
function G:bolt(t, e)
  local b = table.remove(self.bolts) or K.shape(self.layer, 'OVERLAY', 'glow', 4)
  local col = ({ searingPain = { 1, 0.55, 0.2 }, shadowBolt = { 0.75, 0.45, 1 }, corruption = { 0.5, 1, 0.35 }, immolate = { 1, 0.45, 0.15 } })[D.TOWERS[t.kind].key] or { 1, 1, 1 }
  b:SetVertexColor(col[1], col[2], col[3], 1)
  b:SetSize(18, 18)
  b:Show()
  local fx, fy = 8 + (t.c + 0.5) * D.CELL, -8 - (t.r + 0.5) * D.CELL
  local ex, ey = D.at(e.d)
  ex, ey = 8 + ex, -8 - ey
  K.tween(b, 0.15, function(f) b:ClearAllPoints(); b:SetPoint('CENTER', self.board, 'TOPLEFT', K.lerp(fx, ex, f), K.lerp(fy, ey, f)) end,
    function() b:Hide(); self.bolts[#self.bolts + 1] = b end)
end

function G:refresh()
  local s = self.s
  self.goldT:SetText(s.gold .. ' gold')
  self.livesT:SetText(s.lives .. ' lives')
  self.waveT:SetText(s.won and ('All ' .. D.WAVES .. ' waves held!') or ('Wave ' .. s.wave .. ' of ' .. D.WAVES .. (s.running and ' - coming' or '')) .. '   Best: wave ' .. (self.db.best or 0))
  self.waveBtn:SetEnabled(not s.running and not s.done)
  self.waveBtn:SetLabel(s.done and (s.won and 'You held the gate!' or 'The gate fell') or ('Start wave ' .. min(D.WAVES, s.wave + 1)))
  self.speedBtn:SetLabel('Speed x' .. self.speed)
  for i, b in ipairs(self.pickBtns) do
    local can = s.gold >= D.TOWERS[i].cost
    b:SetBorderColor(i == self.pick and C.gold[1] or C.line[1], i == self.pick and C.gold[2] or C.line[2], i == self.pick and C.gold[3] or C.line[3], 1)
    b.icon:SetDesaturated(not can); b.cost:SetTextColor(can and C.gold[1] or C.bad[1], can and C.gold[2] or C.bad[2], can and C.gold[3] or C.bad[3])
  end
  for _, t in ipairs(s.towers) do self:towerView(t) end
  local t = self.sel
  local T = t and D.TOWERS[t.kind] or D.TOWERS[self.pick]
  if t then
    local up = D.upgradeCost(t)
    self.info:SetText(A.SPELLS[T.key].name .. ' tower, level ' .. t.level .. '\n' .. T.note .. '\nUpgrade: ' .. (up and (up .. ' gold') or 'top level') .. '   Sell: ' .. floor(t.spent * 0.6) .. ' gold')
    self.upBtn:SetEnabled(up ~= nil and s.gold >= up); self.sellBtn:SetEnabled(true)
    local x, y = 8 + (t.c + 0.5) * D.CELL, -8 - (t.r + 0.5) * D.CELL
    local rr = T.range * D.CELL * 2
    self.range:SetSize(rr, rr); self.range:ClearAllPoints(); self.range:SetPoint('CENTER', self.board, 'TOPLEFT', x, y); self.range:SetVertexColor(1, 0.85, 0.4, 0.6); self.range:Show()
    self.rangeFill:SetSize(rr, rr); self.rangeFill:ClearAllPoints(); self.rangeFill:SetPoint('CENTER', self.board, 'TOPLEFT', x, y); self.rangeFill:SetVertexColor(1, 0.85, 0.4, 0.07); self.rangeFill:Show()
  else
    self.info:SetText('Building: ' .. A.SPELLS[T.key].name .. ' tower (' .. T.cost .. ' gold)\n' .. T.note .. '\nClick an empty square beside the road. Click a tower to choose it; right-click sells.')
    self.upBtn:SetEnabled(false); self.sellBtn:SetEnabled(false)
    self.range:Hide(); self.rangeFill:Hide()
  end
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if not s then return end
  -- the square under the mouse
  local c, r = self:cellUnderCursor()
  if c and c >= 0 and c < D.COLS and r >= 0 and r < D.ROWS and not s.done and self.board:IsMouseOver() then
    local ok = D.towerAt(s, c, r) or D.canBuild(s, self.pick, c, r)
    self.hover:ClearAllPoints(); self.hover:SetPoint('TOPLEFT', self.board, 'TOPLEFT', 9 + c * D.CELL, -9 - r * D.CELL)
    self.hover:SetVertexColor(ok and 0.6 or 1, ok and 1 or 0.3, ok and 0.5 or 0.3, 0.8); self.hover:Show()
  else self.hover:Hide() end
  if s.done then return end
  local step = dt * self.speed
  D.update(s, step)
  local changed = false
  for _, e in ipairs(s.events) do
    if e.kind == 'shot' then self:bolt(e.tower, e.target)
    elseif e.kind == 'burn' then local v = self.tviews[e.tower]; if v then K.tween(v.glow, 0.6, function(f) v.glow:SetVertexColor(1, 0.5, 0.15, 0.8 * (1 - f)) end) end
    elseif e.kind == 'kill' then
      local x, y = D.at(e.enemy.d)
      self.pop:show('+' .. e.gold, 8 + x, BH + 8 - y, C.gold, 12, 0.6); changed = true
      if e.enemy.kind == 'champion' then A.sound('crit') end
    elseif e.kind == 'leak' then A.sound('miss'); changed = true
    elseif e.kind == 'waveDone' then self.banner:SetText('Wave ' .. s.wave .. ' held!  +' .. e.gold .. ' gold'); A.sound('levelup'); changed = true
    elseif e.kind == 'wave' then changed = true
    elseif e.kind == 'won' or e.kind == 'lost' then
      self.db.best = max(self.db.best or 0, s.won and D.WAVES or s.wave - 1)
      self.banner:SetText(s.won and 'The gate held! All fifteen waves' or ('The gate fell in wave ' .. s.wave))
      A.sound(s.won and 'win' or 'lose'); changed = true
    end
  end
  s.events = {}
  -- draw the enemies
  local seen = {}
  for _, e in ipairs(s.enemies) do
    seen[e.id] = true
    local v = self:enemyView(e)
    local x, y = D.at(e.d)
    v:ClearAllPoints(); v:SetPoint('CENTER', self.board, 'TOPLEFT', 8 + x, -8 - y)
    local f = max(0, e.hp / e.max)
    v.hp:SetWidth(max(1, v.w * f)); v.hp:SetColorTexture(1 - f, 0.3 + 0.7 * f, 0.3, 1)
    local dotted = next(e.dots) ~= nil
    v.dot:SetVertexColor(0.5, 1, 0.3, dotted and 0.35 or 0)
    v:Show()
  end
  for id, v in pairs(self.eviews) do if not seen[id] then v:Hide(); self.eviews[id] = nil end end
  self.tick = (self.tick or 0) + dt
  if changed or self.tick > 0.3 then self.tick = 0; self:refresh() end
end
function G:OnKey(key)
  local i = tonumber(key)
  if i and D.TOWERS[i] and key == tostring(i) then self.pick = i; self.sel = nil; self:refresh(); return true end
  if key == 'SPACE' or key == 'ENTER' then self:nextWave(); return true end
  if key == 'U' then self:upgrade(); return true end
  if key == 'ESCAPE' and self.sel then self.sel = nil; self:refresh(); return true end
  return false
end

A.RegisterGame({
  key = 'gate', name = 'Demon Gate', order = 26, ready = true, kind = 'action', icon = A.TALENTS.demonicPact.spell,
  tagline = 'Spell towers on the road to your gate. Fifteen waves.',
  bestLine = function() local b = A.db('gate').best; return b and b > 0 and ('Best: wave ' .. b) or 'Play' end,
  help = {
    '|cffffd040Hold the gate for fifteen waves.|r Pick a tower (or press 1-6) and click an empty square beside the road. Space or Enter starts the next wave.',
    ' ',
    'Every tower is a Warlock spell with its real numbers (the Forever Warlock Sim\'s standard character): Searing Pain and Shadow Bolt hit with their real damage at their real cast times, Corruption and Immolate put their real ticks on the enemy, Hellfire burns all close by, Curse of the Elements makes enemies near it take more damage.',
    ' ',
    'Gold for every enemy and every wave held. Click a tower to choose it: Upgrade (U) makes it hit x1.5 and x2.1; Sell (right-click) gives 60% back. An enemy at the gate costs a life, a champion five.',
  },
  create = function(parent) return G.create(parent) end,
})
