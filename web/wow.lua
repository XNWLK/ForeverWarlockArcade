-- The part of the WoW UI the arcade uses, for the web page (and for the checks in tools/, which run the same file).
-- The addon's own files run on top of this unchanged. The objects live here in Lua; where they are drawn, their size and
-- the mouse are handled by web/wow-core.js (natives in the table __web). Not part of the addon.
--
-- Strict where the game is strict, so a mistake shows here first: SetText needs text, a FontString needs a font before
-- it shows text, SetPoint needs a known point name, numbers must be numbers.
local N = __web
local floor, type, pairs, ipairs, tostring, select = math.floor, type, pairs, ipairs, tostring, select
unpack = unpack or table.unpack

local objects, scripted, nextId = {}, {}, 0
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local SCRIPTS = { OnUpdate = 1, OnEvent = 1, OnShow = 1, OnHide = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1, OnMouseUp = 1, OnClick = 1,
  OnMouseWheel = 1, OnKeyDown = 1, OnKeyUp = 1, OnDragStart = 1, OnDragStop = 1, OnSizeChanged = 1, OnLoad = 1, OnDoubleClick = 1,
  PostClick = 1, PreClick = 1, OnEnable = 1, OnDisable = 1 }

local function num(v, what) if type(v) ~= 'number' then error(what .. ': number expected, got ' .. type(v), 3) end return v end
local function isVisible(o) while o do if not o.__shown then return false end; o = o.__parent end; return true end
local function fireShow(o, shown)
  -- OnShow / OnHide reach the frame and every shown child whose visibility really changed, like the game
  local s = o.__scripts and o.__scripts[shown and 'OnShow' or 'OnHide']
  if s then s(o) end
  if o.__children then for _, c in ipairs(o.__children) do if c.__shown and c.__scripts then fireShow(c, shown) end end end
end

