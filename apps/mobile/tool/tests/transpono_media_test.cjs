'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const script = fs.readFileSync(path.join(__dirname, '../../assets/web/transpono_media.js'), 'utf8');

test('the Dart-contained integration fixture remains valid injectable JavaScript', () => {
  const fixture = fs.readFileSync(path.join(__dirname, '../../integration_test/fixtures/audio_probe_source.dart'), 'utf8');
  const source = fixture.match(/const audioProbeSource = r'''\r?\n([\s\S]*)\r?\n''';/);
  assert.ok(source);
  assert.doesNotThrow(() => new vm.Script(source[1]));
  const practice = fs.readFileSync(path.join(__dirname,
    '../../integration_test/practice_progression_probe_test.dart'), 'utf8');
  const practiceSource = practice.match(/const _webLoopProbe = r'''\r?\n([\s\S]*)\r?\n''';/);
  assert.ok(practiceSource);
  assert.doesNotThrow(() => new vm.Script(practiceSource[1]));
});

function fixture(options = {}) {
  let clock = 0;
  let tick;
  let ad = false;
  const mediaEvents = new Map();
  const element = {
    currentSrc: 'blob:https://m.youtube.com/fixture', src: '', mediaKeys: null,
    currentTime: 10, duration: 100, playbackRate: 1, preservesPitch: true,
    paused: false, ended: false, seeking: false, readyState: 4,
    isConnected: true, muted: false, volume: 1,
    addEventListener(name, handler) {
      if (!mediaEvents.has(name)) mediaEvents.set(name, new Set());
      mediaEvents.get(name).add(handler);
    },
    removeEventListener(name, handler) { mediaEvents.get(name)?.delete(handler); },
    dispatch(name) { for (const handler of mediaEvents.get(name) || []) handler(); },
    pause() { this.paused = true; this.dispatch('pause'); },
    async play() {
      this.paused = false;
      this.ended = false;
      this.dispatch('play');
      if (this.readyState >= 3 && !this.seeking) this.dispatch('playing');
    },
  };
  let selected = element;
  const state = {sources: [], contexts: [], worklets: [], nodes: [], scheduleFails: false,
    outputSignal: 0.1, inputSignal: 0.1, deferFactory: null};
  class Node {
    constructor(kind) { this.kind = kind; this.connections = []; state.nodes.push(this); }
    connect(target) { this.connections.push(target); return target; }
    disconnect(target) { this.connections = target ? this.connections.filter(node => node !== target) : []; }
  }
  function parameter(value = 0) {
    return {
      value,
      cancelScheduledValues() {},
      setValueAtTime(value) { this.value = value; },
      setTargetAtTime(value) { this.value = value; },
    };
  }
  class Context {
    constructor() {
      this.currentTime = 1;
      this.state = 'running';
      this.sampleRate = 48000;
      this.destination = new Node('destination');
      this.analyzers = 0;
      state.contexts.push(this);
    }
    async resume() { this.state = 'running'; }
    createOscillator() {
      const node = new Node('oscillator');
      node.frequency = parameter();
      node.start = () => { node.started = true; };
      node.stop = () => { node.started = false; };
      return node;
    }
    createConvolver() { return new Node('convolver'); }
    createBuffer(channels, length, sampleRate) {
      const data = Array.from({length: channels}, () => new Float32Array(length));
      return {numberOfChannels: channels, length, sampleRate,
        getChannelData(channel) { return data[channel]; }};
    }
    createGain() {
      const node = new Node('gain');
      node.gain = parameter(1);
      return node;
    }
    createBiquadFilter() {
      const node = new Node('filter');
      node.frequency = parameter();
      node.Q = parameter();
      node.gain = parameter();
      return node;
    }
    createDelay() {
      const node = new Node('delay');
      node.delayTime = parameter();
      return node;
    }
    createAnalyser() {
      const node = new Node(this.analyzers++ % 2 === 0 ? 'input' : 'output');
      Object.defineProperty(node, 'frequencyBinCount', {get() { return this.fftSize / 2; }});
      node.getFloatTimeDomainData = samples => samples.fill(
        node.kind === 'input' ? state.inputSignal : state.outputSignal);
      node.getFloatFrequencyData = samples => {
        const hz = node.kind === 'input' ? 440 : 440 * 2 ** (3 / 12);
        const bin = hz * node.fftSize / this.sampleRate;
        for (let i = 0; i < samples.length; i += 1) {
          samples[i] = Math.max(-120, -20 - (4 * (i - bin)) ** 2);
        }
      };
      return node;
    }
    createMediaElementSource(video) {
      if (state.sources.some(source => source.video === video)) throw new Error('Duplicate source');
      const node = new Node('source');
      node.video = video;
      state.sources.push(node);
      return node;
    }
  }
  const window = {
    location: new URL(options.url || 'https://m.youtube.com/watch?v=one'),
    __transponoAudioProbe: !!options.probe,
    AudioContext: Context,
    async SignalsmithStretch(context, config) {
      if (!state.sources.length)
        assert.equal(state.sources.length, state.worklets.length, 'Worklet is prepared before attaching source');
      assert.equal(config.numberOfInputs, 1);
      if (options.factoryFails) throw new Error('CSP blocked');
      if (state.deferFactory) await state.deferFactory;
      const node = new Node('worklet');
      node.schedules = [];
      node.events = {};
      node.schedule = async value => {
        if (state.scheduleFails) throw new Error('schedule failed');
        node.schedules.push(value);
        return value;
      };
      node.addEventListener = (name, handler) => { node.events[name] = handler; };
      state.worklets.push(node);
      return node;
    },
    TransponoBridge: {messages: [], postMessage(value) { this.messages.push(JSON.parse(value)); }},
  };
  window.top = options.frame ? {} : window;
  const document = {
    title: options.documentTitle ?? 'A song - YouTube',
    querySelector(selector) {
      if (selector === 'video.html5-main-video') return options.mainVideo === false ? null : selected;
      if (selector === 'video') return options.genericVideo || selected;
      if (selector === '.ad-showing, .ad-interrupting') return ad ? {} : null;
      if (selector.startsWith('h1.ytd-watch-metadata'))
        return options.heading ? {textContent: options.heading} : null;
      if (selector === 'meta[property="og:title"]')
        return options.ogTitle ? {getAttribute: () => options.ogTitle} : null;
      if (selector === 'meta[name="title"]')
        return options.metaTitle ? {getAttribute: () => options.metaTitle} : null;
      return null;
    },
  };
  const sandbox = {window, document, URL, performance: {now: () => clock},
    setInterval(fn) { tick = fn; return 1; }, clearInterval() { tick = null; },
    setTimeout, clearTimeout, Float32Array};
  vm.createContext(sandbox);
  vm.runInContext(script, sandbox);
  return {
    ...state, state, window, document, video: element,
    get api() { return window.TransponoMedia; },
    advance(ms = 300) { clock += ms; if (tick) tick(); },
    beginSeek(target = element.currentTime) {
      element.currentTime = target;
      element.seeking = true;
      element.dispatch('seeking');
    },
    finishSeek(target = element.currentTime) {
      element.currentTime = target;
      element.seeking = false;
      element.dispatch('seeked');
    },
    confirmSeek() { this.beginSeek(); this.finishSeek(); },
    setAd(value) { ad = value; this.advance(); },
    navigate(id, replacement) {
      window.location = new URL(id ? 'https://m.youtube.com/watch?v=' + id : 'https://m.youtube.com/results?search_query=music');
      if (replacement !== undefined) selected = replacement;
      this.advance();
    },
    reinject() { vm.runInContext(script, sandbox); },
    gains() { return state.nodes.filter(node => node.kind === 'gain').slice(0, 2).map(node => node.gain.value); },
  };
}

