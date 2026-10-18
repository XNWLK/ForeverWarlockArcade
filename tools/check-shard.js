// Plays Shard & Mult start to finish many times, through the game's own buttons (Button:Click runs the same OnClick as
// the mouse), with a simple bot: best poker hand it can see, discards the rest, buys what it can afford.
// Fails on any Lua error, on a number printed the Lua 5.3 way ("3.0", which the game would never show) and on broken
// rules (cards that vanish, gold below zero). Prints how far the bot gets, as a rough balance check.
//   node tools/check-shard.js [runs=40]
const { boot } = require('./host.js');
const RUNS = +process.argv[2] || 40;

const DRIVER = `
local A = __ADDON_NS
local R, K = A.ShardRules, A.Kit
BOT = {}
function BOT.game() return A.games.shard.obj end
local function combos(list, k, start, cur, out)
  if #cur == k then local t = {}; for i, c in ipairs(cur) do t[i] = c end; out[#out + 1] = t; return end
  for i = start, #list do cur[#cur + 1] = list[i]; combos(list, k, i + 1, cur, out); cur[#cur] = nil end
end
-- the play the bot likes best: base chips x mult of the hand plus the scoring cards' rank chips
function BOT.best(run)
  local hand = run.blind.hand
  local best, bestV, bestHand
  for k = 1, math.min(5, #hand) do
    local all = {}
    combos(hand, k, 1, {}, all)
    for _, set in ipairs(all) do
      local h, scoring = R.evaluate(set)
      local chips, mult = R.handValues(run, h)
      for _, c in ipairs(scoring) do if not R.debuffed(run.blind, c) then chips = chips + R.rankChips(c.rank) end end
      local v = chips * mult - (#set - #scoring) * 0.5
      if not bestV or v > bestV then best, bestV, bestHand = set, v, h end
    end
  end
  return best, bestV, bestHand
end
function BOT.step()
  local g = BOT.game()
  if g:busy() then return 'busy' end
  if g.cashPanel:IsShown() then g.cashPanel.go:Click(); return 'collect' end
  if g.confirmPanel:IsShown() then g.confirmPanel.no:Click(); return 'confirm' end
  local run = g.run
  if run.phase == 'select' then g.selectPanel.cols[run.blindIndex].go:Click(); return 'fight' end
  if run.phase == 'blind' then
    local set, v = BOT.best(run)
    local b = run.blind
    local need = b.info.health - b.score
    g.selected = {}
    -- discard when the best play is weak: keep a flush draw (3+ of a suit) or the best cards
    if b.discards > 0 and v * b.hands < need * 1.3 and (not b.boss or not b.boss.discardCost or run.gold >= b.boss.discardCost) then
      local keep, bySuit = {}, {}
      for _, c in ipairs(b.hand) do bySuit[c.suit] = (bySuit[c.suit] or 0) + 1 end
      local fs, fn = nil, 0
      for s, n in pairs(bySuit) do if n > fn then fs, fn = s, n end end
      if fn >= 3 and fn < 5 then for _, c in ipairs(b.hand) do if c.suit == fs then keep[c.id] = true end end
      else for _, c in ipairs(set) do keep[c.id] = true end end
      local n = 0
      for i = #b.hand, 1, -1 do local c = b.hand[i]; if not keep[c.id] and n < 5 then g.selected[c.id] = true; n = n + 1 end end
      if n > 0 then g:afterSelect(); g.discard:Click(); return 'discard' end
    end
    for _, c in ipairs(set) do g.selected[c.id] = true end
    g:afterSelect()
    -- sometimes use a consumable on the picked cards first
    if run.items[1] then g.picked = { kind = 'item', i = 1 }; g:refreshSlots(); g.slotAction2:Click() end
    g.play:Click()
    return 'play'
  end
  if run.phase == 'shop' then
    local s = g.shopPanel
    -- talents first, then a grimoire for the hand played most, the odd consumable; keep 5+ gold for interest late on
    local most, mostN = 'pair', -1
    for k, n in pairs(run.played) do if n > mostN then most, mostN = k, n end end
    for _, o in ipairs({ s.t1, s.t2 }) do if o.buy:IsShown() and o.buy:IsEnabled() then o.buy:Click() end end
    for i, o in ipairs({ s.i1, s.i2 }) do
      local it = run.shop.items[i]
      if o.buy:IsShown() and o.buy:IsEnabled() and ((it.kind == 'grimoire' and it.hand == most) or (it.kind == 'item' and math.random() < 0.3)) then o.buy:Click() end
    end
    if #run.talents >= 5 and math.random() < 0.1 then g.picked = { kind = 'talent', i = math.random(1, 5) }; g:refreshSlots(); g.slotAction:Click() end
    if run.gold >= 14 and s.reroll:IsEnabled() then s.reroll:Click(); return 'reroll' end
    s.next:Click()
    return 'next'
  end
  if run.phase == 'over' or run.phase == 'victory' then return run.phase end
  return 'idle'
end
function BOT.check()
  local g = BOT.game(); local run = g.run
  assert(run.gold >= 0, 'gold below zero: ' .. run.gold)
  if run.blind then
    local seen = {}
    for _, c in ipairs(run.blind.hand) do assert(not seen[c.id], 'card twice'); seen[c.id] = true end
    for _, c in ipairs(run.blind.pile) do assert(not seen[c.id], 'card twice'); seen[c.id] = true end
    local inDeck = {}
    for _, c in ipairs(run.deck) do inDeck[c.id] = true end
    for id in pairs(seen) do assert(inDeck[id], 'card not in the deck') end
    assert(#run.blind.hand <= R.handSize(run, run.blind.info), 'hand too big')
  end
  return 'ok'
end
function BOT_STEP() return BOT.step() end
function BOT_CHECK() return BOT.check() end
function BOT_INFO() local run = BOT.game().run; return run.phase .. ' ' .. run.ante .. ' ' .. run.blindIndex .. ' ' .. #run.talents .. ' ' .. run.stats.best end
`;

