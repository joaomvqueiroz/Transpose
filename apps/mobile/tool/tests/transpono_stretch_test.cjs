'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const SignalsmithStretch = require('../../assets/web/SignalsmithStretch.js');
const adapter = fs.readFileSync(path.join(__dirname, '../../assets/web/transpono_stretch.js'), 'utf8');

// Only emulate the browser's callback delivery. All pitch processing and buffer
// allocation below use the exact vendored WASM binary shipped in the app.
async function createProcessor(sampleRate = 48000) {
  const window = {SignalsmithStretch};
  vm.runInNewContext(adapter, {window, performance, Float32Array, Event});
  const context = {
    sampleRate,
    audioWorklet: {async addModule() { throw new Error('Fixture: document CSP denies blob modules'); }},
    createScriptProcessor(frames, inputChannels, outputChannels) {
      assert.equal(frames, 2048);
      assert.equal(inputChannels, 2);
      assert.equal(outputChannels, 2);
      return new EventTarget();
    },
  };
  const node = await window.TransponoCreateStretch(context);
  assert.equal(node.transponoBackend, 'wasm-compatibility');
  return {node, sampleRate};
}

function render(processor, frequencies, frameCount, amplitude = 0.2) {
  const channels = frequencies.length;
  const rendered = [new Float32Array(frameCount), new Float32Array(frameCount)];
  for (let offset = 0; offset < frameCount; offset += 2048) {
    const input = frequencies.map(frequency => Float32Array.from({length: 2048}, (_, index) =>
      amplitude * Math.sin(2 * Math.PI * frequency * (offset + index) / processor.sampleRate)));
    const output = [new Float32Array(2048), new Float32Array(2048)];
    processor.node.onaudioprocess({
      inputBuffer: {numberOfChannels: channels, length: 2048, getChannelData: channel => input[channel]},
      outputBuffer: {numberOfChannels: 2, length: 2048, getChannelData: channel => output[channel]},
    });
    output.forEach((buffer, channel) => rendered[channel].set(buffer, offset));
  }
  return rendered;
}

function measure(samples, sampleRate) {
  // Discard startup/transition latency. Interpolated rising crossings avoid FFT
  // bin rounding and measure the produced tone without consulting adapter state.
  const tail = samples.subarray(samples.length - 32768);
  const crossings = [];
  let sumSquares = 0;
  for (let index = 0; index < tail.length; index++) {
    assert.ok(Number.isFinite(tail[index]), 'PCM must remain finite');
    sumSquares += tail[index] * tail[index];
    if (index && tail[index - 1] <= 0 && tail[index] > 0) {
      crossings.push(index - 1 + -tail[index - 1] / (tail[index] - tail[index - 1]));
    }
  }
  assert.ok(crossings.length > 10, 'DSP must produce an audible periodic output');
  return {
    frequency: (crossings.length - 1) * sampleRate / (crossings.at(-1) - crossings[0]),
    rms: Math.sqrt(sumSquares / tail.length),
  };
}

test('real bundled WASM shifts stereo 440/660 Hz by an octave without changing frame count', async () => {
  const processor = await createProcessor();
  await processor.node.schedule({active: true, semitones: 12});
  const frames = 2048 * 72;
  const output = render(processor, [440, 660], frames);
  for (const [channel, expected] of [[0, 880], [1, 1320]]) {
    const result = measure(output[channel], processor.sampleRate);
    assert.ok(Math.abs(result.frequency - expected) < 2,
      `channel ${channel}: expected ${expected} Hz, received ${result.frequency.toFixed(3)} Hz`);
    assert.ok(result.rms > 0.025, `channel ${channel} must remain audible`);
    assert.equal(output[channel].length, frames, 'pitch must not change duration');
  }
  assert.equal(processor.node.transponoDiagnostics().blocks, 72);
  assert.ok(await processor.node.latency() > 0);
});

