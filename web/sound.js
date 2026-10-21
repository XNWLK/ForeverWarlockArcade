// The arcade's sounds on the web page, made on the spot with WebAudio (the game plays sounds of its own library
// instead). A small synth: tones with soft attacks, bells (FM), filtered noise, all through a gentle reverb and a
// limiter. Played by name (A.sound in Core.lua); the old sound kit numbers still map to a name.
// Not part of the addon.
(function () {
  'use strict';
  let ctx = null, out = null, verb = null, last = {};
  const OLD = { 856: 'click', 857: 'select', 839: 'open', 840: 'close', 891: 'coin', 888: 'win', 847: 'lose', 1202: 'card', 3081: 'crit' };

  function init() {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    try { ctx = new AC(); } catch (e) { return null; }
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.ratio.value = 4; comp.attack.value = 0.003; comp.release.value = 0.2;
    const master = ctx.createGain(); master.gain.value = 0.8;
    comp.connect(master); master.connect(ctx.destination);
    out = ctx.createGain(); out.connect(comp);
    // a short, dark room: a made-up impulse of decaying noise
    verb = ctx.createConvolver();
    const len = Math.floor(ctx.sampleRate * 1.4), ir = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let c = 0; c < 2; c++) { const d = ir.getChannelData(c); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 3.2); }
    verb.buffer = ir;
    const wet = ctx.createGain(); wet.gain.value = 0.22;
    const tone = ctx.createBiquadFilter(); tone.type = 'lowpass'; tone.frequency.value = 5200;
    verb.connect(tone); tone.connect(wet); wet.connect(comp);
    return ctx;
  }
  const dest = () => { const g = ctx.createGain(); g.connect(out); g.connect(verb); return g; };

  // a tone: wave, Hz (or [from, to]), start, length, volume, attack
  function tone(type, hz, t0, len, vol, attack) {
    const o = ctx.createOscillator(), g = ctx.createGain(), now = ctx.currentTime + t0;
    o.type = type;
    const [a, b] = Array.isArray(hz) ? hz : [hz, hz];
    o.frequency.setValueAtTime(a, now);
    if (b !== a) o.frequency.exponentialRampToValueAtTime(b, now + len);
    const at = attack || 0.005;
    g.gain.setValueAtTime(0.0001, now);
    g.gain.exponentialRampToValueAtTime(vol, now + at);
    g.gain.exponentialRampToValueAtTime(0.0001, now + len);
    o.connect(g); g.connect(dest());
    o.start(now); o.stop(now + len + 0.05);
  }
  // a bell: a sine with a sine moving its pitch (bright at first, then pure)
  function bell(hz, t0, len, vol, bright) {
    const now = ctx.currentTime + t0;
    const car = ctx.createOscillator(), mod = ctx.createOscillator(), mg = ctx.createGain(), g = ctx.createGain();
    car.frequency.value = hz; mod.frequency.value = hz * 3.5;
    mg.gain.setValueAtTime(hz * (bright || 2), now); mg.gain.exponentialRampToValueAtTime(1, now + len * 0.6);
    mod.connect(mg); mg.connect(car.frequency);
    g.gain.setValueAtTime(0.0001, now); g.gain.exponentialRampToValueAtTime(vol, now + 0.004); g.gain.exponentialRampToValueAtTime(0.0001, now + len);
    car.connect(g); g.connect(dest());
    car.start(now); mod.start(now); car.stop(now + len + 0.05); mod.stop(now + len + 0.05);
  }
  // filtered noise: filter type, Hz (or [from, to]), start, length, volume, q
  function noise(ftype, hz, t0, len, vol, q) {
    const now = ctx.currentTime + t0, n = Math.max(1, Math.floor(ctx.sampleRate * (len + 0.05)));
    const buf = ctx.createBuffer(1, n, ctx.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
    const src = ctx.createBufferSource(); src.buffer = buf;
    const f = ctx.createBiquadFilter(); f.type = ftype; f.Q.value = q || 1;
    const [a, b] = Array.isArray(hz) ? hz : [hz, hz];
    f.frequency.setValueAtTime(a, now); if (b !== a) f.frequency.exponentialRampToValueAtTime(b, now + len);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, now); g.gain.exponentialRampToValueAtTime(vol, now + Math.min(0.02, len / 3)); g.gain.exponentialRampToValueAtTime(0.0001, now + len);
    src.connect(f); f.connect(g); g.connect(dest());
    src.start(now); src.stop(now + len + 0.05);
  }
  const N = (semi) => 440 * Math.pow(2, (semi - 9) / 12);   // semitones from C4 (0 = C4, 12 = C5)

  const SOUNDS = {
    hover: () => tone('sine', 1900, 0, 0.035, 0.018),
    click: () => { tone('triangle', [1300, 900], 0, 0.05, 0.08); noise('highpass', 4000, 0, 0.02, 0.03); },
    select: () => { tone('sine', N(19), 0, 0.09, 0.07); tone('sine', N(26), 0.045, 0.12, 0.06); },
    open: () => { noise('bandpass', [500, 3200], 0, 0.22, 0.05, 0.8); tone('sine', N(7), 0.02, 0.3, 0.05, 0.03); tone('sine', N(14), 0.06, 0.32, 0.04, 0.03); },
    close: () => { noise('bandpass', [2800, 450], 0, 0.2, 0.045, 0.8); tone('sine', [N(14), N(7)], 0, 0.22, 0.04, 0.02); },
    whoosh: () => noise('bandpass', [300, 2600], 0, 0.28, 0.07, 1.2),
    coin: () => { bell(N(28), 0, 0.35, 0.06, 1.5); bell(N(35), 0.07, 0.5, 0.06, 1.5); },
    card: () => { noise('bandpass', [2400, 1200], 0, 0.06, 0.08, 2); tone('triangle', [300, 180], 0, 0.06, 0.05); },
    flip: () => { noise('bandpass', [1600, 3600], 0, 0.08, 0.07, 2.5); },
    place: () => { tone('sine', [220, 140], 0, 0.09, 0.12); noise('lowpass', 900, 0, 0.05, 0.05); },
    pop: () => { tone('sine', [N(24), N(31)], 0, 0.08, 0.08); },
    tick: () => tone('square', 2200, 0, 0.018, 0.02),
    countdown: () => bell(N(21), 0, 0.3, 0.06, 1),
    go: () => { bell(N(33), 0, 0.5, 0.07, 1.2); tone('triangle', N(21), 0, 0.3, 0.04); },
    // the four demon runes of Ritual of Summoning: a chord of four bells
    rune1: () => { bell(N(12), 0, 0.5, 0.07, 1.2); tone('sine', N(12), 0, 0.4, 0.03, 0.01); },
    rune2: () => { bell(N(16), 0, 0.5, 0.07, 1.2); tone('sine', N(16), 0, 0.4, 0.03, 0.01); },
    rune3: () => { bell(N(19), 0, 0.5, 0.07, 1.2); tone('sine', N(19), 0, 0.4, 0.03, 0.01); },
    rune4: () => { bell(N(24), 0, 0.5, 0.07, 1.2); tone('sine', N(24), 0, 0.4, 0.03, 0.01); },
    jump: () => tone('triangle', [N(7), N(19)], 0, 0.12, 0.06),
    lock: () => { noise('bandpass', [3000, 800], 0, 0.12, 0.08, 2); tone('square', [N(24), N(12)], 0, 0.1, 0.03); },
    perfect: () => { bell(N(31), 0, 0.22, 0.05, 1.2); tone('sine', N(43), 0.01, 0.12, 0.02); },
    good: () => bell(N(26), 0, 0.18, 0.04, 0.8),
    miss: () => { tone('triangle', [180, 90], 0, 0.14, 0.07); noise('lowpass', 500, 0, 0.1, 0.04); },
    error: () => { tone('square', N(-1), 0, 0.09, 0.03); tone('square', N(-6), 0.09, 0.14, 0.03); },
    combo: () => { [0, 4, 7].forEach((s, i) => bell(N(24 + s), i * 0.05, 0.3, 0.04, 1)); },
    crit: () => { tone('sine', [140, 45], 0, 0.25, 0.22); noise('lowpass', [3000, 300], 0, 0.18, 0.12); bell(N(36), 0.02, 0.35, 0.05, 2.5); },
    levelup: () => { [0, 4, 7, 12, 16].forEach((s, i) => bell(N(19 + s), i * 0.07, 0.6, 0.05, 1.2)); },
    win: () => {
      [0, 4, 7, 12].forEach((s, i) => { bell(N(12 + s), i * 0.09, 0.9, 0.055, 1.4); tone('triangle', N(s), i * 0.09, 0.6, 0.025, 0.02); });
      [0, 4, 7, 12, 16, 19].forEach((s, i) => tone('sine', N(24 + s), 0.4 + i * 0.03, 1.4, 0.018, 0.08));
      noise('highpass', 6000, 0.38, 1.2, 0.015);
    },
    lose: () => { [7, 3, 0, -5].forEach((s, i) => tone('triangle', N(s), i * 0.14, 0.42, 0.05, 0.02)); tone('sine', [N(-12), N(-17)], 0.5, 0.9, 0.06, 0.05); },
  };

  function play(c, what) {
    if (!ctx || !c) return;
    const name = SOUNDS[what] ? what : OLD[what];
    if (!name) return;
    if (ctx.state === 'suspended') ctx.resume();
    // the same sound twice within 30 ms (a burst of events in one frame) plays once
    const t = ctx.currentTime;
    if (last[name] !== undefined && t - last[name] < 0.03) return;
    last[name] = t;
    try { SOUNDS[name](); } catch (e) { /* a missing audio feature: stay quiet */ }
  }
  window.WowSound = { init, play };
})();
