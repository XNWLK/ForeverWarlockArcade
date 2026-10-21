-- The arcade's window: a title bar, the game picker, and the games that register themselves with A.RegisterGame.
-- In the game it is a movable window (/arcade); on the web page (WOW_WEB) it fills the page.
local ADDON, A = ...
local K = A.Kit
local floor = math.floor
A.NAME = 'Forever Warlock Arcade'
A.WEB = WOW_WEB and true or false
A.W, A.H = 960, 640
A.games, A.order = {}, {}

-- ---- saved settings ----
local DEFAULTS = { scale = 1, sound = true, speed = 1, games = {} }
function A.db(game)
  WarlockArcadeDB = WarlockArcadeDB or {}
  local db = WarlockArcadeDB
  for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = type(v) == 'table' and {} or v end end
  if game then db.games[game] = db.games[game] or {}; return db.games[game] end
  return db
end

-- Sounds by name. In the game: sound kits of the game's own library (names without one stay quiet there, like the
-- per-note sounds, so the game's own sounds are not drowned). On the web page: made-up sounds of web/sound.js, by name.
local SOUNDS = { click = 856, select = 857, open = 839, close = 840, coin = 891, win = 888, lose = 847, card = 1202, crit = 3081,
  flip = 1202, place = 1202, pop = 857, whoosh = 839, levelup = 888, countdown = 856, go = 857,
  rune1 = 856, rune2 = 857, rune3 = 1202, rune4 = 891, jump = 857, lock = 3081 }
function A.sound(name)
  if not A.db().sound or not PlaySound then return end
  if A.WEB then pcall(PlaySound, name); return end
  local id = SOUNDS[name]
  if id then pcall(PlaySound, id, 'SFX') end
end

-- the picker's filters: each game's kind (a game can set def.kind itself)
A.KINDS = { { 'all', 'All' }, { 'daily', 'Daily' }, { 'rhythm', 'Rhythm' }, { 'action', 'Action' }, { 'puzzle', 'Puzzle' }, { 'cards', 'Cards & Quiz' } }
local KIND_OF = { shard = 'cards', juggler = 'action', higher = 'cards', warlockle = 'daily', ware = 'action', pegs = 'action',
  taptap = 'rhythm', merge = 'puzzle', circles = 'rhythm' }

