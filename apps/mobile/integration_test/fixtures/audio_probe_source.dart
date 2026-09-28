// Generated-tone fixture kept outside production assets.
const audioProbeSource = r'''
/*
 * Isolated Android/iOS WebView DSP fixture. Test-only; not a YouTube page.
 * Load an empty HTML document with baseUrl:
 *   https://m.youtube.com/watch?v=transpono-probe
 * Then inject this file, SignalsmithStretch.js and transpono_media.js, in order.
 * The synthetic 440 Hz tone is generated in memory; no network/media fetches.
 * window.TransponoAudioProbe.runCase({pitch: 3, speed: 0.75}) returns a JSON-safe
 * result with measured frequencies, media-clock speed and the final snapshot.
 * This measures the digital graph, not speaker/headphone acoustic output.
 */
(function () {
  'use strict';
  if (window.TransponoAudioProbe) throw new Error('The probe fixture is already installed.');
  if (document.querySelector('video, audio')) throw new Error('Use an empty test document for the audio probe.');
  window.__transponoAudioProbe = true;

  const sampleRate = 48000;
  const frequency = 440;
  const duration = 30;
  const samples = duration * sampleRate;
  const data = new ArrayBuffer(44 + samples * 2);
  const view = new DataView(data);
  const ascii = (offset, text) => {
    for (let i = 0; i < text.length; i += 1) view.setUint8(offset + i, text.charCodeAt(i));
  };
  ascii(0, 'RIFF');
  view.setUint32(4, 36 + samples * 2, true);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  ascii(36, 'data');
  view.setUint32(40, samples * 2, true);
  for (let i = 0; i < samples; i += 1) {
    // 10 ms attack/release avoids clicks in the generated test tone itself.
    const ramp = Math.min(1, i / 480, (samples - 1 - i) / 480);
    view.setInt16(44 + i * 2, Math.round(Math.sin(2 * Math.PI * frequency * i / sampleRate) * 0.15 * ramp * 32767), true);
  }

  document.title = 'Transpono synthetic audio probe';
  const video = document.createElement('video');
  video.controls = true;
  video.playsInline = true;
  video.preload = 'auto';
  video.style.cssText = 'display:block;width:100%;min-height:100px;background:#0b1826';
  const url = URL.createObjectURL(new Blob([data], {type: 'audio/wav'}));
  const ready = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Synthetic WAV did not load.')), 10000);
    video.addEventListener('loadedmetadata', () => {
      clearTimeout(timeout);
      resolve({frequency, duration, sampleRate});
    }, {once: true});
    video.addEventListener('error', () => {
      clearTimeout(timeout);
      reject(new Error('Synthetic WAV playback failed.'));
    }, {once: true});
  });
  document.body.appendChild(video);
  video.src = url;

  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const median = values => {
    const finite = values.filter(Number.isFinite).sort((a, b) => a - b);
    return finite.length ? finite[Math.floor(finite.length / 2)] : null;
  };
  let running = false;
  async function runCase(parameters = {}) {
    if (running) throw new Error('A probe case is already running.');
    running = true;
    try {
      await ready;
      if (!window.TransponoMedia) throw new Error('Inject the media bridge before running a case.');
      const requestedPitch = parameters.pitch === undefined ? 3 : parameters.pitch;
      const requestedSpeed = parameters.speed === undefined ? 1 : parameters.speed;
      await window.TransponoMedia.command({action: 'clearLoop'});
      video.currentTime = 2;
      await video.play();
      // Deliberately create the filters before the first pitch processor (E2).
      await window.TransponoMedia.command({action: 'bass', value: 3});
      await window.TransponoMedia.command({action: 'pitch', value: requestedPitch});
      await window.TransponoMedia.command({action: 'speed', value: requestedSpeed});
      const deadline = performance.now() + 12000;
      const expectedStatus = requestedPitch === 0 ? 'idle' : 'active';
      let snapshot;
      do {
        await sleep(200);
        snapshot = window.TransponoMedia.snapshot();
        if (snapshot.pitchStatus === 'unavailable') throw new Error(snapshot.pitchMessage);
      } while (snapshot.pitchStatus !== expectedStatus && performance.now() < deadline);
      if (snapshot.pitchStatus !== expectedStatus) throw new Error('Expected audio route was not observed.');
      // Flush initial analyser history and the browser's speed-change transition.
      await sleep(1200);
      const measurements = [];
      const started = performance.now();
      const startedPosition = video.currentTime;
      for (let i = 0; i < 8; i += 1) {
        await sleep(200);
        measurements.push(window.TransponoMedia.snapshot());
      }
      const ended = performance.now();
      const actualSpeed = (video.currentTime - startedPosition) / ((ended - started) / 1000);
      snapshot = measurements.at(-1);
      const inputHz = median(measurements.map(value => value.probe.inputHz));
      const outputHz = median(measurements.map(value => value.probe.outputHz));
      const finalHz = median(measurements.map(value => value.probe.finalHz));
      const finalRms = median(measurements.map(value => value.probe.finalRms));
      const expectedHz = frequency * Math.pow(2, requestedPitch / 12);
      const centsError = finalHz ? 1200 * Math.log2(finalHz / expectedHz) : null;
      // Chromium can retain the last rendered AudioParam value in a disconnected
      // branch. Bypass is verified by disconnection AND measured final audio,
      // not by the stale wet gain of a branch no longer producing any samples.
      const routePassed = requestedPitch === 0
        ? !snapshot.probe.dspConnected && snapshot.probe.dryGain === 1 &&
          snapshot.probe.outputRms === 0
        : snapshot.probe.dspConnected && snapshot.probe.wetGain === 1 &&
          snapshot.probe.dryGain === 0;
      return {
        requestedPitch, requestedSpeed, inputHz, outputHz, finalHz, finalRms, expectedHz, centsError,
        routePassed,
        actualSpeed, sampleCount: measurements.length,
        passed: inputHz !== null && Math.abs(inputHz - frequency) < 4 &&
          centsError !== null && Math.abs(centsError) < 15 &&
          Math.abs(actualSpeed - requestedSpeed) < 0.15 &&
          finalRms !== null && finalRms > 0.01 &&
          routePassed &&
          snapshot.probe.sourceCount === 1 && snapshot.pitch === requestedPitch,
        snapshot,
      };
    } finally {
      video.pause();
      running = false;
    }
  }

  async function runPitchTransitionCase() {
    if (running) throw new Error('A probe case is already running.');
    running = true;
    try {
      await ready;
      if (!window.TransponoMedia) throw new Error('Inject the media bridge before running a case.');
      await window.TransponoMedia.command({action: 'pitch', value: 0});
      video.currentTime = 2;
      await video.play();
      await window.TransponoMedia.command({action: 'pitch', value: 3});
      const deadline = performance.now() + 12000;
      let before;
      do {
        await sleep(200);
        before = window.TransponoMedia.snapshot();
        if (before.pitchStatus === 'unavailable') throw new Error(before.pitchMessage);
      } while (before.pitchStatus !== 'active' && performance.now() < deadline);
      if (before.pitchStatus !== 'active') throw new Error('Initial processed signal was not observed.');

      const change = window.TransponoMedia.command({action: 'pitch', value: 5});
      const during = window.TransponoMedia.snapshot();
      await change;
      const after = window.TransponoMedia.snapshot();
      await sleep(1200);
      const settled = window.TransponoMedia.snapshot();
      const expectedHz = frequency * Math.pow(2, 5 / 12);
      const centsError = settled.probe.outputHz
        ? 1200 * Math.log2(settled.probe.outputHz / expectedHz) : null;
      return {
        passed: before.pitch === 3 && before.probe.wetGain === 1 &&
          during.pitch === 3 && during.pendingPitch === 5 &&
          during.probe.wetGain === 1 && during.probe.dryGain === 0 &&
          after.pitch === 5 && after.pitchStatus === 'active' &&
          after.probe.wetGain === 1 && after.probe.dryGain === 0 &&
          centsError !== null && Math.abs(centsError) < 15 &&
          settled.probe.wetGain === 1 && settled.probe.dryGain === 0,
        centsError, before, during, after, settled,
      };
    } finally {
      video.pause();
      running = false;
    }
  }

  window.TransponoAudioProbe = Object.freeze({
    ready, runCase, runPitchTransitionCase,
    cleanup() {
      if (running) throw new Error('Wait for the current probe case before cleanup.');
      video.pause();
      if (window.TransponoMedia) window.TransponoMedia.dispose();
      video.removeAttribute('src');
      video.load();
      URL.revokeObjectURL(url);
      video.remove();
    },
  });
})();
''';
