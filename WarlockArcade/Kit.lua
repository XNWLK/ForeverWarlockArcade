-- Small UI kit shared by the arcade and its games: colours, text, boxes, buttons, icons, tooltips, number formatting,
-- floating text and simple timed sequences. Uses only plain frames and textures, so it looks the same in the game and
-- on the web page.
local ADDON, A = ...
local K = {}
A.Kit = K

K.FONT = 'Fonts\\FRIZQT__.TTF'
K.FONT_NUM = 'Fonts\\ARIALN.TTF'
K.FONT_TITLE = 'Fonts\\MORPHEUS.TTF'
K.WHITE = 'Interface\\Buttons\\WHITE8X8'
K.QUESTION = 'Interface\\Icons\\INV_Misc_QuestionMark'
K.MEDIA = 'Interface\\AddOns\\' .. ADDON .. '\\Media\\'

K.C = {
  bg = { 0.055, 0.04, 0.075 }, panel = { 0.1, 0.075, 0.13 }, panel2 = { 0.14, 0.11, 0.18 }, line = { 0.32, 0.25, 0.42 },
  text = { 0.95, 0.92, 0.86 }, dim = { 0.62, 0.58, 0.68 }, faint = { 0.42, 0.38, 0.48 },
  gold = { 1, 0.82, 0.2 }, shadow = { 0.66, 0.45, 1 }, fel = { 0.55, 0.95, 0.25 }, fire = { 1, 0.5, 0.16 }, flame = { 1, 0.8, 0.25 },
  chips = { 0.22, 0.58, 1 }, mult = { 1, 0.3, 0.26 }, good = { 0.35, 0.9, 0.4 }, bad = { 1, 0.3, 0.3 },
}

local floor, format = math.floor, string.format

-- 1234567 -> "1,234,567"; works with the game's floats and the web page's Lua alike (never prints "3.0")
function K.num(n)
  n = tonumber(n) or 0
  local neg = n < 0
  if neg then n = -n end
  if n >= 1e15 then return format('%.3e', n) end
  local s = format('%.0f', floor(n + 0.5))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (neg and '-' or '') .. out
end
-- 1.5 -> "1.5", 2 -> "2"
function K.dec(n, places)
  local s = format('%.' .. (places or 2) .. 'f', n)
  s = s:gsub('0+$', ''):gsub('%.$', '')
  return s
end
function K.hex(c) return format('|cff%02x%02x%02x', floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5)) end
function K.paint(c, s) return K.hex(c) .. s .. '|r' end

function K.text(parent, size, color, justify, font, flags, layer)
  local fs = parent:CreateFontString(nil, layer or 'OVERLAY')
  fs:SetFont(font or K.FONT, size or 12, flags or '')
  local c = color or K.C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH(justify or 'CENTER')
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  return fs
end

function K.rect(parent, layer, c, a, sub)
  local t = parent:CreateTexture(nil, layer or 'BACKGROUND', nil, sub)
  t:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
  return t
end

-- a frame with a filled background and a border of `edge` units
function K.box(parent, w, h, bg, border, edge, kind)
  local f = CreateFrame(kind or 'Frame', nil, parent)
  if w then f:SetWidth(w) end
  if h then f:SetHeight(h) end
  f.bg = K.rect(f, 'BACKGROUND', bg or K.C.panel, nil, 0)
  f.bg:SetAllPoints()
  edge = edge or 1
  f.edges = {}
  local bc = border or K.C.line
  for i = 1, 4 do
    local t = K.rect(f, 'BORDER', bc, nil, 0)
    f.edges[i] = t
  end
  local e = f.edges
  e[1]:SetPoint('TOPLEFT'); e[1]:SetPoint('TOPRIGHT'); e[1]:SetHeight(edge)
  e[2]:SetPoint('BOTTOMLEFT'); e[2]:SetPoint('BOTTOMRIGHT'); e[2]:SetHeight(edge)
  e[3]:SetPoint('TOPLEFT'); e[3]:SetPoint('BOTTOMLEFT'); e[3]:SetWidth(edge)
  e[4]:SetPoint('TOPRIGHT'); e[4]:SetPoint('BOTTOMRIGHT'); e[4]:SetWidth(edge)
  f.SetBorderColor = K.setBorder
  f.SetFill = K.setFill
  return f
end
function K.setBorder(f, r, g, b, a) for i = 1, 4 do f.edges[i]:SetColorTexture(r, g, b, a or 1) end end
function K.setFill(f, r, g, b, a) f.bg:SetColorTexture(r, g, b, a or 1) end

-- button styles: fill colour, border, text colour
K.STYLES = {
  normal = { { 0.2, 0.15, 0.27 }, { 0.45, 0.36, 0.58 }, K.C.text },
  blue = { { 0.1, 0.33, 0.62 }, { 0.32, 0.6, 0.95 }, { 1, 1, 1 } },
  red = { { 0.6, 0.14, 0.12 }, { 0.95, 0.38, 0.32 }, { 1, 1, 1 } },
  orange = { { 0.72, 0.38, 0.06 }, { 1, 0.66, 0.25 }, { 1, 1, 1 } },
  green = { { 0.16, 0.45, 0.16 }, { 0.42, 0.85, 0.36 }, { 1, 1, 1 } },
  gold = { { 0.55, 0.42, 0.08 }, { 1, 0.82, 0.3 }, { 1, 1, 1 } },
  ghost = { { 0.1, 0.075, 0.13 }, { 0.3, 0.24, 0.38 }, K.C.dim },
}
function K.button(parent, w, h, label, onClick, style, size)
  local b = K.box(parent, w, h, nil, nil, 1, 'Button')
  b.label = K.text(b, size or 13, nil, 'CENTER')
  b.label:SetPoint('CENTER', 0, 0)
  b.label:SetText(label or '')
  b.hl = K.rect(b, 'HIGHLIGHT', { 1, 1, 1 }, 0.08)
  b.hl:SetAllPoints()
  b.hl:Hide()
  b.SetLabel = function(self, t) self.label:SetText(t) end
  b.SetStyle = K.styleButton
  b:SetStyle(style or 'normal')
  b:SetScript('OnEnter', function(self) if self:IsEnabled() then self.hl:Show() end; if self.tipFn then K.showTip(self, self.tipFn(self)) end end)
  b:SetScript('OnLeave', function(self) self.hl:Hide(); if self.tipFn then GameTooltip:Hide() end end)
  b:SetScript('OnMouseDown', function(self) if self:IsEnabled() then self.label:SetPoint('CENTER', 1, -1) end end)
  b:SetScript('OnMouseUp', function(self) self.label:SetPoint('CENTER', 0, 0) end)
  b:SetScript('OnEnable', function(self) self:SetStyle(self.style) end)
  b:SetScript('OnDisable', function(self) self:SetStyle(self.style); self.hl:Hide() end)
  if onClick then b:SetScript('OnClick', function(self, button) A.sound('click'); onClick(self, button) end) end
  return b