function A.RegisterGame(def)
  -- def: key, name, tagline, icon (spell id), order, ready, help (lines), create(parent) -> object with Show/Hide/OnKey/OnUpdate
  def.kind = def.kind or KIND_OF[def.key] or 'action'
  A.games[def.key] = def
  A.order[#A.order + 1] = def
  table.sort(A.order, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

-- ---- window ----
local W
local function fitWeb()
  if not A.WEB or not W then return end
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local s = math.min(sw / A.W, sh / A.H)
  W:SetScale(s)
  W:ClearAllPoints()
  W:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
end

local function build()
  W = CreateFrame('Frame', 'WarlockArcadeFrame', UIParent)
  W:SetSize(A.W, A.H)
  W:SetFrameStrata('HIGH')
  W:EnableMouse(true)
  W:SetClampedToScreen(true)
  -- the window: a rounded, softly lit background with two pools of light and embers drifting up behind everything
  W.bg = K.shape(W, 'BACKGROUND', 'rr14', -8)
  W.bg:SetAllPoints()
  W.bg:SetGradient('VERTICAL', CreateColor(0.025, 0.02, 0.04, 0.98), CreateColor(0.07, 0.05, 0.1, 0.98))
  -- the light and the embers sit in a frame that clips them to the window (nothing spills onto the game world)
  W.back = CreateFrame('Frame', nil, W)
  W.back:SetAllPoints()
  W.back:SetFrameLevel(W:GetFrameLevel() + 1)
  W.back:SetClipsChildren(true)
  local back = CreateFrame('Frame', nil, W.back)
  back:SetAllPoints()
  W.light1 = K.shape(back, 'BACKGROUND', 'glow', -7)
  W.light1:SetSize(760, 560); W.light1:SetPoint('CENTER', W, 'TOPLEFT', 150, -90); W.light1:SetVertexColor(0.55, 0.3, 1, 0.13)
  W.light2 = K.shape(back, 'BACKGROUND', 'glow', -7)
  W.light2:SetSize(700, 520); W.light2:SetPoint('CENTER', W, 'BOTTOMRIGHT', -120, 60); W.light2:SetVertexColor(0.35, 1, 0.3, 0.07)
  W.embers = {}
  for i = 1, 26 do
    local e = K.shape(back, 'BACKGROUND', 'glow', -6)
    local fel = i % 3 == 0
    e.c = fel and { 0.5, 1, 0.35 } or { 0.72, 0.5, 1 }
    e.size = 4 + (i * 7) % 11
    e:SetSize(e.size, e.size)
    e.x, e.y = (i * 137) % A.W, (i * 89) % A.H
    e.speed = 10 + (i * 13) % 22
    e.phase = i * 0.7
    e.alpha = 0.12 + ((i * 5) % 7) / 24
    W.embers[i] = e
  end
  W.frame = K.box(W, nil, nil, { 0, 0, 0, 0 }, { 0.5, 0.36, 0.78, 0.55 }, 1, nil, 14)
  W.frame:SetAllPoints()
  W.frame.bg:Hide()
  W.frame:SetFrameLevel(W:GetFrameLevel() + 50)

  -- title bar: no box, just a hairline under it
  local bar = CreateFrame('Frame', nil, W)
  bar:SetHeight(34)
  bar:SetPoint('TOPLEFT'); bar:SetPoint('TOPRIGHT')
  bar:EnableMouse(true)
  bar.line = K.rect(bar, 'BORDER', { 0.5, 0.36, 0.78 }, 0.3)
  bar.line:SetPoint('BOTTOMLEFT', 10, 0); bar.line:SetPoint('BOTTOMRIGHT', -10, 0); bar.line:SetHeight(1)
  bar.shade = K.rect(bar, 'BACKGROUND', { 1, 1, 1 }, 1)
  bar.shade:SetAllPoints()
  bar.shade:SetGradient('VERTICAL', CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.035))
  if not A.WEB then
    W:SetMovable(true)
    bar:RegisterForDrag('LeftButton')
    bar:SetScript('OnDragStart', function() W:StartMoving() end)
    bar:SetScript('OnDragStop', function()
      W:StopMovingOrSizing()
      local p, _, rp, x, y = W:GetPoint(1)
      A.db().pos = { p, rp, x, y }
    end)
  end
  W.bar = bar
  W.title = K.text(bar, 17, K.C.gold, 'CENTER', K.FONT_TITLE)
  W.title:SetPoint('CENTER', 0, 0)
  W.title:SetText(A.NAME)
  W.back = K.button(bar, 96, 24, '< Games', function() A.open(nil) end, 'normal', 12)
  W.back:SetPoint('LEFT', 6, 0)
  W.help = K.button(bar, 26, 24, '?', function() A.toggleHelp() end, 'normal', 13)
  W.help:SetPoint('RIGHT', A.WEB and -6 or -38, 0)
  W.sound = K.button(bar, 70, 24, '', function() local db = A.db(); db.sound = not db.sound; A.refreshBar() end, 'normal', 11)
  W.sound:SetPoint('RIGHT', W.help, 'LEFT', -4, 0)
  W.sound.tipFn = function() return { 'Sound', A.db().sound and 'On - click to mute' or 'Off - click to turn on' } end
  if not A.WEB then
    W.close = K.button(bar, 26, 24, 'X', function() W:Hide() end, 'red', 12)
    W.close:SetPoint('RIGHT', -6, 0)
  end

  -- the area under the bar, where the picker or a game draws
  W.content = CreateFrame('Frame', nil, W)
  W.content:SetPoint('TOPLEFT', 0, -34)
  W.content:SetPoint('BOTTOMRIGHT', 0, 0)
  W.content:SetFrameLevel(W:GetFrameLevel() + 2)
  W.content:SetClipsChildren(true)   -- shadows and glows of the games stay inside the window

  -- help panel (rules of the open game)
  local help = K.box(W, 540, 440, { 0.075, 0.06, 0.11, 0.98 }, { 1, 0.8, 0.28, 0.7 }, 1)
  help:SetPoint('CENTER', W.content, 'CENTER')
  help:SetFrameLevel(W:GetFrameLevel() + 60)
  help:EnableMouse(true)
  help.title = K.text(help, 20, K.C.gold, 'CENTER', K.FONT_TITLE)
  help.title:SetPoint('TOP', 0, -16)
  help.rule = K.rect(help, 'ARTWORK', K.C.gold, 0.35)
  help.rule:SetPoint('TOP', 0, -46); help.rule:SetSize(120, 1)
  help.body = K.text(help, 13, K.C.text, 'LEFT')
  help.body:SetPoint('TOPLEFT', 26, -62)
  help.body:SetPoint('TOPRIGHT', -26, -62)
  help.body:SetJustifyV('TOP')
  help.body:SetWordWrap(true)
  help.body:SetSpacing(3)
  help.ok = K.button(help, 120, 28, 'Got it', function() help:Hide() end, 'blue')
  help.ok:SetPoint('BOTTOM', 0, 14)
  help:Hide()
  W.helpPanel = help

  W:EnableKeyboard(true)
  W:SetPropagateKeyboardInput(true)
  W:SetScript('OnKeyDown', function(self, key)
    local used = false
    if W.helpPanel:IsShown() and (key == 'ESCAPE' or key == 'ENTER' or key == 'SPACE') then W.helpPanel:Hide(); used = true
    elseif A.current and A.current.obj.OnKey then used = A.current.obj:OnKey(key) and true or false
    elseif not A.current and (key == 'LEFT' or key == 'RIGHT') then A.turnPage(key == 'LEFT' and -1 or 1); used = true end
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not used) end
  end)
  -- letting go of a key (hold notes in Tap Tap DPS)
  W:SetScript('OnKeyUp', function(self, key)
    if A.current and A.current.obj.OnKeyUp then A.current.obj:OnKeyUp(key) end
  end)
  W:SetScript('OnUpdate', function(_, dt)
    K.tick(dt)
    A.drift(dt)
    if A.current and A.current.obj.OnUpdate then A.current.obj:OnUpdate(dt) end
  end)
  W:SetScript('OnHide', function() GameTooltip:Hide(); if A.current and A.current.obj.OnPause then A.current.obj:OnPause() end end)

  A.buildPicker()
  if A.WEB then
    W:RegisterEvent('DISPLAY_SIZE_CHANGED')
    W:SetScript('OnEvent', fitWeb)
    fitWeb()
  else
    tinsert(UISpecialFrames, 'WarlockArcadeFrame')
    local pos = A.db().pos
    W:SetScale(A.db().scale or 1)
    if pos then W:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else W:SetPoint('CENTER') end
    W:Hide()
  end
  A.open(nil)
