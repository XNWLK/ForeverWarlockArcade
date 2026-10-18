// Walks through every screen of the arcade (picker, each phase of Shard & Mult, the panels) and reports text that
// does not fit its box and anything drawn outside the window. Text is measured roughly (tools/host.js), a bit wider
// than the web page's font, about as wide as the game's Friz Quadrata.
//   node tools/check-layout.js
const { boot } = require('./host.js');
const host = boot();
const problems = new Set(), seen = new Set();
const report = (screen, what) => { if (!seen.has(what)) { seen.add(what); problems.add(screen + ': ' + what); } };
function inside(r, w) { return r.l >= w.l - 1 && r.b >= w.b - 1 && r.l + r.w <= w.l + w.w + 1 && r.b + r.h <= w.b + w.h + 1; }
function check(screen) {
  host.layout();
  const win = [...host.nodes.values()].find(n => n.kind === 'frame' && n.id === host.call('ARCADE_WIN'));
  for (const n of host.nodes.values()) {
    if (!n.vis || !n.rect || n.ealpha < 0.05) continue;
    if ((n.kind === 'font' && n.text) || n.kind === 'tex' || n.mouse) {
      if (win && n.id !== win.id && !inside(n.rect, win.rect) && n.rect.w > 0) report(screen, 'outside the window: ' + (n.kind === 'font' ? '"' + n.parsed.plain.slice(0, 40) + '"' : n.kind + ' ' + n.id));
    }
    // a button the mouse cannot reach: something else takes the click at its middle
    if (n.kind === 'button' && n.mouse && n.rect.w > 4) {
      const top = host.hitTest(n.rect.l + n.rect.w / 2, n.rect.b + n.rect.h / 2);
      let p = top; while (p && p !== n.id) { const q = host.node(p); p = q && q.parent; }
      // only a frame that holds the button counts (a panel above its own button); a window open over others is fine
      let a = n.parent, ancestor = false; while (a) { if (a === top) { ancestor = true; break; } const q = host.node(a); a = q && q.parent; }
      if (p !== n.id && ancestor) {
        const label = [...host.nodes.values()].find(x => x.kind === 'font' && x.parent === n.id && x.vis && x.text);
        report(screen, 'button covered by another frame: ' + (label ? '"' + label.parsed.plain + '"' : 'button ' + n.id));
      }
    }
    if (n.kind !== 'font' || !n.text) continue;
    const anchoredWide = n.points.some(p => /LEFT/.test(p.p)) && n.points.some(p => /RIGHT/.test(p.p));
    const fixedW = anchoredWide || n.w > 0;
    const s = host.effScale(n);
    const m = host.measureNode(n, n.wrap && fixedW ? n.rect.w / s : 0);
    if (fixedW && !n.wrap && m.w * s > n.rect.w + 2) report(screen, 'too wide (' + Math.round(m.w) + ' > ' + Math.round(n.rect.w / s) + '): "' + n.parsed.plain.slice(0, 50) + '"');
    // text inside a box: does it fit the box it sits in?
    const parent = host.node(n.parent);
    if (parent && parent.rect && parent.kind !== 'root' && parent.rect.w < 400) {
      const px = parent.rect, tw = (fixedW ? Math.min(m.w * s, n.rect.w) : m.w * s);
      const cx = n.rect.l + n.rect.w / 2, half = tw / 2;
      const left = n.jh === 'LEFT' ? n.rect.l : n.jh === 'RIGHT' ? n.rect.l + n.rect.w - tw : cx - half;
      if (left < px.l - 2 || left + tw > px.l + px.w + 2) report(screen, 'spills out of its box: "' + n.parsed.plain.slice(0, 50) + '"');
      const th = m.h * s;
      if (n.wrap && fixedW && th > px.h + 4) report(screen, 'too tall for its box (' + m.lines + ' lines): "' + n.parsed.plain.slice(0, 50) + '"');
    }
  }
}
host.run('function ARCADE_WIN() return WarlockArcadeFrame.__id end');
check('picker');
host.run('__ADDON_NS.open("shard")');
host.run('math.randomseed(7); __ADDON_NS.games.shard.obj:newRun()');
host.advance(0.5); check('blind select');
host.run('local g = __ADDON_NS.games.shard.obj; g:startBlind()');
host.advance(1); check('blind');
host.run('local g = __ADDON_NS.games.shard.obj; local h = g.run.blind.hand; g.selected = { [h[1].id] = true, [h[2].id] = true }; g:afterSelect()');
host.advance(0.5); check('blind, cards picked');
host.run('local g = __ADDON_NS.games.shard.obj; g:togglePanel("levels")'); host.advance(0.2); check('hand levels');
host.run('local g = __ADDON_NS.games.shard.obj; g.levelPanel:Hide(); __ADDON_NS.toggleHelp()'); host.advance(0.2); check('help');
host.run('__ADDON_NS.toggleHelp()');
// win the blind: give the blind a big score, then play
host.run('local g = __ADDON_NS.games.shard.obj; g.run.blind.score = g.run.blind.info.health - 1; local h = g.run.blind.hand; g.selected = { [h[1].id] = true }; g:afterSelect(); g:playSelected()');
host.advance(6); check('cash out');
host.run('local g = __ADDON_NS.games.shard.obj; g.cashPanel.go:Click(); g.run.gold = 40; g.run.talents = { "shadowMastery", "improvedShadowBolt", "demonicSacrifice", "masterDemonologist", "soulSiphon" }; g.run.items = { { key = "flaskSupremePower" }, { key = "greaterArcaneElixir" } }; g:refresh()');
host.advance(0.5); check('shop, full slots');
host.run('local g = __ADDON_NS.games.shard.obj; g.picked = { kind = "item", i = 1 }; g:refreshSlots()'); host.advance(0.2); check('shop, consumable picked');
host.run('local g = __ADDON_NS.games.shard.obj; g.picked = nil; g:leaveShop(); g.run.blindIndex = 3; g:refresh()'); host.advance(0.5); check('boss select');
host.run('local g = __ADDON_NS.games.shard.obj; g:startBlind(); g.run.blind.hands = 1; local h = g.run.blind.hand; g.selected = { [h[1].id] = true }; g:afterSelect(); g:playSelected()');
host.advance(6); check('run over');
host.run('local g = __ADDON_NS.games.shard.obj; g:confirmNewRun()'); host.advance(0.2); check('confirm');
host.run('__ADDON_NS.games.shard.obj.confirmPanel:Hide(); __ADDON_NS.open("juggler")'); host.advance(0.3); check('juggler start');
host.run('local g = __ADDON_NS.games.juggler.obj; g:start(); g:castOn("baneOfAgony", 1)'); host.advance(40); check('juggler round');
host.run('__ADDON_NS.toggleHelp()'); host.advance(0.2); check('juggler help'); host.run('__ADDON_NS.toggleHelp()');
host.advance(55); check('juggler results');
host.run('__ADDON_NS.open("higher")'); host.advance(0.3); check('higher start');
for (let i = 0; i < 12; i++) {
  host.run('math.randomseed(' + i + '); __ADDON_NS.games.higher.obj:start()'); host.advance(0.2); check('higher round');
  host.run('local g = __ADDON_NS.games.higher.obj; local s = g.s; g:guess(s.right.value >= s.left.value and "lower" or "higher")');
  host.advance(0.3); check('higher wrong'); host.advance(2); check('higher over');
}
host.run('__ADDON_NS.open("warlockle")'); host.advance(0.3); check('warlockle daily');
host.run('local g = __ADDON_NS.games.warlockle.obj; g:openPractice(); local n = 0; for _, k in ipairs(__ADDON_NS.TALENT_ORDER) do if n < 4 and k ~= g.s.target then g:guess(k); n = n + 1 end end');
host.advance(0.3); check('warlockle 4 misses');
host.run('local g = __ADDON_NS.games.warlockle.obj; for _, k in ipairs(__ADDON_NS.TALENT_ORDER) do if not g.s.done and k ~= g.s.target then g:guess(k) end end');
host.advance(0.3); check('warlockle missed');
host.run('__ADDON_NS.open("ware")'); host.advance(0.3); check('ware start');
host.run('__ADDON_NS.games.ware.obj:start()');
for (let i = 0; i < 9; i++) {
  host.advance(1.2); check('ware ' + host.call('tostring', null) + i);
  host.run('local g = __ADDON_NS.games.ware.obj; if g.m then g.m.result = "win" end'); host.advance(1);
}
host.run('local g = __ADDON_NS.games.ware.obj; g.lifeLeft = 1; if g.m then g.m.result = "lose" end'); host.advance(3); check('ware over');
host.run('__ADDON_NS.open("pegs")'); host.advance(0.3); check('pegs start');
host.run('local g = __ADDON_NS.games.pegs.obj; g:overlayGo(); g:shoot()'); host.advance(1); check('pegs shot');
host.run('local g = __ADDON_NS.games.pegs.obj; g.s.balls = 0'); host.advance(15); check('pegs over');
host.run('local g = __ADDON_NS.games.pegs.obj; g.s.orangeHit = g.s.orangeTotal; g:showOverlay("cleared")'); host.advance(0.2); check('pegs cleared');
for (let l = 2; l <= 4; l++) { host.run('local g = __ADDON_NS.games.pegs.obj; g:overlayGo()'); host.advance(0.3); check('pegs level ' + l); host.run('local g = __ADDON_NS.games.pegs.obj; g:showOverlay("cleared")'); }
host.run('__ADDON_NS.open("taptap")'); host.advance(0.3); check('taptap start');
host.run('__ADDON_NS.games.taptap.obj:play()'); host.advance(3); check('taptap playing'); host.advance(12); check('taptap later');
host.advance(60); check('taptap done');
host.run('__ADDON_NS.open("merge")'); host.advance(0.3); check('merge start');
host.run('local g = __ADDON_NS.games.merge.obj; local M = __ADDON_NS.MergeRules; for r = 1, 4 do for c = 1, 4 do g.s.grid[r][c] = { tier = (r - 1) * 4 + c <= 11 and (r - 1) * 4 + c or 1, id = 900 + r * 4 + c } end end; g:draw()');
host.advance(0.5); check('merge every demon');
host.run('local g = __ADDON_NS.games.merge.obj; g:showOverlay("won")'); host.advance(0.2); check('merge won');
host.run('local g = __ADDON_NS.games.merge.obj; g:showOverlay("over")'); host.advance(0.2); check('merge over');
host.run('__ADDON_NS.games.merge.obj:newGame(); __ADDON_NS.open(nil)'); host.advance(0.3); check('picker, all games');
if (host.errors.length) { console.log('FAIL: Lua error\n' + host.errors.join('\n')); process.exit(1); }
if (problems.size) { console.log('CHECK (' + problems.size + '):\n  ' + [...problems].join('\n  ')); process.exit(1); }
console.log('OK: every screen fits');
