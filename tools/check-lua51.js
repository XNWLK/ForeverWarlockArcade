// The game runs Lua 5.1; the web page (fengari) and the checks run Lua 5.3, which accepts more. This finds what only
// 5.3 takes in the addon's files: // (integer division), bit operators (& | ~ << >>), goto and ::labels::, \x \z \u{}
// escapes - outside strings and comments - and functions over 5.1's 60 upvalues (outer locals a function uses).
//   node tools/check-lua51.js
const fs = require('fs'), path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, to_luastring } = fengari;
const ROOT = path.join(__dirname, '..'), ADDON = 'WarlockArcade';
const files = fs.readFileSync(path.join(ROOT, ADDON, ADDON + '.toc'), 'utf8').replace(/\r/g, '').split('\n')
  .map(l => l.trim()).filter(l => l && !l.startsWith('#')).map(l => l.replace(/\\/g, '/'));
const problems = [];

// strips strings and comments (keeps line breaks), so the scan only sees code; reports escapes inside strings
function code(src, file) {
  let out = '', i = 0, line = 1;
  const note = (what) => problems.push(file + ':' + line + ': ' + what);
  while (i < src.length) {
    const c = src[i];
    if (c === '\n') { line++; out += c; i++; continue; }
    if (src.startsWith('--', i)) {
      const lb = /^--\[(=*)\[/.exec(src.slice(i));
      const end = lb ? src.indexOf(']' + lb[1] + ']', i) + lb[1].length + 2 : src.indexOf('\n', i);
      const stop = end < 0 ? src.length : end;
      const body = src.slice(i, stop);
      line += (body.match(/\n/g) || []).length; out += body.replace(/[^\n]/g, ' ');
      i = stop; continue;
    }
    const lb = /^\[(=*)\[/.exec(src.slice(i, i + 20));
    if (lb) {
      const stop = src.indexOf(']' + lb[1] + ']', i) + lb[1].length + 2;
      const body = src.slice(i, stop);
      line += (body.match(/\n/g) || []).length; out += '""' + body.replace(/[^\n]/g, '').slice(0);
      i = stop; continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < src.length && src[j] !== c) {
        if (src[j] === '\\') {
          const e = src[j + 1];
          if (e === 'x') note('\\x escape in a string (5.3 only)');
          if (e === 'z') note('\\z escape in a string (5.3 only)');
          if (e === 'u') note('\\u{} escape in a string (5.3 only)');
          j += 2; continue;
        }
        if (src[j] === '\n') break;
        j++;
      }
      out += '""'; i = j + 1; continue;
    }
    out += c; i++;
  }
  return out;
}
for (const f of files) {
  const src = fs.readFileSync(path.join(ROOT, ADDON, f), 'utf8');
  const lines = code(src, f).split('\n');
  lines.forEach((l, k) => {
    const at = f + ':' + (k + 1) + ': ';
    if (/\/\//.test(l)) problems.push(at + '// (integer division, 5.3 only)');
    if (/(^|[^~<>=])&|\|/.test(l)) problems.push(at + 'bit operator & or | (5.3 only)');
    if (/<<|>>/.test(l)) problems.push(at + 'shift operator (5.3 only)');
    if (/~(?!=)/.test(l)) problems.push(at + '~ (bit not/xor, 5.3 only)');
    if (/\bgoto\b/.test(l) || /::\w+::/.test(l)) problems.push(at + 'goto / label (5.2+ only)');
  });
  // upvalues per function: compile with 5.3 and walk the function prototypes. 5.3 counts _ENV (globals) as one
  // upvalue where 5.1 does not, so 5.3's count is at most one more than the game's.
  const L = lauxlib.luaL_newstate();
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('@' + f)) !== lua.LUA_OK) {
    problems.push(f + ': does not compile: ' + lua.lua_tojsstring(L, -1));
    continue;
  }
  const cl = L.stack[L.top - 1].value;
  let most = 0, where = '';
  (function walk(p) {
    const n = p.upvalues.length;
    if (n > most) { most = n; where = 'line ' + p.linedefined; }
    if (n > 60) problems.push(f + ': the function at line ' + p.linedefined + ' uses ' + n + ' upvalues (5.1 allows 60)');
    p.p.forEach(walk);
  })(cl.p);
  if (most > 50) console.log('note: ' + f + ' has a function with ' + most + ' upvalues (' + where + ')');
}
if (problems.length) { console.log('FAIL:\n' + problems.join('\n')); process.exit(1); }
console.log('OK: ' + files.length + ' files are Lua 5.1 (no 5.3-only syntax, no function over 60 upvalues)');