test('video title prefers watch metadata and never publishes generic YouTube', () => {
  const heading = fixture({heading: 'Santo Pra Sempre', documentTitle: 'YouTube'});
  assert.equal(heading.api.snapshot().title, 'Santo Pra Sempre');
  const metadata = fixture({ogTitle: 'Outra música - YouTube', documentTitle: 'YouTube'});
  assert.equal(metadata.api.snapshot().title, 'Outra música');
  const loading = fixture({documentTitle: 'YouTube'});
  assert.equal(loading.api.snapshot().title, '');
  const fallback = fixture({documentTitle: 'Canção real - YouTube'});
  assert.equal(fallback.api.snapshot().title, 'Canção real');
});

test('timeline snapshots expose monotonic time and explicit seek/rate epochs', () => {
  const f = fixture();
  const first = f.api.snapshot();
  assert.equal(first.sampleTimeMs, 0);
  assert.equal(first.position, 10);
  assert.equal(first.seeking, false);
  f.advance(120);
  assert.equal(f.api.snapshot().sampleTimeMs, 120);
  f.beginSeek(25);
  const seeking = f.api.snapshot();
  assert.equal(seeking.seeking, true);
  assert.equal(seeking.playbackReady, false);
  assert.ok(seeking.timelineSeekEpoch > first.timelineSeekEpoch);
  f.finishSeek();
  assert.equal(f.api.snapshot().seeking, false);
  f.video.playbackRate = 1.5;
  f.video.dispatch('ratechange');
  const faster = f.api.snapshot();
  assert.equal(faster.speed, 1.5);
  assert.ok(faster.timelineRateEpoch > first.timelineRateEpoch);
  f.video.pause();
  assert.equal(f.api.snapshot().playing, false);
  f.setAd(true);
  assert.equal(f.api.snapshot().isAd, true);
  assert.equal(f.api.snapshot().playbackReady, false);
});

// Count active routes, including the final destination rather than only the
// signal analyser upstream of the wet gain. Ignore feedback cycles per path.
function outputRoutes(node, destination, visited = new Set()) {
  if (node === destination) return 1;
  if (!node || visited.has(node) || (node.kind === 'gain' && node.gain.value === 0)) return 0;
  const nextVisited = new Set(visited).add(node);
  return (node.connections || []).reduce((count, next) =>
    count + outputRoutes(next, destination, nextVisited), 0);
}

for (const [action, value] of [
  ['bass', 6], ['mid', -3], ['treble', 4], ['gain', -6],
  ['chorus', .2], ['feedback', .2], ['delay', .2], ['reverb', .2],
]) {
  test(`${action} before pitch keeps the processed route connected through repeated bypass`, async () => {
    const f = fixture();
    await f.api.command({action, value});
    const destination = f.contexts[0].destination;
    const initialRoutes = outputRoutes(f.sources[0], destination);
    assert.ok(initialRoutes > 0);
    for (const pitch of [3, 0, -4, 6, 0, 2]) {
      await f.api.command({action: 'pitch', value: pitch});
      f.advance();
      assert.equal(f.api.snapshot().pitch, pitch);
      assert.deepEqual(f.gains(), pitch === 0 ? [1, 0] : [0, 1]);
      assert.equal(outputRoutes(f.sources[0], destination), initialRoutes,
        'Changing pitch preserves all effect routes without adding a second source route');
      assert.equal(outputRoutes(f.worklets[0], destination), pitch === 0 ? 0 : initialRoutes);
      assert.equal(f.sources.length, 1);
      assert.equal(f.worklets.length, 1);
    }
  });
}

test('pitch before EQ retains one dry/wet route, and processor failure restores original audio', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 3});
  f.advance();
  for (const action of ['bass', 'mid', 'treble', 'gain']) {
    await f.api.command({action, value: -3});
    assert.equal(outputRoutes(f.sources[0], f.contexts[0].destination), 1);
    assert.equal(outputRoutes(f.worklets[0], f.contexts[0].destination), 1);
  }
  f.worklets[0].events.processorerror();
  assert.deepEqual(f.gains(), [1, 0]);
  assert.equal(outputRoutes(f.sources[0], f.contexts[0].destination), 1);
  assert.equal(outputRoutes(f.worklets[0], f.contexts[0].destination), 0);
});

test('all audio effects are reapplied to a replacement element for the same song', async () => {
  const f = fixture();
  const settings = {bass: 6, mid: -3, treble: 4, gain: -6,
    chorus: .2, feedback: .2, delay: .15, reverb: .1};
  for (const [action, value] of Object.entries(settings)) await f.api.command({action, value});
  const replacement = {...f.video, currentSrc: 'blob:https://m.youtube.com/replacement'};
  f.video.isConnected = false;
  f.navigate('one', replacement);
  assert.equal(f.api.snapshot().audioEffects.bass, 0, 'No applied value before the new graph exists');
  await new Promise(setImmediate);
  for (const [action, value] of Object.entries(settings)) {
    assert.ok(Math.abs(f.api.snapshot().audioEffects[action] - value) < 1e-5, action);
  }
  assert.equal(f.sources.length, 2);
  assert.equal(outputRoutes(f.sources[0], f.contexts[0].destination), 0);
  assert.ok(outputRoutes(f.sources[1], f.contexts[0].destination) > 0);
  f.navigate('another', replacement);
  for (const value of Object.values(f.api.snapshot().audioEffects)) assert.equal(value, 0);
});

test('ads bypass effects and restore them on a replacement without native autoplay', async () => {
  const f = fixture();
  await f.api.command({action: 'bass', value: 5});
  f.setAd(true);
  assert.equal(f.api.snapshot().audioEffects.bass, 0);
  const replacement = {...f.video, paused: true, currentSrc: 'blob:https://m.youtube.com/after-ad'};
  f.video.isConnected = false;
  f.navigate('one', replacement);
  await new Promise(setImmediate);
  assert.equal(f.sources.length, 1, 'No graph is created for the ad');
  f.setAd(false);
  await new Promise(setImmediate);
  assert.equal(f.api.snapshot().audioEffects.bass, 5);
  assert.equal(replacement.paused, true);
});

