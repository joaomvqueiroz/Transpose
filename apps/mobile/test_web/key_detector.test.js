const assert = require('node:assert/strict');
const test = require('node:test');
const {KeyDetector, chromaFromSpectrum} =
  require('../assets/web/transpono_key_detector.js');

test('infers a major key from a changing chord progression', () => {
  const detector = new KeyDetector();
  for (let frame = 0; frame < 60; frame++) {
    const chroma = Array(12).fill(0);
    for (const note of [[0, 4, 7], [5, 9, 0], [7, 11, 2]][Math.floor(frame / 20)]) {
      chroma[note] = 1;
    }
    detector.observeChroma(chroma);
  }
  assert.equal(detector.detected.root, 0);
  assert.equal(detector.detected.mode, 'major');
});

test('distinguishes minor and resets between songs', () => {
  const detector = new KeyDetector();
  const minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
    2.54, 4.75, 3.98, 2.69, 3.34, 3.17];
  for (let frame = 0; frame < 30; frame++) detector.observeChroma(minorProfile);
  assert.deepEqual([detector.detected.root, detector.detected.mode], [0, 'minor']);
  detector.reset();
  assert.equal(detector.detected, null);
  assert.equal(detector.frames, 0);
});

test('does not call a single note a musical key', () => {
  const detector = new KeyDetector();
  for (let frame = 0; frame < 90; frame++) {
    detector.observeChroma([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  }
  assert.equal(detector.detected, null);
});

test('silent spectrum contributes no pitch classes', () => {
  const spectrum = new Float32Array(8192).fill(-100);
  assert.equal(chromaFromSpectrum(spectrum, 48000, 16384).reduce((a, b) => a + b), 0);
});
