-- DoT Juggler: training dummies keep arriving; keep Corruption, Bane of Agony and Immolate ticking on as many as you
-- can for 90 seconds. Everything is the sim's standard character with no talents (Data.lua A.CAST / A.CHARACTER):
-- cast times, the 1.5 s global cooldown, mana costs, damage per tick, Life Tap's mana. Refreshing a DoT restarts it
-- (the ticks left are lost, "clipped"), like the game. Score = damage done, shown as DPS.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local J = {}            -- the rules (no drawing)
A.JugglerRules = J
J.LENGTH = 90
J.SPELLS = { 'corruption', 'baneOfAgony', 'immolate' }
J.QUEUE = 0.4           -- the spell queue window: a press this close to the end of a cast or the GCD waits for it
J.SLOT_OPEN = { 0, 0, 6, 18, 32, 50 }   -- when each of the six dummy places opens
J.RESPAWN = 2.5
function J.dummyHealth(n) return 2500 + 600 * n end

function J.new(seed)
  if seed then math.randomseed(seed) end
  local ch = A.CHARACTER
  local s = { t = 0, over = false, mana = ch.maxMana, health = ch.maxHealth, gcdEnd = 0, damage = 0, spawned = 0, kills = 0,
    clipped = 0, fell = 0, casts = 0, taps = 0, dummies = {}, events = {}, dotTime = 0 }
  for i = 1, 6 do s.dummies[i] = { slot = i, at = J.SLOT_OPEN[i] } end
  return s