test('unsupported replacement reports neutral applied effects and retries on a valid source', async () => {
  const f = fixture();
  await f.api.command({action: 'mid', value: 4});
  const replacement = {...f.video, currentSrc: 'https://example.org/protected.mp4'};
  f.video.isConnected = false;
  f.navigate('one', replacement);
  await new Promise(setImmediate);
  assert.equal(f.api.snapshot().audioEffects.mid, 0);
  assert.equal(f.sources.length, 1);
  replacement.currentSrc = 'blob:https://m.youtube.com/compatible';
  f.advance();
  await new Promise(setImmediate);
  assert.equal(f.api.snapshot().audioEffects.mid, 4);
});

test('pending effect commands cannot change another song on the same element', async () => {
  const f = fixture();
  await f.api.command({action: 'bass', value: 2});
  const pending = f.api.command({action: 'bass', value: 8});
  const rejected = assert.rejects(pending, /vídeo mudou/);
  f.navigate('another');
  await rejected;
  assert.equal(f.api.snapshot().audioEffects.bass, 0);
});

test('newer adjustments and cancellation invalidate pending effect requests', async () => {
  const f = fixture();
  await f.api.command({action: 'bass', value: 2});
  const older = f.api.command({action: 'bass', value: 5});
  const rejected = assert.rejects(older, /substituído/);
  const newer = f.api.command({action: 'bass', value: 8});
  await Promise.all([rejected, newer]);
  assert.equal(f.api.snapshot().audioEffects.bass, 8);
  f.api.dispatch('cancel-bass', {action: 'bass', value: -4});
  assert.equal(f.api.cancelCommand('cancel-bass'), true);
  await new Promise(setImmediate);
  assert.equal(f.api.snapshot().audioEffects.bass, 8);
  assert.equal(f.api.commandResult('cancel-bass').status, 'error');
});

test('a failed restoration stays native and an explicit adjustment can retry', async () => {
  const f = fixture();
  await f.api.command({action: 'bass', value: 3});
  const context = f.contexts[0];
  const resume = context.resume;
  let attempts = 0;
  context.resume = async () => { attempts++; throw new Error('context unavailable'); };
  const replacement = {...f.video, currentSrc: 'blob:https://m.youtube.com/new'};
  f.video.isConnected = false;
  f.navigate('one', replacement);
  await new Promise(setImmediate);
  f.advance(); f.advance();
  assert.equal(attempts, 1, 'Failed restoration does not loop on every snapshot');
  assert.equal(f.api.snapshot().audioEffects.bass, 0);
  context.resume = resume;
  await f.api.command({action: 'bass', value: 4});
  assert.equal(f.api.snapshot().audioEffects.bass, 4);
});

test('host and top-level boundary excludes lookalike domains and subframes', () => {
  assert.equal(fixture({url: 'https://youtube.com.attacker.test/watch?v=one'}).api, undefined);
  assert.equal(fixture({url: 'http://youtube.com/watch?v=one'}).api, undefined);
  assert.equal(fixture({frame: true}).api, undefined);
});

async function preparedLoop(f) {
  f.video.currentTime = 10;
  await f.api.command({action: 'markA'});
  f.video.currentTime = 20;
  await f.api.command({action: 'markB'});
  f.advance();
  f.confirmSeek();
  assert.equal(f.video.currentTime, 10);
  assert.equal(f.api.snapshot().loopCount, 0, 'Initial partial pass is not a repetition');
}

test('loop completion waits for seeked and counts only a full armed pass once', async () => {
  const f = fixture();
  await preparedLoop(f);
  const epoch = f.api.snapshot().loopEpoch;
  f.video.currentTime = 20;
  f.advance();
  assert.equal(f.video.currentTime, 10);
  assert.equal(f.api.snapshot().loopCount, 0, 'A currentTime write is not a completed loop');
  f.beginSeek();
  assert.equal(f.api.snapshot().playbackReady, false);
  assert.equal(f.api.snapshot().loopCount, 0);
  f.finishSeek();
  assert.equal(f.api.snapshot().loopCount, 1);
  assert.equal(f.api.snapshot().loopEpoch, epoch, 'An internal loop is not an external seek');
  assert.equal(f.api.snapshot().playbackReady, true);
  f.finishSeek();
  assert.equal(f.api.snapshot().loopCount, 1, 'Duplicate seeked cannot count again');
  f.video.currentTime = 20;
  f.advance();
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 2);
});

test('external seeks change epoch and a middle-of-loop partial pass never counts', async () => {
  const f = fixture();
  await preparedLoop(f);
  const epoch = f.api.snapshot().loopEpoch;
  await f.api.command({action: 'seekTo', value: 15});
  f.confirmSeek();
  assert.ok(f.api.snapshot().loopEpoch > epoch);
  f.video.currentTime = 20;
  f.advance();
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 0);
  f.video.currentTime = 20;
  f.advance();
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 1);
  f.beginSeek(16); // A seek from the website's own controls is also observed.
  f.finishSeek();
  f.video.currentTime = 20;
  f.advance();
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 1);
  f.beginSeek(50);
  f.finishSeek();
  assert.equal(f.api.snapshot().loopEnabled, false);
});

test('seeking exactly to A starts a new full pass without counting the seek', async () => {
  const f = fixture();
  await preparedLoop(f);
  await f.api.command({action: 'seekTo', value: 10});
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 0);
  f.video.currentTime = 20;
  f.advance();
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 1);
});

test('play after paused seek to A arms before a late first polling tick', async () => {
  for (const speed of [.6, 1.5]) {
    const f = fixture();
    await preparedLoop(f);
    await f.api.command({action: 'pause'});
    await f.api.command({action: 'seekTo', value: 10});
    f.confirmSeek();
    await f.api.command({action: 'speed', value: speed});
    await f.api.command({action: 'playPause'});
    // Simulate a real playing clock before its first 200 ms observation.
    f.video.currentTime = 10 + .2 * speed;
    f.advance(200);
    f.video.currentTime = 20;
    f.advance();
    f.confirmSeek();
    assert.equal(f.api.snapshot().loopCount, 1, 'First complete pass at speed ' + speed);
  }
});

test('playing readiness after buffering arms at A but never in the middle', async () => {
  for (const start of [10, 15]) {
    const f = fixture();
    await preparedLoop(f);
    await f.api.command({action: 'pause'});
    await f.api.command({action: 'seekTo', value: start});
    f.confirmSeek();
    f.video.readyState = 2;
    await f.api.command({action: 'playPause'});
    f.video.readyState = 3;
    f.video.dispatch('playing');
    f.video.currentTime = start + .3;
    f.advance(200);
    f.video.currentTime = 20;
    f.advance();
    f.confirmSeek();
    assert.equal(f.api.snapshot().loopCount, start === 10 ? 1 : 0);
  }
});

test('buffered return is conservatively excluded without changing the loop epoch', async () => {
  for (const longBuffer of [false, true]) {
    const f = fixture();
    await preparedLoop(f);
    const epoch = f.api.snapshot().loopEpoch;
    f.video.currentTime = 20;
    f.advance();
    f.beginSeek();
    f.video.readyState = 2;
    if (longBuffer) f.advance(5100);
    f.finishSeek();
    assert.equal(f.api.snapshot().loopCount, 0);
    assert.equal(f.api.snapshot().loopEpoch, epoch);
    f.video.readyState = 3;
    f.video.dispatch('playing');
    f.video.currentTime = 10.3;
    f.advance(200);
    f.video.currentTime = 20;
    f.advance();
    f.confirmSeek();
    assert.equal(f.api.snapshot().loopCount, 1);
    assert.equal(f.api.snapshot().loopEpoch, epoch);
  }
});

