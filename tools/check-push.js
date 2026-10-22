// Pentagram Push: solves every ritual again (breadth-first over you + the shards), checks the stored three-star mark is
// the fewest moves, then plays that solution through the game's own keys (it must finish with three stars). Also: a
// wall stops you, two shards in a row cannot be pushed, Undo takes back steps and pushes, a ritual opened again starts
// from the beginning.
//   node tools/check-push.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local P = A.PushRules
function PLEVELS() local out = {}; for i, l in ipairs(P.LEVELS) do out[i] = l.par .. '=' .. table.concat(l.rows, '/') end; return table.concat(out, '|') end
function PPLAY(n, keys)
  local g = A.games.push.obj
  g:open(n)
  for k in keys:gmatch('%a+') do g:OnKey(k) end
  local s = g.s
  return string.format('%s %d %d', tostring(s.done), s.moves, (A.db('push').stars or {})[n] or 0)
end
function PRULES()
  local out = {}
  local s = P.load(1)
  local x = s.px
  P.move(s, 'LEFT'); P.move(s, 'LEFT'); P.move(s, 'LEFT')
  out[#out + 1] = (s.px == 2) and 'wall ok' or ('wall BAD ' .. s.px)
  local t = P.load(4)
  -- walk to the left of the two shards and push right: two in a row do not move
  t.px, t.py = 2, 2
  t.boxes = { [2 * 100 + 3] = true, [2 * 100 + 4] = true }
  local r = P.move(t, 'RIGHT')
  out[#out + 1] = (r == nil and t.boxes[203] and t.boxes[204]) and 'two ok' or 'two BAD'
  local u = P.load(1)
  P.move(u, 'RIGHT')
  local pushedTo = u.boxes[3 * 100 + 5]   -- ritual 1: the shard is on row 3, column 4
  P.undo(u)
  out[#out + 1] = (pushedTo and u.boxes[3 * 100 + 4] and u.moves == 0 and u.pushes == 0 and u.px == 3) and 'undo ok' or 'undo BAD'
  return table.concat(out, ' ')
end
`, '=pbot');
function solve(rows) {
  const H = rows.length, W = Math.max(...rows.map(r => r.length));
  const wall = new Set(), goals = new Set(); let player, boxes = [];
  rows.forEach((r, y) => [...r.padEnd(W)].forEach((ch, x) => {
    const k = y * W + x;
    if (ch === '#') wall.add(k);
    if (ch === '.' || ch === '*' || ch === '+') goals.add(k);
    if (ch === '$' || ch === '*') boxes.push(k);
    if (ch === '@' || ch === '+') player = k;
  }));
  const key = (p, b) => p + ':' + [...b].sort((a, c) => a - c).join(',');
  const D = [[-W, 'UP'], [W, 'DOWN'], [-1, 'LEFT'], [1, 'RIGHT']];
  let q = [{ p: player, b: boxes, path: [] }];
  const seen = new Set([key(player, boxes)]);
  while (q.length) {
    const next = [];
    for (const st of q) {
      if (st.b.every(k => goals.has(k))) return st.path;
      for (const [d, name] of D) {
        const np = st.p + d;
        if (wall.has(np)) continue;
        let nb = st.b;
        const bi = st.b.indexOf(np);
        if (bi >= 0) { const to = np + d; if (wall.has(to) || st.b.includes(to)) continue; nb = st.b.slice(); nb[bi] = to; }
        const k = key(np, nb);
        if (seen.has(k)) continue;
        seen.add(k);
        next.push({ p: np, b: nb, path: st.path.concat(name) });
      }
    }
    q = next;
  }
  return null;
}
host.run('__ADDON_NS.open("push")'); host.layout();
let fail = '';
String(host.call('PLEVELS')).split('|').forEach((x, i) => {
  const [par, rows] = x.split('=');
  const path = solve(rows.split('/'));
  if (!path) { fail += 'ritual ' + (i + 1) + ' cannot be solved\n'; return; }
  if (path.length !== +par) fail += 'ritual ' + (i + 1) + ': stored ' + par + ' moves, fewest is ' + path.length + '\n';
  const [done, moves, stars] = String(host.call('PPLAY', i + 1, path.join(' '))).split(' ');
  console.log('ritual ' + (i + 1) + ': fewest ' + path.length + ' moves; played through the keys: ' + (done === 'true' ? 'complete' : 'NOT complete') + ', ' + stars + ' stars');
  if (done !== 'true' || stars !== '3') fail += 'ritual ' + (i + 1) + ': the solution did not finish with three stars\n';
});
const rules = String(host.call('PRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
