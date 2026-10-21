-- Spell Lock!: four enemy casters cast Warlock spells at you - real cast times, and a cast that finishes hits you for
-- that spell's real damage (the sim's standard character: 4655 health). Your Felhunter's Spell Lock stops a cast, but
-- it needs a moment to come back: choose which cast to stop. The later you stop it, the more points. Survive 75 s;
-- the casters get quicker every 20 s.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local L = {}
A.SpellLockRules = L
L.FIGHT = 75
L.COOLDOWN = 1.0
L.REGEN = 60                      -- health back per second
L.JOIN = { 0, 0, 20, 45 }         -- when each caster joins the fight (s)
L.CASTS = { 'shadowBolt', 'immolate', 'incinerate', 'searingPain', 'soulFire', 'corruption' }
L.NAMES = { 'Cultist', 'Acolyte', 'Necrolyte', 'Firecaller' }

function L.damage(key)
  local s, c, ch = A.SPELLS[key], A.CAST[key], A.CHARACTER
  local crit = 1 + ch.critPct / 100 * (ch.critMult - 1)
  local direct = c and c.direct or (s.base and (s.base + (s.coef or 0) * ch.sp)) or 0
  local dot = c and c.tick and c.tick * c.ticks or 0
  return floor(direct * crit + dot * 0.5)     -- a DoT's first half: the fight goes on without you
end
local function rng(seed)
  local s = seed % 2147483646 + 1
  return function() s = (s * 16807) % 2147483647; return s / 2147483647 end
end
function L.new(seed)
  local s = { rand = rng(seed or 1), t = 0, hp = A.CHARACTER.maxHealth, maxHp = A.CHARACTER.maxHealth, cd = 0, score = 0, locks = 0,
    hits = 0, taken = 0, done = false, won = false, events = {}, foes = {} }
  for i = 1, 4 do s.foes[i] = { wait = L.JOIN[i] + 0.8 + i * 0.4 } end
  return s
