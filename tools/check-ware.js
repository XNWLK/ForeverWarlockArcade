// Plays Warlock Ware with a bot that answers right most of the time, through the game's own handlers, frame by frame.
// Fails on Lua errors and "nil" on screen; checks that every micro-game can be won and lost.
//   node tools/check-ware.js [games=8]
const { boot } = require('./host.js');
const GAMES = +process.argv[2] || 8;
const host = boot();
host.run(`
local A = __ADDON_NS
local G = A.WareGame
SEEN = {}
-- the right move in each micro-game (or a wrong one, 15% of the time)
function WBOT()
  local g = A.games.ware.obj
  if g.overlay:IsShown() then g.overlay.go:Click(); return 'start' end
  local m = g.m
  if g.phase ~= 'play' or not m or m.result then return '' end
  -- a new round of a micro-game: forget the last one, decide once whether to get it wrong
  if m ~= BOT_M or m.t < (BOT_T or 0) then m.botDone = nil; m.botWrong = math.random() < 0.15 end
  BOT_M, BOT_T = m, m.t
  if m.botDone then return '' end
  local k = m.def.key
  local wrong = m.botWrong
  if k == 'tap' then for _, b in ipairs(m.parts) do if (b.key == 'lifeTap') ~= wrong then b:Click(); m.botDone = true; break end end
  elseif k == 'queue' then if m.cast - m.t <= 0.3 or wrong then g:OnKey('SPACE'); m.botDone = true end
  elseif k == 'proc' then if m.shown and m.btn:IsShown() then if not wrong then m.btn:Click() end; m.botDone = true end
  elseif k == 'refresh' then for _, b in ipairs(m.parts) do if (b == m.low) ~= wrong then b:Click(); m.botDone = true; break end end
  elseif k == 'pick' then
    for _, b in ipairs(m.parts) do
      local right = m.q.ok and m.q.ok(b.key) or (not m.q.ok and b.key == m.answer)
      if right ~= wrong then b:Click(); m.botDone = true; break end
    end
  elseif k == 'drain' then if not wrong then m.btn:Click() end
  elseif k == 'bomb' then g:OnKey(m.safe == 1 and (wrong and 'RIGHT' or 'LEFT') or (wrong and 'LEFT' or 'RIGHT')); m.botDone = true
  end
  return k
end
function WRESULT() local g = A.games.ware.obj; for k, m in pairs(g.micros) do SEEN[k] = true end; return g.cleared .. ' ' .. (g.phase or '') end
function WSEEN() local n = 0; for _ in pairs(SEEN) do n = n + 1 end; return n .. '/' .. #G.ORDER end
`, '=wbot');
host.run('__ADDON_NS.open("ware")');
const scores = [], bad = new Set();
for (let i = 0; i < GAMES && !host.errors.length; i++) {
  host.run('math.randomseed(' + (100 + i) + ')');
  host.call('WBOT');
  for (let t = 0; t < 400 && !host.errors.length; t += 0.05) {
    host.call('WBOT'); host.advance(0.05, 0.05);
    if (Math.round(t * 20) % 40 === 0) for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) bad.add(n.parsed.plain);
    if (String(host.call('WRESULT')).endsWith('over')) break;
  }
  scores.push(+String(host.call('WRESULT')).split(' ')[0]);
}
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (bad.size) { console.log('FAIL: text the game would not show:\n  ' + [...bad].join('\n  ')); process.exit(1); }
console.log(scores.length + ' games, bot (85% right) cleared ' + (scores.reduce((a, b) => a + b, 0) / scores.length).toFixed(1) + ' on average; micro-games seen ' + host.call('WSEEN'));
console.log('OK');
