// The web page's stand-in for the game's UI engine: runs web/wow.lua and the addon's Lua files in fengari, keeps
// every frame, texture and text (where it is anchored, its size, layer, colour) and works out where each one sits,
// the way the game does (anchors, scale, strata, frame level, draw layer). Drawing and input are done by
// web/wow-dom.js; the checks in tools/ use this file without any drawing. Not part of the addon.
(function (root) {
  'use strict';
  const FX = { TOPLEFT: 0, LEFT: 0, BOTTOMLEFT: 0, TOP: 0.5, CENTER: 0.5, BOTTOM: 0.5, TOPRIGHT: 1, RIGHT: 1, BOTTOMRIGHT: 1 };
  const FY = { TOPLEFT: 1, TOP: 1, TOPRIGHT: 1, LEFT: 0.5, CENTER: 0.5, RIGHT: 0.5, BOTTOMLEFT: 0, BOTTOM: 0, BOTTOMRIGHT: 0 };

  // WoW text: |cAARRGGBB ... |r colours, |n line breaks, || a bar. Returns [{text, color|null}] and the plain text.
  function parseText(s) {
    const runs = []; let color = null, cur = '', i = 0;
    const push = () => { if (cur) { runs.push({ text: cur, color }); cur = ''; } };
    while (i < s.length) {
      const c = s[i];
      if (c === '|' && i + 1 < s.length) {
        const n = s[i + 1];
        if ((n === 'c' || n === 'C') && /^[0-9a-fA-F]{8}$/.test(s.substr(i + 2, 8))) { push(); color = '#' + s.substr(i + 4, 6); i += 10; continue; }
        if (n === 'r' || n === 'R') { push(); color = null; i += 2; continue; }
        if (n === 'n') { cur += '\n'; i += 2; continue; }
        if (n === '|') { cur += '|'; i += 2; continue; }
      }
      cur += c; i++;
    }
    push();
    return { runs, plain: runs.map(r => r.text).join('') };
  }

  class WowHost {
    // opts: fengari, measure(plain, font, wrapWidth) -> {w, h, lines}, render(host) (optional), now() seconds,
    //       storage {get(key), set(key, value)}, onError(text), onChat(text), sound(id), soundFile(path), meta {}
    constructor(opts) {
      this.o = opts; this.f = opts.fengari;
      this.nodes = new Map(); this.dirty = true; this.layoutPass = 0;
      this.screen = { w: 1024, h: 768 }; this.cursor = { x: 0, y: 0 }; this.mods = { shift: false, ctrl: false, alt: false };
      this.hover = 0; this.tip = null; this.errors = []; this.chat = [];
      const { lua, lauxlib, lualib } = this.f;
      this.L = lauxlib.luaL_newstate();
      lualib.luaL_openlibs(this.L);
      this.installNatives();
    }
    // ---- Lua plumbing ----
    str(s) { return this.f.to_luastring(String(s)); }
    run(code, name) {
      const { lua, lauxlib } = this.f, L = this.L;
      if (lauxlib.luaL_loadbuffer(L, this.str(code), null, this.str(name || '=chunk')) !== lua.LUA_OK) {
        const msg = this.f.to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); this.error('Lua syntax: ' + msg); return false;
      }
      if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        const msg = this.f.to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); this.error('Lua: ' + msg); return false;
      }
      return true;
    }
    // runs an addon file the way the game does: called with (addon name, the addon's shared table)
    runAddonFile(src, file, addon) {
      const { lua, lauxlib } = this.f, L = this.L;
      if (lauxlib.luaL_loadbuffer(L, this.str(src), null, this.str('@' + file)) !== lua.LUA_OK) {
        const msg = this.f.to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); this.error(msg); return false;
      }
      lua.lua_pushstring(L, this.str(addon));
      lua.lua_getglobal(L, this.str('__ADDON_NS'));
      if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) {
        const msg = this.f.to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); this.error(msg); return false;
      }
      return true;
    }
    // calls a global Lua function with plain arguments; returns its first result
    call(name, ...args) {
      const { lua } = this.f, L = this.L;
      lua.lua_getglobal(L, this.str(name));
      args.forEach(a => this.push(a));
      if (lua.lua_pcall(L, args.length, 1, 0) !== lua.LUA_OK) {
        const msg = this.f.to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); this.error(msg); return undefined;
      }
      const v = this.get(-1); lua.lua_pop(L, 1); return v;
    }
    push(v) {
      const { lua } = this.f, L = this.L;
      if (v === undefined || v === null) lua.lua_pushnil(L);
      else if (typeof v === 'number') lua.lua_pushnumber(L, v);
      else if (typeof v === 'boolean') lua.lua_pushboolean(L, v);
      else lua.lua_pushstring(L, this.str(v));
    }
    get(i) {
      const { lua } = this.f, L = this.L, t = lua.lua_type(L, i);
      if (t === lua.LUA_TNUMBER) return lua.lua_tonumber(L, i);
      if (t === lua.LUA_TSTRING) return this.f.to_jsstring(lua.lua_tostring(L, i));
      if (t === lua.LUA_TBOOLEAN) return lua.lua_toboolean(L, i);
      return null;
    }
    error(msg) { this.errors.push(msg); if (this.o.onError) this.o.onError(msg); }
    installNatives() {
      const { lua } = this.f, L = this.L, self = this;
      lua.lua_newtable(L);
      const def = (name, fn) => {
        lua.lua_pushjsfunction(L, LL => {
          const n = lua.lua_gettop(LL), a = [];
          for (let i = 1; i <= n; i++) a.push(self.get(i));
          let r = fn.apply(self, a);
          if (r === undefined) return 0;
          if (!Array.isArray(r)) r = [r];
          r.forEach(v => self.push(v));
          return r.length;
        });
        lua.lua_setfield(L, -2, self.str(name));
      };
      const N = this.natives();
      Object.keys(N).forEach(k => def(k, N[k]));
      lua.lua_setglobal(L, this.str('__web'));
    }
    node(id) { return this.nodes.get(id); }
    touch() { this.dirty = true; }
    natives() {
      const H = this;
      const set = (id, k, v) => { const n = H.nodes.get(id); if (n) { n[k] = v; n.v++; H.dirty = true; } };
      return {
        create(id, kind, parent, layer, sub) {
          H.nodes.set(id, { id, kind, parent, layer, sub, points: [], w: -1, h: -1, shown: true, alpha: 1, scale: 1, strata: 0, level: 0,
            mouse: false, v: 0, tex: '', color: null, vcolor: null, coords: null, rot: 0, text: '', font: null, tcolor: [1, 1, 1, 1],
            jh: 'CENTER', jv: 'MIDDLE', wrap: true, keys: false, keyboard: false, propagate: false, wheel: false, drag: false });
          H.dirty = true;
        },
        parent(id, p) { set(id, 'parent', p); },
        point(id, p, rel, rp, x, y) {
          const n = H.nodes.get(id); if (!n) return;
          n.points = n.points.filter(q => q.p !== p); n.points.push({ p, rel, rp, x, y }); n.v++; H.dirty = true;
        },
        clear(id) { set(id, 'points', []); },
        size(id, w, h) { const n = H.nodes.get(id); if (n) { n.w = w; n.h = h; n.v++; H.dirty = true; } },
        shown(id, v) { set(id, 'shown', v); },
        alpha(id, a) { set(id, 'alpha', a); },
        scale(id, s) { set(id, 'scale', s); },
        strata(id, s) { set(id, 'strata', s); },
        level(id, l) { set(id, 'level', l); },
        layer(id, l, s) { const n = H.nodes.get(id); if (n) { n.layer = l; n.sub = s; n.v++; H.dirty = true; } },
        mouse(id, v) { set(id, 'mouse', v); },
        wheel(id, v) { set(id, 'wheel', v); },
        keyboard(id, v) { set(id, 'keyboard', v); },
        keys(id, v) { set(id, 'keys', v); },
        propagate(id, v) { set(id, 'propagate', v); },
        drag(id, v) { set(id, 'drag', v); },
        clip(id, v) { set(id, 'clip', v); },
        tex(id, path) { const n = H.nodes.get(id); if (n) { n.tex = path; n.color = null; n.gradient = null; n.v++; H.dirty = true; } },
        color(id, r, g, b, a) { const n = H.nodes.get(id); if (n) { n.color = [r, g, b, a]; n.tex = ''; n.gradient = null; n.v++; H.dirty = true; } },
        vcolor(id, r, g, b, a) { set(id, 'vcolor', [r, g, b, a]); },
        coords(id, l, r, t, b) { set(id, 'coords', [l, r, t, b]); },
        rot(id, r) { set(id, 'rot', r); },
        slice(id, l, t, r, b) { set(id, 'slice', [l, t, r, b]); },
        desat(id, v) { set(id, 'desat', v); },
        blend(id, m) { set(id, 'blend', m); },
        gradient(id, o, r1, g1, b1, a1, r2, g2, b2, a2) { set(id, 'gradient', [o, [r1, g1, b1, a1], [r2, g2, b2, a2]]); },
        font(id, path, size, flags) { set(id, 'font', { path, size, flags }); },
        text(id, t) { const n = H.nodes.get(id); if (n) { n.text = t; n.parsed = parseText(t); n.v++; H.dirty = true; } },
        tcolor(id, r, g, b, a) { set(id, 'tcolor', [r, g, b, a]); },
        justify(id, h, v) { const n = H.nodes.get(id); if (n) { n.jh = h; n.jv = v; n.v++; H.dirty = true; } },
        wrap(id, v) { set(id, 'wrap', v); },
        maxlines(id, v) { set(id, 'maxlines', v); },
        spacing(id, v) { set(id, 'spacing', v); },
        shadow(id, x, y, r, g, b, a) { set(id, 'shadow', [x, y, r, g, b, a]); },
        rect(id) {
          const n = H.nodes.get(id); if (!n) return [null];
          H.layout();
          const r = n.rect; if (!r) return [null];
          const s = H.effScale(n);
          return [r.l / s, r.b / s, r.w / s, r.h / s];
        },
        strw(id) {
          const n = H.nodes.get(id); if (!n || !n.font) return [0, 0];
          const m = H.measureNode(n, n.w > 0 ? n.w : 0);
          return [m.w, m.h];
        },
        over(id) {
          const n = H.nodes.get(id); H.layout(); if (!n || !n.rect) return false;
          const r = n.rect, c = H.cursor;
          return c.x >= r.l && c.x <= r.l + r.w && c.y >= r.b && c.y <= r.b + r.h;
        },
        cursor() { return [H.cursor.x, H.cursor.y]; },
        // which frame the mouse would reach at the middle of this one (for the checks: is a button covered?)
        topAt(id) {
          const n = H.nodes.get(id); H.layout(); if (!n || !n.rect) return 0;
          return H.hitTest(n.rect.l + n.rect.w / 2, n.rect.b + n.rect.h / 2);
        },
        mod(k) { return !!H.mods[k]; },
        now() { return H.o.now(); },
        epoch() { return Date.now() / 1000; },
        tip(owner, anchor, lines) {
          H.tip = owner ? { owner, anchor, lines: lines.split('\x1e').map(l => l.split('\x1f')) } : null;
          H.dirty = true;
        },
        sound(id) { if (H.o.sound) H.o.sound(id); },
        soundFile(p) { if (H.o.soundFile) H.o.soundFile(p); },
        chat(t) { H.chat.push(t); if (H.o.onChat) H.o.onChat(t); },
        err(t) { H.error(t); },
        meta(field) { return (H.o.meta || {})[field] || null; },
      };
    }
    // ---- layout ----
    effScale(n) { let s = 1; while (n) { s *= n.scale || 1; n = n.parent ? this.nodes.get(n.parent) : null; } return s; }
    frameOf(n) { return n.kind === 'tex' || n.kind === 'font' ? this.nodes.get(n.parent) : n; }
    measureNode(n, wrapWidth) {
      const k = n.text + '\x00' + (n.font && n.font.path) + (n.font && n.font.size) + '\x00' + wrapWidth + (n.wrap ? 'w' : '') + (n.spacing || 0);
      if (n.mkey === k) return n.mval;
      const m = this.o.measure ? this.o.measure(n.parsed ? n.parsed.plain : '', n.font, n.wrap ? wrapWidth : 0)
        : { w: (n.parsed ? n.parsed.plain.length : 0) * n.font.size * 0.5, h: n.font.size * 1.15, lines: 1 };
      // SetSpacing adds to every line (the page draws line-height = size * 1.15 + spacing)
      if (n.spacing) m.h += (m.lines || 1) * n.spacing;
      n.mkey = k; n.mval = m; return m;
    }
    layout() {
      if (!this.dirty && this.laidOut) return;
      this.layoutPass++;
      const pass = this.layoutPass;
      const rootId = 1;
      for (const n of this.nodes.values()) { n.rect = undefined; n.pass = pass; }
      const resolving = new Set();
      const rectOf = (n) => {
        if (n.rect !== undefined) return n.rect;
        if (n.kind === 'root') { n.rect = { l: 0, b: 0, w: this.screen.w, h: this.screen.h }; return n.rect; }
        if (resolving.has(n.id)) { n.rect = null; return null; }
        resolving.add(n.id);
        const s = this.effScale(n);
        let L = null, R = null, CX = null, B = null, T = null, CY = null;
        n.points.forEach(q => {
          const t = this.nodes.get(q.rel || n.parent) || this.nodes.get(rootId);
          const tr = t && rectOf(t); if (!tr) return;
          const px = tr.l + FX[q.rp] * tr.w + q.x * s, py = tr.b + FY[q.rp] * tr.h + q.y * s;
          const fx = FX[q.p], fy = FY[q.p];
          if (fx === 0) L = px; else if (fx === 1) R = px; else CX = px;
          if (fy === 0) B = py; else if (fy === 1) T = py; else CY = py;
        });
        resolving.delete(n.id);
        if (!n.points.length) { n.rect = null; return null; }
        let w = n.w >= 0 ? n.w * s : null, h = n.h >= 0 ? n.h * s : null;
        if (n.kind === 'font' && n.font && (w === null || h === null)) {
          const ww = L !== null && R !== null ? (R - L) / s : (w !== null ? w / s : 0);
          const m = this.measureNode(n, ww);
          if (w === null && !(L !== null && R !== null)) w = m.w * s;
          if (h === null && !(B !== null && T !== null)) h = m.h * s;
        }
        let l, b;
        if (L !== null && R !== null) { l = L; w = R - L; }
        else if (L !== null && CX !== null) { l = L; w = 2 * (CX - L); }
        else if (R !== null && CX !== null) { w = 2 * (R - CX); l = R - w; }
        else { w = w || 0; l = L !== null ? L : R !== null ? R - w : CX - w / 2; }
        if (B !== null && T !== null) { b = B; h = T - B; }
        else if (B !== null && CY !== null) { b = B; h = 2 * (CY - B); }
        else if (T !== null && CY !== null) { h = 2 * (T - CY); b = T - h; }
        else { h = h || 0; b = B !== null ? B : T !== null ? T - h : CY - h / 2; }
        if (!isFinite(l) || !isFinite(b)) { n.rect = null; return null; }
        n.rect = { l, b, w: Math.max(0, w), h: Math.max(0, h) };
        return n.rect;
      };
      for (const n of this.nodes.values()) rectOf(n);
      // visibility, alpha and drawing order
      const cut = (a, b) => { if (!a) return b; const l = Math.max(a.l, b.l), bb = Math.max(a.b, b.b); return { l, b: bb, w: Math.max(0, Math.min(a.l + a.w, b.l + b.w) - l), h: Math.max(0, Math.min(a.b + a.h, b.b + b.h) - bb) }; };
      const vis = (n) => {
        if (n.visPass === pass) return n.vis;
        const p = n.parent ? this.nodes.get(n.parent) : null;
        const pv = p ? vis(p) : true;
        n.vis = pv && n.shown && (n.layer !== 5 || (n.kind !== 'tex' && n.kind !== 'font') || this.hover === n.parent); n.ealpha = (p ? p.ealpha : 1) * n.alpha; n.visPass = pass;
        // SetClipsChildren: everything under a clipping frame is cut to its box (and to any clipping frame above it)
        n.clipr = p ? (p.clip && p.rect ? cut(p.clipr, p.rect) : p.clipr) : null;   // HIGHLIGHT layer: only while the mouse is over its frame, like the game
        // strata: the frame's own or its parent's
        const f = this.frameOf(n);
        n.estrata = n.kind === 'tex' || n.kind === 'font' ? (f ? f.estrata : 3) : (n.strata || (p ? p.estrata : 3) || 3);
        return n.vis;
      };
      for (const n of this.nodes.values()) vis(n);
      for (const n of this.nodes.values()) {
        const f = this.frameOf(n);
        const level = f ? f.level : 0;
        n.z = n.estrata * 1000000 + level * 200 + (n.kind === 'tex' || n.kind === 'font' ? n.layer * 20 + (n.sub + 8) : 199);
      }
      this.dirty = false; this.laidOut = true;
    }
    // ---- driving the addon ----
    boot(addon, files, savedNames, readFile) {
      this.addon = addon; this.savedNames = savedNames || [];
      if (!this.run(readFile('web/wow.lua'), '@web/wow.lua')) return false;
      this.run('__ADDON_NS = {}', '=ns');
      const saved = this.o.storage && this.o.storage.get('saved:' + addon);
      if (saved) this.call('__webLoadSaved', saved);
      files.forEach(f => this.runAddonFile(readFile(addon + '/' + f.replace(/\\/g, '/')), f, addon));
      this.event('ADDON_LOADED', addon);
      this.event('PLAYER_LOGIN');
      this.event('PLAYER_ENTERING_WORLD', true, false);
      return this.errors.length === 0;
    }
    save() {
      if (!this.savedNames.length || !this.o.storage) return;
      const s = this.call('__webSave', this.savedNames.join(','));
      if (typeof s === 'string') this.o.storage.set('saved:' + this.addon, s);
    }
    event(name, ...args) { this.call('__webEvent', name, ...args); }
    tick(elapsed) { this.call('__webTick', elapsed); }
    script(id, name, a, b) { return this.call('__webScript', id, name, a, b); }
    resize(w, h) { this.screen = { w, h }; this.dirty = true; if (this.addon) { this.event('DISPLAY_SIZE_CHANGED'); this.event('UI_SCALE_CHANGED'); } }
    // the frames that take the mouse at a point, topmost first
    hitTest(x, y) {
      this.layout();
      let best = null;
      for (const n of this.nodes.values()) {
        if (!n.mouse || !n.vis || !n.rect || n.kind === 'root') continue;
        const r = n.rect;
        const c = n.clipr;
        if (c && !(x >= c.l && x <= c.l + c.w && y >= c.b && y <= c.b + c.h)) continue;
        if (x >= r.l && x <= r.l + r.w && y >= r.b && y <= r.b + r.h && (!best || n.z > best.z || (n.z === best.z && n.id > best.id))) best = n;
      }
      return best ? best.id : 0;
    }
    keyTargets() {
      this.layout();
      return [...this.nodes.values()].filter(n => n.keyboard && n.keys && n.vis).sort((a, b) => b.z - a.z || b.id - a.id);
    }
    // a key from the page, in the game's names (A, 1, SPACE, ESCAPE, LEFT ...)
    key(name, down) {
      const list = this.keyTargets();
      for (const n of list) {
        this.script(n.id, down ? 'OnKeyDown' : 'OnKeyUp', name);
        if (!n.propagate) return true;
      }
      return false;
    }
  }
  WowHost.parseText = parseText;
  if (typeof module !== 'undefined' && module.exports) module.exports = { WowHost, parseText };
  else root.WowHost = WowHost;
})(typeof window !== 'undefined' ? window : globalThis);
