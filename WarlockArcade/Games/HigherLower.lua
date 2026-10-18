-- Higher or Lower: the left card shows its number, guess whether the right one is higher or lower. Keep the streak
-- going. Every number is the Forever Warlock Sim's own: the published results of its ready builds (A.RESULTS: DPS per
-- build and race, damage per spell, what a point of a stat is worth) and the standard character's spells (A.CAST).
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local H = {}
A.HigherLowerRules = H
H.PER_TOPIC = 5          -- guesses before the topic changes
local RES = A.RESULTS
local STAT = {
  sp = { name = '10 spell power', icon = A.CONSUMABLES.greaterArcaneElixir, per = 10 },
  hitPct = { name = '1% hit', talent = 'suppression', per = 1 },
  critPct = { name = '1% crit', talent = 'malevolence', per = 1 },
  hastePct = { name = '1% haste', talent = 'bane', per = 1 },
}
local function buildName(key) return RES.builds[key] and RES.builds[key].name or key end
local function buildIcon(key) local b = RES.builds[key]; return b and A.SPELLS[b.icon] and A.SPELLS[b.icon].id end

H.TOPICS = {
  dps = { title = 'Which sims more DPS?', note = 'Ready builds of the Forever Warlock Sim, ' .. RES.fight .. ', standard gear.', gap = 0.004,
    fmt = function(v) return K.num(v) .. ' DPS' end },
  spell = { title = 'Which deals more damage in its build?', note = 'Damage of one spell over a whole ' .. RES.fight .. ' (Human), from the sim.', gap = 0.04,
    fmt = function(v) return K.num(v) .. ' damage' end },
  weight = { title = 'Which is worth more DPS?', note = 'The sim\'s stat weights: DPS gained from a little more of one stat, per build.', gap = 0.04,
    fmt = function(v) return string.format('%.2f DPS', v) end },
  cast = { title = 'Which hits harder?', note = 'One cast of each spell, all its ticks counted - the sim\'s standard character, no talents.', gap = 0.05,
    fmt = function(v) return K.num(v) .. ' damage' end },
}
H.TOPIC_ORDER = { 'dps', 'spell', 'weight', 'cast' }

