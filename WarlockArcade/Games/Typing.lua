-- Type to Cast: spell names fall towards the ground; type one to cast it. A finished word deals that spell's real
-- damage (the sim's standard character; a damage-over-time spell or a channel only the ticks that land before the
-- 60 s fight ends) and costs its real mana. Life Tap gives mana back, Curse of the Elements adds 10% damage for the
-- rest of the fight. A word that reaches the ground costs a life. Only letters count - spaces type themselves.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local Y = {}
A.TypingRules = Y
Y.FIGHT = 60
Y.LIVES = 3
Y.W, Y.H, Y.GROUND = 620, 470, 34
Y.SPEEDS = { { name = 'Easy', x = 0.75 }, { name = 'Normal', x = 1 }, { name = 'Hard', x = 1.3 } }
Y.WORDS = { 'shadowBolt', 'immolate', 'incinerate', 'searingPain', 'conflagrate', 'shadowburn', 'soulFire', 'hellfire', 'rainOfFire',
  'corruption', 'baneOfAgony', 'siphonLife', 'drainLife', 'drainSoul', 'wrack', 'deathCoil', 'curseOfElements', 'lifeTap' }
Y.CURSE = 0.1                     -- Curse of the Elements: +10% magic damage taken

-- what a spell deals when cast `left` seconds before the fight ends: the sim's standard character, crits at their chance
function Y.damage(key, left)
  local s, c, ch = A.SPELLS[key], A.CAST[key], A.CHARACTER
  local crit = 1 + ch.critPct / 100 * (ch.critMult - 1)
  local direct = c and c.direct or (s.base and (s.base + (s.coef or 0) * ch.sp)) or 0
  local tick = c and c.tick or (s.tickBase and (s.tickBase + (s.tickCoef or 0) * ch.sp)) or 0
  local every = c and c.every or s.tickEvery or 1
  local ticks = c and c.ticks or (s.duration and s.tickEvery and floor(s.duration / s.tickEvery + 0.5)) or 0
  local landed = min(ticks, floor((left or Y.FIGHT) / every))
  return direct * crit + tick * max(0, landed)
end
function Y.letters(name) return (name:upper():gsub('[^%u]', '')) end

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end
function Y.new(speedIndex, seed)
  return { speed = speedIndex, rand = rng(seed or 1), t = 0, nextSpawn = 0.6, words = {}, damage = 0, mana = A.CHARACTER.maxMana,
    lives = Y.LIVES, typed = 0, wrong = 0, cast = 0, combo = 0, maxCombo = 0, curse = false, target = nil, done = false, events = {}, id = 0 }
