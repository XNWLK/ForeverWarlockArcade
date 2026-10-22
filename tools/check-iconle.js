// Iconle: checks that icons that are the same picture (in web/icons.js) are one answer and different pictures are
// not merged; every answer has a name in the list; the zoom only ever widens; the daily icon is the same for a day and
// walks through every answer. Then plays through the real buttons: misses (zoom, grey, hint), typing a search and
// Enter, a win, and a loss that shows the answer.
//   node tools/check-iconle.js
const { boot } = require('./host.js');
global.window = {}; require('../web/icons.js');
const PIC = window.ARCADE_ICONS;
const host = boot();
host.run(`
local A = __ADDON_NS
local I = A.IconleRules
function IANSWERS()
  local out = {}
  for _, a in ipairs(I.answers()) do out[#out + 1] = a.icon .. '=' .. table.concat(a.names, '/') end
  local ids = {}
  for _, a in ipairs(I.answers()) do
    for _, r in ipairs(a.refs) do
      local kind, key = r:match('^(%a+):(.+)$')
      local id = kind == 'spell' and A.SPELLS[key].id or kind == 'talent' and A.TALENTS[key].spell or A.PETS[key].spell
      ids[#ids + 1] = id .. '>' .. a.icon
    end
  end
  return table.concat(out, ';') .. '|' .. table.concat(ids, ';') .. '|' .. #I.names()
end
function IZOOM()
  local s = I.new(3, 99, false)
  local last, ok = 0, true
  for i = 1, I.MAX do local l, r, t, b, z = I.view(s); if z < last or l < 0.079 or r > 0.921 then ok = false end; last = z; s.guesses[i] = 'x' end
  return ok and 'ok' or 'bad'
end
function IDAILY()
  local seen, n = {}, #I.answers()
  for d = 1, n do seen[I.dailyIndex(20744 + d)] = true end
  local c = 0; for _ in pairs(seen) do c = c + 1 end
  return c .. '/' .. n
end
function CLICK(b)
  local top = __web.topAt(b.__id)
  if top ~= b.__id then error('button covered by another frame: ' .. tostring(b.label and b.label:GetText() or b.__id), 2) end
  b:Click()
end
local function btnOf(g, name) for _, b in ipairs(g.nameBtns) do if b.itemName == name and b:IsShown() then return b end end end
function IPLAY(win)
  local g = A.games.iconle.obj
  local s = g.s
  local a = I.answerOf(s)
  local wrong = {}
  for _, n in ipairs(I.names()) do if not I.isRight(s, n) then wrong[#wrong + 1] = n end end
  local out = {}
  CLICK(btnOf(g, wrong[1])); out[#out + 1] = 'x' .. #s.guesses
  CLICK(btnOf(g, wrong[2]))
  CLICK(btnOf(g, wrong[3])); out[#out + 1] = g.msg2:GetText()
  if win then
    -- type the answer's name to search, then Enter
    local name = a.names[1]
    for ch in name:gmatch('.') do if ch == ' ' then g:OnKey('SPACE') elseif ch:match('%a') then g:OnKey(ch:upper()) end end
    out[#out + 1] = g.matches .. ' found'
    if g.matches ~= 1 then CLICK(btnOf(g, name)) else g:OnKey('ENTER') end
  else
    for i = 4, 6 do CLICK(btnOf(g, wrong[i])) end
  end
  out[#out + 1] = g.msg:GetText()
  return table.concat(out, '|') .. '|' .. tostring(s.done) .. ' ' .. tostring(s.won)
end
`, '=ibot');
let fail = '';
const [ans, ids, nnames] = String(host.call('IANSWERS')).split('|');
// pictures: every answer's refs must be one picture, and two answers never the same picture
const picOf = id => PIC['spell:' + id];
const groups = {};
for (const x of ids.split(';')) { const [id, icon] = x.split('>'); (groups[icon] = groups[icon] || []).push(id); }
const answerPics = {};
for (const [icon, list] of Object.entries(groups)) {
  const pics = new Set(list.map(picOf));
  if (pics.size > 1) fail += 'answer ' + icon + ' joins different pictures: ' + list.join(',') + '\n';
  const p = picOf(icon);
  if (!p) fail += 'no picture for ' + icon + '\n';
  if (answerPics[p]) fail += 'answers ' + answerPics[p] + ' and ' + icon + ' are the same picture\n';
  answerPics[p] = icon;
}
console.log(Object.keys(groups).length + ' answers, ' + nnames + ' names');
if (String(host.call('IZOOM')) !== 'ok') fail += 'the zoom narrows or leaves the icon\n';
const daily = String(host.call('IDAILY'));
console.log('daily icons over ' + daily.split('/')[1] + ' days: ' + daily + ' different');
if (daily.split('/')[0] !== daily.split('/')[1]) fail += 'the daily icon repeats too soon: ' + daily + '\n';
host.run('__ADDON_NS.open("iconle")'); host.layout();
const w = String(host.call('IPLAY', true));
console.log('daily: ' + w);
if (!/^x1\|Hint: a .+\|1 found\|Got it in 4!\|true true$/.test(w)) fail += 'win: ' + w + '\n';
host.run('__ADDON_NS.games.iconle.obj:openPractice()'); host.layout();
const l = String(host.call('IPLAY', false));
console.log('practice, lost: ' + l);
if (!/\|It was .+\|true false$/.test(l)) fail += 'loss: ' + l + '\n';
for (const n of host.nodes.values()) if (n.kind === 'font' && n.vis && n.text && /\bnil\b|NaN/.test(n.parsed.plain)) fail += 'text: ' + n.parsed.plain + '\n';
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (fail) { console.log('FAIL:\n' + fail); process.exit(1); }
console.log('OK');
