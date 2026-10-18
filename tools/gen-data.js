// Writes WarlockArcade/Data.lua (the numbers and texts the games use) and web/icons.js (the icons the web page shows)
// from the DPS sim's own data files, so no number is copied by hand. Only the sim's COMMITTED files are read
// (git archive of HEAD), never work in progress in the sim's folder.
//   node tools/gen-data.js            (sim folder: ../wow-forever-warlock-sim, or the SIM_DIR environment variable)
const fs = require('fs'), path = require('path'), os = require('os'), cp = require('child_process');
const ROOT = path.join(__dirname, '..');
const SIM = process.env.SIM_DIR || path.join(ROOT, '..', 'wow-forever-warlock-sim');

const commit = cp.execSync('git -C "' + SIM + '" rev-parse --short HEAD').toString().trim();
const dirty = cp.execSync('git -C "' + SIM + '" status --short -- data engine').toString().trim();
if (dirty) console.log('NOTE: the sim folder has uncommitted changes (not used here):\n' + dirty);
const COPY = path.join(os.tmpdir(), 'warlock-arcade-sim-' + commit);
if (!fs.existsSync(path.join(COPY, 'tools', 'load-wl.js'))) {
  const files = cp.execSync('git -C "' + SIM + '" ls-tree -r --name-only HEAD data engine tools/load-wl.js').toString().trim().split(/\r?\n/);
  files.forEach(f => {
    const dst = path.join(COPY, f); fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.writeFileSync(dst, cp.execSync('git -C "' + SIM + '" show HEAD:' + f, { maxBuffer: 64 << 20 }));
  });
}
const WL = require(path.join(COPY, 'tools', 'load-wl.js')).load(COPY, ['data/tooltips.js', 'data/icons.js']);

// ---- Lua writer ----
const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;
const RESERVED = new Set('and break do else elseif end false for function if in local nil not or repeat return then true until while'.split(' '));
const str = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '')
  .replace(/[\u0080-￿]/g, c => Array.from(Buffer.from(c, 'utf8')).map(b => '\\' + b).join('')) + '"';
function lua(v, ind) {
  ind = ind || '';
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'number') { if (!isFinite(v)) throw new Error('not finite: ' + v); return String(Math.round(v * 1e6) / 1e6); }
  if (typeof v === 'boolean') return String(v);
  if (typeof v === 'string') return str(v);
  if (Array.isArray(v)) return '{ ' + v.map(x => lua(x, ind)).join(', ') + (v.length ? ' ' : '') + '}';
  const keys = Object.keys(v).filter(k => v[k] !== null && v[k] !== undefined && typeof v[k] !== 'function');
  if (!keys.length) return '{}';
  const flat = keys.every(k => typeof v[k] !== 'object' || Array.isArray(v[k]) && v[k].every(x => typeof x !== 'object'));
  const kv = k => (IDENT.test(k) && !RESERVED.has(k) ? k : '[' + str(k) + ']') + ' = ' + lua(v[k], ind + '  ');
  if (flat) return '{ ' + keys.map(kv).join(', ') + ' }';
  return '{\n' + keys.map(k => ind + '  ' + kv(k) + ',\n').join('') + ind + '}';
}

// ---- talent spell ids (the game shows a talent's icon from its rank spell) ----
const vm = require('vm');
// archived raw data, local in the sim's folder (not in its git): read from there
const rawFile = path.join(SIM, 'research', 'raw', 'wowhead_forever_talents-classic_dv27.js');
const nodes = {};
{
  const ctx = { RAW: {} };
  ctx.WH = { setPageData: (k, v) => { ctx.RAW.talentCalc = v; }, Gatherer: { addData: () => {} } };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(rawFile, 'utf8'), ctx);
  const t = ctx.RAW.talentCalc.talents;
  Object.keys(t).forEach(tree => Object.keys(t[tree]).forEach(id => { nodes[id] = t[tree][id]; }));
}

