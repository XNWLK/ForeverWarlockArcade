// Fel Runner: a bot jumps the fire and the hounds and ducks the bats (through the game's key handler) and must run far;
// a short tap jumps lower than holding the key; a runner that does nothing crashes early; the same keys give the same
// run (fixed steps); the best is kept.
//   node tools/check-runner.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local R = A.RunnerRules
function RPLAY(bot, seed, limit)
  local g = A.games.runner.obj
  g:play(true)
  if seed then g.s = R.new(seed) end
  local s = g.s
  g:OnKey('SPACE'); g:OnKeyUp('SPACE')
  local guard, holding, ducking = 0, false, false
  while not s.done and guard < 400000 and s.dist < (limit or 1e9) do
    guard = guard + 1
    if bot then
      local nextOne
      for _, th in ipairs(s.things) do if th.kind ~= 'soul' and th.x + th.w > R.X - R.SIZE / 2 then nextOne = th; break end end
      local wantDuck, wantJump = false, false
      if nextOne then
        local gap = nextOne.x - (R.X + R.SIZE / 2)
        if nextOne.kind == 'bat' then wantDuck = gap < s.speed * 0.25
        else wantJump = gap < s.speed * 0.16 + 10 and gap > -nextOne.w end
      end
      if wantDuck ~= ducking then ducking = wantDuck; if wantDuck then g:OnKey('DOWN') else g:OnKeyUp('DOWN') end end
      if wantJump and not holding and R.onGround(s) and not s.duck then holding = true; g:OnKey('SPACE') end
      if holding and s.vy < 0 then holding = false; g:OnKeyUp('SPACE') end
    end
    g:OnUpdate(1 / 60)
  end
  return string.format('%s %.0f %d %d %d', tostring(s.done), s.dist / 10, s.souls, R.score(s), A.db('runner').best or 0)
end
function RJUMP(hold)
  local s = R.new(3)
  R.jump(s)
  local top = 0
  for i = 1, 120 do
    if not hold and i == 6 then R.release(s) end
    R.update(s, 1 / 120); top = math.max(top, s.y)
  end
  return top
end
`, '=rbot');
host.run('__ADDON_NS.open("runner")');
let fail = '';
for (let i = 1; i <= 3 && !host.errors.length; i++) {
  host.run('math.randomseed(' + i + ')');
  const [done, metres, souls] = String(host.call('RPLAY', true, null, 40000)).split(' ');
  console.log('bot ' + i + ': ' + metres + ' m, ' + souls + ' souls' + (done === 'true' ? ' (crashed)' : ''));
  if (+metres < 1500) fail += 'bot ' + i + ': only ' + metres + ' m\n';
}
const idle = String(host.call('RPLAY', false, 9)).split(' ');
console.log('no keys: crashed after ' + idle[1] + ' m');
if (idle[0] !== 'true' || +idle[1] > 200) fail += 'a runner that does nothing: ' + idle.join(' ') + '\n';
const tap = +host.call('RJUMP', false), hold = +host.call('RJUMP', true);
console.log('jump: tap ' + Math.round(tap) + ' px, hold ' + Math.round(hold) + ' px');
if (!(tap < hold * 0.8)) fail += 'a tap does not jump lower than holding\n';
const a = String(host.call('RPLAY', true, 4242, 8000)), b = String(host.call('RPLAY', true, 4242, 8000));
if (a.split(' ').slice(0, 3).join(' ') !== b.split(' ').slice(0, 3).join(' ')) fail += 'the same run came out different: ' + a + ' / ' + b + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
