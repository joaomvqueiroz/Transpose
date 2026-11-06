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

  /* Last resort when neither route can run WebAssembly (e.g. Gecko on iPhone
   * without JIT): a delay-line pitch shifter made only of native Web Audio
   * nodes, so no JavaScript or WASM runs per sample. Two taps read the input
   * through delays that sweep linearly (a sawtooth), which shifts pitch by
   * the sweep slope; the taps are half a period apart and cross-faded with
   * sine windows, hiding each sawtooth reset.
   * Lower quality than Signalsmith (audible modulation on sustained notes). */
  function nativeDelayNode(context) {
    const period = 0.1; // seconds per sweep
    const smoothing = 0.03;
    const rate = context.sampleRate;
    const frames = Math.max(64, Math.round(period * rate));
    function buffer(fill) {
      const result = context.createBuffer(1, frames, rate);
      const data = result.getChannelData(0);
      for (let i = 0; i < frames; i++) data[i] = fill(i / frames);
      return result;
    }
    function shapes(phase) {
      const at = shape => buffer(p => shape((p + phase) % 1));
      return {
        rising: at(p => p),
        falling: at(p => 1 - p),
        // Equal-power (sine) windows: measured smallest level dips.
        window: at(p => Math.sin(Math.PI * p)),
      };
    }

    const input = context.createGain();
    const output = context.createGain();
    output.gain.value = 0;
    const sources = [];
    const depths = [];
    const start = context.currentTime + 0.01;
    function loop(audioBuffer, target) {
      const source = context.createBufferSource();
      source.buffer = audioBuffer;
      source.loop = true;
      source.connect(target);
      source.start(start);
      sources.push(source);
    }
    for (const phase of [0, 0.5]) {
      const shape = shapes(phase);
      const delay = context.createDelay(1);
      delay.delayTime.value = 0;
      const up = context.createGain();
      const down = context.createGain();
      up.gain.value = 0;
      down.gain.value = 0;
      loop(shape.falling, up); // shrinking delay raises pitch
      loop(shape.rising, down); // growing delay lowers pitch
      up.connect(delay.delayTime);
      down.connect(delay.delayTime);
      const tap = context.createGain();
      tap.gain.value = 0;
      loop(shape.window, tap.gain);
      input.connect(delay).connect(tap).connect(output);
      depths.push({up, down});
    }

    const node = input;
    // The graph connects `input → node → output`; route the node's own
    // connections from the shifter's output instead of its input.
    node.connect = (...args) => output.connect(...args);
    node.disconnect = (...args) => {
      try { output.disconnect(...args); } catch (_) {}
    };
    node.transponoBackend = 'native-delay';
    node.transponoDiagnostics = () => ({periodMs: period * 1000, sources: sources.length});
    node.latency = async () => period / 2;
    node.schedule = async function (state) {
      const now = context.currentTime;
      if (state.semitones !== undefined) {
        if (!Number.isFinite(state.semitones) || Math.abs(state.semitones) > 12) {
          throw new RangeError('Tom fora do intervalo permitido.');
        }
        // Delay slope s gives a pitch ratio of 1 - s; one sweep spans `period`.
        const ratio = Math.pow(2, state.semitones / 12);
        const upDepth = ratio > 1 ? (ratio - 1) * period : 0;
        const downDepth = ratio < 1 ? (1 - ratio) * period : 0;
        for (const depth of depths) {
          depth.up.gain.setTargetAtTime(upDepth, now, smoothing);
          depth.down.gain.setTargetAtTime(downDepth, now, smoothing);
        }
      }
      if (state.active !== undefined) {
        output.gain.setTargetAtTime(state.active ? 1 : 0, now, smoothing);
      }
    };
    return node;
  }

  function hasWasm() {
    try {
      return typeof WebAssembly === 'object' &&
        WebAssembly.validate(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]));
    } catch (_) {
      return false;
    }
  }

  window.TransponoCreateStretch = async function (context, options) {
    // Without WebAssembly (e.g. Gecko without JIT) both Signalsmith routes fail
    // or stall; use the native-node shifter straight away.
    if (!hasWasm()) return nativeDelayNode(context);
    if (!blockedWorklets.has(context)) {
      try {
        const node = await stretchFactory()(context, options);
        node.transponoBackend = 'audio-worklet';
        return node;
      } catch (_) {
        blockedWorklets.add(context);
      }
    }
    try {
      return await compatibilityNode(context);
    } catch (_) {
      return nativeDelayNode(context);
    }
  };
})();
