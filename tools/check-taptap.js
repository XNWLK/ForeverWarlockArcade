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
// changing keys: through the real screen (Change keys, click a row, press a key), saved, swapped when taken, used in play
host.run(`
local g = __ADDON_NS.games.taptap.obj
g.s.done = true
function KEYSTATE() return table.concat(g.keys, ',') .. '|' .. (g.db.keys and table.concat(g.db.keys, ',') or 'none') .. '|' .. g.lanes[1].key:GetText() .. '|' .. g.tapBtn.label:GetText() end
function CLICK(b)
  local top = __web.topAt(b.__id)
  if top ~= b.__id then error('button covered by another frame: ' .. tostring(b.label and b.label:GetText() or b.__id), 2) end
  b:Click()
end
function KCLICK(w) if w == 'open' then CLICK(g.keysBtn) else CLICK(g.keysPanel.rows[tonumber(w)]) end end
function KSHOWN() return g.keysPanel:IsShown() and 'yes' or 'no' end
function KEYPLAY(key)
  g:play()
  local s = g.s
  local n
  for _, m in ipairs(s.notes) do if m.lane == 1 then n = m; break end end
  while s.t < n.t - 0.01 do g:OnUpdate(1 / 120) end
  for _, m in ipairs(s.notes) do if not m.judged and m.t < n.t - 0.2 then m.judged = 'miss' end end
  local used = g:OnKey(key)
  local r = (used and 'used' or 'unused') .. ' lane ' .. n.lane .. ' ' .. tostring(n.judged)
  g:OnKeyUp(key)
  s.done = true
  return r
end
`, '=tkeys');
const press = k => { host.key(k, true); host.key(k, false); };
let ks = '';
host.layout(); host.call('KCLICK', 'open'); host.layout(); host.call('KCLICK', '1');
press('Q');
ks = String(host.call('KEYSTATE'));
if (!ks.startsWith('Q,F,J,K,SPACE|Q,F,J,K,SPACE|Q|')) fail += 'binding Q to lane 1: ' + ks + '\n';
host.call('KCLICK', '5');
press('F');
ks = String(host.call('KEYSTATE'));
if (!ks.startsWith('Q,SPACE,J,K,F|') || !ks.endsWith('(F)')) fail += 'binding F (taken by lane 2) to Life Tap should swap: ' + ks + '\n';
host.call('KCLICK', '3');
press('ESCAPE');
ks = String(host.call('KEYSTATE'));
if (!ks.startsWith('Q,SPACE,J,K,F|')) fail += 'Escape should keep the key: ' + ks + '\n';
press('ESCAPE');
if (host.call('KSHOWN') !== 'no') fail += 'Escape should close the keys panel\n';
let r = String(host.call('KEYPLAY', 'Q'));
console.log('keys: ' + ks + '; first lane 1 note with Q: ' + r);
if (!/^used lane 1 (perfect|good)/.test(r)) fail += 'Q should play lane 1: ' + r + '\n';
r = String(host.call('KEYPLAY', 'D'));
if (!/^unused/.test(r)) fail += 'D should do nothing once moved: ' + r + '\n';
// saved: a new game object reads the keys back
host.run('local A = __ADDON_NS; local g2 = A.games.taptap.create(UIParent); KEYS2 = table.concat(g2.keys, ",")');
host.run('function K2() return KEYS2 end');
if (String(host.call('K2')) !== 'Q,SPACE,J,K,F') fail += 'keys not saved: ' + host.call('K2') + '\n';
host.run('local g = __ADDON_NS.games.taptap.obj; g:openKeys(); g.db.keys = nil; g:loadKeys(); g:closeKeys()');
if (!String(host.call('KEYSTATE')).startsWith('D,F,J,K,SPACE|none|D|Life Tap  (Space)')) fail += 'defaults: ' + host.call('KEYSTATE') + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