local Region = {}
Region.__index = Region
function Region:GetObjectType() return self.__type end
function Region:IsObjectType(t) return self.__type == t or (t == 'Frame' and self.__frame) or (t == 'Region' and true) end
function Region:GetName() return self.__name end
function Region:GetParent() return self.__parent end
function Region:Show() if not self.__shown then local was = isVisible(self.__parent); self.__shown = true; N.shown(self.__id, true); if was then fireShow(self, true) end end end
function Region:Hide() if self.__shown then local was = isVisible(self); self.__shown = false; N.shown(self.__id, false); if was then fireShow(self, false) end end end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.__shown end
function Region:IsVisible() return isVisible(self) end
function Region:SetAlpha(a) num(a, 'SetAlpha'); self.__alpha = math.max(0, math.min(1, a)); N.alpha(self.__id, self.__alpha) end
function Region:GetAlpha() return self.__alpha end
function Region:SetPoint(point, rel, relPoint, x, y)
  if not POINTS[point] then error('SetPoint: unknown point ' .. tostring(point), 2) end
  if type(rel) == 'number' then rel, relPoint, x, y = nil, nil, rel, relPoint
  elseif type(rel) == 'string' then local f = _G[rel]; if not f then error('SetPoint: no frame called ' .. rel, 2) end; rel = f end
  if type(relPoint) == 'number' then relPoint, x, y = nil, relPoint, x end
  if relPoint ~= nil and not POINTS[relPoint] then error('SetPoint: unknown relative point ' .. tostring(relPoint), 2) end
  if rel ~= nil and (type(rel) ~= 'table' or not rel.__id) then error('SetPoint: bad relative frame', 2) end
  if rel == self then error('SetPoint: a region cannot be anchored to itself', 2) end
  x, y = x or 0, y or 0
  num(x, 'SetPoint x'); num(y, 'SetPoint y')
  self.__points = self.__points or {}
  for i, p in ipairs(self.__points) do if p[1] == point then table.remove(self.__points, i); break end end
  local p = { point, rel or self.__parent, relPoint or point, x, y }
  self.__points[#self.__points + 1] = p
  N.point(self.__id, point, (rel or self.__parent or UIParent).__id, relPoint or point, x, y)
end
function Region:ClearAllPoints() self.__points = nil; N.clear(self.__id) end
function Region:SetAllPoints(rel)
  rel = rel or self.__parent
  if type(rel) == 'string' then rel = _G[rel] end
  self:ClearAllPoints(); self:SetPoint('TOPLEFT', rel, 'TOPLEFT', 0, 0); self:SetPoint('BOTTOMRIGHT', rel, 'BOTTOMRIGHT', 0, 0)
end
function Region:GetNumPoints() return self.__points and #self.__points or 0 end
function Region:GetPoint(i)
  local p = self.__points and self.__points[i or 1]
  if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:SetSize(w, h) num(w, 'SetSize width'); num(h, 'SetSize height'); self.__w, self.__h = w, h; N.size(self.__id, w, h) end
function Region:SetWidth(w) num(w, 'SetWidth'); self.__w = w; N.size(self.__id, w, self.__h or -1) end
function Region:SetHeight(h) num(h, 'SetHeight'); self.__h = h; N.size(self.__id, self.__w or -1, h) end
function Region:GetRect() return N.rect(self.__id) end
function Region:GetWidth() local _, _, w = N.rect(self.__id); return w or self.__w or 0 end
function Region:GetHeight() local _, _, _, h = N.rect(self.__id); return h or self.__h or 0 end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local l = N.rect(self.__id); return l end
function Region:GetBottom() local _, b = N.rect(self.__id); return b end
function Region:GetRight() local l, _, w = N.rect(self.__id); return l and l + w end
function Region:GetTop() local _, b, _, h = N.rect(self.__id); return b and b + h end
function Region:GetCenter() local l, b, w, h = N.rect(self.__id); if l then return l + w / 2, b + h / 2 end end
function Region:IsMouseOver() return N.over(self.__id) end
function Region:GetEffectiveScale() local s, o = 1, self; while o do s = s * (o.__scale or 1); o = o.__parent end; return s end
function Region:SetDrawLayer(layer, sub)
  if not LAYERS[layer] then error('SetDrawLayer: unknown layer ' .. tostring(layer), 2) end
  self.__layer, self.__sub = layer, sub or 0; N.layer(self.__id, LAYERS[layer], sub or 0)
end
function Region:GetDrawLayer() return self.__layer, self.__sub end

local function newObject(kind, mt, parent, name)
  nextId = nextId + 1
  local o = setmetatable({ __id = nextId, __type = kind, __parent = parent, __shown = true, __alpha = 1, __name = name }, mt)
  objects[nextId] = o
  if parent then parent.__children = parent.__children or {}; parent.__children[#parent.__children + 1] = o end
  if name then _G[name] = o end
  return o
end

-- Texture
local Texture = setmetatable({}, { __index = Region }); Texture.__index = Texture
function Texture:SetTexture(path)
  if path ~= nil and type(path) ~= 'string' and type(path) ~= 'number' then error('SetTexture: path or file id expected', 2) end
  self.__tex = path; N.tex(self.__id, path and tostring(path) or '')
  return path ~= nil
end
function Texture:GetTexture() return self.__tex end
function Texture:SetColorTexture(r, g, b, a) num(r, 'SetColorTexture'); num(g, 'SetColorTexture'); num(b, 'SetColorTexture'); self.__tex = nil; N.color(self.__id, r, g, b, a or 1) end
function Texture:SetVertexColor(r, g, b, a) num(r, 'SetVertexColor'); num(g, 'SetVertexColor'); num(b, 'SetVertexColor'); N.vcolor(self.__id, r, g, b, a or 1) end
function Texture:SetTexCoord(l, r, t, b, ...)
  if select('#', ...) > 0 then error('SetTexCoord: the 8-number form is not supported by the web page', 2) end
  num(l, 'SetTexCoord'); num(r, 'SetTexCoord'); num(t, 'SetTexCoord'); num(b, 'SetTexCoord'); N.coords(self.__id, l, r, t, b)
end
function Texture:SetRotation(rad) num(rad, 'SetRotation'); self.__rot = rad; N.rot(self.__id, rad) end
function Texture:GetRotation() return self.__rot or 0 end
function Texture:SetDesaturated(v) N.desat(self.__id, v and true or false) end
function Texture:SetBlendMode(m) N.blend(self.__id, m or 'BLEND') end
function Texture:SetGradient(orient, c1, c2)
  if orient ~= 'VERTICAL' and orient ~= 'HORIZONTAL' then error('SetGradient: VERTICAL or HORIZONTAL', 2) end
  if type(c1) ~= 'table' or type(c2) ~= 'table' then error('SetGradient: colours made with CreateColor expected', 2) end
  N.gradient(self.__id, orient, c1.r, c1.g, c1.b, c1.a or 1, c2.r, c2.g, c2.b, c2.a or 1)
end
-- slicing: the web page draws the addon's rounded shapes (Media\rr*, rl*, shadow) as CSS boxes, so the margins only matter in the game
function Texture:SetTextureSliceMargins(l, t, r, b) num(l, 'SetTextureSliceMargins'); num(t, 'SetTextureSliceMargins'); num(r, 'SetTextureSliceMargins'); num(b, 'SetTextureSliceMargins'); N.slice(self.__id, l, t, r, b) end
function Texture:SetTextureSliceMode() end
function Texture:SetSnapToPixelGrid() end
function Texture:SetTexelSnappingBias() end
function Texture:SetHorizTile() end
function Texture:SetVertTile() end

-- FontString
local FontString = setmetatable({}, { __index = Region }); FontString.__index = FontString
function FontString:SetFont(path, size, flags)
  if type(path) ~= 'string' then error('SetFont: font path expected', 2) end
  num(size, 'SetFont size')
  self.__font = { path, size, flags or '' }; N.font(self.__id, path, size, flags or '')
  return true
end
function FontString:GetFont() local f = self.__font; if f then return f[1], f[2], f[3] end end
function FontString:SetFontObject(fo)
  if type(fo) == 'string' then fo = _G[fo] end
  if type(fo) ~= 'table' or not fo.__fontObject then error('SetFontObject: font object expected', 2) end
  self:SetFont(fo.__font[1], fo.__font[2], fo.__font[3])
  if fo.__color then self:SetTextColor(unpack(fo.__color)) end
end
function FontString:SetText(t)
  if t == nil then t = '' end
  if type(t) ~= 'string' and type(t) ~= 'number' then error('SetText: text expected, got ' .. type(t), 2) end
  if not self.__font then error('SetText: Font not set (FontString without SetFont / SetFontObject)', 2) end
  t = tostring(t)
  if t ~= self.__text then self.__text = t; N.text(self.__id, t) end
end
function FontString:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function FontString:GetText() return self.__text end
function FontString:SetTextColor(r, g, b, a) num(r, 'SetTextColor'); num(g, 'SetTextColor'); num(b, 'SetTextColor'); self.__color = { r, g, b, a or 1 }; N.tcolor(self.__id, r, g, b, a or 1) end
function FontString:GetTextColor() local c = self.__color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function FontString:SetJustifyH(j) self.__jh = j; N.justify(self.__id, j or 'CENTER', self.__jv or 'MIDDLE') end
function FontString:SetJustifyV(j) self.__jv = j; N.justify(self.__id, self.__jh or 'CENTER', j or 'MIDDLE') end
function FontString:SetWordWrap(v) N.wrap(self.__id, v and true or false) end
function FontString:SetNonSpaceWrap() end
function FontString:SetMaxLines(n) N.maxlines(self.__id, n or 0) end
function FontString:SetSpacing(s) N.spacing(self.__id, s or 0) end
function FontString:SetShadowOffset(x, y) self.__so = { x or 0, y or 0 }; local c = self.__sc or { 0, 0, 0, 1 }; N.shadow(self.__id, x or 0, y or 0, c[1], c[2], c[3], c[4]) end
function FontString:SetShadowColor(r, g, b, a) self.__sc = { r, g, b, a or 1 }; local o = self.__so or { 0, 0 }; N.shadow(self.__id, o[1], o[2], r, g, b, a or 1) end
function FontString:GetStringWidth() local w = N.strw(self.__id); return w end
function FontString:GetUnboundedStringWidth() local w = N.strw(self.__id); return w end
function FontString:GetStringHeight() local _, h = N.strw(self.__id); return h end
function FontString:SetTextScale() end

-- Frame
local Frame = setmetatable({}, { __index = Region }); Frame.__index = Frame
local function frameLevel(o) return o.__level end
function Frame:SetScript(name, fn)
  if not SCRIPTS[name] then error('SetScript: ' .. self.__type .. ' has no script ' .. tostring(name), 2) end
  if fn ~= nil and type(fn) ~= 'function' then error('SetScript: function expected', 2) end
  self.__scripts = self.__scripts or {}
  self.__scripts[name] = fn
  if name == 'OnUpdate' then scripted[self.__id] = fn and self or nil end
  if name == 'OnKeyDown' or name == 'OnKeyUp' then N.keys(self.__id, fn and true or false) end
end
function Frame:GetScript(name) return self.__scripts and self.__scripts[name] end
function Frame:HasScript(name) return SCRIPTS[name] ~= nil end
function Frame:HookScript(name, fn)
  local old = self:GetScript(name)
  self:SetScript(name, old and function(...) old(...); fn(...) end or fn)
end
function Frame:RegisterEvent(e) self.__events = self.__events or {}; self.__events[e] = true end
function Frame:UnregisterEvent(e) if self.__events then self.__events[e] = nil end end
function Frame:UnregisterAllEvents() self.__events = nil end
function Frame:IsEventRegistered(e) return self.__events and self.__events[e] or false end
function Frame:CreateTexture(name, layer, template, sub)
  local t = newObject('Texture', Texture, self, name)
  t.__layer = layer or 'ARTWORK'
  if not LAYERS[t.__layer] then error('CreateTexture: unknown layer ' .. tostring(layer), 2) end
  N.create(t.__id, 'tex', self.__id, LAYERS[t.__layer], sub or 0)
  return t
end
function Frame:CreateFontString(name, layer, template)
  local f = newObject('FontString', FontString, self, name)
  f.__layer = layer or 'ARTWORK'
  if not LAYERS[f.__layer] then error('CreateFontString: unknown layer ' .. tostring(layer), 2) end
  N.create(f.__id, 'font', self.__id, LAYERS[f.__layer], 0)
  if template then f:SetFontObject(template) end
  return f
end
function Frame:EnableMouse(v) self.__mouse = v and true or false; N.mouse(self.__id, self.__mouse) end
function Frame:IsMouseEnabled() return self.__mouse end
function Frame:EnableMouseWheel(v) N.wheel(self.__id, v and true or false) end
function Frame:EnableKeyboard(v) N.keyboard(self.__id, v and true or false) end
function Frame:SetPropagateKeyboardInput(v) N.propagate(self.__id, v and true or false) end
function Frame:SetFrameStrata(s) if not STRATA[s] then error('SetFrameStrata: unknown strata ' .. tostring(s), 2) end; self.__strata = s; N.strata(self.__id, STRATA[s]) end
function Frame:GetFrameStrata() local o = self; while o do if o.__strata then return o.__strata end; o = o.__parent end; return 'MEDIUM' end
-- like the game: child frames are kept above their parent when the parent is raised
function Frame:SetFrameLevel(l)
  num(l, 'SetFrameLevel'); self.__level = l; N.level(self.__id, l)
  for _, c in ipairs(self.__children or {}) do if c.__frame and (c.__level or 0) <= l then c:SetFrameLevel(l + 1) end end
end
function Frame:GetFrameLevel() return self.__level end
function Frame:Raise() end
function Frame:Lower() end
function Frame:SetToplevel() end
function Frame:SetScale(s) num(s, 'SetScale'); if s <= 0 then error('SetScale: must be above 0', 2) end; self.__scale = s; N.scale(self.__id, s) end
function Frame:GetScale() return self.__scale or 1 end
function Frame:SetMovable(v) self.__movable = v end
function Frame:IsMovable() return self.__movable end
function Frame:SetResizable() end
function Frame:SetClampedToScreen() end
function Frame:SetClipsChildren(v) N.clip(self.__id, v and true or false) end
function Frame:RegisterForDrag(...) N.drag(self.__id, select('#', ...) > 0) end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:SetUserPlaced() end
function Frame:SetHitRectInsets() end
function Frame:SetID(i) self.__fid = i end
function Frame:GetID() return self.__fid or 0 end
function Frame:GetChildren() local t = {}; for _, c in ipairs(self.__children or {}) do if c.__frame then t[#t + 1] = c end end; return unpack(t) end
function Frame:SetParent(p)
  if type(p) == 'string' then p = _G[p] end
  local old = self.__parent
  if old and old.__children then for i, c in ipairs(old.__children) do if c == self then table.remove(old.__children, i); break end end end
  self.__parent = p
  if p then p.__children = p.__children or {}; p.__children[#p.__children + 1] = self end
  N.parent(self.__id, p and p.__id or 0)
end
function Frame:SetFixedFrameStrata() end
function Frame:SetFixedFrameLevel() end

-- Button
local Button = setmetatable({}, { __index = Frame }); Button.__index = Button
function Button:RegisterForClicks(...) local t = {}; for i = 1, select('#', ...) do t[select(i, ...)] = true end; self.__clicks = t end
function Button:Click(button) self:__click(button or 'LeftButton', false) end
function Button:__click(button, down)
  if self.__disabled then return end
  local s = self.__scripts
  if s and s.PreClick then s.PreClick(self, button, down) end
  if s and s.OnClick then s.OnClick(self, button, down) end
  if s and s.PostClick then s.PostClick(self, button, down) end
end
function Button:Enable() if self.__disabled then self.__disabled = false; local s = self:GetScript('OnEnable'); if s then s(self) end end end
function Button:Disable() if not self.__disabled then self.__disabled = true; local s = self:GetScript('OnDisable'); if s then s(self) end end end
function Button:SetEnabled(v) if v then self:Enable() else self:Disable() end end
function Button:IsEnabled() return not self.__disabled end
function Button:SetMotionScriptsWhileDisabled() end

local KINDS = { Frame = Frame, Button = Button }
function CreateFrame(kind, name, parent, template, id)
  local mt = KINDS[kind]
  if not mt then error('CreateFrame: the web page knows only Frame and Button, not ' .. tostring(kind), 2) end
  if type(parent) == 'string' then parent = _G[parent] end
  parent = parent or UIParent
  local f = newObject(kind, mt, parent, name)
  f.__frame = true
  f.__level = parent and (parent.__level or 0) + 1 or 0
  if kind == 'Button' then f.__clicks = { LeftButtonUp = true }; f.__mouse = true end
  N.create(f.__id, kind == 'Button' and 'button' or 'frame', parent and parent.__id or 0, 0, 0)
  N.level(f.__id, f.__level)
  if kind == 'Button' then N.mouse(f.__id, true) end
  if id then f:SetID(id) end
  return f
end

UIParent = newObject('Frame', Frame, nil, 'UIParent'); UIParent.__frame = true; UIParent.__level = 0
N.create(UIParent.__id, 'root', 0, 0, 0)
WorldFrame = UIParent

-- Font objects (only what the arcade might use)
local function fontObject(name, path, size, flags, r, g, b)
  _G[name] = { __fontObject = true, __font = { path, size, flags or '' }, __color = r and { r, g, b, 1 },
    GetFont = function(self) return self.__font[1], self.__font[2], self.__font[3] end, SetFont = function(self, p, s, f) self.__font = { p, s, f or '' } end }
end
fontObject('GameFontNormal', 'Fonts\\FRIZQT__.TTF', 12, '', 1, 0.82, 0)
fontObject('GameFontHighlight', 'Fonts\\FRIZQT__.TTF', 12, '', 1, 1, 1)
fontObject('GameFontNormalSmall', 'Fonts\\FRIZQT__.TTF', 10, '', 1, 0.82, 0)
fontObject('GameFontHighlightSmall', 'Fonts\\FRIZQT__.TTF', 10, '', 1, 1, 1)
fontObject('GameFontNormalLarge', 'Fonts\\FRIZQT__.TTF', 16, '', 1, 0.82, 0)
fontObject('ChatFontNormal', 'Fonts\\ARIALN.TTF', 14, '', 1, 1, 1)
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'

-- Tooltip: drawn by the page as one box
local tipLines = {}
GameTooltip = { __name = 'GameTooltip', __shown = false }
function GameTooltip:SetOwner(owner, anchor, x, y) tipLines = {}; self.__owner = owner; self.__anchor = anchor or 'ANCHOR_RIGHT'; self.__x, self.__y = x or 0, y or 0 end
function GameTooltip:ClearLines() tipLines = {} end
function GameTooltip:SetText(t, r, g, b, a, wrap) tipLines = { { tostring(t or ''), r or 1, g or 0.82, b or 0, wrap and true or false } } end
function GameTooltip:AddLine(t, r, g, b, wrap) tipLines[#tipLines + 1] = { tostring(t or ''), r or 1, g or 0.82, b or 0, wrap and true or false } end
function GameTooltip:AddDoubleLine(l, rt, lr, lg, lb, rr, rg, rb) tipLines[#tipLines + 1] = { tostring(l or ''), lr or 1, lg or 0.82, lb or 0, false, tostring(rt or ''), rr or 1, rg or 1, rb or 1 } end
function GameTooltip:NumLines() return #tipLines end
function GameTooltip:Show()
  self.__shown = true
  local o = self.__owner
  local parts = {}
  for _, l in ipairs(tipLines) do parts[#parts + 1] = table.concat({ l[1], l[2], l[3], l[4], l[5] and 1 or 0, l[6] or '', l[7] or 1, l[8] or 1, l[9] or 1 }, '\31') end
  N.tip(o and o.__id or 0, self.__anchor or 'ANCHOR_RIGHT', table.concat(parts, '\30'))
end
function GameTooltip:Hide() self.__shown = false; N.tip(0, '', '') end
function GameTooltip:IsShown() return self.__shown end
function GameTooltip:IsOwned(f) return self.__owner == f end
function GameTooltip:GetOwner() return self.__owner end
function GameTooltip:SetMinimumWidth() end
function GameTooltip:SetPadding() end

-- Plain game functions
function GetTime() return N.now() end
function GetServerTime() return floor(N.epoch()) end
function GetScreenWidth() local _, _, w = N.rect(UIParent.__id); return w end
function GetScreenHeight() local _, _, _, h = N.rect(UIParent.__id); return h end
function GetCursorPosition() return N.cursor() end
function IsShiftKeyDown() return N.mod('shift') end
function IsControlKeyDown() return N.mod('ctrl') end
function IsAltKeyDown() return N.mod('alt') end
function IsModifierKeyDown() return N.mod('shift') or N.mod('ctrl') or N.mod('alt') end
function GetLocale() return 'enUS' end
function GetBuildInfo() return '1.60.1', 'web', 'web', 16001 end
function InCombatLockdown() return false end
function issecretvalue() return false end
function debugprofilestop() return N.now() * 1000 end
function PlaySound(kit, channel) N.sound(tostring(kit)); return true end
function PlaySoundFile(path, channel) N.soundFile(tostring(path)); return true end
function StopSound() end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGB = function(c) return c.r, c.g, c.b end, GetRGBA = function(c) return c.r, c.g, c.b, c.a end } end
function wipe(t) for k in pairs(t) do t[k] = nil end; return t end
table.wipe = wipe
tinsert, tremove, format, strrep, strsub, strlen, strupper, strlower, strfind, strmatch, gsub = table.insert, table.remove, string.format, string.rep, string.sub, string.len, string.upper, string.lower, string.find, string.match, string.gsub
floor, ceil, abs, max, min, sqrt, random = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.random
function strtrim(s, chars) chars = chars or ' \t\r\n'; local p = '[' .. chars:gsub('%p', '%%%0') .. ']'; return (s:gsub('^' .. p .. '+', ''):gsub(p .. '+$', '')) end
function strsplit(sep, s, limit)
  local out, start = {}, 1
  while true do
    local i, j = string.find(s, sep, start, true)
    if not i or (limit and #out == limit - 1) then out[#out + 1] = string.sub(s, start); break end
    out[#out + 1] = string.sub(s, start, i - 1); start = j + 1
  end
  return unpack(out)
end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function Mixin(o, ...) for i = 1, select('#', ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end; return o end
function CreateFromMixins(...) return Mixin({}, ...) end
function CopyTable(t) local c = {}; for k, v in pairs(t) do c[k] = type(v) == 'table' and CopyTable(v) or v end; return c end
function hooksecurefunc(a, b, c)
  local t, name, fn = _G, a, b
  if type(a) == 'table' then t, name, fn = a, b, c end
  local old = t[name]; t[name] = function(...) local r = { old(...) }; fn(...); return unpack(r) end
end
SlashCmdList = {}
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) N.chat(tostring(m)) end }
function print(...) local t = {}; for i = 1, select('#', ...) do t[i] = tostring((select(i, ...))) end; N.chat(table.concat(t, ' ')) end
C_Timer = {}
local timers = {}
function C_Timer.After(sec, fn) num(sec, 'C_Timer.After'); timers[#timers + 1] = { at = N.now() + sec, fn = fn } end
function C_Timer.NewTicker(sec, fn, n)
  local t = { every = sec, fn = fn, left = n, at = N.now() + sec }
  function t:Cancel() self.cancelled = true end
  function t:IsCancelled() return self.cancelled end
  timers[#timers + 1] = t
  return t
end
function C_Timer.NewTimer(sec, fn) return C_Timer.NewTicker(sec, fn, 1) end
C_AddOns = { GetAddOnMetadata = function(addon, field) return N.meta(field) end, IsAddOnLoaded = function() return true end }
C_Spell = { GetSpellTexture = function(id) return id and ('spell:' .. tostring(id)) or nil end }
C_Item = { GetItemIconByID = function(id) return id and ('item:' .. tostring(id)) or nil end }

-- Called by the page --------------------------------------------------------------------------------------------
local function handler(err) return tostring(err) .. '\n' .. debug.traceback('', 2) end
local function call(fn, ...)
  local ok, err = xpcall(fn, handler, ...)
  if not ok then N.err(err) end
end
local function cpcall(fn, ...) if fn then call(fn, ...) end end

function __webEvent(event, ...)
  local list = {}
  for id = 1, nextId do local o = objects[id]; if o and o.__events and o.__events[event] then list[#list + 1] = o end end
  for _, o in ipairs(list) do local s = o.__scripts and o.__scripts.OnEvent; if s then call(s, o, event, ...) end end
end
function __webTick(elapsed)
  local now = N.now()
  local due = {}
  for i = #timers, 1, -1 do
    local t = timers[i]
    if t.cancelled then table.remove(timers, i)
    elseif now >= t.at then
      due[#due + 1] = t
      if t.every and (t.left == nil or t.left > 1) then t.at = now + t.every; if t.left then t.left = t.left - 1 end else table.remove(timers, i) end
    end
  end
  for i = #due, 1, -1 do local t = due[i]; if t.every then cpcall(t.fn, t) else cpcall(t.fn) end end
  local list = {}
  for id = 1, nextId do local o = scripted[id]; if o and isVisible(o) then list[#list + 1] = o end end
  for _, o in ipairs(list) do local s = o.__scripts and o.__scripts.OnUpdate; if s then call(s, o, elapsed) end end
end
-- mouse and keys, from the page: the object id, the script, its arguments
function __webScript(id, name, a, b)
  local o = objects[id]
  if not o or not isVisible(o) then return false end
  if name == 'OnClick' then
    if o.__type ~= 'Button' then return false end
    if not (o.__clicks[a .. 'Up'] or o.__clicks.AnyUp) then return false end
    call(o.__click, o, a, false)
    return true
  end
  local s = o.__scripts and o.__scripts[name]
  if s then call(s, o, a, b); return true end
  return false
end
function __webVisible(id) local o = objects[id]; return o ~= nil and isVisible(o) end
function __webIsButton(id) local o = objects[id]; return o ~= nil and o.__type == 'Button' end
-- Saved variables: written as Lua and read back with load()
local function ser(v, ind)
  local t = type(v)
  if t == 'number' then return string.format('%.17g', v) end
  if t == 'string' then return string.format('%q', v) end
  if t == 'boolean' then return tostring(v) end
  if t ~= 'table' then return 'nil' end
  local out, ind2 = { '{\n' }, ind .. ' '
  for k, x in pairs(v) do
    local tk = type(k)
    if (tk == 'string' or tk == 'number') and type(x) ~= 'function' then
      out[#out + 1] = ind2 .. '[' .. ser(k, ind2) .. '] = ' .. ser(x, ind2) .. ',\n'
    end
  end
  out[#out + 1] = ind .. '}'
  return table.concat(out)
end
function __webSave(names)
  local out = {}
  for name in string.gmatch(names, '[^,%s]+') do out[#out + 1] = name .. ' = ' .. ser(_G[name], '') end
  return table.concat(out, '\n')
end
function __webLoadSaved(src)
  local f = load(src, '=saved variables')
  if f then pcall(f) end
end
