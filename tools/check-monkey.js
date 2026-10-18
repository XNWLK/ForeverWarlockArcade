// A monkey test: opens each game and does thousands of random things to it - clicks on whatever the mouse can reach
// (hit-tested like the page does), presses and lets go, hovers (tooltips), keys, waits of random length, going back
// to the picker and in again. Any Lua error fails it, with the steps that led there.
//   node tools/check-monkey.js [steps per game=1500] [seed=1]
const { boot } = require('./host.js');
const STEPS = +process.argv[2] || 1500;
let seed = +process.argv[3] || 1;
const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
const pick = a => a[Math.floor(rnd() * a.length)];
const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'SPACE', 'ENTER', 'ESCAPE', 'LEFT', 'RIGHT', 'UP', 'DOWN', 'D', 'F', 'J', 'K', 'W', 'A', 'S', 'H', 'L', 'R'];
const host = boot({ quiet: true });
host.run('math.randomseed(' + seed + ')');
const games = String(host.run('GAMES = {}; for _, d in ipairs(__ADDON_NS.order) do GAMES[#GAMES + 1] = d.key end; GAMES_S = table.concat(GAMES, " ")') && '') || '';
host.run('function GAMELIST() return GAMES_S end');
const keys = host.call('GAMELIST').split(' ');
const label = id => [...host.nodes.values()].filter(x => x.parent === id && x.kind === 'font' && x.text).map(x => x.parsed.plain).join('|').slice(0, 40);
let fails = 0;
for (const game of keys) {
  host.errors.length = 0;
  host.run('__ADDON_NS.open("' + game + '")');
  const log = [];
  for (let i = 0; i < STEPS && !host.errors.length; i++) {
    host.layout();
    const r = rnd();
    if (r < 0.55) {
      const list = [...host.nodes.values()].filter(n => n.mouse && n.vis && n.rect && n.rect.w > 1 && n.kind !== 'root');
      if (!list.length) continue;
      const n = pick(list);
      const x = n.rect.l + n.rect.w * (0.2 + 0.6 * rnd()), y = n.rect.b + n.rect.h * (0.2 + 0.6 * rnd());
      const top = host.hitTest(x, y);
      if (!top) continue;
      host.cursor = { x, y };
      log.push('click ' + label(top) + ' (' + top + ')');
      host.script(top, 'OnEnter', false);
      host.script(top, 'OnMouseDown', 'LeftButton');
      if (rnd() < 0.3) host.advance(rnd() * 0.6);
      host.script(top, 'OnMouseUp', 'LeftButton');
      if (host.node(top)) host.script(top, 'OnClick', rnd() < 0.9 ? 'LeftButton' : 'RightButton');
      host.script(top, 'OnLeave');
    } else if (r < 0.8) {
      const k = pick(KEYS);
      log.push('key ' + k);
      host.key(k, true);
      if (rnd() < 0.5) host.advance(rnd() * 0.4);
      host.key(k, false);
    } else if (r < 0.98) {
      const t = rnd() < 0.8 ? rnd() * 0.8 : rnd() * 6;
      log.push('wait ' + t.toFixed(2));
      host.advance(t, 1 / 30);
    } else {
      log.push('back to the picker and in again');
      host.run('__ADDON_NS.open(nil); __ADDON_NS.open("' + game + '")');
    }
  }
  if (host.errors.length) {
    fails++;
    console.log('FAIL ' + game + ': ' + host.errors[0].split('\n').slice(0, 4).join(' / '));
    console.log('  last steps: ' + log.slice(-8).join(' > '));
  } else console.log('ok   ' + game + ' (' + STEPS + ' random steps)');
}
process.exit(fails ? 1 : 0);