test('paused, buffering, missing seeking confirmation and wrong-target returns never count', async () => {
  for (const change of ['pause', 'buffer', 'missing-seeking', 'wrong-target']) {
    const f = fixture();
    await preparedLoop(f);
    f.video.currentTime = 20;
    f.advance();
    if (change !== 'missing-seeking') f.beginSeek();
    if (change === 'pause') await f.api.command({action: 'pause'});
    if (change === 'buffer') f.video.readyState = 2;
    f.finishSeek(change === 'wrong-target' ? 13 : 10);
    assert.equal(f.api.snapshot().loopCount, 0, change);
    if (change === 'buffer') assert.equal(f.api.snapshot().playbackReady, false);
  }
});

test('normal pause preserves an in-progress pass but buffering cannot trigger a return', async () => {
  const f = fixture();
  await preparedLoop(f);
  f.video.currentTime = 15;
  await f.api.command({action: 'pause'});
  f.advance();
  await f.api.command({action: 'playPause'});
  f.video.currentTime = 20;
  f.video.readyState = 2;
  f.advance();
  assert.equal(f.video.currentTime, 20);
  assert.equal(f.api.snapshot().loopCount, 0);
  f.video.readyState = 3;
  f.advance();
  f.confirmSeek();
  assert.equal(f.api.snapshot().loopCount, 1);
});

test('ad, source changes, marker changes and loop disable cancel pending returns', async () => {
  for (const change of ['ad', 'source', 'marker', 'disable', 'navigation']) {
    const f = fixture();
    await preparedLoop(f);
    const epoch = f.api.snapshot().loopEpoch;
    f.video.currentTime = 20;
    f.advance();
    f.beginSeek();
    if (change === 'ad') f.setAd(true);
    if (change === 'source') {
      f.video.currentSrc = 'blob:https://m.youtube.com/replaced';
      f.api.snapshot();
    }
    if (change === 'marker') await f.api.command({action: 'markA'});
    if (change === 'disable') await f.api.command({action: 'toggleLoop'});
    if (change === 'navigation') f.navigate('two');
    f.finishSeek();
    assert.equal(f.api.snapshot().loopCount, 0, change);
    assert.ok(f.api.snapshot().loopEpoch > epoch, change);
    if (change === 'ad') assert.equal(f.api.snapshot().playbackReady, false);
  }
});

test('loop counter stays monotonic across epoch changes and unsupported states fail closed', async () => {
  const f = fixture();
  await preparedLoop(f);
  assert.equal(f.api.snapshot().loopEventsSupported, true);
  f.video.currentTime = 20;
  f.advance();
  f.confirmSeek();
  const epoch = f.api.snapshot().loopEpoch;
  await f.api.command({action: 'clearLoop'});
  assert.equal(f.api.snapshot().loopCount, 1);
  assert.ok(f.api.snapshot().loopEpoch > epoch);
  await f.api.command({action: 'markA'});
  f.video.currentTime = 100;
  await f.api.command({action: 'markB'});
  assert.equal(f.api.snapshot().loopEventsSupported, false, 'EOF looping is not confirmed reliably');
  f.video.duration = Infinity;
  assert.equal(f.api.snapshot().loopEventsSupported, false);
  f.navigate(null);
  assert.equal(f.api.snapshot().loopEventsSupported, false);
  assert.equal(f.api.snapshot().playbackReady, false);
  const unsupported = fixture({mainVideo: false, genericVideo: {
    currentTime: 10, duration: 100, paused: false, readyState: 4,
  }});
  assert.equal(unsupported.api.snapshot().loopEventsSupported, false);
});

test('stale return timeouts and disposal cannot become phantom repetitions', async () => {
  const f = fixture();
  await preparedLoop(f);
  f.video.currentTime = 20;
  f.advance();
  f.beginSeek();
  f.advance(5100);
  f.finishSeek();
  assert.equal(f.api.snapshot().loopCount, 0);
  f.video.currentTime = 20;
  f.advance();
  f.beginSeek();
  f.api.dispose();
  f.finishSeek();
  assert.equal(f.api.snapshot().loopCount, 0);
  assert.equal(f.api.snapshot().loopEventsSupported, false);
  assert.equal(f.api.snapshot().playbackReady, false);
});

test('spectral diagnostics are opt-in and interpolate known synthetic FFT peaks', async () => {
  const normal = fixture();
  assert.equal(Object.hasOwn(normal.api.snapshot(), 'probe'), false);
  await normal.api.command({action: 'bass', value: 3});
  assert.equal(normal.contexts[0].analyzers, 3, 'No extra analyser in production');
  const f = fixture({probe: true});
  await f.api.command({action: 'pitch', value: 3});
  f.advance();
  const diagnostic = f.api.snapshot().probe;
  assert.ok(Math.abs(diagnostic.inputHz - 440) < 0.01);
  assert.ok(Math.abs(diagnostic.outputHz - 440 * 2 ** (3 / 12)) < 0.01);
  assert.ok(Math.abs(diagnostic.finalHz - diagnostic.outputHz) < 0.01);
  assert.ok(Math.abs(diagnostic.finalRms - 0.1) < 0.0001);
  assert.equal(diagnostic.sampleRate, 48000);
  assert.equal(diagnostic.sourceCount, 1);
  assert.equal(diagnostic.dryGain, 0);
  assert.equal(diagnostic.wetGain, 1);
  assert.equal(diagnostic.dspConnected, true);
  assert.ok(Math.abs(diagnostic.inputRms - 0.1) < 0.0001);
});

test('final-output probe has one destination route across bypass and retire/revive', async () => {
  const f = fixture({probe: true});
  await f.api.command({action: 'bass', value: 3});
  const destination = f.contexts[0].destination;
  const finalAnalyser = f.nodes.find(node => node.connections.includes(destination));
  assert.ok(finalAnalyser);
  assert.equal(f.contexts[0].analyzers, 4);
  for (const pitch of [4, 0, -5, 0]) {
    await f.api.command({action: 'pitch', value: pitch});
    f.advance();
    assert.equal(f.api.snapshot().probe.dspConnected, pitch !== 0);
    assert.equal(outputRoutes(f.sources[0], destination), 1);
  }
  f.video.isConnected = false;
  f.navigate('one', null);
  assert.equal(finalAnalyser.connections.length, 0);
  f.video.isConnected = true;
  f.navigate('one', f.video);
  await f.api.command({action: 'bass', value: 3});
  assert.equal(outputRoutes(f.sources[0], destination), 1);
  assert.equal(f.sources.length, 1);
});

