-- Warlock Ware: micro-games of a few seconds each, one after another, faster and faster. Four lives.
-- The micro-games use the sim's numbers where they have any: the 1.5 s global cooldown, Shadow Bolt's cast time, the
-- 0.4 s spell queue window, DoT durations, which spell is instant / a DoT / Fire, how hard each one hits (A.CAST).
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, random = math.floor, math.min, math.max, math.random

local G = {}
G.__index = G
local SW, SH = 760, 420            -- the stage where a micro-game plays
local LIVES = 4
local SHADOW_TRANCE = 17941

-- each micro-game: title, length in seconds at speed 1, setup(g, m), and update / click / key handlers.
-- m.result = 'win' or 'lose' ends it early; when the time runs out it is a loss unless m.winOnTimeout.
local MICRO = {}
local ORDER = {}
local function micro(def) MICRO[def.key] = def; ORDER[#ORDER + 1] = def.key end

local function iconButton(g, parent, size, spellId)
  local b = K.box(parent, size + 4, size + 4, { 0, 0, 0 }, C.line, 2, 'Button')
  b.icon = K.icon(b, size, spellId); b.icon:SetPoint('CENTER')
  b:SetScript('OnClick', function(btn) if g.m and g.m.def.click then g.m.def.click(g, g.m, btn) end end)
  return b
end

micro({ key = 'tap', title = 'Life Tap!', time = 3,
  setup = function(g, m)
    local pool = { 'shadowBolt', 'corruption', 'immolate', 'baneOfAgony', 'searingPain', 'drainLife', 'deathCoil', 'conflagrate', 'shadowburn', 'soulFire', 'rainOfFire', 'hellfire' }
    K.shuffle(pool)
    local picks = { 'lifeTap', pool[1], pool[2], pool[3], pool[4], pool[5] }
    K.shuffle(picks)
    m.parts = m.parts or {}
    for i = 1, 6 do
      local b = m.parts[i] or iconButton(g, m.f, 64, nil)
      m.parts[i] = b
      b:ClearAllPoints(); b:SetPoint('CENTER', m.f, 'CENTER', (i - 3.5) * 100, -10)
      b.key = picks[i]; b.icon:SetTexture(K.spellTexture(A.SPELLS[picks[i]].id)); b:Show()
    end
    g:say('Out of mana - click Life Tap')
  end,
  click = function(g, m, b) m.result = b.key == 'lifeTap' and 'win' or 'lose' end,
})

micro({ key = 'queue', title = 'Queue it!', time = 4.5, setup = function(g, m)
    m.cast = A.CAST.shadowBolt.cast / g.speed ^ 0.5
    m.window = 0.4
    m.t0 = 0
    if not m.bar then
      m.barBg = K.rect(m.f, 'BORDER', { 0, 0, 0 }, 0.85, 1); m.barBg:SetSize(500, 30); m.barBg:SetPoint('CENTER', 0, -10)
      m.bar = K.rect(m.f, 'ARTWORK', { 1, 0.7, 0.15 }, 1); m.bar:SetPoint('LEFT', m.barBg, 'LEFT'); m.bar:SetHeight(30)
      m.zone = K.rect(m.f, 'ARTWORK', { 0.3, 1, 0.4 }, 0.35, 1); m.zone:SetHeight(30)
      m.label = K.text(m.f, 14, { 1, 1, 1 }, 'CENTER', K.FONT, 'OUTLINE'); m.label:SetPoint('CENTER', m.barBg, 'CENTER')
      m.btn = K.button(m.f, 200, 44, 'Cast the next spell', function() if g.m and g.m.def.key == 'queue' then g.m.def.click(g, g.m) end end, 'blue', 14)
      m.btn:SetPoint('TOP', m.barBg, 'BOTTOM', 0, -30)
    end
    m.zone:ClearAllPoints(); m.zone:SetPoint('RIGHT', m.barBg, 'RIGHT'); m.zone:SetWidth(500 * m.window / m.cast)
    m.label:SetText('Shadow Bolt')
    g:say('Press in the green part (Space or click): the last ' .. K.dec(m.window, 1) .. ' s of the cast')
  end,
  update = function(g, m)
    local f = min(1, m.t / m.cast)
    m.bar:SetWidth(max(1, 500 * f))
    if m.t > m.cast + 0.05 then m.result = 'lose'; g:say('Too late - the cast ended') end
  end,
  click = function(g, m)
    if m.result then return end
    local left = m.cast - m.t
    if left <= m.window and left >= -0.05 then m.result = 'win' else m.result = 'lose'; g:say('Too early') end
  end,
  onKey = function(g, m, key) if key == 'SPACE' or key == 'ENTER' then MICRO.queue.click(g, m); return true end end,
})

micro({ key = 'proc', title = 'Catch the proc!', time = 3.5, setup = function(g, m)
    if not m.btn then m.btn = iconButton(g, m.f, 56, SHADOW_TRANCE) end
    m.btn:Hide()
    m.at = 0.4 + random() * 1.3
    m.life = 1.1 / g.speed ^ 0.6
    g:say('Shadow Trance will flash somewhere - click it')
  end,
  update = function(g, m)
    if not m.shown and m.t >= m.at then
      m.shown = true
      m.btn:ClearAllPoints(); m.btn:SetPoint('CENTER', m.f, 'BOTTOMLEFT', 60 + random() * (SW - 120), 60 + random() * (SH - 150)); m.btn:Show()
    end
    if m.shown and m.t > m.at + m.life and not m.result then m.result = 'lose'; m.btn:Hide(); g:say('It faded') end
  end,
  click = function(g, m) if m.shown then m.result = 'win' end end,
})

micro({ key = 'refresh', title = 'Refresh!', time = 3.5, setup = function(g, m)
    local keys = { 'corruption', 'baneOfAgony', 'immolate' }
    m.parts = m.parts or {}
    local lows = {}
    for i, key in ipairs(keys) do
      local c = A.CAST[key]
      local b = m.parts[i]
      if not b then
        b = iconButton(g, m.f, 64, A.SPELLS[key].id)
        b.secs = K.text(b, 18, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); b.secs:SetPoint('TOP', b, 'BOTTOM', 0, -8)
        m.parts[i] = b
      end
      b:ClearAllPoints(); b:SetPoint('CENTER', m.f, 'CENTER', (i - 2) * 160, 10); b:Show()
      b.key = key
      lows[i] = 1 + random() * (c.duration - 2)
    end
    -- one of them is about to fall off
    local low = random(1, 3)
    lows[low] = 0.9 + random() * 0.6
    for i, b in ipairs(m.parts) do b.left = lows[i]; if i ~= low and b.left < lows[low] + 2 then b.left = lows[low] + 2 + random() * 4 end end
    m.low = m.parts[low]
    g:say('Click the DoT that falls off first')
  end,
  update = function(g, m)
    for _, b in ipairs(m.parts) do
      local left = b.left - m.t
      b.secs:SetText(string.format('%.1f', max(0, left)))
      if b == m.low and left <= 0 and not m.result then m.result = 'lose'; g:say(A.SPELLS[b.key].name .. ' fell off') end
    end
  end,
  click = function(g, m, b) m.result = b == m.low and 'win' or 'lose' end,
})

-- "pick the ..." with the sim's spell data
local QUESTIONS = {
  { text = 'Click the instant spell', ok = function(k) return A.CAST[k].cast == 0 end },
  { text = 'Click the spell with a cast time', ok = function(k) return A.CAST[k].cast > 0 end },
  { text = 'Click the damage over time spell', ok = function(k) return A.CAST[k].tick ~= nil end },
  { text = 'Click the Fire spell', ok = function(k) return A.SPELLS[k].school == 'fire' end },
  { text = 'Click the Shadow spell', ok = function(k) return A.SPELLS[k].school == 'shadow' end },
  { text = 'Click the spell that hits hardest in one cast', best = function(k) local c = A.CAST[k]; return (c.direct or 0) + (c.tick and c.tick * c.ticks or 0) end },
  { text = 'Click the spell that costs the most mana', best = function(k) return A.CAST[k].cost end },
}
micro({ key = 'pick', title = 'Pick it!', time = 4, setup = function(g, m)
    local all = {}
    for k in pairs(A.CAST) do all[#all + 1] = k end
    table.sort(all)
    local q, picks
    for _ = 1, 50 do
      q = QUESTIONS[random(1, #QUESTIONS)]
      K.shuffle(all)
      picks = { all[1], all[2], all[3] }
      local good = 0
      if q.ok then for _, k in ipairs(picks) do if q.ok(k) then good = good + 1 end end
      else
        local vals = {}
        for i, k in ipairs(picks) do vals[i] = q.best(k) end
        table.sort(vals)
        good = vals[3] > vals[2] * 1.05 and 1 or 0
      end
      if good == 1 then break end
    end
    m.q = q
    m.parts = m.parts or {}
    for i = 1, 3 do
      local b = m.parts[i]
      if not b then
        b = iconButton(g, m.f, 64, nil)
        b.name = K.text(m.f, 13, C.text, 'CENTER'); b.name:SetPoint('TOP', b, 'BOTTOM', 0, -8)
        m.parts[i] = b
      end
      b.key = picks[i]
      b.icon:SetTexture(K.spellTexture(A.SPELLS[picks[i]].id)); b.name:SetText(A.SPELLS[picks[i]].name)
      b:ClearAllPoints(); b:SetPoint('CENTER', m.f, 'CENTER', (i - 2) * 170, 10); b:Show()
    end
    if q.best then
      local best, bv
      for _, k in ipairs(picks) do local v = q.best(k); if not bv or v > bv then best, bv = k, v end end
      m.answer = best
    end
    g:say(q.text)
  end,
  click = function(g, m, b)
    local right
    if m.q.ok then right = m.q.ok(b.key) else right = b.key == m.answer end
    m.result = right and 'win' or 'lose'
  end,
})

micro({ key = 'drain', title = 'Drain Soul!', time = 3.5, setup = function(g, m)
    m.need = 6 + floor(g.speed * 2)
    m.hits = 0
    if not m.btn then
      m.btn = iconButton(g, m.f, 110, A.SPELLS.drainSoul.id)
      m.btn:SetPoint('CENTER', 0, 10)
      m.count = K.text(m.f, 22, C.gold, 'CENTER', K.FONT_NUM, 'OUTLINE'); m.count:SetPoint('TOP', m.btn, 'BOTTOM', 0, -12)
    end
    m.btn:Show()
    g:say('Click fast - drain the soul before the time is up')
  end,
  update = function(g, m) m.count:SetText(m.hits .. ' / ' .. m.need) end,
  click = function(g, m) m.hits = m.hits + 1; A.sound('select'); if m.hits >= m.need then m.result = 'win' end end,
})

micro({ key = 'bomb', title = 'Living Bomb!', time = 3, setup = function(g, m)
    if not m.me then
      m.spots = {}
      for i = 1, 3 do
        local s = K.box(m.f, 150, 150, { 0.1, 0.08, 0.13 }, C.line, 1, 'Button')
        s:SetPoint('CENTER', m.f, 'CENTER', (i - 2) * 200, 0)
        s.i = i
        s:SetScript('OnClick', function(btn) if g.m and g.m.def.key == 'bomb' then g.m.def.go(g, g.m, btn.i) end end)
        m.spots[i] = s
      end
      -- the fire and you sit above the spots
      m.top = CreateFrame('Frame', nil, m.f)
      m.top:SetAllPoints()
      m.top:SetFrameLevel(m.spots[1]:GetFrameLevel() + 3)
      m.fire = m.top:CreateTexture(nil, 'ARTWORK'); m.fire:SetTexture(K.MEDIA .. 'circle'); m.fire:SetVertexColor(1, 0.25, 0.1, 0.45); m.fire:SetSize(330, 330)
      m.me = m.top:CreateTexture(nil, 'OVERLAY'); m.me:SetTexture(K.MEDIA .. 'circle'); m.me:SetVertexColor(0.7, 0.4, 1, 1); m.me:SetSize(56, 56)
      m.meText = K.text(m.top, 14, { 1, 1, 1 }, 'CENTER', K.FONT, 'OUTLINE'); m.meText:SetPoint('CENTER', m.me, 'CENTER'); m.meText:SetText('You')
    end
    m.pos = 2
    m.bad = random(1, 2)    -- the bomb covers the middle and one side
    local side = m.bad == 1 and 1 or 3
    m.fire:ClearAllPoints(); m.fire:SetPoint('CENTER', m.f, 'CENTER', (side - 2) * 100, 0)
    m.safe = side == 1 and 3 or 1
    g:place(m)
    m.winOnTimeout = false
    g:say('You are the bomb! Get out of the raid: click the safe spot or press Left / Right')
  end,
  go = function(g, m, i)
    if m.result then return end
    m.pos = i
    g:place(m)
    m.result = i == m.safe and 'win' or 'lose'
  end,
  onKey = function(g, m, key)
    if key == 'LEFT' then MICRO.bomb.go(g, m, max(1, m.pos - 1)); return true end
    if key == 'RIGHT' then MICRO.bomb.go(g, m, min(3, m.pos + 1)); return true end
  end,
})
function G:place(m) m.me:ClearAllPoints(); m.me:SetPoint('CENTER', m.f, 'CENTER', (m.pos - 2) * 200, 0) end

-- ---------------------------------------------------------------------------------------------------------------
function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('ware')
  g.micros = {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.score = K.text(f, 18, C.text, 'LEFT'); self.score:SetPoint('TOPLEFT', 24, -20)
  self.speedText = K.text(f, 13, C.dim, 'LEFT'); self.speedText:SetPoint('TOPLEFT', 24, -46)
  self.lives = {}
  for i = 1, LIVES do
    local t = f:CreateTexture(nil, 'ARTWORK'); t:SetTexture(K.MEDIA .. 'circle'); t:SetSize(22, 22)
    t:SetPoint('TOPRIGHT', -24 - (i - 1) * 28, -22)
    self.lives[i] = t
  end
  self.livesLabel = K.text(f, 11, C.dim, 'RIGHT'); self.livesLabel:SetPoint('TOPRIGHT', -24, -50); self.livesLabel:SetText('Soul shards left')
  self.stage = K.box(f, SW, SH, { 0.08, 0.06, 0.1 }, C.line, 2)
  self.stage:SetPoint('TOP', 0, -96)
  self.fuseBg = K.rect(self.stage, 'BORDER', { 0, 0, 0 }, 0.8, 1); self.fuseBg:SetPoint('TOPLEFT', 2, -2); self.fuseBg:SetPoint('TOPRIGHT', -2, -2); self.fuseBg:SetHeight(8)
  self.fuse = K.rect(self.stage, 'ARTWORK', C.flame, 1); self.fuse:SetPoint('TOPLEFT', self.fuseBg, 'TOPLEFT'); self.fuse:SetHeight(8); self.fuse:SetWidth(1)
  self.big = K.text(self.stage, 44, C.gold, 'CENTER', K.FONT_TITLE, 'OUTLINE'); self.big:SetPoint('CENTER', 0, 40)
  self.line = K.text(f, 15, C.text, 'CENTER'); self.line:SetPoint('TOP', self.stage, 'BOTTOM', 0, -14)
  self.flash = K.rect(self.stage, 'OVERLAY', { 1, 1, 1 }, 0, 3); self.flash:SetPoint('TOPLEFT', 2, -2); self.flash:SetPoint('BOTTOMRIGHT', -2, 2)
  local o = K.box(f, 480, 280, { 0.07, 0.05, 0.1, 0.97 }, C.gold, 2)
  o:SetPoint('CENTER', 0, -10)
  o:SetFrameLevel(f:GetFrameLevel() + 30)
  o:EnableMouse(true)
  o.title = K.text(o, 26, C.gold, 'CENTER', K.FONT_TITLE); o.title:SetPoint('TOP', 0, -18)
  o.body = K.text(o, 14, C.text, 'CENTER'); o.body:SetPoint('TOPLEFT', 24, -64); o.body:SetPoint('TOPRIGHT', -24, -64); o.body:SetWordWrap(true); o.body:SetSpacing(4)
  o.go = K.button(o, 180, 42, 'Start', function() self:start() end, 'orange', 16)
  o.go:SetPoint('BOTTOM', 0, 18)
  self.overlay = o
end

function G:say(t) self.line:SetText(t or '') end

function G:microFrame(key)
  local m = self.micros[key]
  if not m then
    m = { f = CreateFrame('Frame', nil, self.stage), def = MICRO[key] }
    m.f:SetAllPoints()
    m.f:SetFrameLevel(self.stage:GetFrameLevel() + 2)
    self.micros[key] = m
  end
  return m
end

function G:start()
  self.overlay:Hide()
  self.cleared, self.lifeLeft, self.speed = 0, LIVES, 1
  self.bag = {}
  A.sound('open')
  self:nextMicro()
end
function G:pickKey()
  if #self.bag == 0 then for i, k in ipairs(ORDER) do self.bag[i] = k end; K.shuffle(self.bag) end
  return table.remove(self.bag)
end
function G:nextMicro()
  for _, m in pairs(self.micros) do m.f:Hide() end
  local key = self:pickKey()
  local m = self:microFrame(key)
  for _, p in ipairs(m.parts or {}) do p:Hide() end
  m.t, m.result, m.shown, m.winOnTimeout = 0, nil, nil, nil
  self.m = m
  self.phase, self.phaseT = 'ready', 0.85 / self.speed ^ 0.5
  self.big:SetText(m.def.title)
  self.big:Show()
  self:say('')
  self:refresh()
end
function G:refresh()
  self.score:SetText('Cleared: |cffffd040' .. (self.cleared or 0) .. '|r')
  self.speedText:SetText('Speed ' .. K.dec(self.speed or 1, 2) .. 'x   Best: ' .. (self.db.best or 0))
  for i, t in ipairs(self.lives) do
    local on = i <= (self.lifeLeft or LIVES)
    t:SetVertexColor(on and 0.7 or 0.2, on and 0.35 or 0.18, on and 1 or 0.25, 1)
  end
end

function G:Show()
  self.f:Show()
  if not self.phase or self.phase == 'over' then self:showStart() end
  self:refresh()
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:showStart()
  local o = self.overlay
  if self.phase == 'over' then
    local isNew = self.cleared > (self.db.best or 0)
    if isNew then self.db.best = self.cleared end
    o.title:SetText('Out of soul shards')
    o.body:SetText('|cffffd040' .. self.cleared .. ' micro-games cleared|r' .. (isNew and '  |cff60ff60new best!|r' or '') .. '|n|nTop speed: ' .. K.dec(self.speed, 2) .. 'x')
    o.go:SetLabel('Again')
  else
    o.title:SetText('Warlock Ware')
    o.body:SetText('Tiny Warlock challenges, a few seconds each, faster and faster. Read the word, do the thing!|n|nMiss one and you lose a soul shard. ' .. LIVES .. ' shards, then it is over.')
    o.go:SetLabel('Start')
  end
  o:Show()
end

function G:finish(won)
  local m = self.m
  self.phase, self.phaseT = 'result', 0.75 / self.speed ^ 0.5
  self.big:SetText(won and 'Nice!' or 'Oops!')
  self.big:SetTextColor(won and C.good[1] or C.bad[1], won and C.good[2] or C.bad[2], won and C.good[3] or C.bad[3])
  self.big:Show()
  self.flashT = 0.3
  self.flashColor = won and C.good or C.bad
  A.sound(won and 'coin' or 'lose')
  if won then
    self.cleared = self.cleared + 1
    if self.cleared % 4 == 0 then self.speed = self.speed * 1.15; self:say('Faster!') end
  else
    self.lifeLeft = self.lifeLeft - 1
  end
  m.f:Hide()
  self:refresh()
end

function G:OnUpdate(dt)
  if self.flashT then
    self.flashT = self.flashT - dt
    local c = self.flashColor
    self.flash:SetColorTexture(c[1], c[2], c[3], max(0, self.flashT))
    if self.flashT <= 0 then self.flashT = nil end
  end
  if not self.phase or self.phase == 'over' then return end
  self.phaseT = (self.phaseT or 0) - dt
  local m = self.m
  if self.phase == 'ready' then
    if self.phaseT <= 0 then
      self.big:Hide()
      self.big:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
      self.phase = 'play'
      m.limit = m.def.time / self.speed
      m.f:Show()
      m.def.setup(self, m)
    end
  elseif self.phase == 'play' then
    m.t = m.t + dt
    if m.def.update and not m.result then m.def.update(self, m) end
    self.fuse:SetWidth(max(1, (SW - 4) * max(0, 1 - m.t / m.limit)))
    if not m.result and m.t >= m.limit then m.result = m.winOnTimeout and 'win' or 'lose'; if not m.winOnTimeout then self:say('Out of time') end end
    if m.result then self:finish(m.result == 'win') end
  elseif self.phase == 'result' then
    if self.phaseT <= 0 then
      if self.lifeLeft <= 0 then self.phase = 'over'; self:showStart() else self:nextMicro() end
    end
  end
end

function G:OnKey(key)
  if self.overlay:IsShown() then
    if key == 'ENTER' or key == 'SPACE' then self:start(); return true end
    return false
  end
  local m = self.m
  if self.phase == 'play' and m and m.def.onKey and not m.result then return m.def.onKey(self, m, key) and true or false end
  return false
end

G.MICRO, G.ORDER = MICRO, ORDER
A.WareGame = G
A.RegisterGame({
  key = 'ware', name = 'Warlock Ware', order = 5, ready = true, icon = A.SPELLS.lifeTap.id,
  tagline = 'Micro-games of a few seconds each. Life Tap! Spell queue! Catch the proc!',
  bestLine = function() local b = A.db('ware').best; return b and b > 0 and ('Best: ' .. b .. ' cleared') or 'Play' end,
  help = {
    '|cffffd040Tiny challenges, one after another, a few seconds each.|r A word tells you what to do - be quick!',
    ' ',
    'Life Tap! (click the right icon), Queue it! (press in the last 0.4 s of a Shadow Bolt - the spell queue window), Catch the proc! (click Shadow Trance before it fades), Refresh! (click the DoT about to fall off), Pick it! (the instant spell, the DoT, the Fire spell, the hardest hitter...), Drain Soul! (click fast), Living Bomb! (get out of the fire).',
    ' ',
    'Miss one and you lose a soul shard; ' .. LIVES .. ' shards in all. Every 4 cleared, it gets faster.',
  },
  create = function(parent) return G.create(parent) end,
})
