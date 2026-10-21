-- Perfect Rotation: a short fight, a timeline, five spells. Put the casts in the order that deals the most damage.
-- The fight is the sim's standard character: real cast times, the 1.5 s global cooldown, real mana costs and damage.
-- A damage-over-time spell only counts the ticks that land before the fight ends, and casting it again while it is
-- still on the target throws away the ticks it had left. A search finds the best order it can - that is the target;
-- stars for 90%, 97% and 100% of it.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max = math.floor, math.min, math.max

local P = {}
A.RotationRules = P
P.SPELLS = { 'shadowBolt', 'corruption', 'baneOfAgony', 'immolate', 'lifeTap' }
P.DOTS = { corruption = true, baneOfAgony = true, immolate = true }
P.PUZZLES = {
  { name = 'The opener', len = 12, mana = 6126, note = 'A short fight with full mana. What goes first?', best = 'corruption baneOfAgony immolate shadowBolt shadowBolt shadowBolt' },
  { name = 'Short and sharp', len = 18, mana = 6126, note = 'Long enough for every DoT to tick a few times?', best = 'corruption baneOfAgony immolate shadowBolt shadowBolt shadowBolt shadowBolt shadowBolt' },
  { name = 'Running dry', len = 24, mana = 900, note = 'Little mana: when does Life Tap pay off?', best = 'immolate baneOfAgony corruption lifeTap immolate shadowBolt lifeTap shadowBolt shadowBolt lifeTap shadowBolt' },
  { name = 'Half a minute', len = 30, mana = 6126, note = 'Full mana, thirty seconds.', best = 'immolate baneOfAgony shadowBolt shadowBolt corruption baneOfAgony immolate shadowBolt shadowBolt shadowBolt shadowBolt shadowBolt' },
  { name = 'On empty', len = 30, mana = 300, note = 'Almost no mana at the start.', best = 'lifeTap baneOfAgony shadowBolt corruption lifeTap shadowBolt immolate lifeTap shadowBolt shadowBolt lifeTap shadowBolt shadowBolt lifeTap' },
  { name = 'The long one', len = 45, mana = 2000, note = 'Keep your DoTs up without clipping them.', best = 'baneOfAgony immolate corruption shadowBolt shadowBolt immolate lifeTap shadowBolt baneOfAgony lifeTap shadowBolt corruption lifeTap immolate shadowBolt lifeTap shadowBolt shadowBolt lifeTap shadowBolt shadowBolt' },
}
-- (best: the order P.best found, stored so a puzzle opens at once; tools/check-rotation.js checks it is still the best)
P.STARS = { 0.9, 0.97, 0.9995 }

local function critFactor() local ch = A.CHARACTER; return 1 + ch.critPct / 100 * (ch.critMult - 1) end
function P.info(key)
  local c = A.CAST[key]
  if key == 'lifeTap' then return { cast = 0, cost = 0, direct = 0 } end
  return { cast = c.cast, cost = c.cost, direct = (c.direct or 0) * critFactor(), tick = c.tick, ticks = c.ticks, every = c.every }
end

-- a state of the fight: time, mana, damage counted, and the ticks of each DoT still to come
function P.start(level)
  local p = P.PUZZLES[level]
  return { level = level, len = p.len, t = 0, mana = p.mana, dmg = 0, ticks = {}, casts = {}, clipped = 0 }
end
local function copy(s)
  local n = { level = s.level, len = s.len, t = s.t, mana = s.mana, dmg = s.dmg, ticks = {}, casts = s.casts, clipped = s.clipped }
  for k, list in pairs(s.ticks) do n.ticks[k] = list end
  return n
end
-- can this spell be cast now? (time left in the fight, mana)
function P.can(s, key)
  if s.t >= s.len - 0.001 then return false, 'The fight is over' end
  local i = P.info(key)
  if s.mana + 0.001 < i.cost then return false, 'Not enough mana' end
  return true