end
-- quicker every 15 s: casts down to half their time, shorter pauses
function L.pace(s) return 1 - 0.07 * min(5, floor(s.t / 20)) end
local function startCast(s, f)
  local key = L.CASTS[floor(s.rand() * #L.CASTS) + 1]
  local cast = max(1.5, A.SPELLS[key].cast or 1.5)
  f.key, f.len, f.at = key, cast * L.pace(s), 0
end
function L.update(s, dt)
  if s.done then return end
  s.t = s.t + dt
  s.cd = max(0, s.cd - dt)
  s.hp = min(s.maxHp, s.hp + L.REGEN * dt)
  for i, f in ipairs(s.foes) do
    if f.key then
      f.at = f.at + dt
      if f.at >= f.len then
        local dmg = L.damage(f.key)
        s.hp = s.hp - dmg
        s.taken = s.taken + dmg
        s.hits = s.hits + 1
        s.events[#s.events + 1] = { kind = 'hit', foe = i, dmg = dmg, key = f.key }
        f.key = nil
        f.wait = (1.5 + s.rand() * 2) * L.pace(s)
        if s.hp <= 0 then s.hp = 0; s.done = true; s.events[#s.events + 1] = { kind = 'dead' }; return end
      end
    else
      f.wait = f.wait - dt
      if f.wait <= 0 then startCast(s, f); s.events[#s.events + 1] = { kind = 'start', foe = i } end
    end
  end
  if s.t >= L.FIGHT then s.done, s.won = true, true; s.events[#s.events + 1] = { kind = 'won' } end
end
-- Spell Lock on a caster: stops its cast if Spell Lock is ready; points for how late
function L.lock(s, i)
  if s.done then return nil end
  if s.cd > 0 then return nil, 'Spell Lock is not ready' end
  local f = s.foes[i]
  s.cd = L.COOLDOWN
  if not f.key then s.events[#s.events + 1] = { kind = 'wasted', foe = i }; return false end
  local progress = f.at / f.len
  local points = floor(50 + 100 * progress)
  s.score = s.score + points
  s.locks = s.locks + 1
  s.events[#s.events + 1] = { kind = 'lock', foe = i, points = points, key = f.key }
  f.key = nil
  f.wait = (1.5 + s.rand() * 2) * L.pace(s)
  return points
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local FW, FH = 210, 250

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('spelllock')
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16); self.title:SetText('Spell Lock!')
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('Click a caster (or press 1-4) to Spell Lock it. Stop the casts that hurt most - Spell Lock needs a moment to come back.')
  self.top = CreateFrame('Frame', nil, f)
  self.top:SetAllPoints()
  self.top:SetFrameLevel(f:GetFrameLevel() + 40)
  self.pop = K.popups(self.top)
  self.foes = {}
  for i = 1, 4 do
    local b = K.box(f, FW, FH, C.panel, C.line, 1, 'Button')
    b:SetPoint('TOPLEFT', 30 + (i - 1) * (FW + 16), -84)
    b.glow = K.shape(b, 'BACKGROUND', 'shadow', -7); b.glow:SetPoint('TOPLEFT', -20, 20); b.glow:SetPoint('BOTTOMRIGHT', 20, -20); b.glow:SetAlpha(0)
    b.name = K.text(b, 15, C.text, 'CENTER', K.FONT); b.name:SetPoint('TOP', 0, -14); b.name:SetText(L.NAMES[i])
    b.key = K.text(b, 11, C.faint, 'CENTER', K.FONT_NUM); b.key:SetPoint('TOP', b.name, 'BOTTOM', 0, -4); b.key:SetText('key ' .. i)
    b.icon = K.icon(b, 72, nil); b.icon:SetPoint('TOP', 0, -64)
    b.ring = K.shape(b, 'OVERLAY', 'ring'); b.ring:SetSize(96, 96); b.ring:SetPoint('CENTER', b.icon, 'CENTER')
    b.spell = K.text(b, 13, C.gold, 'CENTER'); b.spell:SetPoint('TOP', b.icon, 'BOTTOM', 0, -14)
    b.dmg = K.text(b, 11, C.dim, 'CENTER'); b.dmg:SetPoint('TOP', b.spell, 'BOTTOM', 0, -4)
    b.bar = K.box(b, FW - 28, 16, { 0.05, 0.04, 0.07 }, C.line, 1)
    b.bar:SetPoint('BOTTOM', 0, 18)
    b.barFill = K.shape(b.bar, 'ARTWORK', 'rr4'); b.barFill:SetPoint('TOPLEFT', 1, -1); b.barFill:SetPoint('BOTTOMLEFT', 1, 1)
    b.barT = K.text(b.bar, 10, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); b.barT:SetPoint('CENTER')
    b.i = i
    b:SetScript('OnMouseDown', function(btn) self:lock(btn.i) end)
    self.foes[i] = b
  end
  -- you: health, Spell Lock, score
  local me = K.box(f, 900, 140, C.panel, C.line, 1)
  me:SetPoint('TOPLEFT', 30, -356)
  self.hpBar = K.box(me, 560, 24, { 0.06, 0.03, 0.04 }, C.line, 1)
  self.hpBar:SetPoint('TOPLEFT', 20, -40)
  self.hpFill = K.shape(self.hpBar, 'ARTWORK', 'rr4'); self.hpFill:SetPoint('TOPLEFT', 1, -1); self.hpFill:SetPoint('BOTTOMLEFT', 1, 1)
  K.fill(self.hpFill, 0.2, 0.75, 0.25, 1)
  self.hpT = K.text(self.hpBar, 12, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); self.hpT:SetPoint('CENTER')
  local hl = K.text(me, 11, C.dim, 'LEFT'); hl:SetPoint('BOTTOMLEFT', self.hpBar, 'TOPLEFT', 0, 6); hl:SetText('Your health (the standard character)')
  self.lockIcon = K.icon(me, 54, A.PETS.felhunter.spell); self.lockIcon:SetPoint('TOPLEFT', 600, -24)
  self.lockShade = K.rect(me, 'OVERLAY', { 0, 0, 0 }, 0.65); self.lockShade:SetPoint('BOTTOMLEFT', self.lockIcon, 'BOTTOMLEFT'); self.lockShade:SetWidth(54)
  self.lockT = K.text(me, 12, C.text, 'LEFT'); self.lockT:SetPoint('LEFT', self.lockIcon, 'RIGHT', 12, 8)
  self.lockT2 = K.text(me, 11, C.dim, 'LEFT'); self.lockT2:SetPoint('TOPLEFT', self.lockT, 'BOTTOMLEFT', 0, -4)
  self.scoreT = K.text(me, 26, C.gold, 'LEFT', K.FONT_NUM); self.scoreT:SetPoint('TOPLEFT', 20, -80)
  self.infoT = K.text(me, 12, C.dim, 'LEFT'); self.infoT:SetPoint('LEFT', self.scoreT, 'RIGHT', 16, 0)
  self.timeT = K.text(me, 20, C.text, 'RIGHT', K.FONT_NUM); self.timeT:SetPoint('TOPRIGHT', -20, -84)
  self.msg = K.text(f, 15, C.gold, 'CENTER'); self.msg:SetPoint('TOP', me, 'BOTTOM', 0, -14)
  self.start = K.button(f, 200, 38, 'Start', function() self:play() end, 'orange', 15)
  self.start:SetPoint('BOTTOM', 0, 18)
end

function G:play()
  self.s = L.new(math.random(1, 2000000000))
  self.pop:clear()
  self.msg:SetText('')
  A.sound('go')
  self:refresh()
end
function G:Show() self.f:Show(); self:refresh() end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end
function G:lock(i)
  local s = self.s
  if not s or s.done then return end
  local r, why = L.lock(s, i)
  if r == nil and why then A.sound('error') end
  self:handle()
end

function G:handle()
  local s = self.s
  for _, e in ipairs(s.events) do
    local b = e.foe and self.foes[e.foe]
    local x = b and (30 + (e.foe - 1) * (FW + 16) + FW / 2) or 480
    if e.kind == 'lock' then
      self.pop:show('Locked! +' .. e.points, x, 606 - 200, C.good, 18, 0.8); A.sound('lock')
      K.tween(b.glow, 0.4, function(f) b.glow:SetVertexColor(0.4, 1, 0.4, 1); b.glow:SetAlpha(0.7 * (1 - f)) end)
    elseif e.kind == 'hit' then
      self.pop:show('-' .. K.num(e.dmg), x, 606 - 200, C.bad, 18, 0.8); A.sound('miss')
      K.tween(b.glow, 0.4, function(f) b.glow:SetVertexColor(1, 0.3, 0.3, 1); b.glow:SetAlpha(0.7 * (1 - f)) end)
    elseif e.kind == 'wasted' then self.pop:show('Nothing to stop', x, 606 - 200, C.dim, 14, 0.7); A.sound('error')
    elseif e.kind == 'dead' or e.kind == 'won' then self:finish() end
  end
  s.events = {}
end
function G:finish()
  local s = self.s
  local isNew = s.score > (self.db.best or 0)
  if isNew then self.db.best = s.score end
  self.msg:SetText(s.won and ((isNew and 'New best! ' or 'You made it! ') .. s.score .. ' points, ' .. s.locks .. ' casts stopped') or ('Down after ' .. floor(s.t) .. ' s - ' .. s.score .. ' points'))
  A.sound(s.won and 'win' or 'lose')
  self:refresh()
end

function G:refresh()
  local s = self.s
  local playing = s and not s.done
  for i, b in ipairs(self.foes) do
    local fo = s and s.foes[i]
    if fo and fo.key and playing then
      local sp = A.SPELLS[fo.key]
      b.icon:SetTexture(K.spellTexture(sp.id)); b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
      b.spell:SetText(sp.name)
      b.dmg:SetText('hits you for ' .. K.num(L.damage(fo.key)))
      local f = fo.at / fo.len
      b.barFill:SetWidth(max(1, (FW - 30) * f))
      K.fill(b.barFill, 1, 0.75 - 0.45 * f, 0.2, 1)
      b.barT:SetText(K.dec(max(0, fo.len - fo.at), 1) .. ' s')
      b.ring:SetVertexColor(1, 0.4 + 0.4 * (1 - f), 0.2, 0.4 + 0.6 * f)
      b.ring:Show()
    else
      b.icon:SetTexture(K.spellTexture(A.SPELLS.shadowBolt.id)); b.icon:SetDesaturated(true); b.icon:SetAlpha(0.35)
      b.spell:SetText(playing and (s.t < L.JOIN[i] and ('joins at ' .. L.JOIN[i] .. ' s') or 'gathering power...') or '')
      b.dmg:SetText('')
      b.barFill:SetWidth(1); b.barT:SetText(''); b.ring:Hide()
    end
  end
  local hp, maxHp = s and s.hp or A.CHARACTER.maxHealth, A.CHARACTER.maxHealth
  self.hpFill:SetWidth(max(1, 558 * hp / maxHp))
  K.fill(self.hpFill, hp / maxHp < 0.3 and 0.85 or 0.2, hp / maxHp < 0.3 and 0.2 or 0.75, 0.25, 1)
  self.hpT:SetText(K.num(hp) .. ' / ' .. K.num(maxHp))
  local cd = s and s.cd or 0
  self.lockShade:SetHeight(max(0.01, 54 * cd / L.COOLDOWN))
  self.lockShade:SetShown(cd > 0)
  self.lockT:SetText(cd > 0 and ('Spell Lock: ' .. K.dec(cd, 1) .. ' s') or 'Spell Lock: ready')
  self.lockT2:SetText('comes back in ' .. K.dec(L.COOLDOWN, 1) .. ' s')
  self.scoreT:SetText((s and s.score or 0) .. ' points')
  self.infoT:SetText(s and (s.locks .. ' stopped, ' .. s.hits .. ' got through' .. '   -   best ' .. (self.db.best or 0)) or ('best ' .. (self.db.best or 0)))
  self.timeT:SetText(s and (max(0, floor(L.FIGHT - s.t + 0.99)) .. ' s left') or (L.FIGHT .. ' s'))
  self.start:SetShown(not playing)
  self.start:SetLabel(s and 'Again' or 'Start')
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  local s = self.s
  if not s or s.done then return end
  L.update(s, dt)
  self:handle()
  self:refresh()
end
function G:OnKey(key)
  local i = tonumber(key)
  if i and i >= 1 and i <= 4 and key == tostring(i) then self:lock(i); return true end
  if (key == 'ENTER' or key == 'SPACE') and not (self.s and not self.s.done) then self:play(); return true end
  return false
end

A.RegisterGame({
  key = 'spelllock', name = 'Spell Lock!', order = 19, ready = true, kind = 'action', icon = A.PETS.felhunter.spell,
  tagline = 'Four casters, one Felhunter. Stop the casts that hurt most.',
  bestLine = function() local b = A.db('spelllock').best; return b and b > 0 and ('Best: ' .. b .. ' points') or 'Play' end,
  help = {
    '|cffffd040Stop the enemy casts with your Felhunter\'s Spell Lock.|r Click a caster or press 1-4.',
    ' ',
    'The casters cast real Warlock spells with their real cast times. A cast that gets through hits you for its real damage (the Forever Warlock Sim\'s standard character, ' .. A.CHARACTER.maxHealth .. ' health); you heal slowly.',
    ' ',
    'Spell Lock comes back after ' .. K.dec(L.COOLDOWN, 1) .. ' s, so pick which cast to stop - a Soul Fire hurts far more than a Searing Pain. The later in the cast you stop it, the more points. Survive ' .. L.FIGHT .. ' s: two casters at first, a third joins at ' .. L.JOIN[3] .. ' s and a fourth at ' .. L.JOIN[4] .. ' s, and they get quicker every 20 s.',
  },
  create = function(parent) return G.create(parent) end,
})
