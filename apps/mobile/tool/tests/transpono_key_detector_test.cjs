'use strict';

const assert = require('node:assert/strict');
const {test} = require('node:test');
const {KeyDetector, chromaFromSpectrum} = require('../../assets/web/transpono_key_detector.js');

const major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
  2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
  2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

function rotate(profile, root) {
  return Array.from({length: 12}, (_, note) => profile[(note - root + 12) % 12]);
}

test('stable major and minor chroma yield the intended key', () => {
  for (const [profile, root, mode] of [
    [major, 7, 'major'], [minor, 9, 'minor'],
  ]) {
    const detector = new KeyDetector();
    let detected = null;
    for (let frame = 0; frame < 35; frame++) {
      detected = detector.observeChroma(rotate(profile, root));
    }
    assert.equal(detected?.root, root);
    assert.equal(detected?.mode, mode);
    assert.ok(detected.confidence > 0);
    detector.reset();
    assert.equal(detector.detected, null);
    assert.equal(detector.frames, 0);
  }
});

test('a single note and silence cannot claim a song key', () => {
  const detector = new KeyDetector();
  for (let frame = 0; frame < 90; frame++) {
    assert.equal(detector.observeChroma([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), null);
  }
  assert.equal(detector.observeChroma(new Float64Array(12)), null);
  assert.deepEqual([...chromaFromSpectrum(new Float32Array(8192).fill(-100),
    48000, 16384)], Array(12).fill(0));
});
