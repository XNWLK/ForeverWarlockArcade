-- Ritual of Summoning: four demon runes around a pentagram light up in a sequence, each with its own note. Repeat it -
-- click the runes or press 1-4 (or the arrow keys). Every round adds one more rune and plays a little faster; one
-- wrong rune and the ritual breaks. The longest ritual is kept.
local ADDON, A = ...
local K = A.Kit
local C = K.C
local floor, min, max, cos, sin, pi = math.floor, math.min, math.max, math.cos, math.sin, math.pi

local R = {}
A.RitualRules = R
R.RUNES = { { 'Imp', A.PETS.imp.spell, { 1, 0.5, 0.2 } }, { 'Voidwalker', A.PETS.voidwalker.spell, { 0.45, 0.55, 1 } },
  { 'Succubus', A.PETS.succubus.spell, { 1, 0.4, 0.75 } }, { 'Felhunter', A.PETS.felhunter.spell, { 0.5, 1, 0.4 } } }

local function rng(seed)
  local s = seed % 2147483646 + 1
  return function(n) s = (s * 16807) % 2147483647; return (s % n) + 1 end
end
function R.new(seed)
  local s = { rand = rng(seed or 1), seq = {}, at = 0, round = 0, done = false, phase = 'show' }
  R.grow(s)
  return s
end
function R.grow(s)
  s.seq[#s.seq + 1] = s.rand(4)
  s.round = #s.seq
  s.at = 0
  s.phase = 'show'
end
-- how long a rune stays lit while the sequence is shown: shorter every round
function R.light(s) return max(0.22, 0.55 - 0.025 * (s.round - 1)) end
-- the player presses a rune: 'ok', 'round' (sequence complete, a longer one comes) or 'wrong'
function R.press(s, i)
  if s.done or s.phase ~= 'repeat' then return nil end
  s.at = s.at + 1
  if s.seq[s.at] ~= i then s.done = true; return 'wrong' end
  if s.at == #s.seq then return 'round' end
  return 'ok'
end

-- ---------------------------------------------------------------------------------------------------------------
local G = {}
G.__index = G
local CX, CY, RAD = 330, -300, 175   -- the circle's middle (from the top left) and radius
local POS = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }   -- up, right, down, left
local KEYS = { UP = 1, RIGHT = 2, DOWN = 3, LEFT = 4 }

function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('ritual')
  g.seq = K.sequence()
  g:build()
  g.f:Hide()
  return g
end

