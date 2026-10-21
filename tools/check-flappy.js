// Flappy Imp: a bot flies through the gaps (flaps whenever it sinks below the middle of the next gap) and must pass
// many pillars; a player who never flaps falls into the lava; the same seed and flaps give the same flight (fixed
// step); scores, soul shards and the best are kept; no Lua errors. Flaps go through the game's own key handler.
//   node tools/check-flappy.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local F = A.FlappyRules
function FPLAY(bot, limit, seed, botUntil)
  local g = A.games.flappy.obj
  g:play(true)
  if seed then g.s = F.new(seed) end
  local s = g.s
  g:OnKey('SPACE')
  local guard = 0
  while not s.done and guard < 200000 and s.score < (limit or 999) do
    guard = guard + 1
    if bot and s.score < (botUntil or 999) then
      local target
      for _, p in ipairs(s.pillars) do if p.x + F.PW > F.X - F.R then target = p.mid; break end end
      target = (target or F.H / 2) - 18
      if s.y < target and s.vy < 60 then g:OnKey('SPACE') end
    end
    g:OnUpdate(1 / 60)
  end
  return string.format('%d %d %.2f %s %d', s.score, s.shards, s.t, tostring(s.done), A.db('flappy').best or 0)
end
`, '=fbot');
host.run('__ADDON_NS.open("flappy")');
let fail = '';
const [score, shards, , , best] = String(host.call('FPLAY', true, 60)).split(' ').map(Number);
console.log('bot: ' + score + ' pillars, ' + shards + ' soul shards');
if (score < 30) fail += 'the bot passed only ' + score + ' pillars\n';
if (!shards) fail += 'no soul shard collected\n';
const idle = String(host.call('FPLAY', false, 999)).split(' ');
console.log('no flaps: ' + idle[0] + ' pillars, fell after ' + idle[2] + ' s');
if (idle[3] !== 'true' || +idle[0] !== 0 || +idle[2] > 3) fail += 'a player who never flaps: ' + idle.join(' ') + '\n';
const a = String(host.call('FPLAY', true, 25, 777)), b = String(host.call('FPLAY', true, 25, 777));
if (a.split(' ').slice(0, 3).join(' ') !== b.split(' ').slice(0, 3).join(' ')) fail += 'the same flight came out different: ' + a + ' / ' + b + '\n';
// a flight that ends (the bot stops flapping after 12): the best is kept
host.run('__ADDON_NS.db("flappy").best = nil');
const end = String(host.call('FPLAY', true, 999, 5, 12)).split(' ').map(Number);
console.log('a flight that ends at ' + end[0] + ': best ' + end[4]);
if (end[4] !== end[0] || end[0] < 12) fail += 'best not kept: ' + end.join(' ') + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