test('pitch starts dry, becomes active only with output, and uses one source across updates', async () => {
  const f = fixture();
  const pending = await f.api.command({action: 'pitch', value: 3});
  assert.equal(pending.pitchStatus, 'loading');
  assert.equal(pending.pitch, 0);
  assert.equal(pending.pendingPitch, 3);
  assert.deepEqual(f.gains(), [1, 0]);
  f.state.outputSignal = 0;
  f.advance();
  assert.equal(f.api.snapshot().pitchStatus, 'loading');
  f.state.outputSignal = 0.1;
  f.advance();
  assert.equal(f.api.snapshot().pitchStatus, 'active');
  assert.deepEqual(f.gains(), [0, 1]);
  await f.api.command({action: 'speed', value: 0.75});
  assert.equal(f.api.snapshot().pitch, 3);
  assert.equal(f.video.playbackRate, 0.75);
  assert.equal(f.video.preservesPitch, true);
  await f.api.command({action: 'pitch', value: -2});
  f.advance();
  assert.equal(f.sources.length, 1);
  assert.equal(f.worklets.length, 1);
  assert.equal(f.worklets[0].schedules.at(-1).semitones, -2);
  f.reinject();
  await f.api.command({action: 'pitch', value: 0});
  assert.deepEqual(f.gains(), [1, 0]);
  assert.equal(f.api.snapshot().pitchStatus, 'idle');
});

test('rapid pitch requests during preparation keep only the latest intent and independent speed', async () => {
  for (const lastPitch of [-5, 0]) {
    const f = fixture();
    let finishFactory;
    f.state.deferFactory = new Promise(resolve => { finishFactory = resolve; });
    const first = f.api.command({action: 'pitch', value: 3});
    await new Promise(resolve => setImmediate(resolve));
    const second = f.api.command({action: 'pitch', value: 7});
    await f.api.command({action: 'speed', value: 0.75});
    const last = f.api.command({action: 'pitch', value: lastPitch});
    finishFactory();
    await Promise.all([first, second, last]);
    f.advance();
    assert.equal(f.api.snapshot().pitch, lastPitch);
    assert.equal(f.api.snapshot().pitchStatus, lastPitch === 0 ? 'idle' : 'active');
    assert.equal(f.video.playbackRate, 0.75);
    assert.equal(f.video.preservesPitch, true);
    assert.equal(f.video.paused, false);
    assert.equal(f.sources.length, lastPitch === 0 ? 0 : 1);
    if (lastPitch !== 0) {
      assert.equal(f.worklets[0].schedules.at(-1).semitones, lastPitch);
      assert.equal(outputRoutes(f.sources[0], f.contexts[0].destination), 1);
    }
  }
});

test('direct, cross-origin blob and protected media never acquire an audio source', async () => {
  for (const change of [
    {currentSrc: 'https://rr.youtube.com/stream.m3u8'},
    {currentSrc: 'blob:https://other.test/stream'},
    {mediaKeys: {}},
  ]) {
    const f = fixture();
    Object.assign(f.video, change);
    const result = await f.api.command({action: 'pitch', value: 4});
    assert.equal(result.pitchStatus, 'unavailable');
    assert.equal(result.pitch, 0);
    assert.equal(f.sources.length, 0);
  }
});

test('worklet preparation failure leaves native playback untouched', async () => {
  const f = fixture({factoryFails: true});
  const result = await f.api.command({action: 'pitch', value: 2});
  assert.equal(result.pitchStatus, 'unavailable');
  assert.equal(f.sources.length, 0);
  assert.equal(f.video.paused, false);
});

test('muted and zero-volume media request sound without acquiring an audio source', async () => {
  for (const setting of [{muted: true}, {volume: 0}]) {
    const f = fixture();
    Object.assign(f.video, setting);
    const result = await f.api.command({action: 'pitch', value: 2});
    assert.equal(result.pitchStatus, 'idle');
    assert.equal(result.pitch, 0);
    assert.equal(result.pitchMessage, 'Ative o som do vídeo e tente alterar o tom novamente.');
    assert.equal(f.sources.length, 0);
    assert.equal(f.contexts.length, 0);
    Object.assign(f.video, {muted: false, volume: 1});
    await f.api.command({action: 'pitch', value: 2});
    f.advance();
    assert.equal(f.api.snapshot().pitchStatus, 'active');
  }
});

test('explicit unmute exposes mute state and starts playback without acquiring DSP', async () => {
  for (const setting of [{muted: true, volume: 0.4}, {muted: false, volume: 0}]) {
    const f = fixture();
    Object.assign(f.video, {paused: true}, setting);
    assert.equal(f.api.snapshot().muted, true);
    await f.api.command({action: 'unmute'});
    assert.equal(f.api.snapshot().muted, false);
    assert.equal(f.video.volume, setting.volume === 0 ? 1 : setting.volume);
    assert.equal(f.video.paused, false);
    assert.equal(f.sources.length, 0);
  }
});

test('main YouTube video is selected before generic preview with fallback for fixtures', () => {
  const f = fixture({genericVideo: {currentTime: 90, duration: 100, paused: true, muted: true}});
  assert.equal(f.api.snapshot().position, 10);
  assert.equal(f.api.snapshot().muted, false);
  const fallback = fixture({mainVideo: false});
  assert.equal(fallback.api.snapshot().hasVideo, true);
  assert.equal(fallback.api.snapshot().position, 10);
});

test('muting during preparation never attaches a source and stays retryable', async () => {
  const f = fixture();
  let resolve;
  f.state.deferFactory = new Promise(done => { resolve = done; });
  const pending = f.api.command({action: 'pitch', value: 3});
  await new Promise(done => setImmediate(done));
  f.video.muted = true;
  resolve();
  await pending;
  assert.equal(f.sources.length, 0);
  assert.equal(f.api.snapshot().pitchStatus, 'idle');
  assert.match(f.api.snapshot().pitchMessage, /Ative o som/);
});

test('schedule errors and processor errors restore only the original audio route', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 2});
  f.advance();
  f.state.scheduleFails = true;
  await f.api.command({action: 'pitch', value: 3});
  assert.deepEqual(f.gains(), [1, 0]);
  assert.equal(f.api.snapshot().pitchStatus, 'unavailable');
  f.state.scheduleFails = false;
  await f.api.command({action: 'pitch', value: -1});
  f.advance();
  assert.deepEqual(f.gains(), [0, 1]);
  f.worklets[0].events.processorerror();
  assert.deepEqual(f.gains(), [1, 0]);
  assert.equal(f.api.snapshot().pitchStatus, 'unavailable');
  assert.equal(f.sources.length, 1);
});

test('nonzero input with sustained silent DSP output falls back to dry', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 2});
  f.advance();
  f.state.outputSignal = 0;
  f.advance();
  f.advance(2600);
  assert.equal(f.api.snapshot().pitchStatus, 'unavailable');
  assert.deepEqual(f.gains(), [1, 0]);
});

