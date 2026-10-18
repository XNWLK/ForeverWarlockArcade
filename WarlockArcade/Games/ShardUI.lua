-- Shard & Mult: the screen. Draws the run that ShardRules.lua keeps and replays its reports as animations.
local ADDON, A = ...
local K, R = A.Kit, A.ShardRules
local floor, min, max, exp = math.floor, math.min, math.max, math.exp
local C = K.C

local G = {}   -- the game object (one per arcade window)
G.__index = G

local CW, CH = 76, 104            -- card size
local MAIN_X, MAIN_W = 228, 724   -- the play area right of the sidebar
local HAND_Y = -372               -- top of the hand row
local PLAY_Y = -196               -- top of the row where played cards score

local function cardIcon(c)
  if R.isDemon(c) then return A.PETS[R.DEMON[c.rank]].spell end
  return A.SPELLS[R.SUITS[c.suit].key].id
end
local function dark(c, f) f = f or 0.55; return { c[1] * f, c[2] * f, c[3] * f } end

-- ---------------------------------------------------------------------------------------------------------------
-- building
function G.create(parent)
  local g = setmetatable({}, G)
  g.f = CreateFrame('Frame', nil, parent)
  g.f:SetAllPoints()
  g.db = A.db('shard')
  g.seq = K.sequence()
  g.cards, g.selected, g.selOrder = {}, {}, {}
  g.speed = A.db().speed or 1
  g:buildSidebar()
  g:buildTop()
  g:buildHandArea()
  g:buildPanels()
  g.pop = K.popups(g.f)
  g.f:Hide()
  if g.db.run then
    g.run = g.db.run
    g:relink()
  end
  return g
end

function G:buildSidebar()
  local f = self.f
  local S = {}
  self.side = S
  local x, w = 8, 210
  -- blind
  S.blind = K.box(f, w, 124, C.panel, C.line, 1)
  S.blind:SetPoint('TOPLEFT', x, -8)
  S.blindName = K.text(S.blind, 15, C.gold, 'CENTER')
  S.blindName:SetPoint('TOP', 0, -8)
  S.blindSpell = K.text(S.blind, 12, C.bad, 'CENTER')
  S.blindSpell:SetPoint('TOP', S.blindName, 'BOTTOM', 0, -3)
  S.blindText = K.text(S.blind, 11, C.dim, 'CENTER')
  S.blindText:SetPoint('TOPLEFT', 8, -44); S.blindText:SetPoint('TOPRIGHT', -8, -44)
  S.blindText:SetWordWrap(true); S.blindText:SetJustifyV('TOP')
  S.healthLabel = K.text(S.blind, 11, C.dim, 'LEFT')
  S.healthLabel:SetPoint('BOTTOMLEFT', 8, 8)
  S.healthLabel:SetText('Health')
  S.health = K.text(S.blind, 18, C.bad, 'RIGHT', K.FONT_NUM)
  S.health:SetPoint('BOTTOMRIGHT', -8, 6)
  -- damage dealt
  S.score = K.box(f, w, 58, C.panel, C.line, 1)
  S.score:SetPoint('TOPLEFT', S.blind, 'BOTTOMLEFT', 0, -6)
  S.bar = K.rect(S.score, 'BORDER', { 0.5, 0.12, 0.12 }, 0.55, 1)
  S.bar:SetPoint('TOPLEFT', 1, -1); S.bar:SetPoint('BOTTOMLEFT', 1, 1); S.bar:SetWidth(1)
  S.scoreLabel = K.text(S.score, 11, C.dim, 'LEFT')
  S.scoreLabel:SetPoint('TOPLEFT', 8, -6)
  S.scoreLabel:SetText('Damage dealt')
  S.scoreNum = K.text(S.score, 24, C.text, 'RIGHT', K.FONT_NUM)
  S.scoreNum:SetPoint('BOTTOMRIGHT', -8, 6)
  -- hand: name, level, chips x mult
  S.hand = K.box(f, w, 90, C.panel, C.line, 1)
  S.hand:SetPoint('TOPLEFT', S.score, 'BOTTOMLEFT', 0, -6)
  S.handName = K.text(S.hand, 15, C.text, 'CENTER')
  S.handName:SetPoint('TOP', 0, -8)
  S.chipsBox = K.box(S.hand, 88, 40, dark(C.chips, 0.45), C.chips, 1)
  S.chipsBox:SetPoint('BOTTOMLEFT', 8, 8)
  S.chips = K.text(S.chipsBox, 22, { 1, 1, 1 }, 'CENTER', K.FONT_NUM)
  S.chips:SetPoint('CENTER')
  S.multBox = K.box(S.hand, 88, 40, dark(C.mult, 0.45), C.mult, 1)
  S.multBox:SetPoint('BOTTOMRIGHT', -8, 8)
  S.mult = K.text(S.multBox, 22, { 1, 1, 1 }, 'CENTER', K.FONT_NUM)
  S.mult:SetPoint('CENTER')
  S.x = K.text(S.hand, 20, C.bad, 'CENTER', K.FONT_NUM)
  S.x:SetPoint('BOTTOM', 0, 16)
  S.x:SetText('x')
  -- hands, discards
  local function counter(label, color, anchor, dx)
    local b = K.box(f, (w - 6) / 2, 52, C.panel, C.line, 1)
    b:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', dx, -6)
    b.label = K.text(b, 11, C.dim, 'CENTER'); b.label:SetPoint('TOP', 0, -6); b.label:SetText(label)
    b.num = K.text(b, 22, color, 'CENTER', K.FONT_NUM); b.num:SetPoint('BOTTOM', 0, 6)
    return b
  end
  S.hands = counter('Hands', C.chips, S.hand, 0)
  S.discards = counter('Discards', C.mult, S.hand, (w + 6) / 2)
  S.gold = counter('Gold', C.gold, S.hands, 0)
  S.ante = counter('Ante', C.flame, S.hands, (w + 6) / 2)
  S.ante.label:SetText('Ante')
  -- buttons
  S.levels = K.button(f, (w - 6) / 2, 28, 'Hands info', function() self:togglePanel('levels') end, 'normal', 12)
  S.levels:SetPoint('TOPLEFT', S.gold, 'BOTTOMLEFT', 0, -8)
  S.speed = K.button(f, (w - 6) / 2, 28, '', function() self:cycleSpeed() end, 'normal', 12)
  S.speed:SetPoint('TOPLEFT', S.levels, 'TOPRIGHT', 6, 0)
  S.speed.tipFn = function() return { 'Animation speed', 'How fast scoring is played out. Space or Enter during scoring skips ahead.' } end
  S.newRun = K.button(f, w, 28, 'New run', function() self:confirmNewRun() end, 'ghost', 12)
  S.newRun:SetPoint('TOPLEFT', S.levels, 'BOTTOMLEFT', 0, -6)
  S.deck = K.text(f, 12, C.dim, 'LEFT')
  S.deck:SetPoint('BOTTOMLEFT', x + 2, 12)
  K.tip(self:deckHitbox(), function() return self:deckTip() end, 'ANCHOR_TOP')
end
function G:deckHitbox()
  local h = CreateFrame('Frame', nil, self.f)
  h:SetPoint('BOTTOMLEFT', 8, 6)
  h:SetSize(210, 24)
  return h
end

