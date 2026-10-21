// Crack the Opener: the marks are right (checked against counting by hand), a bot that always guesses an opener that
// fits every mark so far cracks 300 openers within eight tries (and how many it needs), the daily opener is the same
// for a day; then plays one through the real buttons, and a lost one.
//   node tools/check-crack.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local X = A.CrackRules
local all = {}
for a = 1, 6 do for b = 1, 6 do for c = 1, 6 do for d = 1, 6 do all[#all + 1] = { a, b, c, d } end end end end
function XMARKS()
  local bad = 0
  for i = 1, 400 do
    local c, g = all[math.random(1, #all)], all[math.random(1, #all)]
    local gold, tot = 0, 0
    for k = 1, 4 do if c[k] == g[k] then gold = gold + 1 end end
    for v = 1, 6 do local nc, ng = 0, 0; for k = 1, 4 do if c[k] == v then nc = nc + 1 end; if g[k] == v then ng = ng + 1 end end; tot = tot + math.min(nc, ng) end
    local a, b = X.score(c, g)
    if a ~= gold or b ~= tot - gold then bad = bad + 1 end
  end
  return bad
end
local function solve(s, play)
  local cand = {}
  for _, x in ipairs(all) do cand[#cand + 1] = x end
  while not s.done do
    local guess = (#s.tries == 0) and { 1, 1, 2, 2 } or cand[1]
    local g, sv = play(guess)
    local keep = {}
    for _, x in ipairs(cand) do local a, b = X.score(x, guess); if a == g and b == sv then keep[#keep + 1] = x end end
    cand = keep
  end
  return s.won, #s.tries
end
function XSOLVE(n)
  local hist, lost = {}, 0
  for i = 1, n do
    local s = X.new(i * 31 + 7)
    local won, t = solve(s, function(guess) return X.guess(s, guess) end)
    if won then hist[t] = (hist[t] or 0) + 1 else lost = lost + 1 end
  end
  local out = {}
  for t = 1, 8 do out[#out + 1] = t .. ':' .. (hist[t] or 0) end
  return lost .. '|' .. table.concat(out, ' ')
end
function XDAILY() local a, b = X.new(20750 * 977 + 5), X.new(20750 * 977 + 5); return table.concat(a.code, ',') == table.concat(b.code, ',') and 'same' or 'different' end
function CLICK(b) local top = __web.topAt(b.__id); if top ~= b.__id then error('covered', 2) end; b:Click() end
function XPLAY(lose)
  local g = A.games.crack.obj
  local s = g.s
  local function play(guess)
    for _, v in ipairs(guess) do CLICK(g.pick[v]) end
    CLICK(g.goBtn)
    local t = s.tries[#s.tries]
    return t.gold, t.silver
  end
  if lose then
    local missing
    for v = 1, 6 do local inCode = false; for _, c in ipairs(s.code) do if c == v then inCode = true end end; if not inCode then missing = v end end
    for i = 1, 8 do play({ missing, missing, missing, missing }) end
    return tostring(s.done) .. ' ' .. tostring(s.won) .. ' ' .. g.msg:GetText()
  end
  local won, t = solve(s, play)
  return tostring(won) .. ' ' .. t .. ' ' .. g.msg:GetText()
end
`, '=xbot');
let fail = '';
const bad = +host.call('XMARKS');
if (bad) fail += bad + ' wrong marks\n';
const [lost, hist] = String(host.call('XSOLVE', 300)).split('|');
console.log('300 openers: lost ' + lost + ', tries needed ' + hist);
if (+lost > 3) fail += 'the bot lost ' + lost + ' of 300\n';
if (String(host.call('XDAILY')) !== 'same') fail += 'the daily opener differs\n';
host.run('__ADDON_NS.open("crack")'); host.layout();
const w = String(host.call('XPLAY', false));
console.log('daily: ' + w);
if (!/^true \d Cracked in \d!/.test(w)) fail += 'daily play: ' + w + '\n';
host.run('__ADDON_NS.games.crack.obj:openPractice()');
const l = String(host.call('XPLAY', true));
console.log('lost: ' + l);
if (l !== 'true false Out of tries - the opener was:') fail += 'lost play: ' + l + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
