// Solves many Warlockle puzzles with a bot that keeps only the talents that fit every answer so far. Fails if the
// answers ever rule out the real talent (wrong feedback) or on a Lua error; reports how often the bot solves it.
// Also clicks through the screen once (daily, a full miss, practice).
//   node tools/check-warlockle.js [puzzles=300]
const { boot } = require('./host.js');
const N = +process.argv[2] || 300;
const host = boot();
host.run(`
local A = __ADDON_NS
local W = A.WarlockleRules
local function fits(candidate, guess, cmp) local c = W.compare(guess, candidate); for k, v in pairs(cmp) do if c[k] ~= v then return false end end; return true end
function WSOLVE(seed)
  math.randomseed(seed)
  local target = A.TALENT_ORDER[math.random(1, #A.TALENT_ORDER)]
  local s = W.new(target, false)
  local cands = {}
  for _, k in ipairs(A.TALENT_ORDER) do cands[#cands + 1] = k end
  while not s.done do
    local g = cands[math.random(1, #cands)]
    W.guess(s, g)
    local cmp = W.compare(g, target)
    local keep = {}
    for _, k in ipairs(cands) do if k ~= g and fits(k, g, cmp) then keep[#keep + 1] = k end end
    if not s.done then
      local found = false
      for _, k in ipairs(keep) do if k == target then found = true end end
      assert(found, 'the answers ruled out the real talent ' .. target .. ' after guessing ' .. g)
    end
    cands = keep
  end
  return s.won and #s.guesses or 0
end
function WSCREEN()
  local g = A.games.warlockle.obj
  g:openDaily()
  for _, k in ipairs(A.TALENT_ORDER) do if not g.s.done and k ~= g.s.target then g:guess(k) end end
  assert(g.s.done and not g.s.won and #g.s.guesses == W.MAX, 'a daily puzzle should end after ' .. W.MAX .. ' misses')
  g:openPractice(); g:guess(g.s.target)
  assert(g.s.won, 'guessing the target should win')
  return 'ok'
end
`, '=wbot');
host.run('__ADDON_NS.open("warlockle")');
let solved = 0, tries = 0;
for (let i = 0; i < N && !host.errors.length; i++) { const n = host.call('WSOLVE', 3000 + i); if (n > 0) { solved++; tries += n; } }
host.call('WSCREEN');
if (host.errors.length) { console.log('FAIL: ' + host.errors.join('\n')); process.exit(1); }
console.log(N + ' puzzles: the bot solved ' + Math.round(100 * solved / N) + '% in ' + (tries / Math.max(1, solved)).toFixed(2) + ' guesses on average');
console.log('OK');
