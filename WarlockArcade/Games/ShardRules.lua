-- Shard & Mult: the rules (no drawing). A Balatro-style card game with Warlock spells for suits, talents for jokers
-- and Molten Core bosses for boss blinds. Every action changes the run at once and returns a report of what happened,
-- step by step; the screen (ShardUI.lua) only replays that report. So the run is always whole and can be saved.
--
-- Real numbers from the sim (Data.lua): every scored card can crit with the standard character's spell crit chance
-- (A.CHARACTER.critPct) for A.CHARACTER.critMult; the talents carry their real names, icons and game texts.
local ADDON, A = ...
local R = {}
A.ShardRules = R
local floor, min, max, random = math.floor, math.min, math.max, math.random

R.SUITS = {
  { key = 'shadowBolt', name = 'Shadow Bolt', school = 'shadow', color = { 0.68, 0.45, 1 } },
  { key = 'corruption', name = 'Corruption', school = 'shadow', color = { 0.45, 0.85, 0.3 } },
  { key = 'immolate', name = 'Immolate', school = 'fire', color = { 1, 0.42, 0.16 } },
  { key = 'incinerate', name = 'Incinerate', school = 'fire', color = { 1, 0.78, 0.22 } },
}
R.SB, R.CORR, R.IMMO, R.INCIN = 1, 2, 3, 4
R.RANK_NAME = { [11] = 'J', [12] = 'Q', [13] = 'K', [14] = 'A' }
R.DEMON = { [11] = 'imp', [12] = 'succubus', [13] = 'voidwalker' }   -- the face cards are demons
function R.rankName(r) return R.RANK_NAME[r] or tostring(r) end
function R.rankChips(r) if r == 14 then return 11 elseif r >= 11 then return 10 end; return r end
function R.isDemon(c) return c.rank >= 11 and c.rank <= 13 end
function R.isShadow(c) return R.SUITS[c.suit].school == 'shadow' end
function R.isFire(c) return R.SUITS[c.suit].school == 'fire' end
function R.cardName(c) return R.rankName(c.rank) .. ' of ' .. R.SUITS[c.suit].name end