function G:buildTop()
  local f = self.f
  self.talentSlots, self.itemSlots = {}, {}
  local label = K.text(f, 11, C.dim, 'LEFT')
  label:SetPoint('TOPLEFT', MAIN_X, -6)
  self.talentLabel = label
  for i = 1, 5 do
    local s = self:makeSlot(f, 'talent', i)
    s:SetPoint('TOPLEFT', MAIN_X + (i - 1) * (CW + 8), -22)
    self.talentSlots[i] = s
  end
  local ilabel = K.text(f, 11, C.dim, 'RIGHT')
  ilabel:SetPoint('TOPRIGHT', f, 'TOPLEFT', MAIN_X + MAIN_W, -6)
  self.itemLabel = ilabel
  for i = 1, 2 do
    local s = self:makeSlot(f, 'item', i)
    s:SetPoint('TOPLEFT', f, 'TOPLEFT', MAIN_X + MAIN_W - CW - (2 - i) * (CW + 8), -22)
    self.itemSlots[i] = s
  end
  -- the button under a picked talent / consumable: sell or use
  self.slotAction = K.button(f, CW, 22, 'Sell', function() self:slotActionClick() end, 'gold', 11)
  self.slotAction2 = K.button(f, CW, 22, 'Use', function() self:slotUseClick() end, 'blue', 11)
  self.slotAction:Hide(); self.slotAction2:Hide()
end

-- a talent / consumable / shop card
function G:makeSlot(parent, kind, i)
  local s = K.box(parent, CW, CH, { 0.08, 0.06, 0.1 }, C.line, 1, 'Button')
  s.kind, s.i = kind, i
  s.empty = K.text(s, 10, C.faint, 'CENTER')
  s.empty:SetPoint('CENTER')
  s.icon = s:CreateTexture(nil, 'ARTWORK')
  s.icon:SetSize(46, 46)
  s.icon:SetPoint('TOP', 0, -10)
  s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  s.name = K.text(s, 10, C.text, 'CENTER')
  s.name:SetPoint('TOPLEFT', 3, -62); s.name:SetPoint('TOPRIGHT', -3, -62)
  s.name:SetWordWrap(true); s.name:SetJustifyV('TOP')
  s.big = K.text(s, 13, C.text, 'CENTER')
  s.big:SetPoint('TOPLEFT', 4, -30); s.big:SetPoint('TOPRIGHT', -4, -30)
  s.big:SetWordWrap(true)
  s.pick = K.rect(s, 'OVERLAY', C.gold, 0, 1)
  s.pick:SetPoint('BOTTOMLEFT', 0, 0); s.pick:SetPoint('BOTTOMRIGHT', 0, 0); s.pick:SetHeight(3)
  s:SetScript('OnEnter', function(b) self:slotTip(b) end)
  s:SetScript('OnLeave', function() GameTooltip:Hide() end)
  s:SetScript('OnClick', function(b) self:slotClick(b) end)
  return s
end

function G:buildHandArea()
  local f = self.f
  self.handArea = CreateFrame('Frame', nil, f)
  self.handArea:SetPoint('TOPLEFT', MAIN_X, -140)
  self.handArea:SetSize(MAIN_W, 400)
  self.message = K.text(f, 15, C.dim, 'CENTER')
  self.message:SetPoint('TOP', f, 'TOPLEFT', MAIN_X + MAIN_W / 2, -150)
  self.damage = K.text(f, 30, C.gold, 'CENTER', K.FONT_NUM, 'OUTLINE')
  self.damage:SetPoint('TOP', f, 'TOPLEFT', MAIN_X + MAIN_W / 2, PLAY_Y - CH - 18)
  local bw, y = 150, -526
  self.play = K.button(f, bw, 40, 'Play hand', function() self:playSelected() end, 'blue', 15)
  self.play:SetPoint('TOPLEFT', MAIN_X + 80, y)
  self.sortRank = K.button(f, 92, 32, 'Sort: rank', function() self:sort('rank') end, 'ghost', 12)
  self.sortRank:SetPoint('TOPLEFT', self.play, 'TOPRIGHT', 30, -4)
  self.sortSuit = K.button(f, 92, 32, 'Sort: suit', function() self:sort('suit') end, 'ghost', 12)
  self.sortSuit:SetPoint('TOPLEFT', self.sortRank, 'TOPRIGHT', 8, 0)
  self.discard = K.button(f, bw, 40, 'Discard', function() self:discardSelected() end, 'red', 15)
  self.discard:SetPoint('TOPLEFT', self.sortSuit, 'TOPRIGHT', 30, 4)
  self.play.tipFn = function() return { 'Play hand', 'Play the selected cards (1 to 5). Keys: Enter or Space.' } end
  self.discard.tipFn = function() return { 'Discard', 'Throw the selected cards away and draw new ones. Key: D' } end
  self.cardPool = {}
end

-- a playing card frame
function G:makeCard()
  local c = K.box(self.f, CW, CH, { 0.93, 0.89, 0.8 }, C.line, 2, 'Button')
  c:SetFrameLevel(self.f:GetFrameLevel() + 10)
  c:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  c.inner = K.rect(c, 'BORDER', { 0, 0, 0 }, 0, 2)
  c.inner:SetPoint('TOPLEFT', 2, -2); c.inner:SetPoint('BOTTOMRIGHT', -2, 2)
  c.rank = K.text(c, 21, C.text, 'LEFT', K.FONT_NUM)
  c.rank:SetPoint('TOPLEFT', 6, -4)
  c.rank:SetShadowOffset(0, 0)
  c.rank2 = K.text(c, 12, C.text, 'RIGHT', K.FONT_NUM)
  c.rank2:SetPoint('BOTTOMRIGHT', -6, 4)
  c.rank2:SetShadowOffset(0, 0)
  c.iconBg = K.rect(c, 'ARTWORK', { 0, 0, 0 }, 0.85, 0)
  c.iconBg:SetSize(42, 42)
  c.iconBg:SetPoint('CENTER', 0, 2)
  c.icon = c:CreateTexture(nil, 'ARTWORK', nil, 1)
  c.icon:SetSize(38, 38)
  c.icon:SetPoint('CENTER', c.iconBg, 'CENTER')
  c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.suitIcon = c:CreateTexture(nil, 'ARTWORK', nil, 1)
  c.suitIcon:SetSize(12, 12)
  c.suitIcon:SetPoint('TOPLEFT', 5, -27)
  c.suitIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.suit = K.text(c, 9, C.text, 'LEFT')
  c.suit:SetPoint('BOTTOMLEFT', 5, 5)
  c.suit:SetShadowOffset(0, 0)
  c.badge = K.box(c, 34, 15, C.chips, { 0, 0, 0 }, 1)
  c.badge:SetPoint('TOPRIGHT', -3, -3)
  c.badgeText = K.text(c.badge, 10, { 1, 1, 1 }, 'CENTER', K.FONT_NUM)
  c.badgeText:SetPoint('CENTER')
  c.veil = K.rect(c, 'OVERLAY', { 0.55, 0, 0 }, 0.45, 2)
  c.veil:SetPoint('TOPLEFT', 2, -2); c.veil:SetPoint('BOTTOMRIGHT', -2, 2)
  c.veilText = K.text(c, 30, { 1, 0.25, 0.2 }, 'CENTER', K.FONT_NUM, 'OUTLINE')
  c.veilText:SetPoint('CENTER')
  c.veilText:SetText('X')
  c.x, c.y, c.tx, c.ty, c.a, c.ta = 0, 0, 0, 0, 1, 1
  c:SetScript('OnClick', function(b, button) self:cardClick(b, button) end)
  c:SetScript('OnEnter', function(b) self:cardTip(b) end)
  c:SetScript('OnLeave', function() GameTooltip:Hide() end)
  return c
