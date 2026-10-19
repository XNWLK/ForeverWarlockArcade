// Plays Soul Circles at every speed with a bot that points at each circle and clicks on time, follows the ball of
// every slider (cast) to the end - and with mistakes: late clicks, missed circles, letting go early, losing the ball.
// Checks: a perfect run deals exactly the rotation's damage, mistakes cost damage, the chart stays on the board with
// no circle on top of the one before it, the keys can be changed (and swap), no Lua errors, no "nil" on screen.
//   node tools/check-circles.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local O = A.CircleRules
local g
BOTX, BOTY = -999, -999
function CSONG()
  local out = {}
  for sp = 1, 3 do
    local s = O.newSong(sp)
    local bad, close, sliders = 0, 0, 0
    for i, o in ipairs(s.objs) do
      local m = s.r
      if o.x < m or o.x > O.W - m or o.y < m or o.y > O.H - m then bad = bad + 1 end
      if o.slider then sliders = sliders + 1; if o.ex < m or o.ex > O.W - m or o.ey < m or o.ey > O.H - m then bad = bad + 1 end end
      local p = s.objs[i - 1]
      if p then
        local px, py = p.slider and p.ex or p.x, p.slider and p.ey or p.y
        if (o.x - px) ^ 2 + (o.y - py) ^ 2 < (s.r * 1.5) ^ 2 then close = close + 1 end
      end
    end
    out[#out + 1] = string.format('%d %d %d %d', #s.objs, sliders, bad, close)
  end
  return table.concat(out, ',')
end
-- mistakes: 0 = perfect, else the share of circles clicked late, missed, let go early, or the ball lost
function CPLAY(speed, mistakes)
  g = A.games.circles.obj
  g.cursorOnBoard = function() return BOTX, BOTY end
  g.speedIndex = speed
  g:play()
  local s = g.s
  local plan = {}
  for i, o in ipairs(s.objs) do
    local r = math.random()
    plan[i] = mistakes == 0 and 'ok' or (r < mistakes and 'miss' or r < mistakes * 2 and 'late' or r < mistakes * 3 and 'early' or r < mistakes * 4 and 'lose' or 'ok')
  end
  local step = 1 / 120
  local guard, holding = 0, nil
  while not s.done and guard < 100000 do
    guard = guard + 1
    -- point at the next circle a little before its time, or follow the ball of the slider being held
    local tx, ty
    if holding then
      local p = plan[holding.i]
      tx, ty = O.ball(holding, s.t)
      if p == 'lose' and s.t > holding.t + holding.len * 0.4 then tx, ty = tx + 200, ty end
      if s.active ~= holding then
        g:release(holding.key2); holding = nil
      elseif p == 'early' and s.t > holding.t + holding.len * 0.3 then g:release(holding.key2); holding = nil
      end
    end
    for i = s.first, #s.objs do
      local o = s.objs[i]
      if o.t > s.t + 0.3 then break end
      if not o.judged then
        local p = plan[i]
        local at = o.t + (p == 'late' and 0.1 or 0)
        if not holding then tx, ty = o.x, o.y end
        if p ~= 'miss' and s.t >= at - step / 2 then
          BOTX, BOTY = o.x, o.y
          -- the other key than the one held
          local key = (holding and holding.key2 == 'Z') and 'X' or 'Z'
          if g.keys[1] ~= 'Z' then key = (holding and holding.key2 == g.keys[1]) and g.keys[2] or g.keys[1] end
          g:OnKey(key)
          if o.slider and o.judged and o.judged ~= 'miss' then
            if holding then g:release(holding.key2) end
            o.key2 = key; holding = o
          else g:OnKeyUp(key) end
          tx, ty = BOTX, BOTY
        end
        break
      end
    end
    if tx then BOTX, BOTY = tx, ty end
    g:OnUpdate(step)
  end
  if holding then g:release(holding.key2) end
  return string.format('%.3f %.3f %d %d %d %d %d %d', s.damage, s.perfect, s.counts.perfect, s.counts.good, s.counts.meh, s.counts.miss, s.counts.interrupted, s.maxCombo)
end
function CKEYS(i, key) local g = A.games.circles.obj; g.s.done = true; g:openKeys(); g:startBinding(i); g:OnKey(key); local r = table.concat(g.keys, ',') .. '|' .. (g.db.keys and table.concat(g.db.keys, ',') or 'none'); return r end
function CDEFAULTS() local g = A.games.circles.obj; g.db.keys = nil; g:loadKeys(); g:closeKeys(); return table.concat(g.keys, ',') end
`, '=cbot');
host.run('__ADDON_NS.open("circles")');
let fail = '';
const songs = String(host.call('CSONG')).split(',');
songs.forEach((x, i) => {
  const [n, sl, bad, close] = x.split(' ').map(Number);
  console.log('speed ' + (i + 1) + ': ' + n + ' circles, ' + sl + ' sliders, ' + bad + ' off the board, ' + close + ' on top of the one before');
  if (bad) fail += 'speed ' + (i + 1) + ': ' + bad + ' circles off the board\n';
  if (close) fail += 'speed ' + (i + 1) + ': ' + close + ' circles on top of the one before\n';
});
for (let sp = 1; sp <= 3 && !host.errors.length; sp++) {
  host.run('math.randomseed(' + sp + ')');
  const p = String(host.call('CPLAY', sp, 0)).split(' ').map(Number);
  if (Math.abs(p[0] - p[1]) > 0.01 || p[3] + p[4] + p[5] + p[6] > 0) fail += 'speed ' + sp + ': a perfect run dealt ' + p[0] + ' of ' + p[1] + ' (' + p.slice(2).join('/') + ')\n';
  const r = String(host.call('CPLAY', sp, 0.06)).split(' ').map(Number);
  if (!(r[0] < r[1] && r[5] > 0 && r[6] > 0)) fail += 'speed ' + sp + ': mistakes did not cost anything ' + r.join(' ') + '\n';
  console.log('speed ' + sp + ': perfect ' + Math.round(p[0] / 120) + ' DPS (combo ' + p[7] + '); with mistakes ' + Math.round(r[0] / 120) + ' DPS (' + r[2] + ' perfect, ' + r[3] + ' good, ' + r[4] + ' meh, ' + r[5] + ' miss, ' + r[6] + ' interrupted)');
}
// keys: Q for key 1, then X (taken by key 2) for key 1 swaps them; a run with the new keys still plays
let k = String(host.call('CKEYS', 1, 'Q'));
if (k !== 'Q,X|Q,X') fail += 'key 1 to Q: ' + k + '\n';
k = String(host.call('CKEYS', 2, 'Q'));
if (k !== 'X,Q|X,Q') fail += 'key 2 to Q should swap: ' + k + '\n';
host.run('math.randomseed(9)');
const q = String(host.call('CPLAY', 2, 0)).split(' ').map(Number);
if (Math.abs(q[0] - q[1]) > 0.01) fail += 'a perfect run with keys X,Q dealt ' + q[0] + ' of ' + q[1] + '\n';
if (String(host.call('CDEFAULTS')) !== 'Z,X') fail += 'defaults\n';
console.log('keys: changed and swapped, a run with X / Q is perfect too');
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