// ---- what the games use ----
const SPELL_FIELDS = ['id', 'name', 'school', 'tree', 'kind', 'base', 'coef', 'tickBase', 'tickCoef', 'tickEvery', 'duration', 'cast', 'cost', 'cd'];
const spells = {};
Object.keys(WL.SPELLS).forEach(k => {
  const s = WL.SPELLS[k], o = {};
  SPELL_FIELDS.forEach(f => { if (s[f] !== undefined) o[f] = s[f]; });
  const text = WL.SPELL_TEXT && WL.SPELL_TEXT[s.id];
  if (text) o.text = Array.isArray(text) ? text[text.length - 1] : (text.desc || text.text || (typeof text === 'string' ? text : undefined));
  spells[k] = o;
});
const talents = {};
WL.TALENTS.forEach(t => {
  const n = nodes[t.wid], texts = WL.TALENT_TEXT && WL.TALENT_TEXT[t.key];
  talents[t.key] = { name: t.name, tree: t.tree, ranks: t.ranks, row: t.row, col: t.col, req: t.req, spell: n ? n.ranks[t.ranks - 1] || n.ranks[0] : undefined,
    text: texts ? texts[texts.length - 1] : undefined, v: t.v };
});
// the sim's standard character with no talents, no pet: the base numbers of the games
const cfg = JSON.parse(JSON.stringify(WL.DEFAULT_CONFIG));
const blank = { key: 'blank', talents: {}, pet: 'none', rotation: [] };
const st = WL.computeStats(blank, WL.BASELINE_RACE || 'human', cfg);
const table = WL.buildSpellTable(blank, st, cfg);
const sb = table.shadowBolt;
const character = { gear: cfg.gear.name, sp: st.sp, critPct: Math.round(st.critPct * 100) / 100, hitPct: Math.min(st.hitPct, 99),
  hastePct: st.hastePct, critMult: sb.critMult, shadowBoltDmg: Math.round(sb.directDmg), shadowBoltCast: sb.cast,
  maxMana: Math.round(st.maxMana), maxHealth: Math.round(st.maxHealth), mp5: st.mp5, spi: Math.round(st.spi),
  gcd: cfg.combat.gcd, tapMana: Math.round(WL.SPELLS.lifeTap.manaBase + st.spi), tapHealth: WL.SPELLS.lifeTap.healthCost };
// the spells as the standard character casts them (the sim's spell table: cast time, cost, damage per tick)
const castTable = {};
['shadowBolt', 'corruption', 'baneOfAgony', 'immolate', 'incinerate', 'searingPain', 'conflagrate', 'shadowburn', 'drainLife', 'deathCoil'].forEach(k => {
  const x = table[k], s = WL.SPELLS[k];
  if (!x) return;
  const o = { cast: x.cast, cost: Math.round(x.cost) };
  if (x.directDmg) o.direct = Math.round(x.directDmg);
  if (x.tickDmg) { o.tick = Math.round(x.tickDmg * 10) / 10; o.ticks = x.ticks; o.every = s.tickEvery; o.duration = s.duration; }
  if (s.cd) o.cd = s.cd;
  castTable[k] = o;
});
const PETS = { imp: { name: 'Imp', spell: 688 }, voidwalker: { name: 'Voidwalker', spell: 697 }, succubus: { name: 'Succubus', spell: 712 }, felhunter: { name: 'Felhunter', spell: 691 } };

// consumables the games hand out: name, item id (or spell id for the warlock's own stones), the sim's text
const USE = ['buildOil', 'brilliantWizardOil', 'flaskSupremePower', 'shadowPower', 'firePower', 'demonicRune', 'majorManaPotion', 'greaterArcaneElixir'];
const consumables = {};
USE.forEach(k => {
  const c = WL.DEFAULT_CONFIG.consumables[k];
  if (!c) throw new Error('consumable ' + k + ' is gone from the sim');
  consumables[k] = k === 'buildOil' ? { name: WL.OILS.spellstone.name, spell: WL.OILS.spellstone.id, text: c.desc }
    : { name: c.name, item: c.id, text: c.desc };
});