test('unconfirmed silent input has a bounded loading period but paused time is excluded', async () => {
  const f = fixture();
  f.state.inputSignal = f.state.outputSignal = 0;
  await f.api.command({action: 'pitch', value: 2});
  f.video.paused = true;
  for (let i = 0; i < 70; i += 1) f.advance(200);
  assert.equal(f.api.snapshot().pitchStatus, 'loading');
  f.video.paused = false;
  for (let i = 0; i < 52; i += 1) f.advance(200);
  assert.equal(f.api.snapshot().pitchStatus, 'unavailable');
  assert.equal(f.api.snapshot().pitch, 0);
  assert.match(f.api.snapshot().pitchMessage, /Não foi possível confirmar/);
  assert.deepEqual(f.gains(), [1, 0]);
});

test('bypass disconnects DSP output and detached elements retire without losing source ownership', async () => {
  const f = fixture({probe: true});
  await f.api.command({action: 'pitch', value: 3});
  f.advance();
  await f.api.command({action: 'pitch', value: 0});
  assert.equal(f.worklets[0].connections.length, 0);
  const original = f.video;
  original.isConnected = false;
  f.navigate(null, null);
  assert.equal(f.sources[0].connections.length, 0);
  assert.equal(f.api.snapshot().probe.sourceCount, 0);
  original.isConnected = true;
  f.navigate('two', original);
  await f.api.command({action: 'pitch', value: 3});
  f.advance();
  assert.equal(f.sources.length, 1);
  assert.equal(f.api.snapshot().probe.sourceCount, 1);
  assert.equal(f.api.snapshot().pitchStatus, 'active');
  assert.equal(f.worklets[0].connections.length, 1);
});

test('the compatibility factory is preferred when provided by the host', async () => {
  const f = fixture();
  const factory = f.window.SignalsmithStretch;
  let called = false;
  f.window.TransponoCreateStretch = (...args) => { called = true; return factory(...args); };
  f.window.SignalsmithStretch = () => { throw new Error('Unreachable'); };
  await f.api.command({action: 'pitch', value: 2});
  f.advance();
  assert.equal(called, true);
  assert.equal(f.api.snapshot().pitchStatus, 'active');
});

test('three-band EQ and delay filter the selected video without duplicating its source', async () => {
  const f = fixture();
  await f.api.command({action: 'bass', value: 6});
  const filters = f.nodes.filter(node => node.kind === 'filter');
  assert.equal(filters.length, 3);
  assert.equal(filters[0].type, 'lowshelf');
  assert.equal(filters[0].frequency.value, 200);
  assert.equal(filters[0].gain.value, 6);
  await f.api.command({action: 'mid', value: 3});
  assert.equal(filters[2].type, 'peaking');
  assert.equal(filters[2].frequency.value, 1000);
  assert.equal(filters[2].gain.value, 3);
  await f.api.command({action: 'treble', value: -4});
  assert.equal(filters[1].type, 'highshelf');
  assert.equal(filters[1].frequency.value, 3000);
  assert.equal(filters[1].gain.value, -4);
  await f.api.command({action: 'delay', value: 0.2});
  const echo = f.nodes.filter(node => node.kind === 'delay');
  assert.equal(echo.length, 2, 'Echo and chorus have separate delay nodes');
  assert.equal(echo[0].delayTime.value, 0.28);
  assert.equal(echo[1].delayTime.value, 0.018);
  const echoOutput = echo[0].connections[0];
  assert.equal(echoOutput.gain.value, 0.2);
  assert.equal(f.sources.length, 1);
  f.setAd(true);
  assert.equal(filters[0].gain.value, 0);
  assert.equal(filters[1].gain.value, 0);
  assert.equal(filters[2].gain.value, 0);
  assert.equal(echoOutput.gain.value, 0);
  f.setAd(false);
  assert.equal(filters[0].gain.value, 6);
  assert.equal(filters[1].gain.value, -4);
  assert.equal(filters[2].gain.value, 3);
  assert.equal(echoOutput.gain.value, 0.2);
  await f.api.command({action: 'pitch', value: 2});
  f.advance();
  assert.equal(f.api.snapshot().pitchStatus, 'active');
  assert.equal(f.sources.length, 1);
  f.navigate('another');
  assert.equal(filters[0].gain.value, 0);
  assert.equal(filters[1].gain.value, 0);
  assert.equal(filters[2].gain.value, 0);
  assert.equal(echoOutput.gain.value, 0);
});

test('valid loop uses media positions, disarms on external seek, and validates bounds', async () => {
  const f = fixture();
  await assert.rejects(f.api.command({action: 'markB'}));
  await f.api.command({action: 'markA'});
  f.video.currentTime = 10.1;
  await assert.rejects(f.api.command({action: 'markB'}));
  f.video.currentTime = 20;
  await f.api.command({action: 'markB'});
  f.advance();
  assert.equal(f.video.currentTime, 10);
  await f.api.command({action: 'seekBy', value: 30});
  assert.equal(f.api.snapshot().loopEnabled, false);
  assert.equal(f.video.currentTime, 40);
  await f.api.command({action: 'toggleLoop'});
  assert.equal(f.video.currentTime, 10);
  await f.api.command({action: 'clearLoop'});
  assert.equal(f.api.snapshot().loopA, null);
  for (const request of [
    {action: 'pitch', value: NaN}, {action: 'pitch', value: 13},
    {action: 'speed', value: 0.24}, {action: 'speed', value: 2.01},
    {action: 'speed', value: '1'}, {action: 'seekBy', value: Infinity},
  ]) await assert.rejects(f.api.command(request));
});

test('ads bypass pitch/speed/loop without removing or skipping advertisements', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 2});
  await f.api.command({action: 'speed', value: 0.75});
  await f.api.command({action: 'markA'});
  f.video.currentTime = 20;
  await f.api.command({action: 'markB'});
  f.video.duration = 15;
  f.setAd(true);
  assert.equal(f.api.snapshot().isAd, true);
  assert.equal(f.api.snapshot().loopEnabled, false);
  assert.equal(f.video.currentTime, 20);
  assert.equal(f.api.snapshot().loopB, 20);
  assert.equal(f.video.playbackRate, 1);
  assert.deepEqual(f.gains(), [1, 0]);
  await assert.rejects(f.api.command({action: 'seekBy', value: 10}));
  await assert.rejects(f.api.command({action: 'seekTo', value: 5}));
  assert.equal(f.video.currentTime, 20);
  f.video.duration = 100;
  f.setAd(false);
  await new Promise(resolve => setImmediate(resolve));
  f.advance();
  assert.equal(f.video.playbackRate, 0.75);
  assert.equal(f.api.snapshot().pitch, 2);
  assert.equal(f.sources.length, 1);
});

