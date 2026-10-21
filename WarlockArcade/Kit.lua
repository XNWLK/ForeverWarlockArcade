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
  bg = { 0.035, 0.028, 0.055 }, panel = { 0.085, 0.07, 0.125 }, panel2 = { 0.125, 0.1, 0.18 }, line = { 0.3, 0.25, 0.42 },
  text = { 0.96, 0.94, 0.98 }, dim = { 0.66, 0.62, 0.76 }, faint = { 0.44, 0.4, 0.54 },
  gold = { 1, 0.8, 0.28 }, shadow = { 0.7, 0.5, 1 }, fel = { 0.55, 1, 0.35 }, fire = { 1, 0.52, 0.2 }, flame = { 1, 0.8, 0.3 },
  chips = { 0.3, 0.64, 1 }, mult = { 1, 0.34, 0.3 }, good = { 0.4, 0.95, 0.5 }, bad = { 1, 0.36, 0.36 },
  accent = { 0.62, 0.42, 1 },
}

local floor, format, min, max = math.floor, string.format, math.min, math.max

-- ---- shapes: rounded panels drawn by one sliced texture (see tools/gen-media.js) ----
-- rr<R>: a filled rounded rectangle, rl<R>_<W>: its outline, shadow: a soft blur reaching 20 past the panel
function K.shape(parent, layer, name, sub)
  local t = parent:CreateTexture(nil, layer or 'BACKGROUND', nil, sub)
  t:SetTexture(K.MEDIA .. name)
  local m = name == 'shadow' and 24 or tonumber(name:match('^r[rl](%d+)'))
  if m then t:SetTextureSliceMargins(m, m, m, m) end
  return t
end
-- the corner radius that suits a box this big
function K.radiusFor(w, h)
  local m = min(w or 999, h or 999)
  return m < 24 and 4 or m < 64 and 6 or 10
