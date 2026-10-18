// Short made-up tones for the game's sound kit ids the arcade plays (the game plays its own sounds instead).
// Not part of the addon.
(function () {
  'use strict';
  // id: [wave, start Hz, end Hz, seconds, volume]
  const TONES = {
    856: ['triangle', 660, 520, 0.06, 0.12],   // click
    857: ['triangle', 520, 700, 0.05, 0.1],    // select
    839: ['sine', 330, 660, 0.18, 0.12],       // open
    840: ['sine', 660, 330, 0.16, 0.1],        // close
    891: ['square', 988, 1319, 0.12, 0.06],    // coin
    888: ['sawtooth', 392, 784, 0.4, 0.07],    // win
    847: ['sawtooth', 300, 120, 0.5, 0.07],    // lose
    1202: ['triangle', 240, 180, 0.07, 0.12],  // card
    3081: ['square', 880, 1760, 0.09, 0.05],   // crit
  };
  function init() {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    try { return new AC(); } catch (e) { return null; }
  }
  function play(ctx, id) {
    const t = TONES[id];
    if (!t || !ctx) return;
    if (ctx.state === 'suspended') ctx.resume();
    const now = ctx.currentTime, o = ctx.createOscillator(), g = ctx.createGain();
    o.type = t[0];
    o.frequency.setValueAtTime(t[1], now);
    o.frequency.exponentialRampToValueAtTime(t[2], now + t[3]);
    g.gain.setValueAtTime(t[4], now);
    g.gain.exponentialRampToValueAtTime(0.0001, now + t[3]);
    o.connect(g); g.connect(ctx.destination);
    o.start(now); o.stop(now + t[3] + 0.02);
  }
  window.WowSound = { init, play };
})();
