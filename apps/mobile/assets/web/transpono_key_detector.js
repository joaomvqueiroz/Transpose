/* Local, streaming key estimate from pitch-class energy; no audio is stored. */
(function (root) {
  'use strict';

  const major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
    2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
  const minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
    2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

  function correlation(values, profile, rootNote) {
    const meanValues = values.reduce((a, b) => a + b, 0) / 12;
    const meanProfile = profile.reduce((a, b) => a + b, 0) / 12;
    let dot = 0, left = 0, right = 0;
    for (let note = 0; note < 12; note++) {
      const a = values[note] - meanValues;
      const b = profile[(note - rootNote + 12) % 12] - meanProfile;
      dot += a * b;
      left += a * a;
      right += b * b;
    }
    return left && right ? dot / Math.sqrt(left * right) : 0;
  }

  function chromaFromSpectrum(spectrum, sampleRate, fftSize) {
    const result = new Float64Array(12);
    let loudest = -Infinity;
    const lowBin = Math.ceil(80 * fftSize / sampleRate);
    const highBin = Math.min(spectrum.length - 2, Math.floor(1600 * fftSize / sampleRate));
    for (let bin = lowBin; bin <= highBin; bin++) {
      if (spectrum[bin] > loudest) loudest = spectrum[bin];
    }
    if (loudest < -78) return result;
    for (let bin = lowBin + 1; bin < highBin; bin++) {
      const decibels = spectrum[bin];
      if (decibels < loudest - 28 || decibels < spectrum[bin - 1] ||
          decibels < spectrum[bin + 1]) continue;
      const frequency = bin * sampleRate / fftSize;
      const midi = 69 + 12 * Math.log2(frequency / 440);
      const note = Math.round(midi);
      const distance = Math.abs(midi - note);
      if (distance > 0.35) continue;
      const weight = Math.pow(10, (decibels - loudest) / 20) *
        (1 - distance / 0.35) * Math.pow(220 / frequency, 0.25);
      result[(note % 12 + 12) % 12] += weight;
    }
    return result;
  }

  class KeyDetector {
    constructor() { this.reset(); }

    reset() {
      this.history = new Float64Array(12);
      this.frames = 0;
      this.candidate = '';
      this.candidateFrames = 0;
      this.detected = null;
    }

    observeSpectrum(spectrum, sampleRate, fftSize) {
      return this.observeChroma(chromaFromSpectrum(spectrum, sampleRate, fftSize));
    }

    observeChroma(chroma) {
      const total = chroma.reduce((a, b) => a + Math.max(0, b), 0);
      if (total <= 0) return this.detected;
      for (let note = 0; note < 12; note++) {
        this.history[note] = this.history[note] * 0.985 +
          Math.max(0, chroma[note]) / total;
      }
      this.frames++;
      if (this.frames < 24) return this.detected;
      const maximum = Math.max(...this.history);
      // A single sustained note or chord is not sufficient evidence of a key.
      if (this.history.filter(value => value > maximum * 0.16).length < 5)
        return this.detected;

      let best = {score: -Infinity, root: 0, mode: 'major'};
      let second = -Infinity;
      for (let rootNote = 0; rootNote < 12; rootNote++) {
        for (const [mode, profile] of [['major', major], ['minor', minor]]) {
          const score = correlation(this.history, profile, rootNote);
          if (score > best.score) {
            second = best.score;
            best = {score, root: rootNote, mode};
          } else if (score > second) {
            second = score;
          }
        }
      }
      if (best.score < 0.53 || best.score - second < 0.045) return this.detected;
      const candidate = `${best.root}:${best.mode}`;
      if (candidate === this.candidate) this.candidateFrames++;
      else {
        this.candidate = candidate;
        this.candidateFrames = 1;
      }
      if (this.candidateFrames >= 4) {
        this.detected = {
          root: best.root, mode: best.mode,
          confidence: Math.round((best.score - second) * 1000) / 1000,
        };
      }
      return this.detected;
    }
  }

  const api = Object.freeze({KeyDetector, chromaFromSpectrum});
  if (root) root.TransponoKeyDetector = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window === 'undefined' ? null : window);