test('real WASM handles downshift and reset at 44.1 kHz with mono duplicated to stereo', async () => {
  const processor = await createProcessor(44100);
  for (const semitones of [-12, 0]) {
    await processor.node.schedule({active: false});
    await processor.node.schedule({active: true, semitones});
    const output = render(processor, [440], 2048 * 72);
    const expected = 440 * Math.pow(2, semitones / 12);
    const result = measure(output[0], processor.sampleRate);
    assert.ok(Math.abs(result.frequency - expected) < 2,
      `expected ${expected} Hz, received ${result.frequency.toFixed(3)} Hz`);
    assert.ok(result.rms > 0.025);
    const right = measure(output[1], processor.sampleRate);
    assert.ok(Math.abs(right.frequency - expected) < 2,
      `right mono channel: expected ${expected} Hz, received ${right.frequency.toFixed(3)} Hz`);
    let maximumChannelDifference = 0;
    for (let index = output[0].length - 32768; index < output[0].length; index++) {
      maximumChannelDifference = Math.max(maximumChannelDifference,
        Math.abs(output[0][index] - output[1][index]));
    }
    assert.ok(maximumChannelDifference < 0.001,
      `mono channel difference must stay inaudible: ${maximumChannelDifference}`);
  }
  await processor.node.schedule({active: false});
  const inactive = render(processor, [440], 2048 * 2);
  assert.ok(inactive.every(channel => channel.every(sample => sample === 0)));
  await processor.node.schedule({active: true});
  const restarted = render(processor, [0], 2048 * 8);
  assert.ok(restarted.every(channel => channel.every(sample => sample === 0)),
    'restarting must clear the previous audio tail');
});

// Gecko on iPhone runs without JIT, so WebAssembly is unavailable there. The
// adapter must then build the native-node shifter instead of failing.
function fakeAudioContext() {
  const connections = [];
  const param = name => ({
    name, value: 0, targets: [],
    setTargetAtTime(value) { this.targets.push(value); this.value = value; },
  });
  const node = kind => {
    const result = {kind, connect(target) { connections.push([result, target]); return target; }, disconnect() {}};
    return result;
  };
  return {
    connections,
    sampleRate: 48000,
    currentTime: 0,
    createGain() { const gain = node('gain'); gain.gain = param('gain'); return gain; },
    createDelay() { const delay = node('delay'); delay.delayTime = param('delayTime'); return delay; },
    createBuffer(channels, length) {
      const data = new Float32Array(length);
      return {length, getChannelData: () => data};
    },
    createBufferSource() { const source = node('source'); source.start = () => {}; return source; },
  };
}

test('without WebAssembly the native delay shifter is used', async () => {
  const window = {SignalsmithStretch};
  vm.runInNewContext(adapter, {window, performance, Float32Array, Event, WebAssembly: undefined});
  const context = fakeAudioContext();
  const node = await window.TransponoCreateStretch(context);
  assert.equal(node.transponoBackend, 'native-delay');

  // Its own connections leave from the shifter output, not its input.
  const destination = {kind: 'destination'};
  assert.equal(node.connect(destination), destination);
  const [from] = context.connections.at(-1);
  assert.notEqual(from, node);

  await node.schedule({active: true, semitones: 12});
  const depths = context.connections
    .filter(([, target]) => target.name === 'delayTime')
    .map(([gain]) => gain.gain.value);
  // Up taps sweep the full 0.1 s period for an octave; down taps stay at 0.
  assert.deepEqual(depths.map(value => Math.round(value * 1000) / 1000).sort(), [0, 0, 0.1, 0.1]);
  await node.schedule({semitones: -12});
  const lowered = context.connections
    .filter(([, target]) => target.name === 'delayTime')
    .map(([gain]) => Math.round(gain.gain.value * 1000) / 1000).sort();
  assert.deepEqual(lowered, [0, 0, 0.05, 0.05]);
  await assert.rejects(node.schedule({semitones: 13}), {name: 'RangeError'});
});