end
local function event(s, e) s.events[#s.events + 1] = e end
-- a new word at the top, never one whose first letter is already falling (so a first letter always picks one word)
function Y.spawn(s)
  local used = {}
  for _, w in ipairs(s.words) do used[w.letters:sub(1, 1)] = true end
  local pool = {}
  for _, key in ipairs(Y.WORDS) do
    local L = Y.letters(A.SPELLS[key].name)
    if not used[L:sub(1, 1)] and not (key == 'curseOfElements' and s.curse) then pool[#pool + 1] = key end
  end
  if #pool == 0 then return nil end
  -- Life Tap comes more often when mana runs low
  if s.mana < 1200 and not used.L and s.rand() < 0.5 then pool = { 'lifeTap' } end
  local key = pool[floor(s.rand() * #pool) + 1]
  local name = A.SPELLS[key].name
  local width = 34 + #name * 8
  s.id = s.id + 1
  local w = { id = s.id, key = key, name = name, letters = Y.letters(name), pos = 0, x = 12 + s.rand() * (Y.W - width - 24), y = Y.H - 20, width = width }
  s.words[#s.words + 1] = w
  return w
end
-- seconds a word takes to fall, and between new words: both get shorter as the fight goes on
function Y.fallTime(s) return (10 - 4 * min(1, s.t / Y.FIGHT)) / Y.SPEEDS[s.speed].x end
function Y.spawnEvery(s) return (2.4 - 1.2 * min(1, s.t / Y.FIGHT)) / Y.SPEEDS[s.speed].x end

function Y.update(s, dt)
  if s.done then return end
  s.t = s.t + dt
  s.mana = min(A.CHARACTER.maxMana, s.mana + A.CHARACTER.mp5 / 5 * dt)
  s.nextSpawn = s.nextSpawn - dt
  if s.nextSpawn <= 0 then
    if Y.spawn(s) then s.nextSpawn = Y.spawnEvery(s) else s.nextSpawn = 0.3 end
  end
  local v = (Y.H - 20 - Y.GROUND) / Y.fallTime(s)
  for i = #s.words, 1, -1 do
    local w = s.words[i]
    w.y = w.y - v * dt
    if w.y <= Y.GROUND then
      table.remove(s.words, i)
      if s.target == w then s.target = nil end
      s.lives = s.lives - 1
      s.combo = 0
      event(s, { kind = 'ground', x = w.x + w.width / 2, word = w })
      if s.lives <= 0 then s.done = true; event(s, { kind = 'done' }); return end
    end
  end
  if s.t >= Y.FIGHT then s.done = true; event(s, { kind = 'done' }) end
end

-- one letter typed: picks the lowest word starting with it, or goes on with the word being typed
function Y.type(s, letter)
  if s.done then return end
  local w = s.target
  if not w then
    for _, x in ipairs(s.words) do
      if x.letters:sub(1, 1) == letter and (not w or x.y < w.y) then w = x end
    end
    if not w then s.wrong = s.wrong + 1; s.combo = 0; event(s, { kind = 'wrong' }); return end
    s.target = w
  end
  if w.letters:sub(w.pos + 1, w.pos + 1) ~= letter then s.wrong = s.wrong + 1; s.combo = 0; event(s, { kind = 'wrong', word = w }); return end
  w.pos = w.pos + 1
  s.typed = s.typed + 1
  s.combo = s.combo + 1
  s.maxCombo = max(s.maxCombo, s.combo)
  if w.pos >= #w.letters then Y.cast(s, w) else event(s, { kind = 'letter', word = w }) end
end
function Y.cast(s, w)
  for i, x in ipairs(s.words) do if x == w then table.remove(s.words, i); break end end
  s.target = nil
  local cost = A.SPELLS[w.key].cost or 0
  if w.key == 'lifeTap' then
    s.mana = min(A.CHARACTER.maxMana, s.mana + A.CHARACTER.tapMana)
    s.cast = s.cast + 1
    event(s, { kind = 'tap', word = w })
    return
  end
  if s.mana < cost then event(s, { kind = 'oom', word = w }); return end
  s.mana = s.mana - cost
  s.cast = s.cast + 1
  if w.key == 'curseOfElements' then s.curse = true; event(s, { kind = 'curse', word = w }); return end
  local dmg = Y.damage(w.key, Y.FIGHT - s.t) * (s.curse and (1 + Y.CURSE) or 1)
  s.damage = s.damage + dmg
  event(s, { kind = 'hit', word = w, dmg = dmg })
end
-- Escape lets go of the word being typed
function Y.drop(s) if s.target then s.target.pos = 0; s.target = nil end end
function Y.dps(s) return s.damage / Y.FIGHT end
function Y.accuracy(s) local all = s.typed + s.wrong; return all > 0 and 100 * s.typed / all or 100 end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local SW = 290

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('typing')
  g.speedIndex = g.db.speed or 2
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  local board = K.box(f, Y.W, Y.H, { 0.04, 0.03, 0.06 }, C.line, 2)
  board:SetPoint('TOPLEFT', 22, -14)
  board:SetClipsChildren(true)
  self.board = board
  -- the ground: a glow of fire along the bottom
  self.lava = K.rect(board, 'BORDER', { 1, 1, 1 }, 1)
  self.lava:SetPoint('BOTTOMLEFT', 2, 2); self.lava:SetPoint('BOTTOMRIGHT', -2, 2); self.lava:SetHeight(Y.GROUND)
  self.lava:SetGradient('VERTICAL', CreateColor(1, 0.35, 0.08, 0.5), CreateColor(1, 0.3, 0.05, 0))
  self.groundLine = K.rect(board, 'BORDER', C.fire, 0.8, 1)
  self.groundLine:SetPoint('BOTTOMLEFT', 2, Y.GROUND); self.groundLine:SetPoint('BOTTOMRIGHT', -2, Y.GROUND); self.groundLine:SetHeight(1)
  self.layer = CreateFrame('Frame', nil, board)
  self.layer:SetAllPoints()
  self.layer:SetFrameLevel(board:GetFrameLevel() + 2)
  self.top = CreateFrame('Frame', nil, board)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(board:GetFrameLevel() + 40)
  self.pop = K.popups(self.top)
  self.idle = K.text(self.top, 16, C.dim, 'CENTER'); self.idle:SetPoint('CENTER', 0, 20)
  self.idle2 = K.text(self.top, 12, C.faint, 'CENTER'); self.idle2:SetPoint('TOP', self.idle, 'BOTTOM', 0, -8)
  self.views, self.pool = {}, {}
  -- side panel
  local side = K.box(f, SW, Y.H, C.panel, C.line, 1)
  side:SetPoint('TOPLEFT', board, 'TOPRIGHT', 16, 0)
  local function line2(y, label, size, color)
    local a = K.text(side, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', 14, y); a:SetText(label)
    local b = K.text(side, size or 20, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', 14, y - 15)
    return b
  end
  self.dpsT = line2(-14, 'DPS (of a ' .. Y.FIGHT .. ' s fight)', 26, C.gold)
  self.timeT = line2(-70, 'Time left', 18)
  self.manaLabel = K.text(side, 11, C.dim, 'LEFT'); self.manaLabel:SetPoint('TOPLEFT', 14, -118); self.manaLabel:SetText('Mana')
  self.manaBar = K.box(side, SW - 28, 18, { 0.05, 0.04, 0.08 }, C.line, 1)
  self.manaBar:SetPoint('TOPLEFT', 14, -134)
  self.manaFill = K.shape(self.manaBar, 'ARTWORK', 'rr4')
  self.manaFill:SetPoint('TOPLEFT', 1, -1); self.manaFill:SetPoint('BOTTOMLEFT', 1, 1)
  K.fill(self.manaFill, 0.25, 0.5, 1, 1)
  self.manaT = K.text(self.manaBar, 11, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); self.manaT:SetPoint('CENTER')
  self.livesLabel = K.text(side, 11, C.dim, 'LEFT'); self.livesLabel:SetPoint('TOPLEFT', 14, -166); self.livesLabel:SetText('Lives')
  self.lifeDots = {}
  for i = 1, Y.LIVES do
    local d = K.icon(side, 22, A.SPELLS.soulFire.id); d:SetPoint('TOPLEFT', 14 + (i - 1) * 28, -182)
    self.lifeDots[i] = d
  end
  self.accT = line2(-214, 'Accuracy / combo', 15, C.dim)
  self.curseT = K.text(side, 11, C.shadow, 'LEFT'); self.curseT:SetPoint('TOPLEFT', 14, -252)
  self.bestT = line2(-272, 'Best DPS at this speed', 15, C.dim)
  self.speedBtns = {}
  for i, sp in ipairs(Y.SPEEDS) do
    local b = K.button(side, 84, 28, sp.name, function() self.speedIndex = i; self.db.speed = i; self:refreshSide() end, 'normal', 12)
    b:SetPoint('TOPLEFT', 14 + (i - 1) * 90, -322)
    self.speedBtns[i] = b
  end
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 14, -360); note:SetPoint('TOPRIGHT', -12, -360); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Type a falling spell to cast it - its real damage and mana. Life Tap for mana. DoTs only count the ticks before the end.')
  self.start = K.button(side, SW - 28, 40, 'Play', function() self:play() end, 'orange', 16)
  self.start:SetPoint('BOTTOMLEFT', 14, 14)
  self:refreshSide()
end

function G:wordView()
  local v = table.remove(self.pool)
  if not v then
    v = CreateFrame('Frame', nil, self.layer)
    v:SetHeight(26)
    v.bg = K.shape(v, 'BACKGROUND', 'rr6'); v.bg:SetAllPoints()
    v.line = K.shape(v, 'BORDER', 'rl6_1'); v.line:SetAllPoints()
    v.icon = K.icon(v, 18, nil); v.icon:SetPoint('LEFT', 4, 0)
    v.text = K.text(v, 14, C.text, 'LEFT', K.FONT, 'OUTLINE'); v.text:SetPoint('LEFT', 26, 0)
  end
  v:Show()
  return v
end
function G:paintWord(v, w)
  local s = self.s
  -- the typed part of the name in gold (the letters typed; spaces between them go along)
  local name, n, cut = w.name, 0, 0
  for i = 1, #name do
    if n >= w.pos then break end
    if name:sub(i, i):match('%a') then n = n + 1 end
    cut = i
  end
  v.text:SetText(K.paint(C.gold, name:sub(1, cut)) .. name:sub(cut + 1))
  local on = s.target == w
  local low = 1 - (w.y - Y.GROUND) / (Y.H - 20 - Y.GROUND)   -- 0 at the top .. 1 at the ground
  v.bg:SetVertexColor(on and 0.3 or 0.1 + 0.25 * low, on and 0.2 or 0.07, on and 0.45 or 0.14, 0.88)
  v.line:SetVertexColor(on and C.gold[1] or 0.4 + 0.6 * low, on and C.gold[2] or 0.3, on and C.gold[3] or 0.5 - 0.3 * low, on and 1 or 0.6)
end

function G:refreshSide()
  local s = self.s
  self.dpsT:SetText(K.num(s and Y.dps(s) or 0))
  self.timeT:SetText(s and (max(0, floor(Y.FIGHT - s.t + 0.99)) .. ' s') or (Y.FIGHT .. ' s'))
  local mana = s and s.mana or A.CHARACTER.maxMana
  self.manaFill:SetWidth(max(1, (SW - 30) * mana / A.CHARACTER.maxMana))
  self.manaT:SetText(K.num(mana) .. ' / ' .. K.num(A.CHARACTER.maxMana))
  for i, d in ipairs(self.lifeDots) do local on = not s or i <= s.lives; d:SetDesaturated(not on); d:SetAlpha(on and 1 or 0.3) end
  self.accT:SetText(s and (string.format('%.0f%%', Y.accuracy(s)) .. '  /  ' .. s.combo .. ' (best ' .. s.maxCombo .. ')') or '-')
  self.curseT:SetText(s and s.curse and 'Curse of the Elements: +10% damage' or '')
  local best = self.db.best and self.db.best[self.speedIndex]
  self.bestT:SetText(best and (K.num(best) .. ' DPS') or '-')
  local playing = s and not s.done
  for i, b in ipairs(self.speedBtns) do b:SetStyle(i == self.speedIndex and 'gold' or 'normal'); b:SetEnabled(not playing) end
  self.start:SetShown(not playing)
  self.start:SetLabel(s and s.done and 'Play again' or 'Play')
  if playing then self.idle:SetText(''); self.idle2:SetText('')
  elseif not s then self.idle:SetText('Type the spells before they land'); self.idle2:SetText('Press Play or Enter. Escape lets go of a word.') end
end

function G:Show() self.f:Show(); self:refreshSide() end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end
function G:clearViews() for w, v in pairs(self.views) do v:Hide(); self.pool[#self.pool + 1] = v; self.views[w] = nil end end
function G:play()
  self:clearViews()
  self.pop:clear()
  self.s = Y.new(self.speedIndex, math.random(1, 2000000000))
  A.sound('go')
  self:refreshSide()
end
function G:finish()
  local s = self.s
  local dps = Y.dps(s)
  self.db.best = self.db.best or {}
  local isNew = dps > (self.db.best[s.speed] or 0)
  if isNew then self.db.best[s.speed] = dps end
  self:clearViews()
  self.idle:SetText((isNew and 'New best! ' or '') .. K.num(dps) .. ' DPS')
  self.idle2:SetText(s.lives <= 0 and 'Three spells reached the ground' or (s.cast .. ' spells cast, ' .. string.format('%.0f%%', Y.accuracy(s)) .. ' of your keys right'))
  A.sound(s.lives <= 0 and 'lose' or 'win')
  self:refreshSide()
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if not s or s.done then return end
  Y.update(s, dt)
  self:handle()
  if s.done then self:finish(); return end
  local seen = {}
  for _, w in ipairs(s.words) do
    seen[w] = true
    local v = self.views[w]
    if not v then v = self:wordView(); self.views[w] = v; v.icon:SetTexture(K.spellTexture(A.SPELLS[w.key].id)); K.fadeIn(v, 0.2) end
    v:SetWidth(w.width)
    v:SetPoint('BOTTOMLEFT', self.board, 'BOTTOMLEFT', w.x, w.y)
    self:paintWord(v, w)
  end
  for w, v in pairs(self.views) do if not seen[w] then v:Hide(); self.pool[#self.pool + 1] = v; self.views[w] = nil end end
  self.timeT:SetText(max(0, floor(Y.FIGHT - s.t + 0.99)) .. ' s')
  self.manaFill:SetWidth(max(1, (SW - 30) * s.mana / A.CHARACTER.maxMana))
  self.manaT:SetText(K.num(s.mana) .. ' / ' .. K.num(A.CHARACTER.maxMana))
end
function G:handle()
  local s = self.s
  local changed = false
  for _, e in ipairs(s.events) do
    local w = e.word
    local x, y = w and (w.x + w.width / 2) or Y.W / 2, w and (w.y + 30) or 80
    if e.kind == 'hit' then self.pop:show(K.num(e.dmg), x, y, C.gold, 16, 0.8); A.sound('perfect'); changed = true
    elseif e.kind == 'tap' then self.pop:show('+' .. K.num(A.CHARACTER.tapMana) .. ' mana', x, y, C.chips, 15, 0.8); A.sound('coin'); changed = true
    elseif e.kind == 'curse' then self.pop:show('+10% damage', x, y, C.shadow, 15, 0.8); A.sound('combo'); changed = true
    elseif e.kind == 'oom' then self.pop:show('Not enough mana!', x, y, C.bad, 15, 0.9); A.sound('error'); changed = true
    elseif e.kind == 'ground' then self.pop:show('Lost a life', e.x, Y.GROUND + 24, C.bad, 15, 0.9); A.sound('miss'); changed = true
    elseif e.kind == 'wrong' then A.sound('tick'); changed = true
    elseif e.kind == 'letter' then A.sound('hover'); changed = true end
  end
  s.events = {}
  if changed then self:refreshSide() end
end

function G:OnKey(key)
  local s = self.s
  local playing = s and not s.done
  if not playing then
    if key == 'ENTER' then self:play(); return true end
    return false
  end
  if key == 'ESCAPE' then Y.drop(s); return true end
  if #key == 1 and key:match('%a') then Y.type(s, key:upper()); self:handle(); return true end
  if key == 'SPACE' then return true end
  return false
end

A.RegisterGame({
  key = 'typing', name = 'Type to Cast', order = 12, ready = true, kind = 'action', icon = A.SPELLS.searingPain.id,
  tagline = 'Type the falling spells to cast them. Real damage, real mana.',
  bestLine = function() local b = A.db('typing').best; local v = b and (b[3] or b[2] or b[1]); return v and ('Best: ' .. K.num(v) .. ' DPS') or 'Play' end,
  help = {
    '|cffffd040Type a falling spell\'s name to cast it.|r The first letter picks the lowest word starting with it; only letters count, spaces type themselves. Escape lets go of a word.',
    ' ',
    'Every spell deals its real damage for the Forever Warlock Sim\'s standard character and costs its real mana. A damage-over-time spell or a channel only counts the ticks that land before the ' .. Y.FIGHT .. ' s fight ends - type them early.',
    ' ',
    '|cff4fa3ffLife Tap|r gives ' .. A.CHARACTER.tapMana .. ' mana back. |cffb37fffCurse of the Elements|r makes everything after it deal 10% more. Out of mana, a spell fizzles.',
    ' ',
    'A word that reaches the fire on the ground costs a life; three and the fight is over. The words fall faster as the fight goes on.',
  },
  create = function(parent) return G.create(parent) end,
})
