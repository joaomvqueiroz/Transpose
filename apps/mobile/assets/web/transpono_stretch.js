/* Live-input adapter for the vendored Signalsmith Stretch 1.3.2 (MIT).
 * Prefer AudioWorklet. A document may allow WASM but reject blob module scripts;
 * in that case use the same DSP through ScriptProcessorNode. No CSP changes,
 * remote script, media fetch, or stream extraction. This compatibility route
 * runs on the UI thread and has a larger buffer/latency than AudioWorklet.
 */
(function () {
  'use strict';
  // Gecko content-script sandboxes keep `var` globals off the Xray `window`.
  const stretchFactory = () => globalThis.SignalsmithStretch || window.SignalsmithStretch;
  const blockedWorklets = new WeakSet();

  async function compatibilityNode(context) {
    const factory = stretchFactory()?.wasmModuleFactory;
    if (typeof factory !== 'function' || !context.createScriptProcessor) {
      throw new Error('O processamento de tom não está disponível neste navegador.');
    }
    const wasm = await factory();
    const channels = 2;
    const block = 2048;
    // Default quality, and both channels share one DSP instance for coherence.
    wasm._presetDefault(channels, context.sampleRate);
    const length = Math.max(block, wasm._inputLatency() + wasm._outputLatency());
    const pointer = wasm._setBuffers(channels, length);
    const node = context.createScriptProcessor(block, channels, channels);
    let active = false;
    let pitch = 0;
    let failed = false;
    let blocks = 0;
    let maxCallbackMs = 0;
    node.transponoBackend = 'wasm-compatibility';
    node.transponoDiagnostics = () => ({blocks, maxCallbackMs, blockFrames: block});
    node.latency = async () => (wasm._inputLatency() + wasm._outputLatency() + block) / context.sampleRate;
    node.schedule = async function (state) {
      if (failed) throw new Error('O processador de áudio parou.');
      if (state.semitones !== undefined) {
        if (!Number.isFinite(state.semitones) || Math.abs(state.semitones) > 12) {
          throw new RangeError('Tom fora do intervalo permitido.');
        }
        pitch = state.semitones;
        wasm._setTransposeSemitones(pitch, 8000 / context.sampleRate);
      }
      if (state.active !== undefined) {
        if (state.active && !active) wasm._reset();
        active = state.active;
      }
    };
    node.onaudioprocess = function (event) {
      if (!active || failed) {
        for (let c = 0; c < channels; c++) event.outputBuffer.getChannelData(c).fill(0);
        return;
      }
      const started = performance.now();
      try {
        const frames = event.outputBuffer.length;
        if (frames > length) throw new Error('Buffer de áudio incompatível.');
        const memory = wasm.HEAP8.buffer;
        for (let c = 0; c < channels; c++) {
          const input = new Float32Array(memory, pointer + c * length * 4, frames);
          const source = event.inputBuffer.numberOfChannels
            ? event.inputBuffer.getChannelData(c % event.inputBuffer.numberOfChannels)
            : null;
          if (source) input.set(source); else input.fill(0);
        }
        wasm._process(frames, frames);
        for (let c = 0; c < channels; c++) {
          event.outputBuffer.getChannelData(c).set(
            new Float32Array(wasm.HEAP8.buffer, pointer + (c + channels) * length * 4, frames),
          );
        }
        blocks++;
        maxCallbackMs = Math.max(maxCallbackMs, performance.now() - started);
      } catch (_) {
        failed = true;
        active = false;
        for (let c = 0; c < channels; c++) event.outputBuffer.getChannelData(c).fill(0);
        node.dispatchEvent(new Event('processorerror'));
      }
    };
    return node;
  }

  window.TransponoCreateStretch = async function (context, options) {
    if (!blockedWorklets.has(context)) {
      try {
        const node = await stretchFactory()(context, options);
        node.transponoBackend = 'audio-worklet';
        return node;
      } catch (_) {
        blockedWorklets.add(context);
      }
    }
    return compatibilityNode(context);
  };
})();