end
function K.styleButton(b, style)
  b.style = style
  local s = K.STYLES[style] or K.STYLES.normal
  local on = b:IsEnabled()
  local m = on and 1 or 0.45
  b:SetFill(s[1][1] * m, s[1][2] * m, s[1][3] * m, 1)
  b:SetBorderColor(s[2][1] * m, s[2][2] * m, s[2][3] * m, 1)
  local t = on and s[3] or K.C.faint
  b.label:SetTextColor(t[1], t[2], t[3], 1)
end

function K.spellTexture(id)
  local t = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
  return t or K.QUESTION
end
function K.itemTexture(id)
  local t = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  return t or K.QUESTION
end
function K.icon(parent, size, spellId, layer)
  local t = parent:CreateTexture(nil, layer or 'ARTWORK')
  t:SetSize(size, size)
  t:SetTexture(K.spellTexture(spellId))
  t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return t
end

-- tooltip from a list: { title, {text, colour, wrap} ... } or plain strings
function K.showTip(owner, lines, anchor)
  if not lines then return end
  GameTooltip:SetOwner(owner, anchor or 'ANCHOR_RIGHT')
  for i, l in ipairs(lines) do
    local t, c, wrap = l, nil, true
    if type(l) == 'table' then t, c, wrap = l[1], l[2], l[3] ~= false end
    c = c or (i == 1 and { 1, 1, 1 } or K.C.gold)
    if i == 1 then GameTooltip:SetText(t, c[1], c[2], c[3], 1, true) else GameTooltip:AddLine(t, c[1], c[2], c[3], wrap) end
  end
  GameTooltip:Show()
end
function K.tip(frame, fn, anchor)
  frame:EnableMouse(true)
  frame:HookScript('OnEnter', function(self) K.showTip(self, fn(self), anchor) end)
  frame:HookScript('OnLeave', function() GameTooltip:Hide() end)
end

-- Floating text that rises and fades; a small pool per parent
function K.popups(parent)
  local P = { parent = parent, list = {} }
  function P:show(text, x, y, color, size, life)
    local p
    for _, q in ipairs(self.list) do if not q.on then p = q; break end end
    if not p then
      p = { fs = K.text(self.parent, size or 18, nil, 'CENTER', K.FONT, 'OUTLINE') }
      self.list[#self.list + 1] = p
    end
    p.fs:SetFont(K.FONT, size or 18, 'OUTLINE')
    local c = color or K.C.text
    p.fs:SetTextColor(c[1], c[2], c[3], 1)
    p.fs:SetText(text)
    p.x, p.y, p.t, p.life, p.on = x, y, 0, life or 0.9, true
    p.fs:ClearAllPoints(); p.fs:SetPoint('CENTER', self.parent, 'BOTTOMLEFT', x, y); p.fs:SetAlpha(1); p.fs:Show()
  end
  function P:update(dt)
    for _, p in ipairs(self.list) do
      if p.on then
        p.t = p.t + dt
        local f = p.t / p.life
        if f >= 1 then p.on = false; p.fs:Hide()
        else
          p.fs:SetPoint('CENTER', self.parent, 'BOTTOMLEFT', p.x, p.y + 28 * f)
          p.fs:SetAlpha(f < 0.6 and 1 or (1 - f) / 0.4)
        end
      end
    end
  end
  function P:clear() for _, p in ipairs(self.list) do p.on = false; p.fs:Hide() end end
  return P
end

-- A timed list of steps: seq:add(delay, fn) runs fn `delay` seconds after the previous step.
function K.sequence()
  local S = { steps = {}, t = 0, speed = 1 }
  function S:add(delay, fn) self.steps[#self.steps + 1] = { delay, fn } end
  function S:busy() return #self.steps > 0 end
  function S:update(dt)
    self.t = self.t + dt * self.speed
    while self.steps[1] and self.t >= self.steps[1][1] do
      local s = table.remove(self.steps, 1)
      self.t = self.t - s[1]
      s[2]()
    end
    if not self.steps[1] then self.t = 0 end
  end
  function S:finish() while self.steps[1] do local s = table.remove(self.steps, 1); s[2]() end; self.t = 0 end
  function S:clear() self.steps = {}; self.t = 0 end
  return S
end

function K.lerp(a, b, f) return a + (b - a) * f end
function K.shuffle(t) for i = #t, 2, -1 do local j = math.random(1, i); t[i], t[j] = t[j], t[i] end; return t end
function K.copy(t) local c = {}; for k, v in pairs(t) do c[k] = type(v) == 'table' and K.copy(v) or v end; return c end
