// Plays Higher or Lower with a bot that knows the answer most of the time, through the buttons (clicked like a mouse).
// Fails on Lua errors, a covered button, "nil" on screen, a pair of cards too close to call, or a card without a number.
//   node tools/check-higher.js [games=30]
const { boot } = require('./host.js');
const GAMES = +process.argv[2] || 30;
const host = boot();
host.run(`
local A = __ADDON_NS
local H = A.HigherLowerRules
function CLICK(b)
  local top = __web.topAt(b.__id)
  if top ~= b.__id then error('button covered by another frame: ' .. tostring(b.label and b.label:GetText()), 2) end
  b:Click()
end
function HBOT()
  local g = A.games.higher.obj
  if g.overlay:IsShown() then CLICK(g.overlay.go); return 'start' end
  local s = g.s
  if s.last or g.wait then return 'wait' end
  assert(type(s.left.value) == 'number' and type(s.right.value) == 'number', 'card without a number')
  local gap = math.abs(s.left.value - s.right.value) / math.max(s.left.value, s.right.value)
  assert(gap > H.TOPICS[s.topic].gap * 0.99, 'cards too close to call: ' .. s.left.title .. ' / ' .. s.right.title)
  local up = s.right.value >= s.left.value
  if math.random() < 0.1 then up = not up end
  CLICK(up and g.higher or g.lower)
  return 'guess'
end
function HINFO() local g = A.games.higher.obj; return (g.s and g.s.streak or 0) .. ' ' .. (g.s and g.s.topic or '-') end
function HOVER() return A.games.higher.obj.overlay:IsShown() end
function HSIZES() local t = {}; for _, k in ipairs(H.TOPIC_ORDER) do t[#t + 1] = k .. ' ' .. #H.pool(k) end; return table.concat(t, ', ') end
`, '=hbot');
host.run('__ADDON_NS.open("higher")');
const streaks = [], bad = new Set();
for (let g = 0; g < GAMES && !host.errors.length; g++) {
  host.run('math.randomseed(' + (900 + g) + ')');
  let started = false;
  for (let i = 0; i < 400 && !host.errors.length; i++) {
    if (started && host.call('HOVER')) break;
    const what = host.call('HBOT');
    host.advance(0.6);
    if (what === 'guess') started = true;
    for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN|inf/.test(n.parsed.plain)) bad.add(n.parsed.plain);
  }
  streaks.push(+String(host.call('HINFO')).split(' ')[0]);
}
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (bad.size) { console.log('FAIL: text the game would not show:\n  ' + [...bad].join('\n  ')); process.exit(1); }
console.log(streaks.length + ' games, bot (90% right) streak avg ' + (streaks.reduce((a, b) => a + b, 0) / streaks.length).toFixed(1) + '; cards per topic: ' + host.call('HSIZES'));
console.log('OK');