function G:build()
  local f = self.f
  self.title = K.text(f, 22, C.gold, 'LEFT', K.FONT_TITLE); self.title:SetPoint('TOPLEFT', 22, -16); self.title:SetText('Ritual of Summoning')
  self.sub = K.text(f, 12, C.dim, 'LEFT'); self.sub:SetPoint('TOPLEFT', 22, -46)
  self.sub:SetText('Watch the runes light up, then repeat them: click, 1-4 or the arrow keys.')
  -- the circle: a big ring and a five-pointed star of thin lines (dots along each line)
  self.circle = K.shape(f, 'BORDER', 'ring'); self.circle:SetSize(RAD * 2 + 40, RAD * 2 + 40); self.circle:SetPoint('CENTER', f, 'TOPLEFT', CX, CY)
  self.circle:SetVertexColor(0.6, 0.35, 1, 0.35)
  self.glow = K.shape(f, 'BACKGROUND', 'glow'); self.glow:SetSize(RAD * 2.6, RAD * 2.6); self.glow:SetPoint('CENTER', f, 'TOPLEFT', CX, CY)
  self.glow:SetVertexColor(0.55, 0.3, 1, 0.25)
  local pts = {}
  for k = 0, 4 do local a = pi / 2 + k * 2 * pi / 5; pts[k] = { CX + cos(a) * (RAD - 10), CY + sin(a) * (RAD - 10) } end
  self.star = {}
  for k = 0, 4 do
    local a, b = pts[k], pts[(k + 2) % 5]
    for d = 0, 24 do
      local t = K.shape(f, 'BORDER', 'circle'); t:SetSize(3, 3)
      t:SetPoint('CENTER', f, 'TOPLEFT', a[1] + (b[1] - a[1]) * d / 24, a[2] + (b[2] - a[2]) * d / 24)
      t:SetVertexColor(0.7, 0.45, 1, 0.5)
      self.star[#self.star + 1] = t
    end
  end
  -- the four runes
  self.runes = {}
  for i, r in ipairs(R.RUNES) do
    local b = CreateFrame('Button', nil, f)
    b:SetSize(104, 104)
    b:SetPoint('CENTER', f, 'TOPLEFT', CX + POS[i][1] * RAD, CY + POS[i][2] * RAD)
    b.halo = K.shape(b, 'BACKGROUND', 'glow'); b.halo:SetSize(200, 200); b.halo:SetPoint('CENTER'); b.halo:SetVertexColor(r[3][1], r[3][2], r[3][3], 0)
    b.disc = K.shape(b, 'BORDER', 'circle'); b.disc:SetAllPoints(); b.disc:SetVertexColor(0.08, 0.06, 0.12, 1)
    b.icon = b:CreateTexture(nil, 'ARTWORK'); b.icon:SetSize(68, 68); b.icon:SetPoint('CENTER'); b.icon:SetTexture(K.spellTexture(r[2])); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.ring = K.shape(b, 'OVERLAY', 'ring'); b.ring:SetAllPoints(); b.ring:SetVertexColor(r[3][1], r[3][2], r[3][3], 0.6)
    b.key = K.text(b, 12, C.text, 'CENTER', K.FONT_NUM, 'OUTLINE'); b.key:SetPoint('BOTTOM', b, 'BOTTOM', 0, -16); b.key:SetText(i)
    b.i = i
    b:SetScript('OnMouseDown', function(btn) self:press(btn.i) end)
    self.runes[i] = b
  end
  -- the side
  local side = K.box(f, 280, 470, C.panel, C.line, 1)
  side:SetPoint('TOPRIGHT', -24, -84)
  self.roundT = K.text(side, 11, C.dim, 'LEFT'); self.roundT:SetPoint('TOPLEFT', 16, -16); self.roundT:SetText('Ritual length')
  self.roundV = K.text(side, 34, C.gold, 'LEFT', K.FONT_NUM); self.roundV:SetPoint('TOPLEFT', 16, -32)
  self.bestT = K.text(side, 11, C.dim, 'LEFT'); self.bestT:SetPoint('TOPLEFT', 16, -84); self.bestT:SetText('Longest ritual')
  self.bestV = K.text(side, 22, C.text, 'LEFT', K.FONT_NUM); self.bestV:SetPoint('TOPLEFT', 16, -100)
  self.phaseT = K.text(side, 15, C.text, 'LEFT'); self.phaseT:SetPoint('TOPLEFT', 16, -150); self.phaseT:SetWidth(250); self.phaseT:SetWordWrap(true)
  local note = K.text(side, 11, C.dim, 'LEFT'); note:SetPoint('TOPLEFT', 16, -220); note:SetWidth(250); note:SetWordWrap(true); note:SetSpacing(2)
  note:SetText('Every demon has its own note. Each round adds one more rune and plays a little faster. One wrong rune breaks the ritual.')
  self.start = K.button(side, 248, 40, 'Begin the ritual', function() self:play() end, 'orange', 15)
  self.start:SetPoint('BOTTOM', 0, 16)
end

function G:lightRune(i, dur)
  local b, r = self.runes[i], R.RUNES[i]
  A.sound('rune' .. i)
  K.tween(b, dur, function(_, raw)
    local f = raw < 0.25 and raw / 0.25 or 1 - (raw - 0.25) / 0.75
    b.halo:SetVertexColor(r[3][1], r[3][2], r[3][3], 0.9 * f)
    b.disc:SetVertexColor(0.08 + r[3][1] * 0.4 * f, 0.06 + r[3][2] * 0.4 * f, 0.12 + r[3][3] * 0.4 * f, 1)
    b.icon:SetSize(68 + 10 * f, 68 + 10 * f)
  end)
end
-- shows the sequence, then hands over to the player
function G:show()
  local s = self.s
  s.phase = 'show'
  self.seq:clear()
  local d = R.light(s)
  self.seq:add(0.6, function() end)
  for _, i in ipairs(s.seq) do
    self.seq:add(0.12, function() self:lightRune(i, d) end)
    self.seq:add(d, function() end)
  end
  self.seq:add(0.05, function() s.phase = 'repeat'; self:refresh() end)
  self:refresh()
end
function G:play()
  self.s = R.new(math.random(1, 2000000000))
  A.sound('open')
  self:show()
end
function G:press(i)
  local s = self.s
  if not s or s.done or s.phase ~= 'repeat' then return end
  local res = R.press(s, i)
  if res == 'wrong' then
    A.sound('lose')
    local best = self.db.best or 0
    local made = s.round - 1
    if made > best then self.db.best = made end
    self:refresh()
    return
  end
  self:lightRune(i, 0.3)
  if res == 'round' then
    s.phase = 'wait'
    self.seq:add(0.5, function() A.sound('combo'); R.grow(s); self:show() end)
  end
  self:refresh()
end
-- leaving in the middle: the sequence is shown again when you come back
function G:Show() self.f:Show(); local s = self.s; if s and not s.done and s.phase ~= 'repeat' then if s.phase == 'wait' then R.grow(s) end; self:show() end; self:refresh() end
function G:Hide() self.f:Hide(); GameTooltip:Hide(); self.seq:clear() end

function G:refresh()
  local s = self.s
  self.roundV:SetText(tostring(s and s.round or 0))
  self.bestV:SetText(tostring(self.db.best or 0))
  if not s then self.phaseT:SetText('Begin the ritual when you are ready.')
  elseif s.done then self.phaseT:SetText('The ritual broke! You kept ' .. (s.round - 1) .. (s.round - 1 == 1 and ' rune.' or ' runes.') .. ' It was the ' .. R.RUNES[s.seq[s.at]][1] .. '.')
  elseif s.phase == 'show' then self.phaseT:SetText('Watch...')
  elseif s.phase == 'repeat' then self.phaseT:SetText('Your turn: ' .. s.at .. ' of ' .. #s.seq)
  else self.phaseT:SetText('Well done!') end
  self.start:SetShown(not s or s.done)
  self.start:SetLabel(s and 'Again' or 'Begin the ritual')
end

function G:OnUpdate(dt) self.seq:update(dt) end
function G:OnKey(key)
  local i = tonumber(key)
  if not (i and i >= 1 and i <= 4 and key == tostring(i)) then i = KEYS[key] end
  if i then self:press(i); return true end
  if (key == 'ENTER' or key == 'SPACE') and (not self.s or self.s.done) then self:play(); return true end
  return false
end

A.RegisterGame({
  key = 'ritual', name = 'Ritual of Summoning', order = 20, ready = true, kind = 'action', icon = A.PETS.succubus.spell,
  tagline = 'Repeat the demon runes. One more each round.',
  bestLine = function() local b = A.db('ritual').best; return b and b > 0 and ('Best: ' .. b .. ' runes') or 'Play' end,
  help = {
    '|cffffd040Watch the demon runes light up, then repeat them in the same order.|r Click them, press 1-4, or use the arrow keys (up Imp, right Voidwalker, down Succubus, left Felhunter).',
    ' ',
    'Every round adds one more rune and plays a little faster. One wrong rune and the ritual breaks. Every demon has its own note - listening helps.',
  },
  create = function(parent) return G.create(parent) end,
})