end
function G:cardFrame(card)
  local fr = self.cards[card.id]
  if fr then return fr end
  fr = table.remove(self.cardPool) or self:makeCard()
  self.cards[card.id] = fr
  fr.card = card
  fr:Show()
  self:paintCard(fr)
  return fr
end
function G:releaseCard(id)
  local fr = self.cards[id]
  if not fr then return end
  self.cards[id] = nil
  fr:Hide()
  fr.card = nil
  self.cardPool[#self.cardPool + 1] = fr
end
function G:paintCard(fr)
  local card = fr.card
  local s = R.SUITS[card.suit]
  local dc = dark(s.color, 0.5)
  fr:SetBorderColor(s.color[1] * 0.8, s.color[2] * 0.8, s.color[3] * 0.8, 1)
  fr.rank:SetText(R.rankName(card.rank))
  fr.rank:SetTextColor(dc[1], dc[2], dc[3])
  fr.rank2:SetText(R.rankName(card.rank))
  fr.rank2:SetTextColor(dc[1], dc[2], dc[3])
  fr.icon:SetTexture(K.spellTexture(cardIcon(card)))
  fr.iconBg:SetColorTexture(s.color[1] * 0.35, s.color[2] * 0.35, s.color[3] * 0.35, 1)
  fr.suit:SetText(s.name)
  fr.suitIcon:SetTexture(K.spellTexture(A.SPELLS[s.key].id))
  fr.suit:SetTextColor(dc[1], dc[2], dc[3])
  local e = card.enh and R.ENH[card.enh]
  if e then
    fr.badge:Show()
    fr.badge:SetFill(e.color[1] * 0.7, e.color[2] * 0.7, e.color[3] * 0.7, 1)
    fr.badgeText:SetText(card.enh == 'spellstone' and '+30' or card.enh == 'oil' and '+4' or 'x2')
  else fr.badge:Hide() end
  local deb = self.run and self.run.blind and R.debuffed(self.run.blind, card)
  fr.veil:SetShown(deb and true or false); fr.veilText:SetShown(deb and true or false)
end

function G:buildPanels()
  local f = self.f
  local function panel(w, h, level)
    local p = K.box(f, w, h, { 0.07, 0.05, 0.1, 0.97 }, C.line, 1)
    p:SetPoint('TOP', f, 'TOPLEFT', MAIN_X + MAIN_W / 2, -162)
    p:SetFrameLevel(f:GetFrameLevel() + (level or 30))   -- before the children are made, so they sit on it
    p:EnableMouse(true)
    p.title = K.text(p, 20, C.gold, 'CENTER', K.FONT_TITLE)
    p.title:SetPoint('TOP', 0, -12)
    p:Hide()
    return p
  end
  -- choose the next blind
  local sel = panel(MAIN_W, 420)
  sel.cols = {}
  for i = 1, 3 do
    local c = K.box(sel, 226, 352, C.panel, C.line, 1)
    c:SetPoint('TOPLEFT', 8 + (i - 1) * 238, -50)
    c.kind = K.text(c, 12, C.dim, 'CENTER'); c.kind:SetPoint('TOP', 0, -10)
    c.name = K.text(c, 17, C.gold, 'CENTER'); c.name:SetPoint('TOP', 0, -28)
    c.spell = K.text(c, 13, C.bad, 'CENTER'); c.spell:SetPoint('TOP', 0, -56)
    c.text = K.text(c, 12, C.text, 'CENTER'); c.text:SetPoint('TOPLEFT', 12, -78); c.text:SetPoint('TOPRIGHT', -12, -78)
    c.text:SetWordWrap(true); c.text:SetJustifyV('TOP')
    c.healthLabel = K.text(c, 11, C.dim, 'CENTER'); c.healthLabel:SetPoint('TOP', 0, -170); c.healthLabel:SetText('Health')
    c.health = K.text(c, 26, C.bad, 'CENTER', K.FONT_NUM); c.health:SetPoint('TOP', 0, -186)
    c.reward = K.text(c, 13, C.gold, 'CENTER'); c.reward:SetPoint('TOP', 0, -228)
    c.state = K.text(c, 13, C.dim, 'CENTER'); c.state:SetPoint('BOTTOM', 0, 62)
    c.go = K.button(c, 160, 38, 'Fight!', function() self:startBlind() end, 'orange', 16)
    c.go:SetPoint('BOTTOM', 0, 16)
    sel.cols[i] = c
  end
  self.selectPanel = sel
  -- shop
  local shop = panel(MAIN_W, 400)
  shop.title:SetText('The Shop')
  shop.offers = {}
  local function offer(i, kind, x)
    local s = self:makeSlot(shop, kind == 'talent' and 'shopTalent' or 'shopItem', i)
    s:SetPoint('TOPLEFT', x, -70)
    s.price = K.text(shop, 14, C.gold, 'CENTER', K.FONT_NUM)
    s.price:SetPoint('TOP', s, 'BOTTOM', 0, -6)
    s.buy = K.button(shop, CW, 26, 'Buy', function() self:buy(kind, i) end, 'green', 12)
    s.buy:SetPoint('TOP', s.price, 'BOTTOM', 0, -6)
    shop.offers[#shop.offers + 1] = s
    return s
  end
  local tl = K.text(shop, 12, C.dim, 'CENTER'); tl:SetPoint('TOPLEFT', 60, -48); tl:SetText('Talents')
  local il = K.text(shop, 12, C.dim, 'CENTER'); il:SetPoint('TOPLEFT', 336, -48); il:SetText('Consumables')
  shop.t1 = offer(1, 'talent', 40); shop.t2 = offer(2, 'talent', 40 + CW + 16)
  shop.i1 = offer(1, 'item', 316); shop.i2 = offer(2, 'item', 316 + CW + 16)
  shop.reroll = K.button(shop, 150, 34, 'Reroll', function() self:reroll() end, 'normal', 13)
  shop.reroll:SetPoint('TOPRIGHT', -40, -80)
  shop.next = K.button(shop, 150, 40, 'Next blind >', function() self:leaveShop() end, 'orange', 15)
  shop.next:SetPoint('TOPRIGHT', -40, -130)
  shop.note = K.text(shop, 12, C.dim, 'CENTER')
  shop.note:SetPoint('BOTTOMLEFT', 20, 18); shop.note:SetPoint('BOTTOMRIGHT', -20, 18)
  shop.note:SetWordWrap(true)
  shop.note:SetText('Click a talent at the top to sell it. Grimoires level up a poker hand as soon as you buy them.')
  self.shopPanel = shop
  -- cash out
  local cash = panel(420, 300, 35)
  cash.title:SetText('Victory')
  cash.lines = {}
  for i = 1, 6 do
    local l = K.text(cash, 13, C.text, 'LEFT'); l:SetPoint('TOPLEFT', 30, -50 - (i - 1) * 24)
    local r = K.text(cash, 14, C.gold, 'RIGHT', K.FONT_NUM); r:SetPoint('TOPRIGHT', -30, -50 - (i - 1) * 24)
    cash.lines[i] = { l, r }
  end
  cash.go = K.button(cash, 200, 40, 'Collect', function() self:collect() end, 'gold', 15)
  cash.go:SetPoint('BOTTOM', 0, 18)
  self.cashPanel = cash
  -- the end of a run
  local over = panel(460, 330)
  over.body = K.text(over, 14, C.text, 'CENTER')
  over.body:SetPoint('TOPLEFT', 24, -52); over.body:SetPoint('TOPRIGHT', -24, -52)
  over.body:SetWordWrap(true); over.body:SetJustifyV('TOP'); over.body:SetSpacing(4)
  over.again = K.button(over, 180, 40, 'New run', function() self:newRun() end, 'blue', 15)
  over.again:SetPoint('BOTTOMLEFT', 30, 18)
  over.keep = K.button(over, 180, 40, 'Keep going', function() self:keepGoing() end, 'orange', 15)
  over.keep:SetPoint('BOTTOMRIGHT', -30, 18)
  self.overPanel = over
  -- hand levels
  local lv = panel(460, 400)
  lv.title:SetText('Poker hands')
  lv.rows = {}
  for i = 1, #R.HANDS do
    local y = -46 - (i - 1) * 26
    local row = { K.text(lv, 13, C.text, 'LEFT'), K.text(lv, 12, C.dim, 'CENTER'), K.text(lv, 13, C.chips, 'RIGHT', K.FONT_NUM), K.text(lv, 13, C.mult, 'LEFT', K.FONT_NUM), K.text(lv, 12, C.dim, 'RIGHT') }
    row[1]:SetPoint('TOPLEFT', 24, y); row[2]:SetPoint('TOPLEFT', 190, y); row[3]:SetPoint('TOPRIGHT', -200, y)
    row[4]:SetPoint('TOPLEFT', 270, y); row[5]:SetPoint('TOPRIGHT', -24, y)
    lv.rows[i] = row
  end
  lv.close = K.button(lv, 120, 28, 'Close', function() lv:Hide() end, 'normal')
  lv.close:SetPoint('BOTTOM', 0, 12)
  lv:SetHeight(46 + #R.HANDS * 26 + 54)
  self.levelPanel = lv
  -- are you sure?
  local q = panel(380, 150, 40)
  q.title:SetText('Start a new run?')
  q.body = K.text(q, 13, C.text, 'CENTER'); q.body:SetPoint('TOP', 0, -50); q.body:SetText('The run you are in will be lost.')
  q.yes = K.button(q, 140, 34, 'New run', function() q:Hide(); self:newRun() end, 'red')
  q.yes:SetPoint('BOTTOMLEFT', 30, 16)
  q.no = K.button(q, 140, 34, 'Keep playing', function() q:Hide() end, 'normal')
  q.no:SetPoint('BOTTOMRIGHT', -30, 16)
  self.confirmPanel = q
end

-- ---------------------------------------------------------------------------------------------------------------
-- showing the run
function G:Show()
  self.f:Show()
  if not self.run then self:newRun() else self:refresh(true) end
end
function G:Hide() self.f:Hide(); GameTooltip:Hide() end
function G:OnPause() self.seq:finish() end

function G:newRun()
  for id in pairs(self.cards) do self:releaseCard(id) end
  self.seq:clear()
  self.pop:clear()
  self.run = R.newRun()
  self.db.run = self.run
  self.db.runs = (self.db.runs or 0) + 1
  self.selected, self.selOrder, self.picked = {}, {}, nil
  self.damage:SetText('')
  self:refresh(true)
end
function G:confirmNewRun() if self.run and self.run.phase ~= 'over' and self.run.phase ~= 'victory' then self.confirmPanel:Show() else self:newRun() end end

-- the hand / pile hold the same card tables as the deck; saved variables lose that, so it is put back after loading
function G:relink()
  local run = self.run
  if not run.blind then return end
  local byId = {}
  for _, c in ipairs(run.deck) do byId[c.id] = c end
  for _, list in ipairs({ run.blind.hand, run.blind.pile }) do
    for i, c in ipairs(list) do if byId[c.id] then list[i] = byId[c.id] end end
  end
end

function G:busy() return self.seq:busy() end

function G:refresh(snap)
  local run = self.run
  local ph = run.phase
  self.selectPanel:SetShown(ph == 'select')
  self.shopPanel:SetShown(ph == 'shop' and not self.cashPanel:IsShown())
  self.overPanel:SetShown((ph == 'over' or ph == 'victory') and not self.cashPanel:IsShown())
  local inBlind = ph == 'blind'
  for _, b in ipairs({ self.play, self.discard, self.sortRank, self.sortSuit }) do b:SetShown(inBlind) end
  self:refreshSidebar()
  self:refreshSlots()
  if ph == 'select' then self:refreshSelect() end
  if ph == 'shop' then self:refreshShop() end
  if ph == 'over' or ph == 'victory' then self:refreshOver() end
  if inBlind then self:layoutHand(snap) else for id in pairs(self.cards) do self:releaseCard(id) end end
  self:refreshButtons()
  self.message:SetText(inBlind and (next(self.selected) and '' or 'Select up to 5 cards, then play them or discard them') or '')
end

function G:refreshSidebar()
  local S, run = self.side, self.run
  local b = run.blind
  local info = b and b.info or (run.phase == 'select' and R.blindInfo(run, run.blindIndex)) or nil
  if info then
    S.blindName:SetText(info.name)
    S.blindSpell:SetText(info.boss and info.boss.spell or (info.index == 1 and 'Small blind' or 'Big blind'))
    S.blindSpell:SetTextColor(info.boss and C.bad[1] or C.dim[1], info.boss and C.bad[2] or C.dim[2], info.boss and C.bad[3] or C.dim[3])
    S.blindText:SetText(info.boss and info.boss.text or ('Reward: ' .. info.reward .. ' gold'))
    S.health:SetText(K.num(info.health))
    S.healthLabel:Show()
  else
    S.healthLabel:Hide()
    S.blindName:SetText(run.phase == 'shop' and 'Shopping' or run.phase == 'victory' and 'Ragnaros is down' or 'Run over')
    S.blindSpell:SetText(''); S.blindText:SetText(''); S.health:SetText('')
  end
  local score = self.shownScore or (b and b.score or 0)
  S.scoreNum:SetText(K.num(score))
  local frac = info and b and min(1, score / info.health) or 0
  S.bar:SetWidth(max(1, (S.score:GetWidth() - 2) * frac))
  S.bar:SetShown(frac > 0)
  S.hands.num:SetText(b and b.hands or '-')
  S.discards.num:SetText(b and b.discards or '-')
  S.gold.num:SetText((run.gold - (self.cash and self.cash.total or 0)) .. 'g')
  S.ante.num:SetText(run.ante .. ' / 8')
  S.speed:SetLabel('Speed ' .. self.speed .. 'x')
  S.deck:SetText('Deck: ' .. (b and #b.pile or #run.deck) .. ' / ' .. #run.deck .. ' cards')
  if not self:busy() then self:previewHand() end
end

function G:previewHand()
  local S = self.side
  local sel = self:selectedCards()
  if #sel == 0 then
    S.handName:SetText(self.run.phase == 'blind' and 'Pick cards' or '')
    S.chips:SetText('0'); S.mult:SetText('0')
    return
  end
  local hand = R.evaluate(sel)
  local chips, mult, lvl = R.handValues(self.run, hand)
  S.handName:SetText(hand.name .. '  |cff9a8ab0lvl ' .. lvl .. '|r')
  S.chips:SetText(K.num(chips)); S.mult:SetText(K.num(mult))
end

function G:refreshSlots()
  local run = self.run
  self.talentLabel:SetText('Talents ' .. #run.talents .. ' / ' .. run.maxTalents)
  self.itemLabel:SetText('Consumables ' .. #run.items .. ' / ' .. run.maxItems)
  for i, s in ipairs(self.talentSlots) do self:paintSlot(s, run.talents[i] and { talent = run.talents[i] } or nil) end
  for i, s in ipairs(self.itemSlots) do self:paintSlot(s, run.items[i] and { item = run.items[i].key } or nil) end
  self:placeSlotAction()
end

-- content: { talent = key } | { item = key } | { grimoire = handKey }
function G:paintSlot(s, content)
  s.content = content
  s.icon:Hide(); s.name:SetText(''); s.big:SetText(''); s.empty:SetText('')
  s:SetFill(0.08, 0.06, 0.1, 1); s:SetBorderColor(C.line[1], C.line[2], C.line[3], 1)
  s.pick:SetAlpha(0)
  if not content then
    s.empty:SetText(s.kind == 'talent' and 'talent' or s.kind == 'item' and 'consumable' or '')
    s:SetAlpha(s.kind:match('^shop') and 0.35 or 1)
    return
  end
  s:SetAlpha(1)
  if content.talent then
    local d, info = R.TALENTS[content.talent], A.TALENTS[content.talent]
    s.icon:SetTexture(K.spellTexture(info and info.spell)); s.icon:Show()
    s.name:SetText(info and info.name or content.talent)
    local rc = d.rarity == 2 and C.fel or C.chips
    s:SetBorderColor(rc[1] * 0.8, rc[2] * 0.8, rc[3] * 0.8, 1)
  elseif content.item then
    local c = A.CONSUMABLES[content.item]
    s.icon:SetTexture(c.spell and K.spellTexture(c.spell) or K.itemTexture(c.item)); s.icon:Show()
    s.name:SetText(R.ITEMS[content.item].name)
    s:SetBorderColor(C.flame[1] * 0.7, C.flame[2] * 0.7, C.flame[3] * 0.7, 1)
  elseif content.grimoire then
    local h = R.HAND[content.grimoire]
    s:SetFill(0.2, 0.08, 0.26, 1)
    s:SetBorderColor(C.shadow[1], C.shadow[2], C.shadow[3], 1)
    s.big:SetText('Grimoire|n|cffffd040' .. h.name .. '|r')
    s.name:SetText('')
  end
  if self.picked and self.picked.kind == s.kind and self.picked.i == s.i then s.pick:SetAlpha(1) end
end

function G:slotTip(s)
  local c = s.content
  if not c then return end
  local lines
  if c.talent then
    local d, info = R.TALENTS[c.talent], A.TALENTS[c.talent]
    lines = { { (info and info.name or c.talent) .. (d.rarity == 2 and '  |cff8cf060Uncommon|r' or '  |cff60a0ffCommon|r'), { 1, 1, 1 } }, { d.desc, { 1, 1, 1 } } }
    if info and info.text then lines[#lines + 1] = { 'In WoW: ' .. info.text, C.gold } end
    if s.kind == 'talent' then lines[#lines + 1] = { 'Sells for ' .. R.sellValue(self.run, c.talent) .. ' gold - click to sell', C.dim } end
  elseif c.item then
    local d, info = R.ITEMS[c.item], A.CONSUMABLES[c.item]
    lines = { { d.name, { 1, 1, 1 } }, { d.desc, { 1, 1, 1 } } }
    if info and info.text then lines[#lines + 1] = { 'In WoW: ' .. info.text, C.gold } end
    if s.kind == 'item' then lines[#lines + 1] = { 'Click it, then Use or Sell', C.dim } end
  elseif c.grimoire then
    local h = R.HAND[c.grimoire]
    local lvl = self.run.levels[h.key]
    lines = { { 'Grimoire: ' .. h.name, { 1, 1, 1 } }, { 'Levels up ' .. h.name .. ' to level ' .. (lvl + 1) .. ': +' .. h.lc .. ' Chips, +' .. h.lm .. ' Mult.', { 1, 1, 1 } } }
  end
  K.showTip(s, lines, s.kind:match('^shop') and 'ANCHOR_RIGHT' or 'ANCHOR_BOTTOM')
end

function G:slotClick(s)
  if self:busy() or not s.content then return end
  if s.kind == 'talent' or s.kind == 'item' then
    if self.picked and self.picked.kind == s.kind and self.picked.i == s.i then self.picked = nil else self.picked = { kind = s.kind, i = s.i } end
    A.sound('select')
    self:refreshSlots()
  end
end
function G:placeSlotAction()
  local p = self.picked
  local a, u = self.slotAction, self.slotAction2
  a:Hide(); u:Hide()
  if not p then return end
  local list = p.kind == 'talent' and self.run.talents or self.run.items
  if not list[p.i] then self.picked = nil; return end
  local s = (p.kind == 'talent' and self.talentSlots or self.itemSlots)[p.i]
  a:ClearAllPoints(); a:SetPoint('TOP', s, 'BOTTOM', 0, -4)
  local value = p.kind == 'talent' and R.sellValue(self.run, list[p.i]) or max(1, floor(R.ITEMS[list[p.i].key].cost / 2))
  a:SetLabel('Sell +' .. value .. 'g')
  a:SetFrameLevel(self.f:GetFrameLevel() + 45)
  a:Show()
  if p.kind == 'item' then
    u:ClearAllPoints(); u:SetPoint('TOP', a, 'BOTTOM', 0, -3)
    u:SetFrameLevel(self.f:GetFrameLevel() + 45)
    u:Show()
  end
end
function G:slotActionClick()
  local p = self.picked
  if not p or self:busy() then return end
  local v = p.kind == 'talent' and R.sellTalent(self.run, p.i) or R.sellItem(self.run, p.i)
  self.picked = nil
  if v then A.sound('coin') end
  self:refresh()
end
function G:slotUseClick()
  local p = self.picked
  if not p or p.kind ~= 'item' or self:busy() then return end
  local ok, why = R.useItem(self.run, p.i, self:selectedIds())
  if not ok then self:say(why, C.bad); return end
  A.sound('card')
  self.picked = nil
  self.selected, self.selOrder = {}, {}
  if self.run.blind then for _, c in ipairs(self.run.blind.hand) do local fr = self.cards[c.id]; if fr then self:paintCard(fr) end end end
  self:refresh()
end

-- ---------------------------------------------------------------------------------------------------------------
-- the hand
function G:layoutHand(snap)
  local run = self.run
  local hand = run.blind.hand
  local keep = {}
  for _, c in ipairs(hand) do keep[c.id] = true end
  for id in pairs(self.cards) do if not keep[id] and not self.flying then self:releaseCard(id) end end
  local n = #hand
  local gap = min(CW + 10, (MAIN_W - 20 - CW) / max(1, n - 1))
  local total = (n - 1) * gap + CW
  local x0 = MAIN_X + (MAIN_W - total) / 2
  for i, c in ipairs(hand) do
    local fr = self:cardFrame(c)
    fr.tx = x0 + (i - 1) * gap
    fr.ty = HAND_Y + (self.selected[c.id] and 22 or 0)
    fr.ta = 1
    fr:SetFrameLevel(self.f:GetFrameLevel() + 10 + i)
    if snap or fr.fresh then fr.x, fr.y = fr.tx, fr.ty; fr.fresh = nil end
    fr.index = i
    self:paintCard(fr)
    self:placeCard(fr)
  end
end
function G:placeCard(fr)
  fr:ClearAllPoints()
  fr:SetPoint('TOPLEFT', self.f, 'TOPLEFT', fr.x, fr.y)
  fr:SetAlpha(fr.a)
end

function G:selectedCards()
  local out = {}
  if not self.run.blind then return out end
  for _, c in ipairs(self.run.blind.hand) do if self.selected[c.id] then out[#out + 1] = c end end
  return out
end
function G:selectedIds() local t = {}; for _, c in ipairs(self:selectedCards()) do t[#t + 1] = c.id end; return t end

function G:cardClick(fr, button)
  if self:busy() or self.run.phase ~= 'blind' or not fr.card then return end
  local id = fr.card.id
  if button == 'RightButton' then self.selected = {}; self:afterSelect(); return end
  if self.selected[id] then self.selected[id] = nil
  else
    local n = 0; for _ in pairs(self.selected) do n = n + 1 end
    if n >= 5 then self:say('Five cards at most', C.dim); return end
    self.selected[id] = true
  end
  A.sound('select')
  self:afterSelect()
end
function G:afterSelect()
  self:layoutHand()
  self:previewHand()
  self:refreshButtons()
  self.message:SetText('')
end
function G:refreshButtons()
  local b = self.run.blind
  local n = #self:selectedCards()
  local busy = self:busy()
  self.play:SetEnabled(b ~= nil and n > 0 and b.hands > 0 and not busy)
  self.discard:SetEnabled(b ~= nil and n > 0 and b.discards > 0 and not busy)
  if b and b.boss and b.boss.discardCost then self.discard:SetLabel('Discard (' .. b.boss.discardCost .. 'g)') else self.discard:SetLabel('Discard') end
end

function G:cardTip(fr)
  local c = fr.card
  if not c then return end
  local s = R.SUITS[c.suit]
  local lines = { { R.cardName(c), s.color } }
  lines[#lines + 1] = { '+' .. R.rankChips(c.rank) .. ' Chips when scored', { 1, 1, 1 } }
  lines[#lines + 1] = { (s.school == 'shadow' and 'Shadow' or 'Fire') .. ' card' .. (R.isDemon(c) and ', demon (' .. A.PETS[R.DEMON[c.rank]].name .. ')' or ''), C.dim }
  local crit = R.critChance(self.run, c)
  lines[#lines + 1] = { K.dec(crit, 1) .. '% crit chance for x' .. K.dec(R.critMult(self.run, c), 2) .. ' Chips', C.dim }
  if c.enh then local e = R.ENH[c.enh]; lines[#lines + 1] = { e.name .. ': ' .. e.text, e.color } end
  if self.run.blind and R.debuffed(self.run.blind, c) then lines[#lines + 1] = { self.run.blind.boss.spell .. ': scores nothing', C.bad } end
  local spell = A.SPELLS[s.key]
  if spell and spell.text then lines[#lines + 1] = { 'In WoW: ' .. spell.text, C.gold } end
  K.showTip(fr, lines, 'ANCHOR_TOP')
end

function G:sort(by)
  if self:busy() then return end
  R.sortHand(self.run, by)
  self:layoutHand()
end

function G:say(text, color)
  local c = color or C.dim
  self.message:SetText(text)
  self.message:SetTextColor(c[1], c[2], c[3])
end

-- ---------------------------------------------------------------------------------------------------------------
-- actions
function G:startBlind()
  if self.run.phase ~= 'select' then return end
  R.startBlind(self.run)
  self.shownScore = nil
  self.damage:SetText('')
  self.selected = {}
  for _, c in ipairs(self.run.blind.hand) do local fr = self:cardFrame(c); fr.fresh = true end
  A.sound('open')
  self:refresh(false)
  -- cards fly in from the deck
  for i, c in ipairs(self.run.blind.hand) do local fr = self.cards[c.id]; fr.x, fr.y = MAIN_X + MAIN_W - CW, HAND_Y - 40; fr.a = 0 end
end

function G:discardSelected()
  if self:busy() then return end
  local ids = self:selectedIds()
  local res, why = R.discard(self.run, ids)
  if not res then self:say(why, C.bad); return end
  A.sound('card')
  for _, c in ipairs(res.gone) do
    local fr = self.cards[c.id]
    if fr then fr.ty = fr.y - 50; fr.ta = 0 end
  end
  self.selected = {}
  self.flying = true
  self.seq:add(0.25 / self.speed, function()
    self.flying = nil
    for _, c in ipairs(res.gone) do self:releaseCard(c.id) end
    for _, c in ipairs(res.drawn) do local fr = self:cardFrame(c); fr.x, fr.y, fr.a = MAIN_X + MAIN_W - CW, HAND_Y - 40, 0 end
    self:refresh()
  end)
  self:refreshButtons()
end

function G:playSelected()
  if self:busy() then return end
  local run = self.run
  local before = run.blind.score
  local ids = self:selectedIds()
  local cards = self:selectedCards()
  local report, why = R.play(run, ids)
  if not report then self:say(why, C.bad); return end
  self.shownScore = before
  self.selected = {}
  self.flying = true
  self.message:SetText('')
  local S = self.side
  -- move the played cards up into the scoring row
  local n = #cards
  local total = n * CW + (n - 1) * 10
  local x0 = MAIN_X + (MAIN_W - total) / 2
  local pos = {}
  for i, c in ipairs(cards) do
    local fr = self.cards[c.id]
    fr.tx = x0 + (i - 1) * (CW + 10)
    fr.ty = PLAY_Y + (report.scoring[c.id] and 12 or 0)
    fr.ta = report.scoring[c.id] and 1 or 0.5
    fr:SetFrameLevel(self.f:GetFrameLevel() + 20 + i)
    pos[c.id] = fr
  end
  -- the rest of the hand closes up
  local rest = {}
  for _, c in ipairs(self.run.blind and self.run.blind.hand or {}) do rest[#rest + 1] = c end
  local step = 0.42
  S.handName:SetText(report.hand.name .. '  |cff9a8ab0lvl ' .. report.level .. '|r')
  S.chips:SetText(K.num(report.baseChips)); S.mult:SetText(K.num(report.baseMult))
  self:refreshButtons()
  local seq = self.seq
  seq:add(0.35, function() end)
  for _, st in ipairs(report.steps) do
    if st.kind ~= 'hand' then
      seq:add(step, function() self:showStep(st, pos) end)
    end
  end
  seq:add(step, function()
    self.damage:SetText(K.num(report.chips) .. ' x ' .. K.num(report.mult) .. ' = ' .. K.num(report.damage))
    A.sound(report.won and 'win' or 'coin')
  end)
  seq:add(0.5, function()
    self.shownScore = nil
    self:refreshSidebar()
    for _, c in ipairs(cards) do local fr = self.cards[c.id]; if fr then fr.ty = fr.y - 30; fr.ta = 0 end end
  end)
  seq:add(0.45, function()
    self.flying = nil
    for _, c in ipairs(cards) do self:releaseCard(c.id) end
    self.damage:SetText('')
    for _, c in ipairs(report.drawn or {}) do local fr = self:cardFrame(c); fr.x, fr.y, fr.a = MAIN_X + MAIN_W - CW, HAND_Y - 40, 0 end
    if report.won then self:showCashout(report.cashout)
    elseif report.lost then self:endRun()
    end
    self:refresh()
  end)
end

function G:showStep(st, pos)
  local S = self.side
  local x, y
  local fr = st.card and pos[st.card]
  if st.kind == 'talent' and st.slot then
    local s = self.talentSlots[st.slot]
    x, y = MAIN_X + (st.slot - 1) * (CW + 8) + CW / 2, 0
    if s then s.bump = 0.25 end
    y = self.f:GetHeight() - 22 - CH - 10
  elseif fr then
    x, y = fr.x + CW / 2, self.f:GetHeight() + fr.y + 18
    fr.bump = 0.2
  else
    x, y = MAIN_X + MAIN_W / 2, self.f:GetHeight() + PLAY_Y + 30
  end
  local text, color
  if st.none then text, color = st.text or 'Nothing', C.bad
  elseif st.xmult then text, color = 'x' .. K.dec(st.xmult, 2) .. ' Mult', C.mult
  elseif st.mult then text, color = '+' .. K.num(st.mult) .. ' Mult', C.mult
  elseif st.chips then text, color = '+' .. K.num(st.chips), C.chips
  elseif st.gold then text, color = (st.gold > 0 and '+' or '') .. st.gold .. 'g', C.gold
  else text, color = st.text or '', C.shadow end
  if st.crit then text = 'Crit! ' .. text; color = C.flame; A.sound('crit') end
  if st.again then text = 'Again! ' .. text end
  if st.text and not st.none and (st.chips or st.mult or st.xmult) then text = st.text .. ' ' .. text end
  if st.gold and st.kind == 'talent' then text = text .. ' +' .. st.gold .. 'g' end
  self.pop:show(text, x, y, color, st.crit and 20 or 17, 1.0 / self.speed + 0.3)
  S.chips:SetText(K.num(st.chipsAfter)); S.mult:SetText(K.num(st.multAfter))
  if st.gold then S.gold.num:SetText(self.run.gold .. 'g') end
end

function G:showCashout(cash)
  local p = self.cashPanel
  self.cash = cash
  p.title:SetText(cash.victory and 'Ragnaros defeated!' or (cash.blind.name .. ' defeated'))
  for i, l in ipairs(p.lines) do
    local row = cash.lines[i]
    l[1]:SetText(row and row[1] or ''); l[2]:SetText(row and ('+' .. row[2] .. 'g') or '')
  end
  p.go:SetLabel('Collect +' .. cash.total .. 'g')
  p:Show()
  A.sound('coin')
  local best = self.db.best or {}
  best.ante = max(best.ante or 0, self.run.ante)
  self.db.best = best
end
function G:collect()
  self.cashPanel:Hide()
  local cash = self.cash
  self.cash = nil
  if cash and cash.victory then
    self.db.wins = (self.db.wins or 0) + 1
    self:endRun()
  end
  self:refresh()
end
function G:endRun()
  local best = self.db.best or {}
  best.ante = max(best.ante or 0, self.run.ante)
  best.damage = max(best.damage or 0, self.run.stats.best)
  self.db.best = best
  A.sound(self.run.phase == 'victory' and 'win' or 'lose')
end
function G:keepGoing() R.keepGoing(self.run); self:refresh() end

function G:refreshSelect()
  local run = self.run
  for i, col in ipairs(self.selectPanel.cols) do
    local info = R.blindInfo(run, i)
    col.kind:SetText(i == 1 and 'Small blind' or i == 2 and 'Big blind' or 'Boss blind')
    col.name:SetText(info.name)
    col.spell:SetText(info.boss and info.boss.spell or '')
    col.text:SetText(info.boss and info.boss.text or (i == 1 and 'A warm-up.' or 'Hits back harder - well, it would, if dummies hit back.'))
    col.health:SetText(K.num(info.health))
    col.reward:SetText('Reward: ' .. info.reward .. ' gold')
    local now = i == run.blindIndex
    col.go:SetShown(now)
    col.state:SetText(i < run.blindIndex and 'Defeated' or (now and '' or 'Up next'))
    col:SetAlpha(now and 1 or 0.55)
    col:SetBorderColor(now and C.gold[1] or C.line[1], now and C.gold[2] or C.line[2], now and C.gold[3] or C.line[3], 1)
  end
  self.selectPanel.title:SetText('Ante ' .. run.ante .. (run.ante <= 8 and ' of 8' or ' (endless)'))
end

function G:refreshShop()
  local run, shop = self.run, self.shopPanel
  local o = run.shop
  local function fill(s, content, price, sold)
    self:paintSlot(s, (not sold) and content or nil)
    s.price:SetText(sold and 'Sold' or (price .. 'g'))
    s.buy:SetShown(not sold)
    s.buy:SetEnabled(not sold and run.gold >= price)
  end
  for i = 1, 2 do
    local t = o.talents[i]
    local s = i == 1 and shop.t1 or shop.t2
    if t then fill(s, { talent = t.key }, R.price(run, R.TALENTS[t.key].cost), t.sold) else fill(s, nil, 0, true) end
    local it = o.items[i]
    local si = i == 1 and shop.i1 or shop.i2
    fill(si, it.kind == 'grimoire' and { grimoire = it.hand } or { item = it.key }, R.itemCost(run, it), it.sold)
  end
  local rc = R.price(run, run.rerollCost)
  shop.reroll:SetLabel('Reroll (' .. rc .. 'g)')
  shop.reroll:SetEnabled(run.gold >= rc)
end
function G:buy(kind, i)
  if self:busy() then return end
  GameTooltip:Hide()
  local ok, why = (kind == 'talent' and R.buyTalent or R.buyItem)(self.run, i)
  if not ok then self.shopPanel.note:SetText('|cffff6060' .. why .. '|r'); return end
  A.sound('coin')
  if why == 'levelup' then
    local it = self.run.shop.items[i]
    self.shopPanel.note:SetText(R.HAND[it.hand].name .. ' is now level ' .. self.run.levels[it.hand] .. '.')
  end
  self:refresh()
end
function G:reroll()
  local ok, why = R.reroll(self.run)
  if not ok then self.shopPanel.note:SetText('|cffff6060' .. why .. '|r'); return end
  A.sound('coin')
  self:refresh()
end
function G:leaveShop() self.picked = nil; R.leaveShop(self.run); self:refresh() end

function G:refreshOver()
  local run, p = self.run, self.overPanel
  local st = run.stats
  local won = run.phase == 'victory'
  p.title:SetText(won and 'Molten Core cleared!' or 'Wiped')
  local lines = {}
  if won then lines[#lines + 1] = 'Ragnaros is down. Keep going for endless antes, or start fresh.' end
  if not won and run.blind then lines[#lines + 1] = run.blind.info.name .. ' had ' .. K.num(run.blind.info.health - run.blind.score) .. ' health left.' end
  lines[#lines + 1] = 'Reached ante ' .. run.ante
  lines[#lines + 1] = 'Hands played: ' .. st.hands
  lines[#lines + 1] = 'Best hand: ' .. K.num(st.best) .. (st.bestHand and (' (' .. st.bestHand .. ')') or '')
  lines[#lines + 1] = 'Damage in total: ' .. K.num(st.damage)
  local b = self.db.best
  if b then lines[#lines + 1] = '|cff9a8ab0Your best: ante ' .. (b.ante or 1) .. ', best hand ' .. K.num(b.damage or 0) .. (self.db.wins and (', ' .. self.db.wins .. ' wins') or '') .. '|r' end
  p.body:SetText(table.concat(lines, '|n'))
  p.keep:SetShown(won)
end

function G:togglePanel(which)
  local lv = self.levelPanel
  if lv:IsShown() then lv:Hide(); return end
  for i, h in ipairs(R.HANDS) do
    local chips, mult, lvl = R.handValues(self.run, h)
    local row = lv.rows[i]
    row[1]:SetText(h.name); row[2]:SetText('lvl ' .. lvl); row[3]:SetText(K.num(chips)); row[4]:SetText('x ' .. K.num(mult))
    row[5]:SetText('played ' .. (self.run.played[h.key] or 0))
  end
  lv:Show()
end
function G:cycleSpeed()
  self.speed = self.speed == 1 and 2 or self.speed == 2 and 4 or 1
  A.db().speed = self.speed
  self.side.speed:SetLabel('Speed ' .. self.speed .. 'x')
end

function G:deckTip()
  local run = self.run
  local counts = { 0, 0, 0, 0 }
  local list = run.blind and run.blind.pile or run.deck
  for _, c in ipairs(list) do counts[c.suit] = counts[c.suit] + 1 end
  local lines = { { run.blind and 'Cards left to draw' or 'Your deck', { 1, 1, 1 } } }
  for i, s in ipairs(R.SUITS) do lines[#lines + 1] = { s.name .. ': ' .. counts[i], s.color } end
  return lines
end

-- ---------------------------------------------------------------------------------------------------------------
-- every frame
function G:OnUpdate(dt)
  self.seq.speed = self.speed
  self.seq:update(dt)
  self.pop:update(dt * (self.speed > 1 and 1.5 or 1))
  local f = 1 - exp(-dt * 14)
  for _, fr in pairs(self.cards) do
    local by = 0
    if fr.bump then fr.bump = fr.bump - dt; by = fr.bump > 0 and 8 * (fr.bump / 0.2) or 0; if fr.bump <= 0 then fr.bump = nil end end
    local nx, ny, na = K.lerp(fr.x, fr.tx, f), K.lerp(fr.y, fr.ty, f), K.lerp(fr.a, fr.ta, f)
    if math.abs(nx - fr.x) > 0.05 or math.abs(ny - fr.y) > 0.05 or math.abs(na - fr.a) > 0.005 or by > 0 or fr.wasBumped then
      fr.x, fr.y, fr.a = nx, ny, na
      fr:ClearAllPoints()
      fr:SetPoint('TOPLEFT', self.f, 'TOPLEFT', fr.x, fr.y + by)
      fr:SetAlpha(fr.a)
      fr.wasBumped = by > 0
    end
  end
  for _, s in ipairs(self.talentSlots) do
    if s.bump then
      s.bump = s.bump - dt
      local by = s.bump > 0 and 6 * (s.bump / 0.25) or 0
      s:SetPoint('TOPLEFT', self.f, 'TOPLEFT', MAIN_X + (s.i - 1) * (CW + 8), -22 + by)
      if s.bump <= 0 then s.bump = nil end
    end
  end
  if self.refreshPending and not self:busy() then self.refreshPending = nil; self:refresh() end
end

function G:OnKey(key)
  if self.cashPanel:IsShown() then
    if (key == 'ENTER' or key == 'SPACE') and not self:busy() then self:collect(); return true end
    return false
  end
  if self.confirmPanel:IsShown() or self.levelPanel:IsShown() then
    if key == 'ESCAPE' and A.WEB then self.confirmPanel:Hide(); self.levelPanel:Hide(); return true end
    return false
  end
  if self:busy() then
    if key == 'SPACE' or key == 'ENTER' then self.seq:finish(); return true end
    return false
  end
  local run = self.run
  if run.phase == 'blind' then
    local n = tonumber(key)
    if n and n >= 1 and n <= 9 then
      local c = run.blind.hand[n]
      if c then self:cardClick(self.cards[c.id], 'LeftButton') end
      return true
    end
    if key == 'ENTER' or key == 'SPACE' then if self.play:IsEnabled() then self:playSelected() end; return true end
    if key == 'D' then if self.discard:IsEnabled() then self:discardSelected() end; return true end
    if key == 'R' then self:sort('rank'); return true end
    if key == 'S' then self:sort('suit'); return true end
    if key == 'ESCAPE' and A.WEB then self.selected = {}; self:afterSelect(); return true end
  elseif run.phase == 'select' and (key == 'ENTER' or key == 'SPACE') then self:startBlind(); return true
  elseif run.phase == 'shop' and key == 'ENTER' then self:leaveShop(); return true
  end
  return false
end

A.RegisterGame({
  key = 'shard', name = 'Shard & Mult', order = 1, ready = true, icon = A.SPELLS.soulFire.id,
  tagline = 'Poker hands of Warlock spells. Talents are your jokers, Molten Core bosses the blinds.',
  bestLine = function()
    local db = A.db('shard')
    if not db.best then return db.run and 'Run in progress' or 'Play' end
    return 'Best: ante ' .. (db.best.ante or 1) .. ((db.wins or 0) > 0 and (' - ' .. db.wins .. ' wins') or '')
  end,
  help = {
    '|cffffd040Beat each blind before your hands run out.|r Each ante has a small blind, a big blind and a Molten Core boss; Ragnaros waits at ante 8.',
    ' ',
    'Select up to 5 cards and play them as a poker hand. The hand gives base |cff3a94ffChips|r and |cffff4d42Mult|r; every scoring card adds its rank in Chips (J, Q, K = 10, A = 11). Damage = Chips x Mult.',
    ' ',
    'The four suits are Shadow Bolt and Corruption (Shadow) and Immolate and Incinerate (Fire). J, Q and K are demons: Imp, Succubus and Voidwalker.',
    ' ',
    'Every scored card can |cffffc040crit|r with the real spell crit chance of the Forever Warlock Sim\'s standard character (' .. K.dec(A.CHARACTER.critPct, 2) .. '%), for x' .. K.dec(A.CHARACTER.critMult, 2) .. ' its Chips.',
    ' ',
    'Win gold, then buy |cff8cf060talents|r (your jokers, up to 5), consumables and grimoires (level up a hand) in the shop. Interest: 1 gold per 5 you hold, up to 5.',
    ' ',
    'Keys: 1-9 pick cards, Enter / Space play, D discard, R / S sort. Space during scoring skips ahead.',
  },
  create = function(parent) return G.create(parent) end,
})
