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

-- sounds of the game's own library (sound kit ids); the web page plays a short tone for each instead
local SOUNDS = { click = 856, select = 857, open = 839, close = 840, coin = 891, win = 888, lose = 847, card = 1202, crit = 3081 }
function A.sound(name)
  if not A.db().sound then return end
  local id = SOUNDS[name]
  if id and PlaySound then pcall(PlaySound, id, 'SFX') end
end

function A.RegisterGame(def)
  -- def: key, name, tagline, icon (spell id), order, ready, help (lines), create(parent) -> object with Show/Hide/OnKey/OnUpdate
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
  W.bg = K.rect(W, 'BACKGROUND', K.C.bg, 0.97)
  W.bg:SetAllPoints()
  W.frame = K.box(W, nil, nil, { 0, 0, 0, 0 }, { 0.36, 0.27, 0.48 }, 2)
  W.frame:SetAllPoints()
  W.frame.bg:Hide()
  W.frame:SetFrameLevel(W:GetFrameLevel() + 50)

  -- title bar
  local bar = K.box(W, nil, 34, { 0.09, 0.065, 0.12 }, { 0.36, 0.27, 0.48 }, 1)
  bar:SetPoint('TOPLEFT'); bar:SetPoint('TOPRIGHT')
  bar:EnableMouse(true)
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

  -- help panel (rules of the open game)
  local help = K.box(W, 520, 420, { 0.07, 0.05, 0.1, 0.98 }, K.C.gold, 2)
  help:SetPoint('CENTER', W.content, 'CENTER')
  help:SetFrameLevel(W:GetFrameLevel() + 60)
  help:EnableMouse(true)
  help.title = K.text(help, 18, K.C.gold, 'CENTER', K.FONT_TITLE)
  help.title:SetPoint('TOP', 0, -14)
  help.body = K.text(help, 13, K.C.text, 'LEFT')
  help.body:SetPoint('TOPLEFT', 22, -48)
  help.body:SetPoint('TOPRIGHT', -22, -48)
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
    elseif A.current and A.current.obj.OnKey then used = A.current.obj:OnKey(key) and true or false end
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not used) end
  end)
  -- letting go of a key (hold notes in Tap Tap DPS)
  W:SetScript('OnKeyUp', function(self, key)
    if A.current and A.current.obj.OnKeyUp then A.current.obj:OnKeyUp(key) end
  end)
  W:SetScript('OnUpdate', function(_, dt) if A.current and A.current.obj.OnUpdate then A.current.obj:OnUpdate(dt) end end)
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
  local head = K.text(P, 30, K.C.gold, 'CENTER', K.FONT_TITLE)
  head:SetPoint('TOP', 0, -26)
  head:SetText('Pick a game')
  local sub = K.text(P, 13, K.C.dim, 'CENTER')
  sub:SetPoint('TOP', head, 'BOTTOM', 0, -6)
  sub:SetText('Little Warlock games built on the numbers of the Forever Warlock Sim')
  P.tiles = {}
  -- 4 tiles a row for up to 8 games, 5 (narrower) for 9 or 10
  local cols, tw, th, gap = 4, 212, 232, 14
  if #A.order > 8 then cols, tw = 5, 172 end
  local x0 = (A.W - (cols * tw + (cols - 1) * gap)) / 2
  for i, def in ipairs(A.order) do
    local col, row = (i - 1) % cols, floor((i - 1) / cols)
    local t = K.box(P, tw, th, K.C.panel, K.C.line, 1, 'Button')
    t:SetPoint('TOPLEFT', x0 + col * (tw + gap), -96 - row * (th + gap))
    t.def = def
    t.glow = K.rect(t, 'BACKGROUND', K.C.shadow, 0.0, 1)
    t.glow:SetPoint('TOPLEFT', 1, -1); t.glow:SetPoint('BOTTOMRIGHT', -1, 1)
    t.iconBg = K.rect(t, 'BORDER', { 0, 0, 0 }, 0.6, 1)
    t.iconBg:SetSize(78, 78)
    t.iconBg:SetPoint('TOP', 0, -20)
    t.icon = K.icon(t, 72, def.icon)
    t.icon:SetPoint('CENTER', t.iconBg, 'CENTER')
    t.name = K.text(t, 17, K.C.gold, 'CENTER', K.FONT)
    t.name:SetPoint('TOP', t.iconBg, 'BOTTOM', 0, -12)
    t.name:SetText(def.name)
    t.tag = K.text(t, 12, K.C.dim, 'CENTER')
    t.tag:SetPoint('TOPLEFT', 12, -140); t.tag:SetPoint('TOPRIGHT', -12, -140)
    t.tag:SetWordWrap(true)
    t.tag:SetJustifyV('TOP')
    t.tag:SetText(def.tagline or '')
    t.best = K.text(t, 12, K.C.text, 'CENTER')
    t.best:SetPoint('BOTTOM', 0, 12)
    t:SetScript('OnEnter', function(self) if self.def.ready then self.glow:SetColorTexture(K.C.shadow[1], K.C.shadow[2], K.C.shadow[3], 0.16); self:SetBorderColor(K.C.gold[1], K.C.gold[2], K.C.gold[3]) end end)
    t:SetScript('OnLeave', function(self) self.glow:SetColorTexture(0, 0, 0, 0); self:SetBorderColor(K.C.line[1], K.C.line[2], K.C.line[3]) end)
    t:SetScript('OnClick', function(self) if self.def.ready then A.sound('open'); A.open(self.def.key) end end)
    P.tiles[i] = t
  end
  local foot = K.text(P, 11, K.C.faint, 'CENTER')
  foot:SetPoint('BOTTOM', 0, 12)
  foot:SetText(A.WEB and 'Also an addon for WoW: Forever - same games in the game, type /arcade' or 'Also on the web: xnwlk.github.io/ForeverWarlockArcade')
end

function A.refreshPicker()
  for _, t in ipairs(W.picker.tiles) do
    local def = t.def
    t.icon:SetDesaturated(not def.ready)
    t.icon:SetAlpha(def.ready and 1 or 0.45)
    t.name:SetTextColor(def.ready and K.C.gold[1] or K.C.faint[1], def.ready and K.C.gold[2] or K.C.faint[2], def.ready and K.C.gold[3] or K.C.faint[3])
    local line = def.ready and (def.bestLine and def.bestLine() or 'Play') or 'Coming soon'
    t.best:SetText(line)
    t.best:SetTextColor(def.ready and K.C.text[1] or K.C.faint[1], def.ready and K.C.text[2] or K.C.faint[2], def.ready and K.C.text[3] or K.C.faint[3])
  end
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