end

-- the embers: rise, sway, pulse, come back at the bottom
local emberT = 0
function A.drift(dt)
  emberT = emberT + dt
  for _, e in ipairs(W.embers) do
    e.y = e.y + e.speed * dt
    if e.y > A.H + 10 then e.y = -10; e.x = (e.x + 331) % A.W end
    local x = e.x + math.sin(emberT * 0.6 + e.phase) * 14
    e:SetPoint('CENTER', W, 'BOTTOMLEFT', x, e.y)
    local fade = math.min(1, e.y / 80, (A.H - e.y) / 120)
    e:SetVertexColor(e.c[1], e.c[2], e.c[3], math.max(0, e.alpha * fade * (0.7 + 0.3 * math.sin(emberT * 2 + e.phase * 3))))
  end
end

function A.refreshBar()
  W.sound:SetLabel(A.db().sound and 'Sound on' or '|cff777777Sound off|r')
  W.back:SetShown(A.current ~= nil)
  W.title:SetText(A.current and (A.current.def.name .. '  |cff8a7aa0- ' .. A.NAME .. '|r') or A.NAME)
  local help = A.current and A.current.def.help
  W.help:SetShown(help ~= nil)
end

function A.toggleHelp()
  local p = W.helpPanel
  if p:IsShown() then p:Hide(); return end
  local def = A.current and A.current.def
  if not def or not def.help then return end
  p.title:SetText(def.name)
  p.body:SetText(table.concat(def.help, '|n'))
  p:Show()