end
-- the state after casting a spell (s itself is not changed). keepLog: remember the casts and ticks for the timeline
function P.cast(s, key, keepLog)
  local ok, why = P.can(s, key)
  if not ok then return nil, why end
  local ch = A.CHARACTER
  local i = P.info(key)
  local n = copy(s)
  local busy = max(ch.gcd, i.cast)
  local done = n.t + i.cast
  n.mana = n.mana - i.cost
  if key == 'lifeTap' then n.mana = min(ch.maxMana, n.mana + ch.tapMana) end
  if i.direct > 0 and done <= n.len + 0.0001 then n.dmg = n.dmg + i.direct end
  local log
  if keepLog then
    log = { key = key, t = n.t, cast = i.cast, busy = busy, mana = n.mana, dmg = (i.direct > 0 and done <= n.len + 0.0001) and i.direct or 0, ticks = {} }
  end
  if P.DOTS[key] then
    -- a new application: the old one's ticks after this moment are lost
    local old = n.ticks[key]
    if old then
      local lost = 0
      for _, tt in ipairs(old) do if tt > done + 0.0001 then lost = lost + 1 end end
      if lost > 0 then
        n.dmg = n.dmg - lost * i.tick
        n.clipped = n.clipped + lost
        if keepLog then
          for _, c in ipairs(n.casts) do if c.key == key then for _, tk in ipairs(c.ticks) do if tk.t > done + 0.0001 then tk.clipped = true end end end end
        end
      end
    end
    local list = {}
    if done <= n.len + 0.0001 then
      for k = 1, i.ticks do
        local tt = done + k * i.every
        if tt <= n.len + 0.0001 then list[#list + 1] = tt; n.dmg = n.dmg + i.tick; if log then log.ticks[#log.ticks + 1] = { t = tt, dmg = i.tick } end end
      end
    end
    n.ticks[key] = list
  end
  -- mana comes back over the time this cast takes
  n.t = n.t + busy
  n.mana = min(ch.maxMana, n.mana + ch.mp5 / 5 * busy)
  if keepLog then
    local casts = {}
    for k, c in ipairs(s.casts) do casts[k] = c end
    casts[#casts + 1] = log
    n.casts = casts
  end
  return n
end
-- a whole order of spells, from the start
function P.run(level, seq, keepLog)
  local s = P.start(level)
  for _, key in ipairs(seq) do
    local n, why = P.cast(s, key, keepLog)
    if not n then return s, why end
    s = n
  end
  return s
end
function P.over(s) return s.t >= s.len - 0.001 end

-- the best order the search finds: a beam over the number of casts, keeping the most promising states (the damage
-- counted so far, plus what a Shadow Bolt filler would add in the time left); the same states merged
function P.best(level, width)
  width = width or 300
  local s0 = P.start(level)
  s0.seq = {}
  local sbDps = P.info('shadowBolt').direct / P.info('shadowBolt').cast
  local beam, best = { s0 }, nil
  for depth = 1, 60 do
    local nextList, seen = {}, {}
    for _, s in ipairs(beam) do
      local any = false
      for _, key in ipairs(P.SPELLS) do
        local n = P.cast(s, key)
        if n then
          any = true
          local seq = {}
          for k, x in ipairs(s.seq) do seq[k] = x end
          seq[#seq + 1] = key
          n.seq = seq
          n.score = n.dmg + max(0, n.len - n.t) * sbDps
          local sig = string.format('%.1f|%d', n.t, floor(n.mana / 25))
          for _, d in ipairs({ 'corruption', 'baneOfAgony', 'immolate' }) do local l = n.ticks[d]; sig = sig .. '|' .. (l and #l > 0 and string.format('%.1f', l[#l]) or '-') end
          if not seen[sig] or seen[sig].dmg < n.dmg then seen[sig] = n end
        end
      end
      if not any and (not best or s.dmg > best.dmg) then best = s end
    end
    for _, n in pairs(seen) do nextList[#nextList + 1] = n end
    if #nextList == 0 then break end
    table.sort(nextList, function(a, b) return a.score > b.score end)
    beam = {}
    for k = 1, min(width, #nextList) do beam[k] = nextList[k] end
  end
  for _, s in ipairs(beam) do if P.over(s) and (not best or s.dmg > best.dmg) then best = s end end
  return best.dmg, best.seq
end
function P.stars(dmg, target)
  local n = 0
  for i, f in ipairs(P.STARS) do if dmg >= target * f then n = i end end
  return n
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local TLX, TLW = 30, 900             -- the timeline: left edge and width
local TLY = -212
local SCOL = { shadowBolt = { 0.8, 0.5, 1 }, corruption = { 0.45, 0.85, 0.3 }, baneOfAgony = { 0.7, 0.45, 1 }, immolate = { 1, 0.45, 0.15 }, lifeTap = { 0.3, 0.6, 1 } }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('rotation')
  g.level = g.db.level or 1
  g.targets = {}
  g.blocks, g.tickViews = {}, {}
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 30, -14)
  self.note = K.text(f, 12, C.dim, 'LEFT'); self.note:SetPoint('TOPLEFT', 30, -44)
  -- the puzzles
  self.levelBtns = {}
  for i = 1, #P.PUZZLES do
    local b = K.button(f, 54, 30, tostring(i), function() self:open(i) end, 'normal', 12)
    b:SetPoint('TOPRIGHT', -30 - (#P.PUZZLES - i) * 60, -16)
    b.tipFn = function() local p = P.PUZZLES[i]; return { p.name, p.len .. ' s fight, ' .. K.num(p.mana) .. ' mana at the start', (self.db.stars and self.db.stars[i] or 0) .. ' of 3 stars' } end
    self.levelBtns[i] = b
  end
  -- the spells
  self.spellBtns = {}
  for i, key in ipairs(P.SPELLS) do
    local b = K.box(f, 170, 58, C.panel2, C.line, 1, 'Button')
    b:SetPoint('TOPLEFT', TLX + (i - 1) * 182, -72)
    b.icon = K.icon(b, 38, A.SPELLS[key].id); b.icon:SetPoint('LEFT', 10, 0)
    b.name = K.text(b, 13, C.text, 'LEFT'); b.name:SetPoint('TOPLEFT', b.icon, 'TOPRIGHT', 8, -1); b.name:SetText(A.SPELLS[key].name)
    local inf = P.info(key)
    b.sub = K.text(b, 10, C.dim, 'LEFT'); b.sub:SetPoint('TOPLEFT', b.name, 'BOTTOMLEFT', 0, -4)
    b.sub:SetText(key == 'lifeTap' and ('+' .. A.CHARACTER.tapMana .. ' mana, instant') or ((inf.cast > 0 and (K.dec(inf.cast, 1) .. ' s cast') or 'instant') .. ', ' .. inf.cost .. ' mana'))
    b.hl = K.shape(b, 'HIGHLIGHT', 'rr6'); b.hl:SetAllPoints(); b.hl:SetVertexColor(1, 1, 1, 0.07)
    b.key = key
    b:SetScript('OnClick', function(btn) self:add(btn.key) end)
    b:SetScript('OnEnter', function(btn) K.showTip(btn, self:spellTip(btn.key)) end)
    b:SetScript('OnLeave', function() GameTooltip:Hide() end)
    self.spellBtns[i] = b
  end
  local hint = K.text(f, 11, C.faint, 'LEFT'); hint:SetPoint('TOPLEFT', TLX, -140); hint:SetText('Click the spells (or press 1-5) to add them to the fight. Backspace takes the last one back.')
  -- the timeline
  self.tl = K.box(f, TLW, 150, { 0.04, 0.03, 0.06 }, C.line, 1)
  self.tl:SetPoint('TOPLEFT', TLX, TLY + 52)
  self.tl:SetClipsChildren(true)
  self.scale = {}
  for k = 0, 60, 3 do
    local m = K.rect(self.tl, 'BORDER', { 1, 1, 1 }, 0.06); m:SetWidth(1); m:SetPoint('TOP', self.tl, 'TOPLEFT', 0, 0); m:SetPoint('BOTTOM', self.tl, 'BOTTOMLEFT', 0, 0)
    local t = K.text(self.tl, 9, C.faint, 'LEFT', K.FONT_NUM); t:SetPoint('BOTTOMLEFT', m, 'BOTTOMLEFT', 3, 3)
    self.scale[#self.scale + 1] = { mark = m, text = t, s = k }
  end
  self.lanes = {}
  local names = { { 'corruption', 'Corruption' }, { 'baneOfAgony', 'Bane of Agony' }, { 'immolate', 'Immolate' } }
  for i, x in ipairs(names) do
    self.lanes[x[1]] = -64 - (i - 1) * 22
    local band = K.rect(self.tl, 'BORDER', SCOL[x[1]], 0.06); band:SetPoint('TOPLEFT', 0, self.lanes[x[1]] + 7); band:SetPoint('TOPRIGHT', 0, self.lanes[x[1]] + 7); band:SetHeight(14)
    local lab = K.text(self.tl, 9, SCOL[x[1]], 'LEFT'); lab:SetPoint('LEFT', band, 'LEFT', 4, 0); lab:SetText(x[2] .. ' ticks')
  end
  -- the results
  local y = TLY - 112
  local function stat(x, label, size, color)
    local a = K.text(f, 11, C.dim, 'LEFT'); a:SetPoint('TOPLEFT', x, y); a:SetText(label)
    local b = K.text(f, size or 22, color or C.text, 'LEFT', K.FONT_NUM); b:SetPoint('TOPLEFT', x, y - 15)
    return b
  end
  self.dmgT = stat(TLX, 'Damage', 26, C.gold)
  self.dpsT = stat(TLX + 170, 'DPS', 22)
  self.timeT = stat(TLX + 300, 'Time used', 22)
  self.manaT = stat(TLX + 450, 'Mana', 22, C.chips)
  self.targetT = stat(TLX + 600, 'Target (the best the search found)', 22, C.dim)
  self.starViews = {}
  for i = 1, 3 do
    local st = K.shape(f, 'ARTWORK', 'spark'); st:SetSize(40, 40); st:SetPoint('TOPLEFT', TLX + 600 + (i - 1) * 40, y - 52)
    self.starViews[i] = st
  end
  self.pctT = K.text(f, 13, C.text, 'LEFT'); self.pctT:SetPoint('TOPLEFT', TLX + 730, y - 64)
  self.msg = K.text(f, 14, C.gold, 'LEFT'); self.msg:SetPoint('TOPLEFT', TLX, y - 60); self.msg:SetWidth(540); self.msg:SetWordWrap(true)
  self.bestRow = K.text(f, 11, C.dim, 'LEFT'); self.bestRow:SetPoint('TOPLEFT', TLX, y - 104); self.bestRow:SetWidth(900); self.bestRow:SetWordWrap(true)
  self.undoBtn = K.button(f, 110, 32, 'Undo', function() self:undo() end, 'normal', 13)
  self.undoBtn:SetPoint('BOTTOMLEFT', TLX, 18)
  self.clearBtn = K.button(f, 110, 32, 'Start over', function() self.seq = {}; self:refresh(); A.sound('flip') end, 'normal', 13)
  self.clearBtn:SetPoint('LEFT', self.undoBtn, 'RIGHT', 10, 0)
  self.showBtn = K.button(f, 170, 32, 'Show the best order', function() self.reveal = not self.reveal; self:refresh() end, 'ghost', 12)
  self.showBtn:SetPoint('BOTTOMRIGHT', -30, 18)
end

function G:spellTip(key)
  local i = P.info(key)
  local lines = { { A.SPELLS[key].name, { 1, 1, 1 } } }
  if key == 'lifeTap' then lines[#lines + 1] = { 'Gives ' .. A.CHARACTER.tapMana .. ' mana. Instant (1.5 s global cooldown).', C.gold }
  else
    lines[#lines + 1] = { (i.cast > 0 and (K.dec(i.cast, 1) .. ' s cast') or 'Instant (1.5 s global cooldown)') .. ' - ' .. i.cost .. ' mana', C.gold }
    if i.direct > 0 then lines[#lines + 1] = { K.num(i.direct) .. ' damage when the cast ends (crits counted)', C.text } end
    if i.tick then lines[#lines + 1] = { i.ticks .. ' ticks of ' .. K.num(i.tick) .. ', one every ' .. i.every .. ' s', C.text } end
    if P.DOTS[key] then lines[#lines + 1] = { 'Cast again while it ticks and the ticks it had left are lost.', C.dim } end
  end
  local ok, why = self.s and P.can(self.s, key)
  if self.s and not ok then lines[#lines + 1] = { why, C.bad } end
  return lines
end

function G:open(level)
  self.level = level
  self.db.level = level
  self.seq = {}
  self.reveal = false
  self:target()
  self:refresh()
  A.sound('select')
end
-- the target: the stored best order (searched again only if there is none)
function G:target()
  local t = self.targets[self.level]
  if not t then
    local stored = P.PUZZLES[self.level].best
    local seq = {}
    if stored then for k in stored:gmatch('%a+') do seq[#seq + 1] = k end end
    local dmg = P.run(self.level, seq).dmg
    if not stored then dmg, seq = P.best(self.level) end
    t = { dmg = dmg, seq = seq }
    self.targets[self.level] = t
  end
  return t
end
function G:Show() self.f:Show(); if not self.seq then self:open(self.level) else self:refresh() end end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:add(key)
  if not self.s or P.over(self.s) then return end
  local ok, why = P.can(self.s, key)
  if not ok then self.msg:SetText(why); A.sound('error'); return end
  self.seq[#self.seq + 1] = key
  self:refresh()
  A.sound(P.over(self.s) and 'select' or 'place')
  if P.over(self.s) then self:finish() end
end
function G:undo()
  if #self.seq == 0 then return end
  table.remove(self.seq)
  self:refresh()
  A.sound('flip')
end
function G:finish()
  local t = self:target()
  local stars = P.stars(self.s.dmg, t.dmg)
  self.db.stars = self.db.stars or {}
  self.db.best = self.db.best or {}
  self.db.stars[self.level] = max(self.db.stars[self.level] or 0, stars)
  self.db.best[self.level] = max(self.db.best[self.level] or 0, self.s.dmg)
  local beat = self.s.dmg > t.dmg + 0.5
  self.msg:SetText(beat and 'You beat the search - nice!' or stars == 3 and 'Perfect - as good as the best order found!' or stars > 0 and (stars .. (stars == 1 and ' star' or ' stars') .. ' - can you find more?') or 'Below 90% of the target - try another order')
  A.sound(stars >= 3 and 'win' or stars > 0 and 'levelup' or 'lose')
  for i, st in ipairs(self.starViews) do
    if i <= stars then K.tween(st, 0.3 + i * 0.12, function(_, raw) local f = max(0, min(1, (raw * (0.3 + i * 0.12) - i * 0.12) / 0.3)); st:SetSize(40 + 30 * (1 - f), 40 + 30 * (1 - f)) end) end
  end
  self:refresh(true)
end

local function px(s, t) return TLW * t / s.len end
function G:refresh(keepMsg)
  local s, why = P.run(self.level, self.seq, true)
  self.s = s
  local p = P.PUZZLES[self.level]
  self.title:SetText('Perfect Rotation ' .. self.level .. ': ' .. p.name)
  self.note:SetText(p.note .. '  -  a ' .. p.len .. ' s fight, ' .. K.num(p.mana) .. ' mana at the start')
  for i, b in ipairs(self.levelBtns) do
    local st = self.db.stars and self.db.stars[i] or 0
    b:SetLabel(i .. (st > 0 and (' ' .. string.rep('*', st)) or ''))
    b:SetStyle(i == self.level and 'gold' or 'normal')
  end
  for _, b in ipairs(self.spellBtns) do
    local ok = P.can(s, b.key)
    b:SetAlpha(ok and 1 or 0.45)
    b.icon:SetDesaturated(not ok)
  end
  -- the time scale: a mark every 3 s
  for _, m in ipairs(self.scale) do
    local on = m.s <= p.len
    m.mark:SetShown(on); m.text:SetShown(on and m.s < p.len)
    if on then
      m.mark:ClearAllPoints(); m.mark:SetPoint('TOP', self.tl, 'TOPLEFT', px(s, m.s), 0); m.mark:SetPoint('BOTTOM', self.tl, 'BOTTOMLEFT', px(s, m.s), 0)
      m.text:SetText(m.s .. ' s')
    end
  end
  -- the casts and their ticks
  local nb, nt = 0, 0
  for _, c in ipairs(s.casts) do
    nb = nb + 1
    local b = self.blocks[nb]
    if not b then
      b = CreateFrame('Frame', nil, self.tl)
      b:SetHeight(34)
      b.gcd = K.shape(b, 'BACKGROUND', 'rr4'); b.gcd:SetAllPoints()
      b.cast = K.shape(b, 'BORDER', 'rr4'); b.cast:SetPoint('TOPLEFT'); b.cast:SetPoint('BOTTOMLEFT')
      b.icon = b:CreateTexture(nil, 'ARTWORK'); b.icon:SetSize(24, 24); b.icon:SetPoint('LEFT', 4, 0); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      b.line = K.shape(b, 'OVERLAY', 'rl4_1'); b.line:SetAllPoints()
      self.blocks[nb] = b
    end
    local col = SCOL[c.key]
    b:ClearAllPoints()
    b:SetPoint('TOPLEFT', self.tl, 'TOPLEFT', px(s, c.t) + 1, -8)
    b:SetWidth(max(4, px(s, c.busy) - 2))
    K.fill(b.gcd, col[1] * 0.25, col[2] * 0.25, col[3] * 0.25, 1)
    b.cast:SetShown(c.cast > 0)
    b.cast:SetWidth(max(1, px(s, c.cast) - 2))
    K.fill(b.cast, col[1] * 0.6, col[2] * 0.6, col[3] * 0.6, 1)
    b.line:SetVertexColor(col[1], col[2], col[3], 0.8)
    b.icon:SetTexture(K.spellTexture(A.SPELLS[c.key].id))
    b.icon:SetShown(px(s, c.busy) > 30)
    b:Show()
    for _, tk in ipairs(c.ticks) do
      nt = nt + 1
      local v = self.tickViews[nt]
      if not v then v = K.shape(self.tl, 'ARTWORK', 'circle'); v:SetSize(9, 9); self.tickViews[nt] = v end
      v:ClearAllPoints(); v:SetPoint('CENTER', self.tl, 'TOPLEFT', px(s, tk.t), self.lanes[c.key])
      if tk.clipped then v:SetVertexColor(1, 0.3, 0.3, 0.9) else v:SetVertexColor(col[1], col[2], col[3], 1) end
      v:Show()
    end
  end
  for i = nb + 1, #self.blocks do self.blocks[i]:Hide() end
  for i = nt + 1, #self.tickViews do self.tickViews[i]:Hide() end
  -- numbers
  local t = self:target()
  self.dmgT:SetText(K.num(s.dmg))
  self.dpsT:SetText(K.num(s.dmg / s.len))
  self.timeT:SetText(K.dec(min(s.t, s.len), 1) .. ' / ' .. s.len .. ' s')
  self.manaT:SetText(K.num(s.mana))
  self.targetT:SetText(K.num(t.dmg))
  local over = P.over(s)
  local stars = over and P.stars(s.dmg, t.dmg) or 0
  local earned = self.db.stars and self.db.stars[self.level] or 0
  for i, st in ipairs(self.starViews) do
    if over and i <= stars then st:SetVertexColor(1, 0.82, 0.3, 1) elseif i <= earned then st:SetVertexColor(1, 0.82, 0.3, 0.35) else st:SetVertexColor(0.3, 0.27, 0.36, 1) end
  end
  self.pctT:SetText(string.format('%.1f%%', 100 * s.dmg / t.dmg) .. ' of the target')
  if not keepMsg then
    self.msg:SetText(over and '' or (#self.seq == 0 and 'Add the first spell' or ((s.clipped > 0 and (s.clipped .. ' ticks clipped - ') or '') .. K.dec(s.len - s.t, 1) .. ' s left')))
  end
  self.undoBtn:SetEnabled(#self.seq > 0)
  self.clearBtn:SetEnabled(#self.seq > 0)
  self.showBtn:SetLabel(self.reveal and 'Hide the best order' or 'Show the best order')
  if self.reveal then
    local names = {}
    for _, k in ipairs(t.seq) do names[#names + 1] = A.SPELLS[k].name end
    self.bestRow:SetText('The best order found (' .. K.num(t.dmg) .. '): ' .. table.concat(names, ' > '))
  else self.bestRow:SetText('') end
end

function G:OnKey(key)
  local i = tonumber(key)
  if i and P.SPELLS[i] and key == tostring(i) then self:add(P.SPELLS[i]); return true end
  if key == 'BACKSPACE' then self:undo(); return true end
  return false
end

A.RegisterGame({
  key = 'rotation', name = 'Perfect Rotation', order = 16, ready = true, kind = 'puzzle', icon = A.SPELLS.siphonLife.id,
  tagline = 'Order the casts of a short fight for the most damage.',
  bestLine = function()
    local st = A.db('rotation').stars
    local n = 0
    if st then for _, v in pairs(st) do n = n + v end end
    return n > 0 and (n .. ' of ' .. 3 * #P.PUZZLES .. ' stars') or 'Play'
  end,
  help = {
    '|cffffd040Put the casts of a short fight in the order that deals the most damage.|r Click the spells (or press 1-5) to add them; Backspace takes one back.',
    ' ',
    'The fight is the Forever Warlock Sim\'s standard character: real cast times, the 1.5 s global cooldown, real mana costs and damage, mana coming back slowly, ' .. A.CHARACTER.tapMana .. ' mana per Life Tap.',
    ' ',
    'A damage-over-time spell only counts the ticks that land before the fight ends (the dots on the timeline). Cast it again while it still ticks and the ticks it had left are lost (red dots).',
    ' ',
    'The target is the best order a search found. Stars for 90%, 97% and 100% of it - and if you beat the search, you found something it missed.',
  },
  create = function(parent) return G.create(parent) end,
})