end
local function event(s, e) s.events[#s.events + 1] = e end
local function spawn(s, d)
  s.spawned = s.spawned + 1
  d.alive, d.hp, d.maxHp, d.dots, d.n = true, J.dummyHealth(s.spawned), J.dummyHealth(s.spawned), {}, s.spawned
  event(s, { kind = 'spawn', slot = d.slot })
end
local function hurt(s, d, amount, kind)
  if not d.alive then return end
  local dealt = min(d.hp, amount)
  d.hp = d.hp - dealt
  s.damage = s.damage + dealt
  if d.hp <= 0 then
    d.alive, d.dots, d.at = false, {}, s.t + J.RESPAWN
    s.kills = s.kills + 1
    event(s, { kind = 'kill', slot = d.slot })
  end
end
function J.ready(s) return not s.casting and s.t >= s.gcdEnd end
function J.busyLeft(s) return max(s.gcdEnd - s.t, s.casting and (s.casting.ends - s.t) or 0) end

-- start a spell on a dummy place (lifeTap needs none). Returns true, 'queued' or nil + reason.
function J.cast(s, key, slot)
  if s.over then return nil, 'The round is over' end
  local spell = A.CAST[key]
  if key ~= 'lifeTap' then
    local d = s.dummies[slot]
    if not d or not d.alive then return nil, 'No target there' end
    if s.mana < spell.cost then return nil, 'Not enough mana - Life Tap!' end
  elseif s.health <= A.CHARACTER.tapHealth then return nil, 'Not enough health to Life Tap' end
  if not J.ready(s) then
    if J.busyLeft(s) <= J.QUEUE then s.queued = { key = key, slot = slot }; return 'queued' end
    return nil, 'Not ready yet'
  end
  s.queued = nil
  s.casts = s.casts + 1
  s.gcdEnd = s.t + A.CHARACTER.gcd
  if key == 'lifeTap' then
    s.health = s.health - A.CHARACTER.tapHealth
    s.mana = min(A.CHARACTER.maxMana, s.mana + A.CHARACTER.tapMana)
    s.taps = s.taps + 1
    event(s, { kind = 'tap' })
    return true
  end
  if spell.cast > 0 then
    s.casting = { key = key, slot = slot, start = s.t, ends = s.t + spell.cast, dummy = s.dummies[slot].n }
    s.gcdEnd = max(s.gcdEnd, s.t + spell.cast)
  else J.land(s, key, slot) end
  return true
end
-- the spell lands: mana is paid, the DoT (re)starts
function J.land(s, key, slot)
  local spell, d = A.CAST[key], s.dummies[slot]
  s.mana = s.mana - spell.cost
  local old = d.dots[key]
  if old and old.left > 0 then
    s.clipped = s.clipped + old.left
    event(s, { kind = 'clip', slot = slot, key = key, ticks = old.left })
  end
  d.dots[key] = { next = s.t + spell.every, ends = s.t + spell.duration, left = spell.ticks, start = s.t }
  event(s, { kind = 'land', slot = slot, key = key })
  if spell.direct then
    local crit = math.random() * 100 < A.CHARACTER.critPct
    local dmg = floor(spell.direct * (crit and A.CHARACTER.critMult or 1) + 0.5)
    event(s, { kind = 'hit', slot = slot, key = key, amount = dmg, crit = crit })
    hurt(s, d, dmg)
  end
end

function J.update(s, dt)
  if s.over then return end
  local stepTo = min(s.t + dt, J.LENGTH)
  -- move in small steps so ticks, casts and the end come in the right order
  while s.t < stepTo - 1e-9 do
    local t = min(stepTo, s.t + 0.05)
    s.mana = min(A.CHARACTER.maxMana, s.mana + A.CHARACTER.mp5 / 5 * (t - s.t))
    local up = 0
    for _, d in ipairs(s.dummies) do
      if d.alive then
        for key, dot in pairs(d.dots) do
          up = up + 1
          while dot.left > 0 and dot.next <= t do
            dot.left = dot.left - 1
            event(s, { kind = 'tick', slot = d.slot, key = key, amount = A.CAST[key].tick })
            hurt(s, d, A.CAST[key].tick)
            if not d.alive then break end
            dot.next = dot.next + A.CAST[key].every
          end
          if d.alive and dot.left <= 0 then d.dots[key] = nil; s.fell = s.fell + 1; event(s, { kind = 'fell', slot = d.slot, key = key }) end
        end
      elseif d.at and t >= d.at and t < J.LENGTH - 3 then spawn(s, d) end
    end
    s.dotTime = s.dotTime + up * (t - s.t)
    s.t = t
    local c = s.casting
    if c and s.t >= c.ends then
      s.casting = nil
      local d = s.dummies[c.slot]
      if d.alive and d.n == c.dummy then J.land(s, c.key, c.slot) else event(s, { kind = 'fizzle', slot = c.slot }) end
    end
    if s.queued and J.ready(s) then local q = s.queued; s.queued = nil; J.cast(s, q.key, q.slot) end
  end
  if s.t >= J.LENGTH - 1e-9 then s.over = true; s.casting = nil; event(s, { kind = 'over' }) end
end
function J.dps(s) return s.t > 0 and s.damage / s.t or 0 end
function J.dotsUp(s) local n = 0; for _, d in ipairs(s.dummies) do if d.alive then for _ in pairs(d.dots) do n = n + 1 end end end; return n end

-- ---------------------------------------------------------------------------------------------------------------
-- the screen
local G = {}
G.__index = G
local PW, PH = 296, 196
local KEYS = { corruption = '1', baneOfAgony = '2', immolate = '3', lifeTap = '4' }
local COLORS = { corruption = { 0.45, 0.85, 0.3 }, baneOfAgony = { 0.7, 0.45, 1 }, immolate = { 1, 0.45, 0.15 } }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('juggler')
  g:build()
  g.pop = K.popups(g.f)
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  -- top strip
  local top = K.box(f, 944, 52, C.panel, C.line, 1)
  top:SetPoint('TOPLEFT', 8, -8)
  self.stats = {}
  local labels = { 'Time left', 'Damage', 'DPS', 'DoTs ticking', 'Clipped ticks', 'Fell off' }
  for i, l in ipairs(labels) do
    local x = 12 + (i - 1) * 155
    local a = K.text(top, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', x, -7); a:SetText(l)
    local b = K.text(top, 20, i == 3 and C.gold or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', x, -22)
    self.stats[i] = b
  end
  -- the six dummy places
  self.panels = {}
  for i = 1, 6 do
    local col, row = (i - 1) % 3, floor((i - 1) / 3)
    local p = K.box(f, PW, PH, C.panel, C.line, 1, 'Button')
    p:SetPoint('TOPLEFT', 16 + col * (PW + 16), -72 - row * (PH + 12))
    p:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    p.slot = i
    p.name = K.text(p, 13, C.text, 'LEFT'); p.name:SetPoint('TOPLEFT', 10, -8)
    p.hpText = K.text(p, 12, C.dim, 'RIGHT', K.FONT_NUM); p.hpText:SetPoint('TOPRIGHT', -10, -9)
    p.hpBg = K.rect(p, 'BORDER', { 0.15, 0.04, 0.04 }, 1, 1); p.hpBg:SetPoint('TOPLEFT', 10, -28); p.hpBg:SetPoint('TOPRIGHT', -10, -28); p.hpBg:SetHeight(10)
    p.hp = K.rect(p, 'ARTWORK', { 0.75, 0.15, 0.12 }, 1); p.hp:SetPoint('TOPLEFT', p.hpBg, 'TOPLEFT'); p.hp:SetHeight(10); p.hp:SetWidth(1)
    p.wait = K.text(p, 14, C.faint, 'CENTER'); p.wait:SetPoint('CENTER', 0, 0)
    p.flash = K.rect(p, 'OVERLAY', { 1, 1, 1 }, 0, 2); p.flash:SetAllPoints()
    p.dots = {}
    for j, key in ipairs(J.SPELLS) do
      local b = K.box(p, 76, 116, { 0.06, 0.045, 0.08 }, C.line, 1, 'Button')
      b:SetPoint('TOPLEFT', 14 + (j - 1) * 92, -48)
      b:SetFrameLevel(p:GetFrameLevel() + 2)
      b.key, b.slot = key, i
      b.icon = K.icon(b, 52, A.SPELLS[key].id); b.icon:SetPoint('TOP', 0, -6)
      b.veil = K.rect(b, 'OVERLAY', { 0, 0, 0 }, 0.65, 1); b.veil:SetPoint('TOPLEFT', b.icon, 'TOPLEFT'); b.veil:SetPoint('BOTTOMRIGHT', b.icon, 'BOTTOMRIGHT')
      b.key1 = K.text(b, 11, C.dim, 'RIGHT', K.FONT_NUM, 'OUTLINE'); b.key1:SetPoint('TOPRIGHT', b.icon, 'TOPRIGHT', -2, -2); b.key1:SetText(KEYS[key])
      b.barBg = K.rect(b, 'BORDER', { 0, 0, 0 }, 0.8, 1); b.barBg:SetPoint('TOPLEFT', 6, -64); b.barBg:SetPoint('TOPRIGHT', -6, -64); b.barBg:SetHeight(8)
      local c = COLORS[key]
      b.bar = K.rect(b, 'ARTWORK', c, 1); b.bar:SetPoint('TOPLEFT', b.barBg, 'TOPLEFT'); b.bar:SetHeight(8); b.bar:SetWidth(1)
      b.secs = K.text(b, 15, C.text, 'CENTER', K.FONT_NUM); b.secs:SetPoint('TOP', 0, -76)
      b.label = K.text(b, 9, C.dim, 'CENTER'); b.label:SetPoint('BOTTOM', 0, 5)
      b.label:SetText(A.SPELLS[key].name)
      b:SetScript('OnClick', function(btn) self:castOn(btn.key, btn.slot) end)
      b:SetScript('OnEnter', function(btn) self.hover = btn.slot; self:spellTip(btn, btn.key) end)
      b:SetScript('OnLeave', function() self.hover = nil; GameTooltip:Hide() end)
      p.dots[j] = b
    end
    p:SetScript('OnEnter', function(b) self.hover = b.slot end)
    p:SetScript('OnLeave', function() self.hover = nil end)
    p:SetScript('OnClick', function(b) self.target = b.slot; A.sound('select') end)
    self.panels[i] = p
  end
  -- the player: mana, health, cast bar, the four buttons
  local me = K.box(f, 944, 92, C.panel, C.line, 1)
  me:SetPoint('BOTTOMLEFT', 8, 8)
  self.me = me
  local function bar(y, color, label)
    local bg = K.rect(me, 'BORDER', { 0, 0, 0 }, 0.8, 1); bg:SetPoint('TOPLEFT', 12, y); bg:SetSize(330, 16)
    local fill = K.rect(me, 'ARTWORK', color, 1); fill:SetPoint('TOPLEFT', bg, 'TOPLEFT'); fill:SetHeight(16); fill:SetWidth(1)
    local t = K.text(me, 11, { 1, 1, 1 }, 'CENTER', K.FONT_NUM, 'OUTLINE'); t:SetPoint('CENTER', bg, 'CENTER')
    return { bg = bg, fill = fill, text = t, label = label }
  end
  self.manaBar = bar(-14, { 0.15, 0.35, 0.9 }, 'Mana')
  self.healthBar = bar(-36, { 0.15, 0.65, 0.2 }, 'Health')
  self.castBg = K.rect(me, 'BORDER', { 0, 0, 0 }, 0.8, 1); self.castBg:SetPoint('TOPLEFT', 12, -60); self.castBg:SetSize(330, 18)
  self.castFill = K.rect(me, 'ARTWORK', { 1, 0.7, 0.15 }, 1); self.castFill:SetPoint('TOPLEFT', self.castBg, 'TOPLEFT'); self.castFill:SetHeight(18); self.castFill:SetWidth(1)
  self.castText = K.text(me, 11, { 1, 1, 1 }, 'CENTER', K.FONT, 'OUTLINE'); self.castText:SetPoint('CENTER', self.castBg, 'CENTER')
  self.buttons = {}
  local keys = { 'corruption', 'baneOfAgony', 'immolate', 'lifeTap' }
  for i, key in ipairs(keys) do
    local b = K.box(me, 60, 60, { 0, 0, 0 }, C.line, 1, 'Button')
    b:SetPoint('TOPLEFT', 370 + (i - 1) * 70, -16)
    b.key = key
    b.icon = K.icon(b, 56, A.SPELLS[key].id); b.icon:SetPoint('CENTER')
    b.veil = K.rect(b, 'OVERLAY', { 0, 0, 0 }, 0.6, 1); b.veil:SetPoint('BOTTOMLEFT', 2, 2); b.veil:SetPoint('BOTTOMRIGHT', -2, 2); b.veil:SetHeight(1)
    b.key1 = K.text(b, 13, { 1, 1, 1 }, 'RIGHT', K.FONT_NUM, 'OUTLINE'); b.key1:SetPoint('TOPRIGHT', -4, -3); b.key1:SetText(KEYS[key])
    b:SetScript('OnClick', function(btn) if btn.key == 'lifeTap' then self:castOn('lifeTap') else self:castOn(btn.key, self.target) end end)
    b:SetScript('OnEnter', function(btn) self:spellTip(btn, btn.key) end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    self.buttons[i] = b
  end
  self.hint = K.text(me, 12, C.dim, 'LEFT')
  self.hint:SetPoint('TOPLEFT', 660, -16); self.hint:SetPoint('TOPRIGHT', -12, -16)
  self.hint:SetWordWrap(true); self.hint:SetJustifyV('TOP')
  self.hint:SetText('Click a DoT on a dummy to cast it there. Or point at a dummy and press 1, 2, 3. 4 = Life Tap.')
  self.msg = K.text(f, 15, C.bad, 'CENTER')
  self.msg:SetPoint('BOTTOM', f, 'BOTTOM', 0, 108)
  -- start / results
  local o = K.box(f, 520, 330, { 0.07, 0.05, 0.1, 0.97 }, C.gold, 2)
  o:SetPoint('CENTER', 0, 20)
  o:SetFrameLevel(f:GetFrameLevel() + 30)
  o:EnableMouse(true)
  o.title = K.text(o, 24, C.gold, 'CENTER', K.FONT_TITLE); o.title:SetPoint('TOP', 0, -16)
  o.body = K.text(o, 13, C.text, 'CENTER'); o.body:SetPoint('TOPLEFT', 24, -56); o.body:SetPoint('TOPRIGHT', -24, -56)
  o.body:SetWordWrap(true); o.body:SetJustifyV('TOP'); o.body:SetSpacing(4)
  o.go = K.button(o, 200, 42, 'Start', function() self:start() end, 'orange', 16)
  o.go:SetPoint('BOTTOM', 0, 18)
  self.overlay = o
end

function G:spellTip(owner, key)
  local c, sp = A.CAST[key], A.SPELLS[key]
  local lines = { { sp.name, { 1, 1, 1 } } }
  if key == 'lifeTap' then
    lines[#lines + 1] = { 'Instant. +' .. A.CHARACTER.tapMana .. ' mana for ' .. A.CHARACTER.tapHealth .. ' health.', { 1, 1, 1 } }
  else
    lines[#lines + 1] = { (c.cast > 0 and (K.dec(c.cast, 1) .. ' s cast') or 'Instant') .. ', ' .. c.cost .. ' mana', { 1, 1, 1 } }
    lines[#lines + 1] = { K.dec(c.tick, 1) .. ' damage every ' .. c.every .. ' s for ' .. c.duration .. ' s (' .. K.num(c.tick * c.ticks) .. ' in all)' ..
      (c.direct and (', plus ' .. c.direct .. ' when it lands') or ''), { 1, 1, 1 } }
  end
  if sp.text then lines[#lines + 1] = { 'In WoW: ' .. sp.text, C.gold } end
  K.showTip(owner, lines, 'ANCHOR_TOP')
end

function G:Show()
  self.f:Show()
  if not self.s or self.s.over then self:showStart() end
  self:draw()
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end
function G:OnPause() if self.s and not self.s.over then self.paused = true end end

function G:showStart()
  local o = self.overlay
  local best = self.db.best
  o.title:SetText(self.s and self.s.over and 'Time!' or 'DoT Juggler')
  if self.s and self.s.over then
    local s = self.s
    local dps = J.dps(s)
    local isBest = s.wasBest
    if not s.recorded then
      s.recorded = true
      isBest = not best or dps > best
      s.wasBest = isBest
      if isBest then self.db.best = dps end
      self.db.plays = (self.db.plays or 0) + 1
    end
    o.body:SetText('|cffffd040' .. K.num(dps) .. ' DPS|r' .. (isBest and '  |cff60ff60new best!|r' or '') .. '|n|n' ..
      K.num(s.damage) .. ' damage in ' .. J.LENGTH .. ' seconds, ' .. s.kills .. ' dummies destroyed.|n' ..
      'DoTs ticking on average: ' .. K.dec(s.dotTime / J.LENGTH, 1) .. '|n' ..
      'Ticks lost to clipping: ' .. s.clipped .. ' - DoTs that fell off: ' .. s.fell .. '|n' ..
      'Casts: ' .. s.casts .. ', Life Taps: ' .. s.taps ..
      (best and not isBest and ('|n|n|cff9a8ab0Your best: ' .. K.num(best) .. ' DPS|r') or ''))
    o.go:SetLabel('Again')
  else
    o.body:SetText('Training dummies keep arriving - up to six at once. Keep |cff73d94cCorruption|r, |cffb373ffBane of Agony|r and |cffff7326Immolate|r ticking on as many as you can for ' .. J.LENGTH .. ' seconds.|n|n' ..
      'Real numbers: cast times, the 1.5 s global cooldown, mana, damage per tick and Life Tap are the Forever Warlock Sim\'s standard character. Refreshing a DoT early restarts it and loses the ticks it had left.' ..
      (best and ('|n|n|cff9a8ab0Your best: ' .. K.num(best) .. ' DPS|r') or ''))
    o.go:SetLabel('Start')
  end
  o:Show()
end

function G:start()
  self.s = J.new()
  self.paused = false
  self.target = 1
  self.overlay:Hide()
  self.pop:clear()
  self.msg:SetText('')
  A.sound('open')
  self:draw()
end

function G:castOn(key, slot)
  local s = self.s
  if not s or s.over or self.paused then return end
  if key ~= 'lifeTap' and not slot then self:say('Point at a dummy (or click one) first'); return end
  local ok, why = J.cast(s, key, slot)
  if not ok then self:say(why); return end
  if slot then self.target = slot end
  A.sound(ok == 'queued' and 'select' or 'click')
  self.msg:SetText('')
end
function G:say(t) self.msg:SetText(t); self.msgUntil = GetTime() + 1.5 end

function G:panelPoint(slot, ox, oy)
  local col, row = (slot - 1) % 3, floor((slot - 1) / 3)
  return 16 + col * (PW + 16) + (ox or PW / 2), self.f:GetHeight() - 72 - row * (PH + 12) - (oy or 0)
end

function G:handleEvents()
  local s = self.s
  for _, e in ipairs(s.events) do
    if e.kind == 'tick' or e.kind == 'hit' then
      local j = e.key == 'corruption' and 1 or e.key == 'baneOfAgony' and 2 or 3
      local x, y = self:panelPoint(e.slot, 14 + (j - 1) * 92 + 38, 40)
      local c = e.crit and C.flame or COLORS[e.key]
      self.pop:show((e.crit and 'Crit ' or '') .. K.num(e.amount), x, y, c, e.crit and 18 or 14, 0.8)
    elseif e.kind == 'kill' then
      local x, y = self:panelPoint(e.slot, nil, PH / 2)
      self.pop:show('Destroyed!', x, y, C.gold, 22, 1.2)
      self.panels[e.slot].flashT = 0.4
      A.sound('coin')
    elseif e.kind == 'fell' then
      local x, y = self:panelPoint(e.slot, nil, 20)
      self.pop:show(A.SPELLS[e.key].name .. ' fell off', x, y - 150, C.bad, 13, 1.1)
    elseif e.kind == 'clip' then
      local x, y = self:panelPoint(e.slot, nil, 20)
      self.pop:show('Clipped ' .. e.ticks .. (e.ticks == 1 and ' tick' or ' ticks'), x, y - 150, C.dim, 13, 1.1)
    elseif e.kind == 'spawn' then
      self.panels[e.slot].flashT = 0.25
    elseif e.kind == 'fizzle' then
      self:say('The target died before your cast landed')
    elseif e.kind == 'over' then
      A.sound('win')
      self:showStart()
    end
  end
  s.events = {}
end

function G:draw()
  local s = self.s
  local st = self.stats
  if not s then
    st[1]:SetText(J.LENGTH .. ' s'); for i = 2, 6 do st[i]:SetText('-') end
  else
    st[1]:SetText(string.format('%.1f s', max(0, J.LENGTH - s.t)))
    st[2]:SetText(K.num(s.damage)); st[3]:SetText(K.num(J.dps(s)))
    st[4]:SetText(J.dotsUp(s)); st[5]:SetText(s.clipped); st[6]:SetText(s.fell)
  end
  for i, p in ipairs(self.panels) do
    local d = s and s.dummies[i]
    local alive = d and d.alive
    p.name:SetText(alive and ('Training Dummy ' .. d.n) or '')
    p.hpText:SetText(alive and (K.num(d.hp) .. ' / ' .. K.num(d.maxHp)) or '')
    p.hpBg:SetShown(alive and true or false); p.hp:SetShown(alive and true or false)
    if alive then p.hp:SetWidth(max(1, (PW - 20) * d.hp / d.maxHp)) end
    if not s then p.wait:SetText('')
    elseif not alive then
      local at = d.at or 0
      p.wait:SetText(at > s.t and string.format('A dummy arrives in %.1f s', at - s.t) or (s.over and '' or 'Destroyed'))
    else p.wait:SetText('') end
    local sel = s and self.target == i and alive
    local hov = s and self.hover == i and alive
    local bc = sel and C.gold or hov and { 0.8, 0.75, 0.9 } or C.line
    p:SetBorderColor(bc[1], bc[2], bc[3], 1)
    for j, b in ipairs(p.dots) do
      b:SetShown(alive and true or false)
      if alive then
        local dot = d.dots[b.key]
        local c = A.CAST[b.key]
        if dot then
          local left = max(0, dot.ends - s.t)
          b.bar:SetWidth(max(1, 64 * left / c.duration)); b.bar:Show()
          b.secs:SetText(string.format('%.1f', left))
          local low = left <= c.every
          b.secs:SetTextColor(low and 1 or 0.95, low and 0.4 or 0.92, low and 0.3 or 0.86)
          b.veil:Hide()
        else
          b.bar:Hide(); b.secs:SetText('-'); b.secs:SetTextColor(C.faint[1], C.faint[2], C.faint[3]); b.veil:Show()
        end
        local casting = s.casting and s.casting.slot == i and s.casting.key == b.key
        b:SetBorderColor(casting and 1 or C.line[1], casting and 0.8 or C.line[2], casting and 0.2 or C.line[3], 1)
      end
    end
    if p.flashT then p.flash:SetColorTexture(1, 1, 1, max(0, p.flashT)) end
  end
  -- player
  local ch = A.CHARACTER
  local mana, health = s and s.mana or ch.maxMana, s and s.health or ch.maxHealth
  self.manaBar.fill:SetWidth(max(1, 330 * mana / ch.maxMana)); self.manaBar.text:SetText('Mana ' .. K.num(mana) .. ' / ' .. K.num(ch.maxMana))
  self.healthBar.fill:SetWidth(max(1, 330 * health / ch.maxHealth)); self.healthBar.text:SetText('Health ' .. K.num(health) .. ' / ' .. K.num(ch.maxHealth))
  local c = s and s.casting
  if c then
    local f = (s.t - c.start) / (c.ends - c.start)
    self.castFill:SetWidth(max(1, 330 * f)); self.castFill:Show()
    self.castText:SetText(A.SPELLS[c.key].name .. string.format('  %.1f', max(0, c.ends - s.t)))
  else
    self.castFill:Hide()
    self.castText:SetText(s and s.queued and ('Queued: ' .. A.SPELLS[s.queued.key].name) or '')
  end
  local gcdLeft = s and J.busyLeft(s) or 0
  for _, b in ipairs(self.buttons) do
    local h = gcdLeft > 0 and 56 * min(1, gcdLeft / ch.gcd) or 0
    b.veil:SetHeight(max(1, h)); b.veil:SetShown(h > 0)
    local cost = b.key == 'lifeTap' and 0 or A.CAST[b.key].cost
    b.icon:SetDesaturated(s ~= nil and (b.key == 'lifeTap' and health <= ch.tapHealth or mana < cost))
  end
  if self.msgUntil and GetTime() > self.msgUntil then self.msg:SetText(''); self.msgUntil = nil end
end

function G:OnUpdate(dt)
  self.pop:update(dt)
  for _, p in ipairs(self.panels) do if p.flashT then p.flashT = p.flashT - dt * 2; if p.flashT <= 0 then p.flashT = nil; p.flash:SetColorTexture(1, 1, 1, 0) end end end
  local s = self.s
  if s and not s.over then
    if self.paused then self.paused = false end
    J.update(s, dt)
    self:handleEvents()
  end
  self:draw()
end

function G:OnKey(key)
  if self.overlay:IsShown() then
    if key == 'ENTER' or key == 'SPACE' then self:start(); return true end
    return false
  end
  local map = { ['1'] = 'corruption', ['2'] = 'baneOfAgony', ['3'] = 'immolate', ['4'] = 'lifeTap' }
  local spell = map[key]
  if spell then self:castOn(spell, spell ~= 'lifeTap' and (self.hover or self.target) or nil); return true end
  return false
end

A.RegisterGame({
  key = 'juggler', name = 'DoT Juggler', order = 2, ready = true, icon = A.SPELLS.corruption.id,
  tagline = 'Keep your DoTs ticking on every dummy - refresh each one before it falls off.',
  bestLine = function() local b = A.db('juggler').best; return b and ('Best: ' .. K.num(b) .. ' DPS') or 'Play' end,
  help = {
    '|cffffd040Keep as many DoTs ticking as you can for ' .. J.LENGTH .. ' seconds.|r Training dummies keep arriving, up to six. When one is destroyed, a new one takes its place.',
    ' ',
    'Click a DoT on a dummy to cast it there. Or point at a dummy (or click it) and press 1 Corruption, 2 Bane of Agony, 3 Immolate. 4 is Life Tap.',
    ' ',
    'Casting takes real time: Corruption and Immolate have a 2 s cast, Bane of Agony is instant, and every spell starts the 1.5 s global cooldown. A key pressed in the last 0.4 s of a cast waits for it (the spell queue).',
    ' ',
    'Refreshing a DoT early restarts it: the ticks it had left are lost (clipped). Let it run low first - the timer turns red in its last tick.',
    ' ',
    'Mana runs out: Life Tap trades ' .. A.CHARACTER.tapHealth .. ' health for ' .. A.CHARACTER.tapMana .. ' mana. Health does not come back.',
  },
  create = function(parent) return G.create(parent) end,
})