end

-- open a game by key, or the picker with nil
function A.open(key)
  GameTooltip:Hide()
  if A.current then A.current.obj:Hide() end
  A.current = nil
  W.helpPanel:Hide()
  if key and A.games[key] and A.games[key].ready then
    local def = A.games[key]
    def.obj = def.obj or def.create(W.content)
    A.current = { def = def, obj = def.obj }
    W.picker:Hide()
    def.obj:Show()
    A.db().last = key
  else
    W.picker:Show()
    A.refreshPicker()
  end
  A.refreshBar()
end

-- ---- the game picker ----
function A.buildPicker()
  local P = CreateFrame('Frame', nil, W.content)
  P:SetAllPoints()
  W.picker = P
  local head = K.text(P, 28, K.C.gold, 'LEFT', K.FONT_TITLE)
  head:SetPoint('TOPLEFT', 24, -18)
  head:SetText('Pick a game')
  local sub = K.text(P, 12, K.C.dim, 'LEFT')
  sub:SetPoint('TOPLEFT', head, 'BOTTOMLEFT', 1, -4)
  sub:SetText('Little Warlock games built on the numbers of the Forever Warlock Sim')
  -- filters: one chip per kind, right-aligned on the header row
  P.chips = {}
  local x = -24
  for i = #A.KINDS, 1, -1 do
    local k = A.KINDS[i]
    local c = K.button(P, 18 + #k[2] * 7, 26, k[2], function() A.db().filter = k[1]; A.pickerPage = 1; A.refreshPicker(true) end, 'ghost', 11)
    c:SetPoint('TOPRIGHT', x, -26)
    c.kind = k[1]
    x = x - (18 + #k[2] * 7) - 6
    P.chips[i] = c
  end
  P.tiles = {}
  for i, def in ipairs(A.order) do
    local t = K.box(P, 222, 114, K.C.panel, K.C.line, 1, 'Button')
    t.def = def
    t.hover = K.shape(t, 'BACKGROUND', 'shadow', -7)
    t.hover:SetPoint('TOPLEFT', -20, 20); t.hover:SetPoint('BOTTOMRIGHT', 20, -20)
    t.hover:SetVertexColor(K.C.accent[1], K.C.accent[2], K.C.accent[3], 1)
    t.hover:SetAlpha(0)
    t.iconBg = K.shape(t, 'BORDER', 'rr6', 1)
    t.iconBg:SetSize(66, 66)
    t.iconBg:SetPoint('LEFT', 12, 0)
    t.iconBg:SetVertexColor(0, 0, 0, 0.55)
    t.icon = K.icon(t, 58, def.icon)
    t.icon:SetPoint('CENTER', t.iconBg, 'CENTER')
    t.iconRing = K.shape(t, 'OVERLAY', 'rl6_1')
    t.iconRing:SetPoint('TOPLEFT', t.iconBg, 'TOPLEFT'); t.iconRing:SetPoint('BOTTOMRIGHT', t.iconBg, 'BOTTOMRIGHT')
    t.iconRing:SetVertexColor(1, 0.8, 0.28, 0.35)
    t.name = K.text(t, 15, K.C.gold, 'LEFT', K.FONT)
    t.name:SetPoint('TOPLEFT', 90, -13)
    t.name:SetPoint('TOPRIGHT', -10, -13)
    t.name:SetText(def.name)
    t.tag = K.text(t, 11, K.C.dim, 'LEFT')
    t.tag:SetPoint('TOPLEFT', t.name, 'BOTTOMLEFT', 0, -4)
    t.tag:SetPoint('TOPRIGHT', t.name, 'BOTTOMRIGHT', 0, -4)
    t.tag:SetHeight(40)
    t.tag:SetWordWrap(true)
    t.tag:SetJustifyV('TOP')
    t.tag:SetSpacing(1)
    t.tag:SetText(def.tagline or '')
    t.best = K.text(t, 11, K.C.text, 'LEFT')
    t.best:SetPoint('BOTTOMLEFT', 90, 11)
    t.best:SetPoint('BOTTOMRIGHT', -10, 11)
    t:SetScript('OnEnter', function(self)
      if not self.def.ready then return end
      self:SetBorderColor(K.C.accent[1], K.C.accent[2], K.C.accent[3], 1)
      K.tween(self.hover, 0.15, function(f) self.hover:SetAlpha(0.5 * f); self.icon:SetSize(58 + 4 * f, 58 + 4 * f) end)
      A.sound('hover')
    end)
    t:SetScript('OnLeave', function(self)
      self:SetBorderColor(K.C.line[1], K.C.line[2], K.C.line[3], 1)
      local a = self.hover:GetAlpha()
      K.tween(self.hover, 0.2, function(f) self.hover:SetAlpha(a * (1 - f)); self.icon:SetSize(62 - 4 * f, 62 - 4 * f) end, function() self.icon:SetSize(58, 58) end)
    end)
    t:SetScript('OnClick', function(self) if self.def.ready then A.sound('open'); A.open(self.def.key) end end)
    P.tiles[i] = t
  end
  -- pages of sixteen: the arrows, the mouse wheel or Left / Right
  P.prev = K.button(P, 30, 26, '<', function() A.turnPage(-1) end, 'ghost', 13)
  P.next = K.button(P, 30, 26, '>', function() A.turnPage(1) end, 'ghost', 13)
  P.pageT = K.text(P, 12, K.C.dim, 'CENTER')
  P.pageT:SetPoint('BOTTOM', 0, 15)
  P.prev:SetPoint('RIGHT', P.pageT, 'LEFT', -12, 0)
  P.next:SetPoint('LEFT', P.pageT, 'RIGHT', 12, 0)
  P:EnableMouseWheel(true)
  P:SetScript('OnMouseWheel', function(_, d) A.turnPage(d > 0 and -1 or 1) end)
  local foot = K.text(P, 11, K.C.faint, 'CENTER')
  P.foot = foot
  foot:SetPoint('BOTTOM', 0, 12)
  foot:SetText(A.WEB and 'Also an addon for WoW: Forever - same games in the game, type /arcade' or 'Also on the web: xnwlk.github.io/ForeverWarlockArcade')
end

-- lays out the tiles of the chosen filter (4 a row), fading them in one after another
function A.refreshPicker(animate)
  local P = W.picker
  local filter = A.db().filter or 'all'
  if filter ~= 'all' then
    local any = false
    for _, def in ipairs(A.order) do if def.kind == filter then any = true end end
    if not any then filter = 'all' end
  end
  for _, c in ipairs(P.chips) do c:SetStyle(c.kind == filter and 'gold' or 'ghost') end
  local cols, tw, th, gap, per = 4, 222, 114, 8, 16
  local x0 = (A.W - (cols * tw + (cols - 1) * gap)) / 2
  local total = 0
  for _, t in ipairs(P.tiles) do if filter == 'all' or t.def.kind == filter then total = total + 1 end end
  local pages = math.max(1, math.ceil(total / per))
  A.pickerPage = math.max(1, math.min(pages, A.pickerPage or 1))
  P.pages = pages
  local first = (A.pickerPage - 1) * per
  local n, k = 0, 0
  for _, t in ipairs(P.tiles) do
    local def = t.def
    local fits = filter == 'all' or def.kind == filter
    local show = fits and k >= first and k < first + per
    if fits then k = k + 1 end
    t:SetShown(show)
    if show then
      local col, row = n % cols, floor(n / cols)
      local tx, ty = x0 + col * (tw + gap), -76 - row * (th + gap)
      t:ClearAllPoints(); t:SetPoint('TOPLEFT', tx, ty)
      if animate ~= false then
        local d = n * 0.025
        K.tween(t, 0.22 + d, function(_, raw)
          local f = math.max(0, math.min(1, (raw * (0.22 + d) - d) / 0.22))
          f = 1 - (1 - f) * (1 - f)
          t:SetAlpha(f); t:SetPoint('TOPLEFT', tx, ty - 10 * (1 - f))
        end)
      end
      n = n + 1
    end
    t.icon:SetDesaturated(not def.ready)
    t.icon:SetAlpha(def.ready and 1 or 0.45)
    t.name:SetTextColor(def.ready and K.C.gold[1] or K.C.faint[1], def.ready and K.C.gold[2] or K.C.faint[2], def.ready and K.C.gold[3] or K.C.faint[3])
    local line = def.ready and (def.bestLine and def.bestLine() or 'Play') or 'Coming soon'
    t.best:SetText(line)
    t.best:SetTextColor(def.ready and K.C.text[1] or K.C.faint[1], def.ready and K.C.text[2] or K.C.faint[2], def.ready and K.C.text[3] or K.C.faint[3])
  end
  P.foot:SetShown(pages == 1 and n <= 12)   -- four full rows reach the bottom
  P.pageT:SetText('Page ' .. A.pickerPage .. ' of ' .. pages)
  P.pageT:SetShown(pages > 1); P.prev:SetShown(pages > 1); P.next:SetShown(pages > 1)
  P.prev:SetEnabled(A.pickerPage > 1); P.next:SetEnabled(A.pickerPage < pages)
end
function A.turnPage(d)
  local P = W.picker
  local p = math.max(1, math.min(P.pages or 1, (A.pickerPage or 1) + d))
  if p == A.pickerPage then return end
  A.pickerPage = p
  A.sound('flip')
  A.refreshPicker(true)
end

function A.toggle()
  if not W then return end
  if W:IsShown() then W:Hide() else W:Show(); A.sound('open'); if not A.current then A.refreshPicker() end end
end

-- ---- start ----
local boot = CreateFrame('Frame')
boot:RegisterEvent('ADDON_LOADED')
boot:SetScript('OnEvent', function(self, event, name)
  if name ~= ADDON then return end
  self:UnregisterEvent('ADDON_LOADED')
  A.db()
  build()
end)

SLASH_WARLOCKARCADE1 = '/arcade'
SLASH_WARLOCKARCADE2 = '/fwa'
SlashCmdList.WARLOCKARCADE = function(msg)
  msg = strtrim(msg or ''):lower()
  if msg == 'reset' then
    A.db().pos = nil; A.db().scale = 1
    if W then W:SetScale(1); W:ClearAllPoints(); W:SetPoint('CENTER'); W:Show() end
  elseif msg:match('^scale') then
    local s = tonumber(msg:match('^scale%s+([%d%.]+)'))
    if s and s >= 0.5 and s <= 1.5 and W then A.db().scale = s; W:SetScale(s) end
  else
    A.toggle()
  end
end