test('absolute seek clamps bounds and only disarms a loop when leaving its range', async () => {
  const f = fixture();
  await f.api.command({action: 'markA'});
  f.video.currentTime = 20;
  await f.api.command({action: 'markB'});
  await f.api.command({action: 'seekTo', value: 15.75});
  assert.equal(f.video.currentTime, 15.75);
  assert.equal(f.api.snapshot().loopEnabled, true);
  await f.api.command({action: 'seekTo', value: 20});
  assert.equal(f.api.snapshot().loopEnabled, false);
  assert.equal(f.api.snapshot().loopA, 10);
  assert.equal(f.api.snapshot().loopB, 20);
  assert.equal(f.video.currentTime, 20);
  await f.api.command({action: 'seekTo', value: -100});
  assert.equal(f.video.currentTime, 0);
  await f.api.command({action: 'seekTo', value: 1000});
  assert.equal(f.video.currentTime, 100);
  for (const value of [NaN, Infinity, -Infinity, '10', null, undefined]) {
    await assert.rejects(f.api.command({action: 'seekTo', value}));
    assert.equal(f.video.currentTime, 100);
  }
});

test('absolute seek rejects live or unavailable timelines without moving video', async () => {
  for (const duration of [Infinity, NaN, 0]) {
    const f = fixture();
    f.video.duration = duration;
    await assert.rejects(f.api.command({action: 'seekTo', value: 15}), /ao vivo/);
    assert.equal(f.video.currentTime, 10);
  }
  const f = fixture();
  f.navigate(null);
  await assert.rejects(f.api.command({action: 'seekTo', value: 15}), /Escolha/);
});

test('SPA reset and disposal preserve source ownership without automatic playback', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 2});
  await f.api.command({action: 'speed', value: 0.75});
  await f.api.command({action: 'markA'});
  f.navigate('two');
  assert.equal(f.api.snapshot().pitch, 0);
  assert.equal(f.api.snapshot().loopA, null);
  assert.equal(f.video.playbackRate, 1);
  assert.deepEqual(f.gains(), [1, 0]);
  await f.api.command({action: 'pitch', value: 4});
  assert.equal(f.sources.length, 1);
  f.api.dispose();
  assert.equal(f.video.paused, true);
  assert.deepEqual(f.gains(), [1, 0]);
  f.reinject();
  await f.api.command({action: 'pitch', value: 1});
  assert.equal(f.sources.length, 1);
  assert.equal(f.video.paused, true);
});

test('navigation during worklet creation cannot attach an old video', async () => {
  const f = fixture();
  let resolve;
  f.state.deferFactory = new Promise(done => { resolve = done; });
  const pending = f.api.command({action: 'pitch', value: 3});
  await new Promise(done => setImmediate(done));
  f.navigate('two');
  resolve();
  await pending;
  assert.equal(f.sources.length, 0);
  assert.equal(f.api.snapshot().pitch, 0);
});

test('pause is immediate while pitch prepares and no-video commands explain next step', async () => {
  const f = fixture();
  let resolve;
  f.state.deferFactory = new Promise(done => { resolve = done; });
  const pending = f.api.command({action: 'pitch', value: 3});
  await f.api.command({action: 'pause'});
  assert.equal(f.video.paused, true);
  resolve();
  await pending;
  f.navigate(null);
  assert.equal(f.api.snapshot().hasVideo, false);
  await assert.rejects(f.api.command({action: 'playPause'}), /Escolha/);
});

test('pending AudioContext resume never starts after pause, disposal, source or ad changes', async () => {
  for (const action of ['play', 'playPause', 'unmute']) {
    for (const interruption of ['pause', 'dispose', 'video-id', 'source', 'ad']) {
      const f = fixture();
      await f.api.command({action: 'pitch', value: 2});
      await f.api.command({action: 'pause'});
      let finishResume;
      f.contexts[0].resume = () => new Promise(resolve => { finishResume = resolve; });
      let plays = 0;
      const play = f.video.play.bind(f.video);
      f.video.play = async () => { plays += 1; await play(); };
      const oldPlay = f.api.command({action});
      if (interruption === 'pause') await f.api.command({action: 'pause'});
      if (interruption === 'dispose') f.api.dispose();
      if (interruption === 'video-id') f.navigate('two');
      // Do not tick: completion must detect a source replaced while timers slept.
      if (interruption === 'source') f.video.currentSrc = 'blob:https://m.youtube.com/new';
      if (interruption === 'ad') f.setAd(true);
      finishResume();
      await oldPlay;
      assert.equal(plays, 0, `${action}/${interruption} resurrected playback`);
      assert.equal(f.video.paused, true);
      f.api.dispose();
    }
  }
});

test('explicit Play is idempotent and never implicitly unmutes the video', async () => {
  const f = fixture();
  await f.api.command({action: 'pause'});
  f.video.muted = true;
  let plays = 0;
  const play = f.video.play.bind(f.video);
  f.video.play = async () => { plays += 1; await play(); };
  await f.api.command({action: 'play'});
  await f.api.command({action: 'play'});
  f.api.dispatch('already-playing', {action: 'play'});
  assert.equal(f.api.cancelCommand('already-playing'), true);
  assert.equal(plays, 1, 'Repeated Play must not request or toggle playback again');
  assert.equal(f.video.paused, false, 'Cancelling a no-op must not own the existing Play');
  assert.equal(f.video.muted, true);
});

test('explicit Play acknowledgement cannot restart after cancellation by Pause', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 2});
  await f.api.command({action: 'pause'});
  let finishResume;
  f.contexts[0].resume = () => new Promise(resolve => { finishResume = resolve; });
  f.api.dispatch('explicit-play', {action: 'play'});
  assert.equal(f.api.commandResult('explicit-play').status, 'pending');
  await f.api.command({action: 'pause'});
  finishResume();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.api.commandResult('explicit-play').status, 'done');
  assert.equal(f.video.paused, true);
});

test('pending media play cannot undo pause when its promise completes late', async () => {
  const f = fixture();
  await f.api.command({action: 'pause'});
  let finishPlay;
  const play = f.video.play.bind(f.video);
  f.video.play = async () => {
    await new Promise(resolve => { finishPlay = resolve; });
    await play();
  };
  const oldPlay = f.api.command({action: 'playPause'});
  await f.api.command({action: 'pause'});
  finishPlay();
  await oldPlay;
  assert.equal(f.video.paused, true);
});

test('native page pause also invalidates a pending Play without cancelling newer stale-event playback', async () => {
  const f = fixture();
  await f.api.command({action: 'pause'});
  let finishPlay;
  const play = f.video.play.bind(f.video);
  f.video.play = async () => {
    await new Promise(resolve => { finishPlay = resolve; });
    await play();
  };
  const oldPlay = f.api.command({action: 'playPause'});
  f.video.pause(); // A page control, not Transpono's command('pause').
  finishPlay();
  await oldPlay;
  assert.equal(f.video.paused, true);
  f.video.play = play;
  await f.api.command({action: 'playPause'});
  f.video.dispatch('pause'); // A queued event after a newer Play is already active.
  assert.equal(f.video.paused, false);
});

test('an older Play completion does not pause a newer explicit Play', async () => {
  const f = fixture();
  await f.api.command({action: 'pause'});
  let finishOldPlay;
  const play = f.video.play.bind(f.video);
  let calls = 0;
  f.video.play = async () => {
    if (++calls === 1) await new Promise(resolve => { finishOldPlay = resolve; });
    await play();
  };
  const oldPlay = f.api.command({action: 'playPause'});
  await f.api.command({action: 'pause'});
  await f.api.command({action: 'playPause'});
  assert.equal(f.video.paused, false);
  finishOldPlay();
  await oldPlay;
  assert.equal(f.video.paused, false, 'Old completion must not override the new Play intent');
});