end
-- a soft shadow under a frame (drawn from the frame's own BACKGROUND layer, below its fill)
function K.shadow(f, alpha, drop)
  local s = K.shape(f, 'BACKGROUND', 'shadow', -8)
  drop = drop or 4
  s:SetPoint('TOPLEFT', -20, 20 - drop); s:SetPoint('BOTTOMRIGHT', 20, -20 - drop)
  s:SetVertexColor(0, 0, 0, alpha or 0.55)
  f.shadowTex = s
  return s
end
-- a two-colour vertical fill: a touch lighter at the top
function K.fill(t, r, g, b, a)
  a = a or 1
  t:SetGradient('VERTICAL', CreateColor(r * 0.82, g * 0.82, b * 0.82, a), CreateColor(min(1, r * 1.15 + 0.015), min(1, g * 1.15 + 0.015), min(1, b * 1.15 + 0.02), a))
end

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

-- a frame with a rounded, softly lit fill and an outline `edge` (1 or 2) wide; radius picked from the size unless given
function K.box(parent, w, h, bg, border, edge, kind, radius)
  local f = CreateFrame(kind or 'Frame', nil, parent)
  if w then f:SetWidth(w) end
  if h then f:SetHeight(h) end
  local r = radius or K.radiusFor(w, h)
  f.radius = r
  f.bg = K.shape(f, 'BACKGROUND', 'rr' .. r, 0)
  f.bg:SetAllPoints()
  f.line = K.shape(f, 'BORDER', 'rl' .. r .. '_' .. ((edge or 1) >= 2 and 2 or 1), 0)
  f.line:SetAllPoints()
  if edge == 0 then f.line:Hide() end
  f.SetBorderColor = K.setBorder
  f.SetFill = K.setFill
  local c = bg or K.C.panel
  f:SetFill(c[1], c[2], c[3], c[4] or 1)
  local bc = border or K.C.line
  f:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
  -- big panels get a shadow and fade in when they appear
  if (w or 0) * (h or 0) >= 150 * 150 and kind ~= 'Button' then
    K.shadow(f, 0.5)
    f:HookScript('OnShow', function(self) K.fadeIn(self, 0.14) end)
  end
  return f
end
function K.setBorder(f, r, g, b, a) f.line:SetVertexColor(r, g, b, a or 1) end
function K.setFill(f, r, g, b, a) K.fill(f.bg, r, g, b, a) end

-- button styles: fill colour, border, text colour
K.STYLES = {
  normal = { { 0.17, 0.135, 0.25 }, { 0.42, 0.34, 0.58 }, K.C.text },
  blue = { { 0.12, 0.34, 0.7 }, { 0.42, 0.66, 1 }, { 1, 1, 1 } },
  red = { { 0.66, 0.16, 0.16 }, { 1, 0.45, 0.4 }, { 1, 1, 1 } },
  orange = { { 0.82, 0.4, 0.08 }, { 1, 0.72, 0.34 }, { 1, 1, 1 } },
  green = { { 0.18, 0.52, 0.2 }, { 0.5, 0.95, 0.45 }, { 1, 1, 1 } },
  gold = { { 0.62, 0.46, 0.1 }, { 1, 0.85, 0.4 }, { 1, 1, 1 } },
  ghost = { { 0.09, 0.075, 0.135 }, { 0.28, 0.23, 0.4 }, K.C.dim },
}
function K.button(parent, w, h, label, onClick, style, size)
  local b = K.box(parent, w, h, nil, nil, 1, 'Button')
  -- a glow in the style's colour while the mouse is over it
  b.glow = K.shape(b, 'BACKGROUND', 'shadow', -7)
  b.glow:SetPoint('TOPLEFT', -20, 20); b.glow:SetPoint('BOTTOMRIGHT', 20, -20)
  b.glow:SetAlpha(0)
  b.label = K.text(b, size or 13, nil, 'CENTER')
  b.label:SetPoint('CENTER', 0, 0)
  b.label:SetText(label or '')
  b.hl = K.shape(b, 'HIGHLIGHT', 'rr' .. b.radius)
  b.hl:SetAllPoints()
  b.hl:SetVertexColor(1, 1, 1, 0.07)
  b.hl:Hide()
  b.SetLabel = function(self, t) self.label:SetText(t) end
  b.SetStyle = K.styleButton
  b:SetStyle(style or 'normal')
  b:SetScript('OnEnter', function(self)
    if self:IsEnabled() then self.hl:Show(); K.tween(self.glow, 0.12, function(f) self.glow:SetAlpha(0.55 * f) end) end
    if self.tipFn then K.showTip(self, self.tipFn(self)) end
  end)
  b:SetScript('OnLeave', function(self)
    self.hl:Hide()
    local a = self.glow:GetAlpha()
    K.tween(self.glow, 0.18, function(f) self.glow:SetAlpha(a * (1 - f)) end)
    if self.tipFn then GameTooltip:Hide() end
  end)
  b:SetScript('OnMouseDown', function(self) if self:IsEnabled() then self.label:SetPoint('CENTER', 0, -1); self.bg:SetAlpha(0.8) end end)
  b:SetScript('OnMouseUp', function(self) self.label:SetPoint('CENTER', 0, 0); self.bg:SetAlpha(1) end)
  b:SetScript('OnEnable', function(self) self:SetStyle(self.style) end)
  b:SetScript('OnDisable', function(self) self:SetStyle(self.style); self.hl:Hide(); self.glow:SetAlpha(0) end)
  if onClick then b:SetScript('OnClick', function(self, button) A.sound('click'); onClick(self, button) end) end
  return b
end
function K.styleButton(b, style)
  b.style = style
  local s = K.STYLES[style] or K.STYLES.normal
  local on = b:IsEnabled()
  local m = on and 1 or 0.45
  b:SetFill(s[1][1] * m, s[1][2] * m, s[1][3] * m, 1)
  b:SetBorderColor(s[2][1] * m, s[2][2] * m, s[2][3] * m, on and 0.9 or 0.5)
  b.glow:SetVertexColor(s[2][1], s[2][2], s[2][3], 1)
  local t = on and s[3] or K.C.faint
  b.label:SetTextColor(t[1], t[2], t[3], 1)
end

-- ---- motion: small tweens, run by the arcade window every frame (K.tick) ----
-- K.tween(key, seconds, fn(f, raw), done): fn gets 0..1 eased (and the plain 0..1); a new tween with the same key
-- replaces the old one
K.tweens = {}
local function ease(f) return 1 - (1 - f) * (1 - f) * (1 - f) end
function K.tween(key, dur, fn, done)
  K.tweens[key] = { t = 0, dur = max(0.001, dur), fn = fn, done = done }
  fn(0, 0)
end
local runKeys, runTweens = {}, {}
function K.tick(dt)
  -- a copy first: a tween's done() may start new tweens
  local n = 0
  for key, tw in pairs(K.tweens) do n = n + 1; runKeys[n] = key; runTweens[n] = tw end
  for i = 1, n do
    local key, tw = runKeys[i], runTweens[i]
    runKeys[i], runTweens[i] = nil, nil
    tw.t = tw.t + dt
    local f = min(1, tw.t / tw.dur)
    tw.fn(ease(f), f)
    if f >= 1 then
      if K.tweens[key] == tw then K.tweens[key] = nil end
      if tw.done then tw.done() end
    end
  end
end
function K.fadeIn(f, dur) K.tween(f, dur or 0.15, function(x) f:SetAlpha(x) end) end

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