-- poker hands, best first: base chips, base mult, + per level (Balatro's values)
R.HANDS = {
  { key = 'flushFive', name = 'Flush Five', chips = 160, mult = 16, lc = 50, lm = 3, secret = true },
  { key = 'flushHouse', name = 'Flush House', chips = 140, mult = 14, lc = 40, lm = 4, secret = true },
  { key = 'fiveKind', name = 'Five of a Kind', chips = 120, mult = 12, lc = 35, lm = 3, secret = true },
  { key = 'straightFlush', name = 'Straight Flush', chips = 100, mult = 8, lc = 40, lm = 4 },
  { key = 'fourKind', name = 'Four of a Kind', chips = 60, mult = 7, lc = 30, lm = 3 },
  { key = 'fullHouse', name = 'Full House', chips = 40, mult = 4, lc = 25, lm = 2 },
  { key = 'flush', name = 'Flush', chips = 35, mult = 4, lc = 15, lm = 2 },
  { key = 'straight', name = 'Straight', chips = 30, mult = 4, lc = 30, lm = 3 },
  { key = 'threeKind', name = 'Three of a Kind', chips = 30, mult = 3, lc = 20, lm = 2 },
  { key = 'twoPair', name = 'Two Pair', chips = 20, mult = 2, lc = 20, lm = 1 },
  { key = 'pair', name = 'Pair', chips = 10, mult = 2, lc = 15, lm = 1 },
  { key = 'highCard', name = 'High Card', chips = 5, mult = 1, lc = 10, lm = 1 },
}
R.HAND = {}
for i, h in ipairs(R.HANDS) do R.HAND[h.key] = h; h.index = i end

-- a little gentler than Balatro (300, 800, 2000, 5000, 11000, 20000, 35000, 50000): a game for a few minutes of fun
R.ANTE_BASE = { 300, 700, 1600, 3500, 7000, 13000, 22000, 35000 }
function R.anteBase(a)
  if a <= 8 then return R.ANTE_BASE[a] end
  return floor(35000 * 2.4 ^ (a - 8) / 1000) * 1000
end
R.BLINDS = {
  { key = 'small', name = 'Training Dummy', mult = 1, reward = 3 },
  { key = 'big', name = 'Heroic Training Dummy', mult = 1.5, reward = 4 },
  { key = 'boss', name = 'Boss', mult = 2, reward = 5 },
}

-- Molten Core (and Onyxia) as boss blinds; each effect echoes the boss's real fight
R.BOSSES = {
  lucifron = { name = 'Lucifron', spell = 'Curse of Lucifron', text = 'Every discard costs 1 gold.', discardCost = 1 },
  magmadar = { name = 'Magmadar', spell = 'Panic', text = 'Demon cards (J, Q, K) are feared: they score nothing.', debuff = 'demon' },
  shazzrah = { name = 'Shazzrah', spell = 'Counterspell', text = 'The first card of every hand is countered and scores nothing.', counterFirst = true },
  garr = { name = 'Garr', spell = 'Firesworn', text = 'Eight Firesworn stand by him: twice the health.', healthMult = 2, minAnte = 2 },
  geddon = { name = 'Baron Geddon', spell = 'Ignite Mana', text = 'Every hand you play burns 1 gold.', handCost = 1 },
  majordomo = { name = 'Majordomo Executus', spell = 'Magic Reflection', text = 'Your first hand is reflected: it deals half damage.', firstHalf = true },
  onyxia = { name = 'Onyxia', spell = 'Deep Breath', text = 'One card fewer in your hand.', handSize = -1 },
  ragnaros = { name = 'Ragnaros', spell = 'Fire immunity', text = 'Immune to Fire: Immolate and Incinerate cards score nothing. Twice the health.', debuff = 'fire', healthMult = 2, final = true },
}
R.BOSS_POOL = { 'lucifron', 'magmadar', 'shazzrah', 'garr', 'geddon', 'majordomo', 'onyxia' }

-- ---- talents (the jokers) ----
-- kind: 'card' runs for every scored card (ctx, card), 'hand' once per hand after the cards, 'mod' only changes rules.
-- Text in plain words; the talent's real game text is shown under it in the tooltip.
local T = {}
R.TALENTS = T
local function t(key, cost, rarity, desc, kind, fn, extra)
  local d = extra or {}
  d.key, d.cost, d.rarity, d.desc, d.kind, d.fn = key, cost, rarity, desc, kind, fn
  T[key] = d
  return d
end
t('shadowMastery', 5, 1, '+4 Mult for every scored Shadow card (Shadow Bolt, Corruption).', 'card',
  function(ctx, c) if R.isShadow(c) then return { mult = 4 } end end)
t('agonizingFlames', 5, 1, '+4 Mult for every scored Fire card (Immolate, Incinerate).', 'card',
  function(ctx, c) if R.isFire(c) then return { mult = 4 } end end)
t('improvedCorruption', 4, 1, 'Corruption cards give +30 Chips when scored.', 'card',
  function(ctx, c) if c.suit == R.CORR then return { chips = 30 } end end)
t('aftermath', 4, 1, 'Immolate cards give +30 Chips when scored.', 'card',
  function(ctx, c) if c.suit == R.IMMO then return { chips = 30 } end end)
t('unholyPower', 5, 1, 'Demon cards (J, Q, K) give +30 Chips when scored.', 'card',
  function(ctx, c) if R.isDemon(c) then return { chips = 30 } end end)
t('masterDemonologist', 6, 1, '+5 Mult for every scored demon card (J, Q, K).', 'card',
  function(ctx, c) if R.isDemon(c) then return { mult = 5 } end end)
t('malevolence', 3, 1, 'Shadow cards get +5% crit chance (the talent\'s real +5% Shadow crit).', 'mod', nil, { critShadow = 5 })
t('fireAndBrimstone', 4, 1, 'Immolate cards get +25% crit chance (the real +25% on Conflagrate).', 'mod', nil, { critImmolate = 25 })
t('bane', 6, 1, '+1 hand in every blind (faster casts, more casts).', 'mod', nil, { hands = 1 })
t('demonicEmbrace', 6, 1, '+1 card in your hand.', 'mod', nil, { handSize = 1 })
t('cataclysm', 5, 1, 'Everything in the shop costs 10% less (the real -10% mana cost), at least 1 gold off.', 'mod', nil, { discount = 10 })
t('soulHarvesting', 5, 1, '+2 gold at the end of every blind you win.', 'mod', nil, { endGold = 2 })
t('improvedLifeTap', 5, 1, 'Every discard you did not use gives 1 gold when you win a blind.', 'mod', nil, { discardGold = 1 })
t('siphonLife', 6, 1, 'Every scored Corruption card has a 1 in 2 chance to give 1 gold.', 'card',
  function(ctx, c) if c.suit == R.CORR and random() < 0.5 then return { gold = 1 } end end)
t('intensity', 5, 1, '+8 Mult if the hand is a Pair, Three or Four of a Kind.', 'hand',
  function(ctx) local k = ctx.hand.key; if k == 'pair' or k == 'threeKind' or k == 'fourKind' then return { mult = 8 } end end)
t('ruin', 7, 2, 'Crits of Shadow Bolt, Immolate and Incinerate cards deal x2 instead of x1.5 (the real +100% crit bonus).', 'mod', nil, { ruin = true })
t('pandemic', 4, 2, 'Crits of Corruption cards deal x2 instead of x1.5 (the real +100% crit bonus of periodic damage).', 'mod', nil, { pandemic = true })
t('conflagrate', 7, 2, 'Immolate cards score twice.', 'mod', nil, { retrigger = R.IMMO })
t('improvedShadowBolt', 7, 2, 'When a Shadow Bolt card crits, every later Shadow card in that hand gives x1.2 Mult (the real +20% Shadow damage taken).', 'card',
  function(ctx, c) if ctx.isb and R.isShadow(c) and ctx.isb < ctx.cardIndex then return { xmult = 1.2 } end end)
t('nightfall', 6, 2, 'Every scored Corruption card has a 1 in 4 chance to make the next Shadow Bolt card score twice (Shadow Trance).', 'mod', nil, { nightfall = 4 })
t('shadowAndFlame', 7, 2, 'x1.5 Mult if the hand scores both a Shadow and a Fire card.', 'hand',
  function(ctx) if ctx.shadowScored and ctx.fireScored then return { xmult = 1.5 } end end)
t('demonicSacrifice', 7, 2, 'x2 Mult if no demon card (J, Q, K) scored in the hand.', 'hand',
  function(ctx) if not ctx.demonScored then return { xmult = 2 } end end)
t('soulSiphon', 7, 2, 'x1.12 Mult for every Corruption card scored in the hand, up to x1.36 (the real 12% per effect, 36% at most).', 'hand',
  function(ctx) local n = min(3, ctx.count[R.CORR] or 0); if n > 0 then return { xmult = 1 + 0.12 * n } end end)
t('incinerate', 6, 2, 'Incinerate cards give x1.25 Mult if an Immolate card scored before them in the hand (the real +25% on burning targets).', 'card',
  function(ctx, c) if c.suit == R.INCIN and ctx.immolateSeen then return { xmult = 1.25 } end end)
t('decimation', 6, 2, 'x2 Mult while the target is below 35% health (the real Decimation threshold).', 'hand',
  function(ctx) if ctx.healthLeftPct < 35 then return { xmult = 2 } end end)
t('shadowburn', 8, 2, 'x3 Mult on the last hand of a blind.', 'hand',
  function(ctx) if ctx.lastHand then return { xmult = 3 } end end)
t('baneOfHavoc', 7, 2, 'The first scored card scores a second time (Havoc hits a second target).', 'mod', nil, { havoc = true })
t('demonicKnowledge', 6, 2, '+3 Mult for every demon card (J, Q, K) left in your hand.', 'hand',
  function(ctx) local n = 0; for _, c in ipairs(ctx.held) do if R.isDemon(c) then n = n + 1 end end; if n > 0 then return { mult = 3 * n } end end)
R.TALENT_KEYS = {}
for k in pairs(T) do R.TALENT_KEYS[#R.TALENT_KEYS + 1] = k end
table.sort(R.TALENT_KEYS)

-- ---- consumables ----
-- grimoires level up a hand; the others work on selected cards (min / max cards)
R.ITEMS = {
  buildOil = { name = 'Major Spellstone', cost = 3, cards = { 1, 2 }, desc = 'Up to 2 selected cards get Spellstone: +30 Chips when scored.', enh = 'spellstone' },
  brilliantWizardOil = { name = 'Brilliant Wizard Oil', cost = 3, cards = { 1, 2 }, desc = 'Up to 2 selected cards get Wizard Oil: +4 Mult when scored.', enh = 'oil' },
  flaskSupremePower = { name = 'Flask of Supreme Power', cost = 4, cards = { 1, 1 }, desc = '1 selected card gets Supreme Power: x2 Mult when scored, but a 1 in 4 chance to shatter afterwards.', enh = 'supreme' },
  shadowPower = { name = 'Elixir of Shadow Power', cost = 3, cards = { 1, 3 }, desc = 'Up to 3 selected cards become Shadow Bolt cards.', suit = R.SB },
  firePower = { name = 'Elixir of Fire Power', cost = 3, cards = { 1, 3 }, desc = 'Up to 3 selected cards become Immolate cards.', suit = R.IMMO },
  demonicRune = { name = 'Demonic Rune', cost = 3, cards = { 1, 2 }, desc = 'Destroy up to 2 selected cards for good.', destroy = true },
  majorManaPotion = { name = 'Major Mana Potion', cost = 3, cards = { 0, 0 }, desc = '+1 discard in this blind.', blindOnly = true, discards = 1 },
  greaterArcaneElixir = { name = 'Greater Arcane Elixir', cost = 4, cards = { 1, 1 }, desc = 'Add a copy of 1 selected card to your deck.', copy = true },
}
R.ITEM_KEYS = { 'buildOil', 'brilliantWizardOil', 'flaskSupremePower', 'shadowPower', 'firePower', 'demonicRune', 'majorManaPotion', 'greaterArcaneElixir' }
R.ENH = {
  spellstone = { name = 'Spellstone', text = '+30 Chips', color = { 0.3, 0.6, 1 } },
  oil = { name = 'Wizard Oil', text = '+4 Mult', color = { 1, 0.35, 0.3 } },
  supreme = { name = 'Supreme Power', text = 'x2 Mult, may shatter', color = { 1, 0.85, 0.3 } },
}

-- ---- a run ----
local function newDeck(run)
  local d = {}
  for s = 1, 4 do for r = 2, 14 do run.nextCard = run.nextCard + 1; d[#d + 1] = { id = run.nextCard, suit = s, rank = r } end end
  return d
end
function R.newRun(seed)
  if seed then math.randomseed(seed) end
  local run = { ante = 1, blindIndex = 1, gold = 4, talents = {}, items = {}, levels = {}, played = {}, nextCard = 0,
    phase = 'select', bosses = {}, stats = { hands = 0, best = 0, bestHand = nil, damage = 0 }, rerollCost = 5, maxTalents = 5, maxItems = 2 }
  run.deck = newDeck(run)
  for _, h in ipairs(R.HANDS) do run.levels[h.key] = 1 end
  R.rollBosses(run)
  return run
end
function R.rollBosses(run)
  local pool = {}
  for i, k in ipairs(R.BOSS_POOL) do pool[i] = k end
  A.Kit.shuffle(pool)
  -- a boss with minAnte never comes earlier: swap it with a later one
  for a = 1, 7 do
    local b = R.BOSSES[pool[a]]
    if b.minAnte and a < b.minAnte then for j = b.minAnte, 7 do local o = R.BOSSES[pool[j]]; if not o.minAnte or o.minAnte <= a then pool[a], pool[j] = pool[j], pool[a]; break end end end
  end
  for a = 1, 7 do run.bosses[a] = pool[a] end
  run.bosses[8] = 'ragnaros'
end
function R.bossOf(run, ante) local k = run.bosses[((ante - 1) % 8) + 1] or 'garr'; if ante > 8 and k == 'ragnaros' then k = R.BOSS_POOL[(ante % 7) + 1] end; return k end
function R.has(run, key) for _, k in ipairs(run.talents) do if k == key then return true end end; return false end
function R.sumMod(run, field)
  local n = 0
  for _, k in ipairs(run.talents) do local d = T[k]; if d and d[field] then n = n + (type(d[field]) == 'number' and d[field] or 1) end end
  return n
end
function R.blindInfo(run, index)
  local b = R.BLINDS[index]
  local info = { key = b.key, name = b.name, reward = b.reward, index = index }
  local health = R.anteBase(run.ante) * b.mult
  if b.key == 'boss' then
    local bk = R.bossOf(run, run.ante)
    local boss = R.BOSSES[bk]
    info.boss, info.bossKey, info.name = boss, bk, boss.name
    health = health * (boss.healthMult or 1)
  end
  info.health = floor(health)
  return info
end
function R.handSize(run, blind) return 8 + R.sumMod(run, 'handSize') + (blind and blind.boss and blind.boss.handSize or 0) end

local function draw(run, n)
  local b = run.blind
  local drawn = {}
  for _ = 1, n do
    local c = table.remove(b.pile)
    if not c then break end
    b.hand[#b.hand + 1] = c
    drawn[#drawn + 1] = c
  end
  return drawn
end
function R.fillHand(run) local b = run.blind; return draw(run, max(0, R.handSize(run, b.info) - #b.hand)) end

function R.startBlind(run)
  local info = R.blindInfo(run, run.blindIndex)
  local pile = {}
  for i, c in ipairs(run.deck) do pile[i] = c end
  A.Kit.shuffle(pile)
  run.blind = { info = info, boss = info.boss, score = 0, hands = 4 + R.sumMod(run, 'hands'), discards = 3, pile = pile, hand = {}, handsPlayed = 0 }
  run.phase = 'blind'
  R.fillHand(run)
  R.sortHand(run, run.sortBy or 'rank')
  return run.blind
end

function R.sortHand(run, by)
  run.sortBy = by
  local h = run.blind and run.blind.hand
  if not h then return end
  table.sort(h, function(a, b)
    if by == 'suit' then if a.suit ~= b.suit then return a.suit < b.suit end; if a.rank ~= b.rank then return a.rank > b.rank end
    else if a.rank ~= b.rank then return a.rank > b.rank end; if a.suit ~= b.suit then return a.suit < b.suit end end
    return a.id < b.id
  end)
end

-- which poker hand the cards make, and which of them score
function R.evaluate(cards)
  local n = #cards
  if n == 0 then return nil end
  local byRank, bySuit = {}, {}
  for _, c in ipairs(cards) do
    byRank[c.rank] = byRank[c.rank] or {}; table.insert(byRank[c.rank], c)
    bySuit[c.suit] = (bySuit[c.suit] or 0) + 1
  end
  local groups = {}
  for r, list in pairs(byRank) do groups[#groups + 1] = { rank = r, cards = list } end
  table.sort(groups, function(a, b) if #a.cards ~= #b.cards then return #a.cards > #b.cards end; return a.rank > b.rank end)
  local flush = n == 5 and (function() for _, k in pairs(bySuit) do if k == 5 then return true end end; return false end)()
  local straight = false
  if n == 5 and #groups == 5 then
    local ranks = {}
    for _, c in ipairs(cards) do ranks[#ranks + 1] = c.rank end
    table.sort(ranks)
    straight = ranks[5] - ranks[1] == 4 or (ranks[5] == 14 and ranks[1] == 2 and ranks[4] == 5)
  end
  local top, second = #groups[1].cards, groups[2] and #groups[2].cards or 0
  local key
  if top == 5 and flush then key = 'flushFive'
  elseif top == 3 and second == 2 and flush then key = 'flushHouse'
  elseif top == 5 then key = 'fiveKind'
  elseif straight and flush then key = 'straightFlush'
  elseif top == 4 then key = 'fourKind'
  elseif top == 3 and second == 2 then key = 'fullHouse'
  elseif flush then key = 'flush'
  elseif straight then key = 'straight'
  elseif top == 3 then key = 'threeKind'
  elseif top == 2 and second == 2 then key = 'twoPair'
  elseif top == 2 then key = 'pair'
  else key = 'highCard' end
  -- scoring cards
  local scoring = {}
  local all = { flushFive = 1, flushHouse = 1, fiveKind = 1, straightFlush = 1, fullHouse = 1, flush = 1, straight = 1 }
  local inSet = {}
  if all[key] then for _, c in ipairs(cards) do inSet[c] = true end
  elseif key == 'highCard' then inSet[groups[1].cards[1]] = true
  else
    local need = key == 'twoPair' and 2 or 1
    for i = 1, need do for _, c in ipairs(groups[i].cards) do inSet[c] = true end end
  end
  for _, c in ipairs(cards) do if inSet[c] then scoring[#scoring + 1] = c end end
  return R.HAND[key], scoring
end
function R.handValues(run, hand)
  local lvl = run.levels[hand.key] or 1
  return hand.chips + hand.lc * (lvl - 1), hand.mult + hand.lm * (lvl - 1), lvl
end

local function debuffed(blind, c)
  local b = blind.boss
  if not b then return false end
  if b.debuff == 'demon' then return R.isDemon(c) end
  if b.debuff == 'fire' then return R.isFire(c) end
  return false
end
R.debuffed = debuffed

function R.critChance(run, c)
  local p = A.CHARACTER.critPct
  if R.isShadow(c) then p = p + R.sumMod(run, 'critShadow') end
  if c.suit == R.IMMO then p = p + R.sumMod(run, 'critImmolate') end
  return min(100, p)
end
function R.critMult(run, c)
  if (c.suit ~= R.CORR and R.has(run, 'ruin')) or (c.suit == R.CORR and R.has(run, 'pandemic')) then return 2 end
  return A.CHARACTER.critMult
end

local function applyEffect(ctx, e, step)
  if not e then return false end
  if e.chips then ctx.chips = ctx.chips + e.chips; step.chips = (step.chips or 0) + e.chips end
  if e.mult then ctx.mult = ctx.mult + e.mult; step.mult = (step.mult or 0) + e.mult end
  if e.xmult then ctx.mult = ctx.mult * e.xmult; step.xmult = (step.xmult or 1) * e.xmult end
  if e.gold then ctx.gold = ctx.gold + e.gold; step.gold = (step.gold or 0) + e.gold end
  return true
end

-- Plays the cards with these ids. Returns the report, or nil and a reason.
function R.play(run, ids)
  local b = run.blind
  if run.phase ~= 'blind' or not b or b.hands <= 0 then return nil, 'No hands left' end
  local chosen, rest, pick = {}, {}, {}
  for _, id in ipairs(ids) do pick[id] = true end
  for _, c in ipairs(b.hand) do if pick[c.id] then chosen[#chosen + 1] = c else rest[#rest + 1] = c end end
  if #chosen < 1 or #chosen > 5 then return nil, 'Select 1 to 5 cards' end
  local hand, scoring = R.evaluate(chosen)
  local chips, mult, lvl = R.handValues(run, hand)
  local ctx = { run = run, hand = hand, chips = chips, mult = mult, gold = 0, held = rest, count = {}, cardIndex = 0,
    healthLeftPct = 100 * (b.info.health - b.score) / b.info.health, lastHand = b.hands == 1 }
  local report = { hand = hand, level = lvl, played = chosen, scoring = {}, steps = {}, baseChips = chips, baseMult = mult }
  local scoringSet = {}
  for _, c in ipairs(scoring) do scoringSet[c] = true end
  for _, c in ipairs(chosen) do report.scoring[c.id] = scoringSet[c] or false end
  local steps = report.steps
  local function push(s) s.chipsAfter, s.multAfter = ctx.chips, ctx.mult; steps[#steps + 1] = s; return s end
  push({ kind = 'hand' })
  if b.boss and b.boss.handCost and run.gold > 0 then
    local burn = min(run.gold, b.boss.handCost)
    run.gold = run.gold - burn
    push({ kind = 'boss', text = b.boss.spell .. ': -' .. burn .. ' gold', gold = -burn })
  end
  local nightfall = 0
  local shattered = {}
  local first = true
  local scored = 0
  for _, c in ipairs(scoring) do
    ctx.cardIndex = ctx.cardIndex + 1
    local times = 1
    if R.has(run, 'conflagrate') and c.suit == R.IMMO then times = times + 1 end
    if c.suit == R.SB and nightfall > 0 then times = times + 1; nightfall = nightfall - 1 end
    if first and R.has(run, 'baneOfHavoc') then times = times + 1 end
    local countered = first and b.boss and b.boss.counterFirst
    first = false
    if countered then push({ kind = 'card', card = c.id, text = 'Countered', none = true })
    elseif debuffed(b, c) then push({ kind = 'card', card = c.id, text = b.boss.spell, none = true })
    else
      for k = 1, times do
        scored = scored + 1
        ctx.count[c.suit] = (ctx.count[c.suit] or 0) + (k == 1 and 1 or 0)
        if R.isShadow(c) then ctx.shadowScored = true end
        if R.isFire(c) then ctx.fireScored = true end
        if R.isDemon(c) then ctx.demonScored = true end
        local base = R.rankChips(c.rank)
        local crit = random() * 100 < R.critChance(run, c)
        local gain = crit and floor(base * R.critMult(run, c) + 0.5) or base
        ctx.chips = ctx.chips + gain
        push({ kind = 'card', card = c.id, chips = gain, crit = crit, critMult = crit and R.critMult(run, c) or nil, again = k > 1 })
        if crit and c.suit == R.SB and R.has(run, 'improvedShadowBolt') and not ctx.isb then ctx.isb = ctx.cardIndex end
        if c.enh == 'spellstone' then ctx.chips = ctx.chips + 30; push({ kind = 'card', card = c.id, chips = 30, text = 'Spellstone' }) end
        if c.enh == 'oil' then ctx.mult = ctx.mult + 4; push({ kind = 'card', card = c.id, mult = 4, text = 'Wizard Oil' }) end
        if c.enh == 'supreme' then ctx.mult = ctx.mult * 2; push({ kind = 'card', card = c.id, xmult = 2, text = 'Supreme Power' }) end
        for slot, key in ipairs(run.talents) do
          local d = T[key]
          if d and d.kind == 'card' then
            local s = { kind = 'talent', slot = slot, talent = key, card = c.id }
            if applyEffect(ctx, d.fn(ctx, c), s) then push(s) end
          end
        end
        if c.suit == R.CORR and R.has(run, 'nightfall') and random() < 1 / 4 then
          nightfall = nightfall + 1
          push({ kind = 'talent', slot = R.slotOf(run, 'nightfall'), talent = 'nightfall', text = 'Shadow Trance!' })
        end
      end
      if c.suit == R.IMMO then ctx.immolateSeen = true end
      if c.enh == 'supreme' and random() < 0.25 then shattered[#shattered + 1] = c end
    end
  end
  for slot, key in ipairs(run.talents) do
    local d = T[key]
    if d and d.kind == 'hand' then
      local s = { kind = 'talent', slot = slot, talent = key }
      if applyEffect(ctx, d.fn(ctx), s) then push(s) end
    end
  end
  local damage = floor(ctx.chips * ctx.mult)
  if b.boss and b.boss.firstHalf and b.handsPlayed == 0 then
    damage = floor(damage / 2)
    push({ kind = 'boss', text = b.boss.spell .. ': half damage' })
  end
  report.chips, report.mult, report.damage, report.gold = ctx.chips, ctx.mult, damage, ctx.gold
  -- the result
  b.score = b.score + damage
  b.hands = b.hands - 1
  b.handsPlayed = b.handsPlayed + 1
  run.gold = run.gold + ctx.gold
  run.played[hand.key] = (run.played[hand.key] or 0) + 1
  run.stats.hands = run.stats.hands + 1
  run.stats.damage = run.stats.damage + damage
  if damage > run.stats.best then run.stats.best = damage; run.stats.bestHand = hand.name end
  for _, c in ipairs(shattered) do R.removeFromDeck(run, c.id) end
  report.shattered = shattered
  b.hand = rest
  report.won = b.score >= b.info.health
  if report.won then
    report.cashout = R.win(run)
  elseif b.hands <= 0 then
    run.phase = 'over'; report.lost = true
  else
    report.drawn = R.fillHand(run)
    R.sortHand(run, run.sortBy)
  end
  return report
end
function R.slotOf(run, key) for i, k in ipairs(run.talents) do if k == key then return i end end end
function R.removeFromDeck(run, id) for i, c in ipairs(run.deck) do if c.id == id then table.remove(run.deck, i); return true end end end
function R.findCard(run, id) for _, c in ipairs(run.deck) do if c.id == id then return c end end end

function R.discard(run, ids)
  local b = run.blind
  if run.phase ~= 'blind' or b.discards <= 0 then return nil, 'No discards left' end
  if #ids < 1 or #ids > 5 then return nil, 'Select 1 to 5 cards' end
  local cost = b.boss and b.boss.discardCost or 0
  if cost > 0 and run.gold < cost then return nil, 'Not enough gold (' .. b.boss.spell .. ')' end
  local pick, gone, rest = {}, {}, {}
  for _, id in ipairs(ids) do pick[id] = true end
  for _, c in ipairs(b.hand) do if pick[c.id] then gone[#gone + 1] = c else rest[#rest + 1] = c end end
  b.hand = rest
  b.discards = b.discards - 1
  run.gold = run.gold - cost
  local drawn = R.fillHand(run)
  R.sortHand(run, run.sortBy)
  return { gone = gone, drawn = drawn, cost = cost }
end

-- the blind is beaten: money, then the shop (or the end of the run after Ragnaros)
function R.win(run)
  local b = run.blind
  local lines = {}
  local total = 0
  local function add(label, n) if n > 0 then lines[#lines + 1] = { label, n }; total = total + n end end
  add(b.info.name .. ' defeated', b.info.reward)
  add('Hands left (' .. b.hands .. ')', b.hands)
  add('Interest (1 per 5 gold, up to 5)', min(5, floor(run.gold / 5)))
  add('Soul Harvesting', R.sumMod(run, 'endGold'))
  if R.has(run, 'improvedLifeTap') then add('Improved Life Tap (' .. b.discards .. ' discards)', b.discards) end
  run.gold = run.gold + total
  local cash = { lines = lines, total = total, blind = b.info }
  if b.info.key == 'boss' then
    if b.info.boss.final and not run.endless then run.phase = 'victory'; run.won = true; cash.victory = true
    else run.ante = run.ante + 1; run.blindIndex = 1; run.phase = 'shop' end
  else
    run.blindIndex = run.blindIndex + 1; run.phase = 'shop'
  end
  run.blind = nil
  if run.phase == 'shop' then R.newShop(run) end
  return cash
end
function R.keepGoing(run)
  run.endless = true; run.ante = run.ante + 1; run.blindIndex = 1; run.phase = 'shop'; R.newShop(run)
end

-- ---- shop ----
function R.price(run, base)
  local d = R.sumMod(run, 'discount')
  if d <= 0 then return base end
  return max(1, min(base - 1, floor(base * (100 - d) / 100)))
end
local function rollTalent(run, taken)
  local pool = {}
  local wantRare = random() < 0.3
  for _, k in ipairs(R.TALENT_KEYS) do
    local d = T[k]
    if not R.has(run, k) and not taken[k] and ((d.rarity == 2) == wantRare) then pool[#pool + 1] = k end
  end
  if #pool == 0 then for _, k in ipairs(R.TALENT_KEYS) do if not R.has(run, k) and not taken[k] then pool[#pool + 1] = k end end end
  if #pool == 0 then return nil end
  return pool[random(1, #pool)]
end
local function rollItem()
  if random() < 0.45 then
    -- a grimoire: hands that can be played without special cards
    local list = { 'highCard', 'pair', 'twoPair', 'threeKind', 'straight', 'flush', 'fullHouse', 'fourKind', 'straightFlush' }
    return { kind = 'grimoire', hand = list[random(1, #list)] }
  end
  return { kind = 'item', key = R.ITEM_KEYS[random(1, #R.ITEM_KEYS)] }
end
function R.itemCost(run, it)
  return R.price(run, it.kind == 'grimoire' and 3 or R.ITEMS[it.key].cost)
end
function R.newShop(run, keepCost)
  local taken = {}
  local shop = { talents = {}, items = {} }
  for i = 1, 2 do local k = rollTalent(run, taken); if k then taken[k] = true; shop.talents[i] = { key = k } end end
  for i = 1, 2 do shop.items[i] = rollItem() end
  if not keepCost then run.rerollCost = 5 end
  run.shop = shop
  return shop
end
function R.reroll(run)
  if run.phase ~= 'shop' then return nil, 'Not in the shop' end
  local cost = R.price(run, run.rerollCost)
  if run.gold < cost then return nil, 'Not enough gold' end
  run.gold = run.gold - cost
  run.rerollCost = run.rerollCost + 1
  R.newShop(run, true)
  return true
end
function R.buyTalent(run, i)
  local offer = run.shop and run.shop.talents[i]
  if not offer or offer.sold then return nil, 'Nothing there' end
  if #run.talents >= run.maxTalents then return nil, 'No free talent slot (sell one first)' end
  local cost = R.price(run, T[offer.key].cost)
  if run.gold < cost then return nil, 'Not enough gold' end
  run.gold = run.gold - cost
  run.talents[#run.talents + 1] = offer.key
  offer.sold = true
  return true
end
function R.buyItem(run, i)
  local offer = run.shop and run.shop.items[i]
  if not offer or offer.sold then return nil, 'Nothing there' end
  local cost = R.itemCost(run, offer)
  if run.gold < cost then return nil, 'Not enough gold' end
  if offer.kind == 'grimoire' then
    run.gold = run.gold - cost
    offer.sold = true
    run.levels[offer.hand] = run.levels[offer.hand] + 1
    return true, 'levelup'
  end
  if #run.items >= run.maxItems then return nil, 'No free consumable slot' end
  run.gold = run.gold - cost
  run.items[#run.items + 1] = { key = offer.key }
  offer.sold = true
  return true
end
function R.sellValue(run, key) return max(1, floor(T[key].cost / 2)) end
function R.sellTalent(run, slot)
  local key = run.talents[slot]
  if not key then return nil end
  table.remove(run.talents, slot)
  local v = R.sellValue(run, key)
  run.gold = run.gold + v
  return v
end
function R.sellItem(run, slot)
  local it = run.items[slot]
  if not it then return nil end
  table.remove(run.items, slot)
  local v = max(1, floor(R.ITEMS[it.key].cost / 2))
  run.gold = run.gold + v
  return v
end
-- uses consumable `slot` on the hand cards with these ids
function R.useItem(run, slot, ids)
  local it = run.items[slot]
  if not it then return nil, 'Nothing there' end
  local d = R.ITEMS[it.key]
  ids = ids or {}
  if d.blindOnly and run.phase ~= 'blind' then return nil, 'Only during a blind' end
  if d.cards[2] > 0 and run.phase ~= 'blind' then return nil, 'Select cards in your hand during a blind' end
  if #ids < d.cards[1] or #ids > d.cards[2] then
    if d.cards[2] == 0 then ids = {} else return nil, d.cards[1] == d.cards[2] and ('Select ' .. d.cards[1] .. ' card') or ('Select 1 to ' .. d.cards[2] .. ' cards') end
  end
  local b = run.blind
  local cards = {}
  for _, id in ipairs(ids) do for _, c in ipairs(b.hand) do if c.id == id then cards[#cards + 1] = c end end end
  if d.enh then for _, c in ipairs(cards) do c.enh = d.enh end end
  if d.suit then for _, c in ipairs(cards) do c.suit = d.suit end end
  if d.discards then b.discards = b.discards + d.discards end
  if d.destroy then
    for _, c in ipairs(cards) do
      R.removeFromDeck(run, c.id)
      for i, h in ipairs(b.hand) do if h == c then table.remove(b.hand, i); break end end
    end
  end
  if d.copy then
    for _, c in ipairs(cards) do
      run.nextCard = run.nextCard + 1
      local copy = { id = run.nextCard, suit = c.suit, rank = c.rank, enh = c.enh }
      run.deck[#run.deck + 1] = copy
    end
  end
  table.remove(run.items, slot)
  if b then R.sortHand(run, run.sortBy) end
  return true
end
function R.leaveShop(run)
  if run.phase ~= 'shop' then return end
  run.shop = nil
  run.phase = 'select'
end