// the sim's own published results (data/default-results.js: every ready build, every race, 120 s fights, standard gear)
let hl = null;
{
  const ctx = {}; ctx.window = ctx; vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(COPY, 'data', 'default-results.js'), 'utf8'), ctx);
  const D = ctx.WL.DEFAULT_RESULTS, builds = JSON.parse(D.builds), settings = JSON.parse(D.settings);
  const RACE = { human: 'Human', gnome: 'Gnome', orc: 'Orc', undead: 'Undead', troll: 'Troll', none: 'no racial' };
  const PET_SPELL = { 'pet:melee': 'Pet melee', 'pet:lashOfPain': 'Lash of Pain', 'pet:firebolt': 'Firebolt' };
  const mainSpell = b => /wrack/i.test(b.key) ? 'wrack' : /incin/.test(b.key) ? 'incinerate' : /fire/.test(b.key) ? 'immolate' : 'shadowBolt';
  hl = { generated: D.generated, fight: settings.fight.duration + ' s fight, 1 target', gear: settings.gear.name, builds: {}, dps: [], spells: [], weights: {} };
  builds.forEach(b => { hl.builds[b.key] = { name: b.short, pet: b.pet, icon: mainSpell(b) }; });
  D.results.forEach((r, i) => {
    const key = D.keys[i];
    hl.dps.push({ build: key, race: RACE[r.race] || r.race, dps: Math.round(r.dps * 10) / 10 });
    if (r.race !== 'human') return;
    Object.keys(r.bySpell).forEach(s => {
      const x = r.bySpell[s];
      const name = WL.SPELLS[s] ? WL.SPELLS[s].name : PET_SPELL[s];
      if (!name || x.dmg < 500) return;
      hl.spells.push({ build: key, spell: s, name, dmg: Math.round(x.dmg), casts: Math.round(x.casts * 10) / 10 });
    });
  });
  Object.keys(D.weights).forEach(k => { const w = D.weights[k].w; hl.weights[k] = { sp: w.sp, hitPct: w.hitPct, critPct: w.critPct, hastePct: w.hastePct }; });
}

const out = [];
out.push('-- GENERATED by tools/gen-data.js from the DPS sim\'s committed data files. Do not edit: run the script again.');
out.push('local ADDON, A = ...');
out.push('A.SIM_COMMIT = ' + str(commit));
out.push('A.SPELLS = ' + lua(spells));
out.push('A.TALENTS = ' + lua(talents));
out.push('A.TALENT_ORDER = ' + lua(WL.TALENTS.map(t => t.key)));
out.push('A.PETS = ' + lua(PETS));
out.push('A.CONSUMABLES = ' + lua(consumables));
out.push('A.CHARACTER = ' + lua(character));
out.push('A.CAST = ' + lua(castTable));
out.push('A.RESULTS = ' + lua(hl));
out.push('');
fs.writeFileSync(path.join(ROOT, 'WarlockArcade', 'Data.lua'), out.join('\n'));

// ---- icons for the web page: spell id -> picture ----
const icons = {};
const add = (id, key) => { if (id && WL.ICONS[key]) icons['spell:' + id] = WL.ICONS[key]; };
Object.keys(WL.SPELLS).forEach(k => add(WL.SPELLS[k].id, k));
Object.keys(WL.BOOK_RANKS || {}).forEach(k => { const b = WL.spellsFor({ options: { bookRanks: true } })[k]; if (b) add(b.id, k); });
Object.keys(talents).forEach(k => add(talents[k].spell, 'talent_' + k));
Object.keys(PETS).forEach(k => add(PETS[k].spell, 'pet_' + k));
USE.forEach(k => { const c = consumables[k], pic = WL.ICONS['consumable_' + k]; if (pic) icons[c.spell ? 'spell:' + c.spell : 'item:' + c.item] = pic; });
icons.unknown = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><rect width="36" height="36" fill="#2a2333"/><text x="18" y="26" font-size="22" text-anchor="middle" fill="#a89cc0" font-family="serif">?</text></svg>');
fs.writeFileSync(path.join(ROOT, 'web', 'icons.js'),
  '// GENERATED by tools/gen-data.js: Wowhead icons (wow.zamimg.com) from the DPS sim\'s data/icons.js, by spell id. Do not edit.\n' +
  'window.ARCADE_ICONS = ' + JSON.stringify(icons, null, 0).replace(/","/g, '",\n"') + ';\n');
console.log('Data.lua from sim ' + commit + ': ' + Object.keys(spells).length + ' spells, ' + Object.keys(talents).length + ' talents (' +
  Object.values(talents).filter(t => t.spell).length + ' with spell ids), character ' + JSON.stringify(character));
console.log('web/icons.js: ' + (Object.keys(icons).length - 1) + ' icons');
