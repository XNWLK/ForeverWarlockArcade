// Guess the DPS: every question has its answer inside the slider; a spot-on guess gets 100, one a quarter of the
// slider away 0; the daily round is the same for a day. Plays rounds through the real controls: the slider dragged
// with the cursor, Left / Right, Lock it in.
//   node tools/check-guessdps.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local Q = A.GuessDpsRules
function QPOOL()
  local out, bad = {}, 0
  for _, k in ipairs(Q.pool()) do
    out[#out + 1] = k.key .. '=' .. #k.list
    for _, x in ipairs(k.list) do if x.value < k.lo or x.value > k.hi then bad = bad + 1 end end
    if Q.points(k, k.list[1].value, k.list[1].value) ~= 100 then bad = bad + 1 end
    if Q.points(k, k.list[1].value + (k.hi - k.lo) / 4, k.list[1].value) ~= 0 then bad = bad + 1 end
  end
  return table.concat(out, ' ') .. '|' .. bad
end
function QDAILY() local a, b = Q.newRound(20750 * 613 + 17), Q.newRound(20750 * 613 + 17); for i = 1, 5 do if a.qs[i].item ~= b.qs[i].item then return 'different' end end; return 'same' end
function CLICK(b) local top = __web.topAt(b.__id); if top ~= b.__id then error('covered', 2) end; b:Click() end
local old = GetCursorPosition
function GetCursorPosition() if __CURX then return __CURX, __CURY end; return old() end
-- exact: drag the slider to the answer with the cursor; else push it all the way left with the keys
function QPLAY(exact)
  local g = A.games.guessdps.obj
  g:openPractice()
  local s = g.s
  for i = 1, 5 do
    local q = s.qs[s.at]
    local kind = Q.kindOf(q.kind)
    if exact then
      local f = (q.item.value - kind.lo) / (kind.hi - kind.lo)
      local sc = g.track:GetEffectiveScale()
      __CURX, __CURY = (g.track:GetLeft() + 700 * f) * sc, (g.track:GetBottom() + 8) * sc
      g.track:GetScript('OnMouseDown')(g.track)
      g:OnUpdate(0.02)
      g.track:GetScript('OnMouseUp')(g.track)
    else for k = 1, 120 do g:OnKey('LEFT') end end
    CLICK(g.lockBtn)
    CLICK(g.lockBtn)
  end
  return string.format('%s %d %s', tostring(s.done), s.total, g.msg:GetText())
end
`, '=qbot');
let fail = '';
const [pool, bad] = String(host.call('QPOOL')).split('|');
console.log('questions: ' + pool);
if (+bad) fail += bad + ' questions outside their slider or wrong points\n';
if (String(host.call('QDAILY')) !== 'same') fail += 'the daily round differs\n';
host.run('__ADDON_NS.open("guessdps")'); host.layout();
const ex = String(host.call('QPLAY', true));
console.log('spot-on round: ' + ex);
if (!/^true (49[0-9]|500) /.test(ex)) fail += 'a spot-on round: ' + ex + '\n';
const lo = String(host.call('QPLAY', false));
console.log('all-left round: ' + lo);
if (!/^true \d+ Round over/.test(lo) || +lo.split(' ')[1] > 300) fail += 'an all-left round: ' + lo + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
