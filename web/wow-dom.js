// Draws what web/wow-core.js laid out, as plain page elements, and passes the mouse and keyboard on to the addon.
// The page is one WoW screen: 768 units tall like the game's UIParent, as wide as the window allows. Not part of the addon.
(function () {
  'use strict';
  const UI_HEIGHT = 768;
  const FONTS = {   // the game's fonts -> the closest free fonts (loaded in index.html)
    'FRIZQT__.TTF': "'Philosopher', 'Palatino Linotype', serif",
    'ARIALN.TTF': "'Roboto Condensed', 'Arial Narrow', sans-serif",
    'MORPHEUS.TTF': "'Cinzel', 'Times New Roman', serif",
    'SKURRI.TTF': "'Cinzel', serif",
  };
  const family = path => FONTS[String(path).split(/[\\/]/).pop().toUpperCase()] || FONTS['FRIZQT__.TTF'];
  const fontCss = f => (f.flags && /THICK/.test(f.flags) ? '700 ' : '400 ') + f.size + 'px ' + family(f.path);
  const rgba = (c, m) => { m = m || [1, 1, 1, 1]; return 'rgba(' + Math.round(c[0] * m[0] * 255) + ',' + Math.round(c[1] * m[1] * 255) + ',' + Math.round(c[2] * m[2] * 255) + ',' + (c[3] * m[3]) + ')'; };
  const KEYS = { ' ': 'SPACE', Enter: 'ENTER', Escape: 'ESCAPE', ArrowLeft: 'LEFT', ArrowRight: 'RIGHT', ArrowUp: 'UP', ArrowDown: 'DOWN',
    Backspace: 'BACKSPACE', Tab: 'TAB', Delete: 'DELETE', Shift: 'LSHIFT', Control: 'LCTRL', Alt: 'LALT' };
  const keyName = e => KEYS[e.key] || (e.key.length === 1 ? e.key.toUpperCase() : /^F\d+$/.test(e.key) ? e.key : null);

  let canvas = null;
  function measure(plain, font, wrapWidth) {
    canvas = canvas || document.createElement('canvas').getContext('2d');
    canvas.font = fontCss(font);
    const lh = font.size * 1.15;
    const lines = [];
    String(plain).split('\n').forEach(par => {
      if (!wrapWidth) { lines.push(canvas.measureText(par).width); return; }
      let cur = '';
      par.split(/(\s+)/).forEach(word => {
        const t = cur + word;
        if (cur && canvas.measureText(t.trimEnd()).width > wrapWidth) { lines.push(canvas.measureText(cur.trimEnd()).width); cur = word.trimStart(); }
        else cur = t;
      });
      lines.push(canvas.measureText(cur.trimEnd()).width);
    });
    return { w: Math.ceil(Math.max(0, ...lines)), h: Math.ceil(lines.length * lh), lines: lines.length };
  }

  function texUrl(path) {
    const icons = window.ARCADE_ICONS || {};
    if (!path) return null;
    if (/^(spell|item):/.test(path)) return { url: icons[path] || icons.unknown, mask: false };
    const p = path.replace(/\//g, '\\');
    const m = /^Interface\\AddOns\\([^\\]+)\\Media\\(.+?)(\.(tga|blp|png))?$/i.exec(p);
    if (m) return { url: 'web/media/' + m[2].replace(/\\/g, '/') + '.png', mask: true };
    if (/WHITE8X8$/i.test(p)) return { url: null, mask: false, white: true };
    const icon = /^Interface\\Icons\\(.+)$/i.exec(p);
    if (icon) return { url: icons['icon:' + icon[1].toLowerCase()] || icons.unknown, mask: false };
    return { url: icons.unknown, mask: false };
  }

  function start(opts) {
    const stage = document.getElementById('stage');
    const ui = document.createElement('div'); ui.className = 'wow-ui'; stage.appendChild(ui);
    const errBar = document.createElement('div'); errBar.className = 'wow-error'; document.body.appendChild(errBar);
    const tipEl = document.createElement('div'); tipEl.className = 'wow-tip'; ui.appendChild(tipEl);
    const t0 = performance.now();
    let audio = null;
    const host = new WowHost({
      fengari: window.fengari,
      measure,
      now: () => (performance.now() - t0) / 1000,
      storage: { get: k => { try { return localStorage.getItem(opts.addon + ':' + k); } catch (e) { return null; } },
        set: (k, v) => { try { localStorage.setItem(opts.addon + ':' + k, v); } catch (e) { /* private window */ } } },
      onError: msg => { console.error(msg); errBar.textContent = 'Error: ' + msg.split('\n')[0]; errBar.style.display = 'block'; },
      onChat: t => console.log('[chat] ' + t.replace(/\|c[0-9a-fA-F]{8}|\|r/g, '')),
      sound: id => { if (window.WowSound) { audio = audio || WowSound.init(); if (audio) WowSound.play(audio, id); } },
      soundFile: () => {},
      meta: {},
    });
    window.wowHost = host;
    let k = 1;
    function fit() {
      const vw = stage.clientWidth || window.innerWidth, vh = stage.clientHeight || window.innerHeight;
      k = vh / UI_HEIGHT;
      const w = vw / k;
      ui.style.width = w + 'px'; ui.style.height = UI_HEIGHT + 'px'; ui.style.transform = 'scale(' + k + ')';
      host.resize(w, UI_HEIGHT);
    }
    // ---- drawing ----
    const els = new Map();
    function el(n) {
      let e = els.get(n.id);
      if (!e) {
        e = document.createElement('div');
        e.className = n.kind === 'font' ? 'wow-font' : n.kind === 'tex' ? 'wow-tex' : 'wow-frame';
        e.dataset.id = n.id;
        ui.appendChild(e); els.set(n.id, e); e._s = {};
      }
      return e;
    }
    const css = (e, k, v) => { if (e._s[k] !== v) { e._s[k] = v; e.style[k] = v; } };
    function drawNode(n) {
      const r = n.rect;
      const needs = n.kind === 'tex' || n.kind === 'font' || n.mouse;
      if (!needs) return;
      const show = n.vis && r && n.ealpha > 0.001 && (n.kind !== 'tex' || n.tex || n.color || n.gradient) && (n.kind !== 'font' || n.text);
      if (!show) { const e = els.get(n.id); if (e) css(e, 'display', 'none'); return; }
      const e = el(n);
      css(e, 'display', 'block');
      css(e, 'left', r.l + 'px'); css(e, 'top', (host.screen.h - r.b - r.h) + 'px');
      css(e, 'width', r.w + 'px'); css(e, 'height', r.h + 'px');
      css(e, 'zIndex', String(n.z));
      css(e, 'opacity', String(n.ealpha));
      const vkey = n.v + ':' + (n.kind === 'font' ? host.effScale(n) : 0);
      if (e._v === vkey) return;
      e._v = vkey;
      if (n.kind === 'tex') {
        const vc = n.vcolor || [1, 1, 1, 1];
        css(e, 'transform', n.rot ? 'rotate(' + (-n.rot) + 'rad)' : '');
        css(e, 'mixBlendMode', n.blend === 'ADD' ? 'plus-lighter' : '');
        if (n.gradient) {
          const [o, a, b] = n.gradient;
          css(e, 'background', 'linear-gradient(' + (o === 'VERTICAL' ? 'to top' : 'to right') + ',' + rgba(a, vc) + ',' + rgba(b, vc) + ')');
          css(e, 'maskImage', ''); css(e, 'webkitMaskImage', ''); css(e, 'filter', '');
          return;
        }
        if (n.color) {
          css(e, 'background', rgba(n.color, vc)); css(e, 'maskImage', ''); css(e, 'webkitMaskImage', ''); css(e, 'filter', '');
          return;
        }
        const t = texUrl(n.tex);
        const c = n.coords || [0, 1, 0, 1];
        const bw = r.w / Math.max(1e-6, c[1] - c[0]), bh = r.h / Math.max(1e-6, c[3] - c[2]);
        const size = bw + 'px ' + bh + 'px', pos = (-c[0] * bw) + 'px ' + (-c[2] * bh) + 'px';
        if (t.white) { css(e, 'background', rgba([1, 1, 1, 1], vc)); return; }
        if (t.mask) {
          css(e, 'background', rgba([1, 1, 1, 1], vc));
          const u = 'url("' + t.url + '")';
          css(e, 'webkitMaskImage', u); css(e, 'maskImage', u);
          css(e, 'webkitMaskSize', size); css(e, 'maskSize', size);
          css(e, 'webkitMaskPosition', pos); css(e, 'maskPosition', pos);
          css(e, 'webkitMaskRepeat', 'no-repeat'); css(e, 'maskRepeat', 'no-repeat');
          css(e, 'filter', '');
        } else {
          css(e, 'background', t.url ? 'url("' + t.url + '") ' + pos + ' / ' + size + ' no-repeat' : '#444');
          css(e, 'maskImage', ''); css(e, 'webkitMaskImage', '');
          const bright = Math.max(vc[0], vc[1], vc[2]);
          css(e, 'filter', (n.desat ? 'grayscale(1) ' : '') + (bright < 0.999 ? 'brightness(' + bright + ')' : ''));
          if (vc[3] < 1) css(e, 'opacity', String(n.ealpha * vc[3]));
        }
        // rounded art is cut by the shape file; icons get the slight rounding the game's icons have
      } else if (n.kind === 'font') {
        const sc = host.effScale(n), f = Object.assign({}, n.font, { size: n.font.size * sc });
        css(e, 'font', fontCss(f));
        css(e, 'lineHeight', (f.size * 1.15 + (n.spacing || 0) * sc) + 'px');
        css(e, 'color', rgba(n.tcolor));
        css(e, 'justifyContent', n.jh === 'LEFT' ? 'flex-start' : n.jh === 'RIGHT' ? 'flex-end' : 'center');
        css(e, 'textAlign', n.jh === 'LEFT' ? 'left' : n.jh === 'RIGHT' ? 'right' : 'center');
        css(e, 'alignItems', n.jv === 'TOP' ? 'flex-start' : n.jv === 'BOTTOM' ? 'flex-end' : 'center');
        css(e, 'whiteSpace', n.wrap ? 'pre-wrap' : 'pre');
        const sh = [];
        if (/OUTLINE/.test(f.flags || '')) { const o = /THICK/.test(f.flags) ? 1.6 : 1; sh.push(`${o}px 0 0 #000`, `-${o}px 0 0 #000`, `0 ${o}px 0 #000`, `0 -${o}px 0 #000`, `${o}px ${o}px 0 #000`, `-${o}px -${o}px 0 #000`, `${o}px -${o}px 0 #000`, `-${o}px ${o}px 0 #000`); }
        if (n.shadow) sh.push(n.shadow[0] * sc + 'px ' + (-n.shadow[1] * sc) + 'px 0 ' + rgba(n.shadow.slice(2)));
        css(e, 'textShadow', sh.join(','));
        let inner = e.firstChild;
        if (!inner) { inner = document.createElement('span'); e.appendChild(inner); }
        inner.textContent = '';
        n.parsed.runs.forEach(run => {
          const s = document.createElement('span'); s.textContent = run.text;
          if (run.color) s.style.color = run.color;
          inner.appendChild(s);
        });
      }
    }
    function drawTip() {
      const t = host.tip;
      if (!t) { tipEl.style.display = 'none'; return; }
      const owner = host.node(t.owner);
      tipEl.innerHTML = '';
      t.lines.forEach((l, i) => {
        const row = document.createElement('div'); row.className = 'wow-tip-row' + (i === 0 ? ' head' : '');
        const left = document.createElement('span');
        WowHost.parseText(l[0]).runs.forEach(run => { const s = document.createElement('span'); s.textContent = run.text; if (run.color) s.style.color = run.color; left.appendChild(s); });
        left.style.color = rgba([+l[1], +l[2], +l[3], 1]);
        if (l[4] === '1') left.className = 'wrap';
        row.appendChild(left);
        if (l[5]) { const right = document.createElement('span'); right.className = 'right'; right.textContent = l[5]; right.style.color = rgba([+l[6], +l[7], +l[8], 1]); row.appendChild(right); }
        tipEl.appendChild(row);
      });
      tipEl.style.display = 'block'; tipEl.style.zIndex = '99999999';
      const r = owner && owner.rect;
      const tw = tipEl.offsetWidth, th = tipEl.offsetHeight, W = host.screen.w, H = host.screen.h;
      let x, top;
      if (!r || t.anchor === 'ANCHOR_CURSOR') { x = host.cursor.x + 16; top = H - host.cursor.y + 16; }
      else if (t.anchor === 'ANCHOR_TOP') { x = r.l + r.w / 2 - tw / 2; top = H - (r.b + r.h) - th - 6; }
      else if (t.anchor === 'ANCHOR_BOTTOM') { x = r.l + r.w / 2 - tw / 2; top = H - r.b + 6; }
      else if (t.anchor === 'ANCHOR_LEFT') { x = r.l - tw - 6; top = H - (r.b + r.h); }
      else { x = r.l + r.w + 6; top = H - (r.b + r.h); }
      if (x + tw > W - 4) x = r ? r.l - tw - 6 : W - tw - 4;
      if (x < 4) x = 4;
      if (top + th > H - 4) top = H - th - 4;
      if (top < 4) top = 4;
      tipEl.style.left = x + 'px'; tipEl.style.top = top + 'px';
    }
    function render() {
      host.layout();
      for (const n of host.nodes.values()) drawNode(n);
      drawTip();
    }
    // ---- input ----
    let downId = 0, downBtn = null, downAt = null, dragging = false, touchHover = false;
    const BTN = ['LeftButton', 'MiddleButton', 'RightButton'];
    function toUi(e) {
      const b = ui.getBoundingClientRect();
      return { x: (e.clientX - b.left) / k, y: host.screen.h - (e.clientY - b.top) / k };
    }
    function setHover(id) {
      if (id === host.hover) return;
      const old = host.hover; host.hover = id;
      if (old) host.script(old, 'OnLeave');
      if (id) host.script(id, 'OnEnter', false);
      ui.style.cursor = id && host.call('__webIsButton', id) ? 'pointer' : '';
    }
    ui.addEventListener('pointermove', e => {
      const p = toUi(e); host.cursor = p;
      if (downId && downAt && !dragging && Math.hypot(p.x - downAt.x, p.y - downAt.y) > 5) {
        const n = host.node(downId);
        if (n && n.drag) { dragging = true; host.script(downId, 'OnDragStart', downBtn); }
      }
      if (e.pointerType !== 'touch') setHover(host.hitTest(p.x, p.y));
    });
    ui.addEventListener('pointerleave', e => { if (e.pointerType !== 'touch') setHover(0); });
    ui.addEventListener('pointerdown', e => {
      const p = toUi(e); host.cursor = p;
      const id = host.hitTest(p.x, p.y);
      if (e.pointerType === 'touch') { setHover(id); touchHover = true; }
      downId = id; downBtn = BTN[e.button] || 'LeftButton'; downAt = p; dragging = false;
      if (id) { host.script(id, 'OnMouseDown', downBtn); e.preventDefault(); }
      audioUnlock();
    });
    window.addEventListener('pointerup', e => {
      const p = toUi(e); host.cursor = p;
      const id = downId; downId = 0;
      if (!id) return;
      host.script(id, 'OnMouseUp', downBtn);
      if (dragging) { host.script(id, 'OnDragStop'); dragging = false; }
      else if (host.hitTest(p.x, p.y) === id) host.script(id, 'OnClick', downBtn);
      if (touchHover) { setHover(0); touchHover = false; }
    });
    // the browser took the touch over (a scroll, a long press): nothing is pressed any more
    window.addEventListener('pointercancel', () => {
      if (downId) host.script(downId, 'OnMouseUp', downBtn);
      downId = 0; dragging = false;
      if (touchHover) { setHover(0); touchHover = false; }
    });
    ui.addEventListener('contextmenu', e => e.preventDefault());
    ui.addEventListener('wheel', e => {
      const p = toUi(e);
      host.layout();
      let best = null;
      for (const n of host.nodes.values()) {
        if (!n.wheel || !n.vis || !n.rect) continue;
        const r = n.rect;
        if (p.x >= r.l && p.x <= r.l + r.w && p.y >= r.b && p.y <= r.b + r.h && (!best || n.z > best.z)) best = n;
      }
      if (best) { host.script(best.id, 'OnMouseWheel', e.deltaY < 0 ? 1 : -1); e.preventDefault(); }
    }, { passive: false });
    const mods = e => { host.mods = { shift: e.shiftKey, ctrl: e.ctrlKey, alt: e.altKey }; };
    window.addEventListener('keydown', e => { mods(e); if (e.repeat) return; const kname = keyName(e); if (kname && host.key(kname, true)) e.preventDefault(); });
    window.addEventListener('keyup', e => { mods(e); const kname = keyName(e); if (kname) host.key(kname, false); });
    function audioUnlock() { if (window.WowSound && !audio) audio = WowSound.init(); }
    // ---- start ----
    const v = '?v=' + (opts.version || Date.now());
    fetch(opts.addon + '/' + opts.addon + '.toc' + v).then(r => r.text()).then(toc => {
      const lines = toc.replace(/\r/g, '').split('\n');
      const meta = {}; const files = [];
      lines.forEach(l => {
        const m = /^##\s*([^:]+):\s*(.*)$/.exec(l);
        if (m) meta[m[1].trim()] = m[2].trim();
        else if (l.trim() && !l.startsWith('#') && /\.lua$/i.test(l.trim())) files.push(l.trim());
      });
      host.o.meta = meta;
      const saved = (meta.SavedVariables || '').split(',').map(s => s.trim()).filter(Boolean)
        .concat((meta.SavedVariablesPerCharacter || '').split(',').map(s => s.trim()).filter(Boolean));
      return Promise.all(files.map(f => fetch(opts.addon + '/' + f.replace(/\\/g, '/') + v).then(r => { if (!r.ok) throw new Error(f + ': ' + r.status); return r.text(); })))
        .then(srcs => fetch('web/wow.lua' + v).then(r => r.text()).then(wowLua => {
          const map = { 'web/wow.lua': wowLua };
          files.forEach((f, i) => { map[opts.addon + '/' + f.replace(/\\/g, '/')] = srcs[i]; });
          fit();
          host.run('WOW_WEB = true', '=web');
          host.boot(opts.addon, files, saved, p => map[p]);
          window.addEventListener('resize', fit);
          const fonts = document.fonts && document.fonts.ready;
          if (fonts) fonts.then(() => { for (const n of host.nodes.values()) { n.mkey = null; n.v++; } host.touch(); });
          let last = performance.now();
          // one game frame: OnUpdate, then drawing. requestAnimationFrame stops in a hidden tab, so a slow timer keeps
          // the arcade going there (timers and the end of an animation still happen)
          const frame = now => {
            const dt = Math.min(0.1, Math.max(0, (now - last) / 1000)); last = now;
            host.tick(dt);
            render();
          };
          const loop = now => { frame(now); requestAnimationFrame(loop); };
          requestAnimationFrame(loop);
          setInterval(() => { if (document.hidden || performance.now() - last > 250) frame(performance.now()); }, 200);
          const save = () => host.save();
          window.addEventListener('pagehide', save);
          document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') save(); });
          setInterval(save, 15000);
          document.body.classList.add('ready');
        }));
    }).catch(err => { errBar.textContent = 'Could not load the arcade: ' + err.message; errBar.style.display = 'block'; });
  }
  window.WowDom = { start, measure };
})();
