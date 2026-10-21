// Drain Snake: a bot steers to the soul along a free path (breadth-first, through the game's key handler) and must
// drain many souls; the beam grows by one per soul and two per soul shard; it cannot turn straight back; the wall and
// the beam itself end it; the best is kept.
//   node tools/check-snake.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local S = A.SnakeRules
local NAMES = { { 0, -1, 'UP' }, { 0, 1, 'DOWN' }, { -1, 0, 'LEFT' }, { 1, 0, 'RIGHT' } }
-- the first step of a shortest free path from the head to (tx, ty), or nil
local function path(s, tx, ty)
  local blocked = {}
  for i = 1, #s.body - 1 do local b = s.body[i]; blocked[b[1] * 100 + b[2]] = true end
  local head = s.body[1]
  local q, from = { { head[1], head[2] } }, { [head[1] * 100 + head[2]] = 'start' }
  local i = 1
  while q[i] do
    local x, y = q[i][1], q[i][2]; i = i + 1
    if x == tx and y == ty then
      local k = x * 100 + y
      while from[k] ~= 'start' and from[from[k]] ~= 'start' do k = from[k] end
      local fx, fy = math.floor(k / 100), k % 100
      for _, d in ipairs(NAMES) do if head[1] + d[1] == fx and head[2] + d[2] == fy then return d[3] end end
    end
    for _, d in ipairs(NAMES) do
      local nx, ny = x + d[1], y + d[2]
      local k = nx * 100 + ny
      if nx >= 1 and nx <= S.W and ny >= 1 and ny <= S.H and not blocked[k] and not from[k] then from[k] = x * 100 + y; q[#q + 1] = { nx, ny } end
    end
  end
end
function SPLAY(limit)
  local g = A.games.snake.obj
  g:play()
  local s = g.s
  local shards, guard, lenOk = 0, 0, true
  local lastSouls = 0
  while not s.done and s.souls < limit and guard < 200000 do
    guard = guard + 1
    local before = s.score
    local target = s.shard or s.soul
    local d = path(s, target[1], target[2]) or path(s, s.soul[1], s.soul[2])
    if not d then
      for _, n in ipairs(NAMES) do local h = s.body[1]; local x, y = h[1] + n[1], h[2] + n[2]; if x >= 1 and x <= S.W and y >= 1 and y <= S.H and S.free(s, x, y) then d = n[3]; break end end
    end
    if d then g:OnKey(d) end
    -- one step at a time
    g:OnUpdate(S.step(s) + 0.0001)
    if s.score - before == 5 then shards = shards + 1 end
  end
  local expected = 3 + s.souls + 2 * shards
  -- the beam may still be growing by what it just ate
  local len = #s.body + s.grow
  return string.format('%s %d %d %d %d', tostring(s.done), s.souls, shards, len, expected)
end
function SRULES()
  local out = {}
  local s = S.new(5)
  S.turn(s, 'LEFT')
  out[#out + 1] = #s.queue == 0 and 'no reverse ok' or 'reverse BAD'
  s.body = { { S.W, 5 }, { S.W - 1, 5 }, { S.W - 2, 5 } }
  for i = 1, 3 do S.update(s, 0.2) end
  out[#out + 1] = s.done and 'wall ok' or 'wall BAD'
  local t = S.new(6)
  t.body = { { 5, 5 }, { 6, 5 }, { 6, 6 }, { 5, 6 }, { 4, 6 } }
  t.dir = { 0, 1 }
  S.update(t, 0.15)
  out[#out + 1] = t.done and 'bite ok' or 'bite BAD'
  return table.concat(out, ' ')
end
`, '=sbot');
host.run('__ADDON_NS.open("snake")');
let fail = '';
for (let i = 1; i <= 3 && !host.errors.length; i++) {
  host.run('math.randomseed(' + i + ')');
  const [done, souls, shards, len, expected] = String(host.call('SPLAY', 60)).split(' ');
  console.log('bot ' + i + ': ' + souls + ' souls, ' + shards + ' soul shards, beam ' + len + (done === 'true' ? ' (ended)' : ''));
  if (+souls < 30) fail += 'bot ' + i + ': only ' + souls + ' souls\n';
  if (len !== expected) fail += 'bot ' + i + ': beam ' + len + ', should be ' + expected + '\n';
}
const rules = String(host.call('SRULES'));
console.log('rules: ' + rules);
if (/BAD/.test(rules)) fail += rules + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