local pools = {}
function H.pool(topic)
  if pools[topic] then return pools[topic] end
  local list = {}
  if topic == 'dps' then
    for _, r in ipairs(RES.dps) do list[#list + 1] = { title = buildName(r.build), sub = r.race == 'no racial' and 'No racial' or r.race, icon = buildIcon(r.build), value = r.dps } end
  elseif topic == 'spell' then
    for _, r in ipairs(RES.spells) do
      local s = A.SPELLS[r.spell]
      local pet = r.spell:match('^pet:')
      local icon = s and s.id or (RES.builds[r.build] and RES.builds[r.build].pet and A.PETS[RES.builds[r.build].pet] and A.PETS[RES.builds[r.build].pet].spell)
      list[#list + 1] = { title = r.name, sub = 'in ' .. buildName(r.build), icon = icon, value = r.dmg, pet = pet and true or nil }
    end
  elseif topic == 'weight' then
    for bk, w in pairs(RES.weights) do
      for sk, st in pairs(STAT) do
        local icon = st.talent and A.TALENTS[st.talent] and A.TALENTS[st.talent].spell
        list[#list + 1] = { title = st.name, sub = 'in ' .. buildName(bk), icon = icon, item = st.icon and st.icon.item, value = w[sk] * st.per }
      end
    end
    table.sort(list, function(a, b) return a.title .. a.sub < b.title .. b.sub end)
  elseif topic == 'cast' then
    for key, c in pairs(A.CAST) do
      local total = (c.direct or 0) + (c.tick and c.tick * c.ticks or 0)
      if total > 0 then
        local how = c.tick and (c.direct and 'hits, then ' .. c.ticks .. ' ticks' or c.ticks .. ' ticks over ' .. c.duration .. ' s') or (c.cast > 0 and K.dec(c.cast, 1) .. ' s cast' or 'instant')
        list[#list + 1] = { title = A.SPELLS[key].name, sub = how, icon = A.SPELLS[key].id, value = total }
      end
    end
    table.sort(list, function(a, b) return a.title < b.title end)
  end
  pools[topic] = list
  return list
end
-- a card of the topic that differs clearly from `other`
function H.pick(topic, other)
  local list, gap = H.pool(topic), H.TOPICS[topic].gap
  for _ = 1, 200 do
    local c = list[math.random(1, #list)]
    if not other or (c ~= other and abs(c.value - other.value) > gap * max(c.value, other.value) and not (c.title == other.title and c.sub == other.sub)) then return c end
  end
  return list[1]
end
function H.new(seed)
  if seed then math.randomseed(seed) end
  local s = { streak = 0, inTopic = 0, over = false }
  H.newTopic(s)
  return s
end
function H.newTopic(s)
  local topic
  repeat topic = H.TOPIC_ORDER[math.random(1, #H.TOPIC_ORDER)] until topic ~= s.topic or #H.TOPIC_ORDER == 1
  s.topic, s.inTopic = topic, 0
  s.left = H.pick(topic)
  s.right = H.pick(topic, s.left)
end
-- 'higher' or 'lower'; returns right or wrong
function H.guess(s, dir)
  if s.over then return nil end
  local up = s.right.value >= s.left.value
  local ok = (dir == 'higher') == up
  s.last = { ok = ok, dir = dir }
  if ok then s.streak = s.streak + 1; s.inTopic = s.inTopic + 1 else s.over = true end
  return ok
end
-- after a right guess: the right card moves left, a new one comes in (or a new topic)
function H.advance(s)
  if s.over then return end
  if s.inTopic >= H.PER_TOPIC then H.newTopic(s)
  else s.left = s.right; s.right = H.pick(s.topic, s.left) end
  s.last = nil
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local CW, CHT = 300, 330

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('higher')
  g:build()
  g.f:Hide()
  return g
end

local function card(parent, x)
  local c = K.box(parent, CW, CHT, C.panel, C.line, 2)
  c:SetPoint('TOP', parent, 'TOPLEFT', x, -118)
  c.iconBg = K.rect(c, 'BORDER', { 0, 0, 0 }, 0.7, 1); c.iconBg:SetSize(84, 84); c.iconBg:SetPoint('TOP', 0, -24)
  c.icon = c:CreateTexture(nil, 'ARTWORK'); c.icon:SetSize(78, 78); c.icon:SetPoint('CENTER', c.iconBg, 'CENTER'); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.title = K.text(c, 19, C.gold, 'CENTER'); c.title:SetPoint('TOPLEFT', 14, -122); c.title:SetPoint('TOPRIGHT', -14, -122); c.title:SetWordWrap(true)
  c.sub = K.text(c, 13, C.dim, 'CENTER'); c.sub:SetPoint('TOPLEFT', 14, -176); c.sub:SetPoint('TOPRIGHT', -14, -176); c.sub:SetWordWrap(true)
  c.value = K.text(c, 30, C.text, 'CENTER', K.FONT_NUM); c.value:SetPoint('BOTTOM', 0, 70)
  c.mark = K.text(c, 15, C.good, 'CENTER'); c.mark:SetPoint('BOTTOM', 0, 40)
  return c
end

function G:build()
  local f = self.f
  self.topic = K.text(f, 24, C.gold, 'CENTER', K.FONT_TITLE); self.topic:SetPoint('TOP', 0, -22)
  self.note = K.text(f, 13, C.dim, 'CENTER'); self.note:SetPoint('TOP', 0, -60)
  self.streak = K.text(f, 15, C.text, 'LEFT'); self.streak:SetPoint('TOPLEFT', 24, -24)
  self.best = K.text(f, 13, C.dim, 'RIGHT'); self.best:SetPoint('TOPRIGHT', -24, -26)
  self.left = card(f, 300)
  self.right = card(f, 660)
  self.vs = K.text(f, 30, C.faint, 'CENTER', K.FONT_TITLE); self.vs:SetPoint('CENTER', f, 'TOPLEFT', 480, -283); self.vs:SetText('vs')
  self.higher = K.button(f, 140, 44, 'Higher', function() self:guess('higher') end, 'green', 16)
  self.higher:SetPoint('TOPLEFT', f, 'TOPLEFT', 660 - 146, -462)
  self.lower = K.button(f, 140, 44, 'Lower', function() self:guess('lower') end, 'red', 16)
  self.lower:SetPoint('TOPLEFT', f, 'TOPLEFT', 660 + 6, -462)
  self.higher.tipFn = function() return { 'Higher', 'The right card\'s number is higher (or the same). Key: Up arrow or H' } end
  self.lower.tipFn = function() return { 'Lower', 'The right card\'s number is lower (or the same). Key: Down arrow or L' } end
  self.hint = K.text(f, 12, C.faint, 'CENTER'); self.hint:SetPoint('BOTTOM', 0, 22)
  self.hint:SetText('Every number comes from the Forever Warlock Sim (results of ' .. RES.generated .. ').')
  local o = K.box(f, 480, 260, { 0.07, 0.05, 0.1, 0.97 }, C.gold, 2)
  o:SetPoint('CENTER', 0, -10)
  o:SetFrameLevel(f:GetFrameLevel() + 30)
  o:EnableMouse(true)
  o.title = K.text(o, 24, C.gold, 'CENTER', K.FONT_TITLE); o.title:SetPoint('TOP', 0, -18)
  o.body = K.text(o, 14, C.text, 'CENTER'); o.body:SetPoint('TOPLEFT', 24, -62); o.body:SetPoint('TOPRIGHT', -24, -62); o.body:SetWordWrap(true); o.body:SetSpacing(4)
  o.go = K.button(o, 180, 42, 'Play', function() self:start() end, 'orange', 16)
  o.go:SetPoint('BOTTOM', 0, 18)
  self.overlay = o
end

function G:paint(c, item, reveal, topic)
  c.icon:SetTexture(item.item and K.itemTexture(item.item) or K.spellTexture(item.icon))
  c.title:SetText(item.title)
  c.sub:SetText(item.sub)
  c.value:SetText(reveal and H.TOPICS[topic].fmt(item.value) or '?')
  c.value:SetTextColor(reveal and C.text[1] or C.faint[1], reveal and C.text[2] or C.faint[2], reveal and C.text[3] or C.faint[3])
end

function G:refresh()
  local s = self.s
  self.streak:SetText('Streak: |cffffd040' .. (s and s.streak or 0) .. '|r')
  self.best:SetText('Best streak: ' .. (self.db.best or 0))
  if not s then return end
  local t = H.TOPICS[s.topic]
  self.topic:SetText(t.title)
  self.note:SetText(t.note)
  self:paint(self.left, s.left, true, s.topic)
  self:paint(self.right, s.right, s.last ~= nil, s.topic)
  self.left.mark:SetText('')
  if s.last then
    self.right.mark:SetText(s.last.ok and 'Right!' or 'Wrong')
    self.right.mark:SetTextColor(s.last.ok and C.good[1] or C.bad[1], s.last.ok and C.good[2] or C.bad[2], s.last.ok and C.good[3] or C.bad[3])
    local bc = s.last.ok and C.good or C.bad
    self.right:SetBorderColor(bc[1], bc[2], bc[3], 1)
  else
    self.right.mark:SetText('')
    self.right:SetBorderColor(C.line[1], C.line[2], C.line[3], 1)
  end
  local can = not s.last and not s.over
  self.higher:SetEnabled(can); self.lower:SetEnabled(can)
end

function G:Show()
  self.f:Show()
  if not self.s then self:showStart() end
  self:refresh()
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end

function G:showStart()
  local o = self.overlay
  local s = self.s
  if s and s.over then
    local isNew = s.streak > (self.db.best or 0)
    if isNew then self.db.best = s.streak end
    o.title:SetText('Streak over')
    local r = s.right
    o.body:SetText('|cffffd040' .. s.streak .. (s.streak == 1 and ' right guess' or ' right guesses') .. '|r' .. (isNew and '  |cff60ff60new best!|r' or '') ..
      '|n|n' .. r.title .. ' (' .. r.sub .. '): ' .. H.TOPICS[s.topic].fmt(r.value) .. '|n' .. s.left.title .. ' (' .. s.left.sub .. '): ' .. H.TOPICS[s.topic].fmt(s.left.value))
    o.go:SetLabel('Again')
  else
    o.title:SetText('Higher or Lower')
    o.body:SetText('The left card shows its number. Is the right one higher or lower? Builds, spells, stats - every number is the Forever Warlock Sim\'s.|n|nOne wrong guess ends the streak.')
    o.go:SetLabel('Play')
  end
  o:Show()
end

function G:start()
  self.s = H.new()
  self.overlay:Hide()
  self.wait = nil
  A.sound('open')
  self:refresh()
end

function G:guess(dir)
  local s = self.s
  if not s or s.last or s.over then return end
  local ok = H.guess(s, dir)
  A.sound(ok and 'coin' or 'lose')
  self.wait = ok and 1.1 or 1.6
  self:refresh()
end

function G:OnUpdate(dt)
  if self.wait then
    self.wait = self.wait - dt
    if self.wait <= 0 then
      self.wait = nil
      if self.s.over then self:showStart() else H.advance(self.s); self:refresh() end
    end
  end
end

function G:OnKey(key)
  if self.overlay:IsShown() then
    if key == 'ENTER' or key == 'SPACE' then self:start(); return true end
    return false
  end
  if key == 'UP' or key == 'H' then self:guess('higher'); return true end
  if key == 'DOWN' or key == 'L' then self:guess('lower'); return true end
  return false
end

A.RegisterGame({
  key = 'higher', name = 'Higher or Lower', order = 3, ready = true, icon = A.SPELLS.baneOfDoom.id,
  tagline = 'Which build sims higher? Which spell hits harder? Guess right, keep your streak.',
  bestLine = function() local b = A.db('higher').best; return b and b > 0 and ('Best streak: ' .. b) or 'Play' end,
  help = {
    '|cffffd040The left card shows its number. Is the right card\'s number higher or lower?|r A tie counts as right either way.',
    ' ',
    'Four topics take turns, ' .. H.PER_TOPIC .. ' guesses each: the DPS of the sim\'s ready builds for each race, how much damage one spell deals in a build over a whole fight, how much DPS a little more of a stat is worth in a build, and how hard one cast of a spell hits.',
    ' ',
    'Every number comes from the Forever Warlock Sim: its published results (' .. RES.fight .. ', ' .. RES.gear .. ') and its standard character.',
    ' ',
    'Keys: Up arrow or H = higher, Down arrow or L = lower.',
  },
  create = function(parent) return G.create(parent) end,
})
