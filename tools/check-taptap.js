// Plays Tap Tap DPS at every speed with a bot that presses each note on time (and holds casts to the end), sometimes
// late, sometimes letting go early. Checks: a perfect run deals exactly the rotation's damage, misses and interrupted
// casts cost damage, no Lua errors, no "nil" on screen. Also prints the rotation (what the chart is made of).
//   node tools/check-taptap.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local T = A.TapTapRules
function TROT()
  local c = { shadowBolt = 0, corruption = 0, baneOfAgony = 0, immolate = 0, lifeTap = 0 }
  for _, x in ipairs(T.rotation()) do c[x.key] = c[x.key] + 1 end
  local s = T.newSong(2)
  return string.format('casts: %d Shadow Bolt, %d Corruption, %d Agony, %d Immolate, %d Life Tap; perfect DPS %.0f; %d notes in %.0f s at Normal', c.shadowBolt, c.corruption, c.baneOfAgony, c.immolate, c.lifeTap, T.perfectDps(s), #s.notes, s.length)
end
-- mistakes: 0 = perfect, else the share of notes pressed late (good), missed, or let go early
function TPLAY(speed, mistakes)
  local g = A.games.taptap.obj
  g.speedIndex = speed
  g:play()
  local s = g.s
  local plan = {}
  for i, n in ipairs(s.notes) do
    local r = math.random()
    plan[i] = mistakes == 0 and 'ok' or (r < mistakes and 'miss' or r < mistakes * 2 and 'late' or r < mistakes * 3 and 'early' or 'ok')
  end
  local step = 1 / 120
  local guard = 0
  while not s.done and guard < 100000 do
    guard = guard + 1
    for i, n in ipairs(s.notes) do
      if n.t > s.t + 0.2 then break end
      local p = plan[i]
      local at = n.t + (p == 'late' and 0.1 or 0)
      -- a note chained to a held one starts by itself: no press
      if not n.botDown and n.judged and s.held[n.lane] == n then n.botDown = true end
      if not n.botDown and p ~= 'miss' and s.t >= at - step / 2 then n.botDown = true; g:press(n.lane) end
      if n.botDown and n.hold and not n.botUp then
        local upAt = n.t + n.len * (p == 'early' and 0.4 or 1) + step
        -- let go at the end, unless the next cast of the lane has chained on (then that one is held now)
        if s.t >= upAt then n.botUp = true; if s.held[n.lane] == n or not s.held[n.lane] then g:release(n.lane) end end
      end
    end
    g:OnUpdate(step)
  end
  return string.format('%.3f %.3f %d %d %d %d', s.damage, s.perfect, s.counts.perfect, s.counts.good, s.counts.miss, s.counts.interrupted)
end
`, '=tbot');
host.run('__ADDON_NS.open("taptap")');
console.log(host.call('TROT'));
let fail = '';
for (let sp = 1; sp <= 3 && !host.errors.length; sp++) {
  host.run('math.randomseed(' + sp + ')');
  const [dmg, perfect, p, g, m, i] = String(host.call('TPLAY', sp, 0)).split(' ').map(Number);
  if (Math.abs(dmg - perfect) > 0.01 || g + m + i > 0) fail += 'speed ' + sp + ': a perfect run dealt ' + dmg + ' of ' + perfect + ' (' + p + '/' + g + '/' + m + '/' + i + ')\n';
  const r = String(host.call('TPLAY', sp, 0.08)).split(' ').map(Number);
  if (!(r[0] < r[1] && r[4] + r[5] > 0)) fail += 'speed ' + sp + ': mistakes did not cost anything ' + r.join(' ') + '\n';
  console.log('speed ' + sp + ': perfect ' + Math.round(dmg / 120) + ' DPS; with mistakes ' + Math.round(r[0] / 120) + ' DPS (' + r[2] + ' perfect, ' + r[3] + ' good, ' + r[4] + ' miss, ' + r[5] + ' interrupted)');
}
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
