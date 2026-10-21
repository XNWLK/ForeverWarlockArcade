// Warlock Connections: makes 400 puzzles and checks each one - four groups of four, sixteen different things, every
// thing fits exactly one of the four groups shown (no other answer possible), the daily puzzle is the same for a day.
// Then plays through the real buttons: a wrong guess, a "one away", the four groups (a win), and a lost puzzle.
//   node tools/check-connections.js
const { boot } = require('./host.js');
const host = boot();
host.run(`
local A = __ADDON_NS
local R = A.ConnectionsRules
function CCHECK(n)
  local bad, fails, used = {}, 0, {}
  for seed = 1, n do
    local s = R.newPuzzle(seed * 7 + 3)
    if not s then fails = fails + 1 else
      local seen = {}
      for gi, g in ipairs(s.groups) do
        used[g.cat] = (used[g.cat] or 0) + 1
        for _, name in ipairs(g.items) do
          if seen[name] then bad[#bad + 1] = seed .. ': ' .. name .. ' twice' end
          seen[name] = true
          local it = R._byName[name]
          local fits = 0
          for _, o in ipairs(s.groups) do for _, c in ipairs(R.CATS) do if c[1] == o.cat and c[4](it) then fits = fits + 1 end end end
          if fits ~= 1 then bad[#bad + 1] = seed .. ': ' .. name .. ' fits ' .. fits .. ' groups' end
        end
      end
      if #s.board ~= 16 then bad[#bad + 1] = seed .. ': board of ' .. #s.board end
    end
  end
  local cats = 0
  for _ in pairs(used) do cats = cats + 1 end
  return fails .. '|' .. cats .. '/' .. #R.CATS .. '|' .. table.concat(bad, '; ')
end
function CDAILY() local a, b = R.newPuzzle(R.dailySeed(20750)), R.newPuzzle(R.dailySeed(20750)); return table.concat(a.board, ',') == table.concat(b.board, ',') and 'same' or 'different' end
function CLICK(b)
  local top = __web.topAt(b.__id)
  if top ~= b.__id then error('button covered by another frame: ' .. tostring(b.label and b.label:GetText() or b.__id), 2) end
  b:Click()
end
local function tileOf(g, name) for _, t in ipairs(g.tiles) do if t:IsShown() and t.itemName == name then return t end end end
local function pick(g, names) if #g.picked > 0 then CLICK(g.clearBtn) end; for _, n in ipairs(names) do CLICK(tileOf(g, n)) end end
-- plays the open puzzle: first a wrong guess and a one-away, then the four groups
function CPLAY(lose)
  local g = A.games.connections.obj
  local s = g.s
  local out = {}
  local a, b = s.groups[1].items, s.groups[2].items
  pick(g, { a[1], a[2], b[1], b[2] }); CLICK(g.submitBtn); out[#out + 1] = g.msg:GetText()
  pick(g, { a[1], a[2], a[3], b[1] }); CLICK(g.submitBtn); out[#out + 1] = g.msg:GetText()
  if lose then
    local c, d = s.groups[3].items, s.groups[4].items
    pick(g, { c[1], c[2], d[1], d[2] }); CLICK(g.submitBtn)
    pick(g, { c[1], d[1], d[2], d[3] }); CLICK(g.submitBtn)
    out[#out + 1] = g.msg:GetText()
    return table.concat(out, '|') .. '|' .. tostring(s.done) .. ' ' .. tostring(s.won) .. ' bars ' .. (g.bars[4]:IsShown() and 4 or 0)
  end
  for gi = 4, 1, -1 do pick(g, s.groups[gi].items); CLICK(g.submitBtn) end
  out[#out + 1] = g.msg:GetText()
  return table.concat(out, '|') .. '|' .. tostring(s.done) .. ' ' .. tostring(s.won) .. ' ' .. s.mistakes
end
function CSTATS() local db = A.db('connections'); return (db.played or 0) .. ' ' .. (db.won or 0) .. ' ' .. (db.streak or 0) end
`, '=cbot');
let fail = '';
const [fails, cats, bad] = String(host.call('CCHECK', 400)).split('|');
console.log('400 puzzles: ' + fails + ' could not be made, groups used ' + cats);
if (+fails) fail += fails + ' puzzles could not be made\n';
if (bad) fail += bad.slice(0, 600) + '\n';
if (String(host.call('CDAILY')) !== 'same') fail += 'the daily puzzle differs for the same day\n';
host.run('__ADDON_NS.open("connections")'); host.layout();
const win = String(host.call('CPLAY', false));
console.log('daily: ' + win);
if (!/^Not a group\|One away\.\.\.\|Solved with 2 mistakes\|true true 2$/.test(win)) fail += 'daily play: ' + win + '\n';
if (String(host.call('CSTATS')) !== '1 1 1') fail += 'stats after the daily: ' + host.call('CSTATS') + '\n';
// a reload: the saved daily puzzle comes back without anything built yet
host.run('local R = __ADDON_NS.ConnectionsRules; R._items, R._byName = nil, nil; local g = __ADDON_NS.games.connections.obj; g.s = nil; __ADDON_NS.open(nil); __ADDON_NS.open("connections")'); host.layout();
if (host.errors.length) fail += 'the saved daily puzzle does not open after a reload\n';
host.run('__ADDON_NS.games.connections.obj:openPractice()'); host.layout();
const lose = String(host.call('CPLAY', true));
console.log('practice, lost: ' + lose);
if (!/Out of mistakes - here are the groups\|true false bars 4$/.test(lose)) fail += 'lost play: ' + lose + '\n';
if (String(host.call('CSTATS')) !== '1 1 1') fail += 'practice changed the daily stats: ' + host.call('CSTATS') + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