const host = boot({ quiet: false });
host.run(DRIVER, '=driver');
host.run('__ADDON_NS.open("shard")');
const results = [], badText = new Set();
function textCheck() {
  for (const n of host.nodes.values()) {
    if (n.kind !== 'font' || !n.vis || !n.text) continue;
    const t = n.parsed.plain;
    if (/\d\.0(?!\d)/.test(t) || /\bnil\b/.test(t) || /\d{5,}\.\d/.test(t)) badText.add(t);
  }
}
for (let r = 0; r < RUNS && !host.errors.length; r++) {
  host.run('math.randomseed(' + (1000 + r) + '); BOT.game():newRun()');
  let steps = 0;
  while (steps++ < 4000) {
    const what = host.call('BOT_STEP');
    host.advance(0.3);
    if (what === 'play' || what === 'discard') { host.run('BOT.game().seq:finish()'); host.advance(0.3); }
    if (host.errors.length) break;
    host.call('BOT_CHECK');
    if (steps % 5 === 0) textCheck();
    if (what === 'over' || what === 'victory') break;
  }
  const [phase, ante, blind, talents, best] = String(host.call('BOT_INFO')).split(' ');
  results.push({ phase, ante: +ante, blind: +blind, talents: +talents, best: +best, steps });
}
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
const antes = results.map(r => r.ante);
const avg = antes.reduce((a, b) => a + b, 0) / antes.length;
const hist = {};
antes.forEach(a => { hist[a] = (hist[a] || 0) + 1; });
console.log(results.length + ' runs: average ante ' + avg.toFixed(2) + ', wins ' + results.filter(r => r.phase === 'victory').length +
  ', ante reached: ' + Object.keys(hist).sort((a, b) => a - b).map(k => k + ':' + hist[k]).join(' ') + ', best hand ' + Math.max(...results.map(r => r.best)));
if (badText.size) { console.log('FAIL: text the game would not show:\n  ' + [...badText].slice(0, 12).join('\n  ')); process.exit(1); }
console.log('OK');
