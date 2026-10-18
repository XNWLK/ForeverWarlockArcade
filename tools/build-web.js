// Builds web/fengari.js: fengari (a Lua VM written in JavaScript, MIT licence) packed into one file for the browser,
// so the web page runs the addon's own Lua files. No download: it packs the copy in tools/node_modules.
//   node tools/build-web.js
// The Node-only parts of fengari (files, the shell, the io library) sit behind "typeof process" tests and are never
// loaded in the browser; their require() calls get empty stand-ins here.
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const SRC = path.join(__dirname, 'node_modules', 'fengari', 'src');
const SPRINTF = path.join(__dirname, 'node_modules', 'sprintf-js', 'src', 'sprintf.js');
const LICENCE = path.join(__dirname, 'node_modules', 'fengari', 'LICENSE');

const mods = {};
fs.readdirSync(SRC).filter(f => f.endsWith('.js')).forEach(f => { mods['./' + f] = fs.readFileSync(path.join(SRC, f), 'utf8'); });
// fengari's own browser build (fengari-web) sets this to nothing as well
mods['./luaconf.js'] = mods['./luaconf.js'].replace('process.env.FENGARICONF', 'undefined');
mods['sprintf-js'] = fs.readFileSync(SPRINTF, 'utf8');
const STUBS = ['fs', 'tmp', 'readline-sync', 'path', 'os', 'child_process'];

let out = '/* fengari 0.1.5 - https://github.com/fengari-lua/fengari - packed by tools/build-web.js. Do not edit.\n' +
  (fs.existsSync(LICENCE) ? fs.readFileSync(LICENCE, 'utf8').replace(/\*\//g, '* /') : 'MIT licence') + '*/\n' +
  '(function () {\n"use strict";\nvar defs = {}, cache = {}, process = undefined; // always the browser build, also when tested under Node\n' +
  'var stubs = ' + JSON.stringify(STUBS) + ';\n' +
  'function req(name) {\n' +
  '  if (stubs.indexOf(name) >= 0) return {};\n' +
  '  if (cache[name]) return cache[name].exports;\n' +
  '  var d = defs[name]; if (!d) throw new Error("fengari bundle: no module " + name);\n' +
  '  var m = cache[name] = { exports: {} };\n' +
  '  d.call(m.exports, m, m.exports, req);\n' +
  '  return m.exports;\n}\n';
Object.keys(mods).forEach(name => {
  out += 'defs[' + JSON.stringify(name) + '] = function (module, exports, require) {\n' + mods[name] + '\n};\n';
});
out += 'window.fengari = req("./fengari.js");\n})();\n';
fs.mkdirSync(path.join(ROOT, 'web'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'web', 'fengari.js'), out);
console.log('web/fengari.js: ' + Object.keys(mods).length + ' modules, ' + Math.round(out.length / 1024) + ' KB');
