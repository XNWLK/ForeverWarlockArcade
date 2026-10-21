// Ritual of Summoning: a bot with a perfect memory repeats the sequence (clicking the runes, the way a player does)
// for 15 rounds - each round one longer; a wrong rune breaks it and the best is kept; presses while the sequence is
// shown are ignored; leaving and coming back mid-sequence shows it again.
//   node tools/check-ritual.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local R = A.RitualRules
function CLICK(b) local top = __web.topAt(b.__id); if top ~= b.__id then error('covered', 2) end; b:GetScript('OnMouseDown')(b) end
function RPLAY(rounds)
  local g = A.games.ritual.obj
  g:play()
  local s = g.s
  local early = 0
  -- a press during the show does nothing
  CLICK(g.runes[1]); if s.at ~= 0 or s.done then early = 1 end
  for r = 1, rounds do
    local guard = 0
    while s.phase ~= 'repeat' and guard < 2000 do guard = guard + 1; g:OnUpdate(1 / 30) end
    if r == 3 then __ADDON_NS.open(nil); __ADDON_NS.open('ritual') end
    while s.phase ~= 'repeat' and guard < 4000 do guard = guard + 1; g:OnUpdate(1 / 30) end
    if #s.seq ~= r then return 'length ' .. #s.seq .. ' in round ' .. r end
    for _, i in ipairs(s.seq) do CLICK(g.runes[i]) end
  end
  while s.phase ~= 'repeat' do g:OnUpdate(1 / 30) end
  local wrong = (s.seq[1] % 4) + 1
  CLICK(g.runes[wrong])
  return string.format('%s %d %d %d', tostring(s.done), s.round, A.db('ritual').best or 0, early)
end
`, '=rbot');
host.run('__ADDON_NS.open("ritual")'); host.layout();
let fail = '';
const r = String(host.call('RPLAY', 15)).split(' ');
console.log('15 rounds repeated, then a wrong rune: ' + r.join(' '));
if (r[0] !== 'true' || r[1] !== '16' || r[2] !== '15' || r[3] !== '0') fail += 'play: ' + r.join(' ') + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