test('command acknowledgement waits for completion and supplies a fresh ordered snapshot', async () => {
  const f = fixture();
  await f.api.command({action: 'pause'});
  let finishPlay;
  let calls = 0;
  const play = f.video.play.bind(f.video);
  f.video.play = async () => {
    calls += 1;
    await new Promise(resolve => { finishPlay = resolve; });
    await play();
  };
  assert.equal(f.api.dispatch('play-1', {action: 'playPause'}), true);
  const pending = f.api.commandResult('play-1');
  assert.equal(pending.status, 'pending');
  assert.equal(pending.snapshot.playing, false);
  assert.equal(f.api.dispatch('play-1', {action: 'playPause'}), true);
  assert.equal(calls, 1, 'Retrying a retained ID must not toggle twice');
  finishPlay();
  await new Promise(resolve => setImmediate(resolve));
  const done = f.api.commandResult('play-1');
  assert.equal(done.status, 'done');
  assert.equal(done.snapshot.playing, true);
  assert.ok(done.snapshot.snapshotRevision > pending.snapshot.snapshotRevision);
  f.video.currentTime = 42;
  const latest = f.api.commandResult('play-1');
  assert.equal(latest.snapshot.position, 42, 'ACK reads current state, not stale completion state');
  assert.ok(latest.snapshot.snapshotRevision > done.snapshot.snapshotRevision);
  assert.equal(f.api.forgetCommand('play-1'), true);
  assert.equal(f.api.commandResult('play-1'), null);
});

test('failed commands report errors and invalid acknowledgement IDs are rejected', async () => {
  const f = fixture();
  for (const id of ['', 'x'.repeat(101), 4, null, undefined]) {
    assert.throws(() => f.api.dispatch(id, {action: 'pause'}), /inválido/);
  }
  f.api.dispatch('bad', {action: 'invalid'});
  await new Promise(resolve => setImmediate(resolve));
  const failure = f.api.commandResult('bad');
  assert.equal(failure.status, 'error');
  assert.match(failure.error, /não reconhecido/);
  assert.ok(failure.snapshot.snapshotRevision > 0);
  assert.equal(f.api.commandResult('missing'), null);
  f.api.dispose();
  f.api.dispatch('closed', {action: 'pause'});
  await new Promise(resolve => setImmediate(resolve));
  const closed = f.api.commandResult('closed');
  assert.equal(closed.status, 'error');
  assert.equal(closed.snapshot, null);
});

test('acknowledgements retain at most 64 entries and do not evict pending commands', async () => {
  const f = fixture();
  for (let i = 0; i < 70; i += 1) {
    f.api.dispatch(`done-${i}`, {action: 'speed', value: 1});
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.equal(f.api.commandResult('done-5'), null);
  assert.equal(f.api.commandResult('done-6').status, 'done');
  assert.equal(f.api.commandResult('done-69').status, 'done');
  await f.api.command({action: 'pitch', value: 2});
  await f.api.command({action: 'pause'});
  let finishResume;
  const resume = new Promise(resolve => { finishResume = resolve; });
  f.contexts[0].resume = () => resume;
  for (let i = 0; i < 64; i += 1) f.api.dispatch(`pending-${i}`, {action: 'playPause'});
  assert.throws(() => f.api.dispatch('overflow', {action: 'pause'}), /pendentes/);
  assert.equal(f.api.commandResult('pending-0').status, 'pending');
  assert.equal(f.api.commandResult('pending-63').status, 'pending');
  assert.equal(f.api.commandResult('done-69'), null);
  f.api.forgetCommand('pending-0');
  await f.api.command({action: 'pause'});
  finishResume();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.api.commandResult('pending-0'), null, 'Forgotten asynchronous results cannot reappear');
  assert.equal(f.api.commandResult('pending-63').status, 'done');
  assert.equal(f.video.paused, true);
});

test('cancelling a pending command prevents late audio resume and keeps error acknowledgement', async () => {
  const f = fixture();
  await f.api.command({action: 'pitch', value: 2});
  await f.api.command({action: 'pause'});
  let finishResume;
  f.contexts[0].resume = () => new Promise(resolve => { finishResume = resolve; });
  f.api.dispatch('expired', {action: 'playPause'});
  assert.equal(f.api.commandResult('expired').status, 'pending');
  assert.equal(f.api.cancelCommand('expired'), true);
  assert.equal(f.api.commandResult('expired').status, 'error');
  finishResume();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.video.paused, true);
  assert.equal(f.api.commandResult('expired').status, 'error');
  assert.equal(f.api.cancelCommand('expired'), false);
  assert.equal(f.api.cancelCommand('unknown'), false);
});

test('cancelling an old dispatch cannot cancel a newer untagged or tagged Play', async () => {
  for (const tagged of [false, true]) {
    const f = fixture();
    await f.api.command({action: 'pause'});
    let finishOldPlay;
    const play = f.video.play.bind(f.video);
    let calls = 0;
    f.video.play = async () => {
      if (++calls === 1) await new Promise(resolve => { finishOldPlay = resolve; });
      await play();
    };
    f.api.dispatch('old', {action: 'playPause'});
    if (tagged) f.api.dispatch('new', {action: 'playPause'});
    else await f.api.command({action: 'playPause'});
    assert.equal(f.video.paused, false);
    assert.equal(f.api.cancelCommand('old'), true);
    assert.equal(f.video.paused, false);
    finishOldPlay();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.video.paused, false);
    assert.equal(f.api.commandResult('old').status, 'error');
    if (tagged) assert.equal(f.api.commandResult('new').status, 'done');
  }
});

test('cancelling pending pitch cancels only its own DSP intent and does not reattach it', async () => {
  const f = fixture();
  let finishFactory;
  f.state.deferFactory = new Promise(resolve => { finishFactory = resolve; });
  f.api.dispatch('pitch-old', {action: 'pitch', value: 3});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.api.cancelCommand('pitch-old'), true);
  finishFactory();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.sources.length, 0);
  assert.equal(f.api.snapshot().pitch, 0);
  assert.equal(f.api.snapshot().pitchStatus, 'idle');
  assert.equal(f.api.commandResult('pitch-old').status, 'error');

  const g = fixture();
  let finishSecondFactory;
  g.state.deferFactory = new Promise(resolve => { finishSecondFactory = resolve; });
  g.api.dispatch('first', {action: 'pitch', value: 2});
  await new Promise(resolve => setImmediate(resolve));
  g.api.dispatch('second', {action: 'pitch', value: 4});
  assert.equal(g.api.cancelCommand('first'), true);
  finishSecondFactory();
  await new Promise(resolve => setImmediate(resolve));
  g.advance();
  assert.equal(g.api.snapshot().pitch, 4);
  assert.equal(g.api.commandResult('second').status, 'done');
});
