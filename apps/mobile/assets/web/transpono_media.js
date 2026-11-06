/* Transpono's page-local controls. No media is captured, fetched or exported. */
(function () {
  'use strict';

  const allowedPage = () => window.top === window &&
    /(^|\.)(youtube|soundcloud)\.com$/i.test(window.location.hostname) &&
    window.location.protocol === 'https:';
  if (!allowedPage()) return;
  // SoundCloud plays through an Audio element that is never put in the page,
  // so it cannot be found with querySelector: remember the one that last
  // started playing. (In Gecko this runs in the relay's content-script
  // sandbox, where the page's own prototype is reached through
  // wrappedJSObject and the hook is handed back with exportFunction.)
  const soundCloud = () => /(^|\.)soundcloud\.com$/i.test(window.location.hostname);
  if (soundCloud() && !window.__transponoPlayHook) {
    window.__transponoPlayHook = true;
    try {
      const pageWindow = window.wrappedJSObject || window;
      const proto = pageWindow.HTMLMediaElement.prototype;
      const originalPlay = proto.play;
      const remember = function () {
        window.__transponoPlaying = this;
        return originalPlay.apply(this, arguments);
      };
      proto.play = typeof exportFunction === 'function'
        ? exportFunction(remember, pageWindow)
        : remember;
    } catch (_) {
      // Without the hook the bridge simply finds no SoundCloud player.
    }
  }
  // Mini player: on m.youtube.com the watch-page player is a fixed
  // "sticky-player" under the top bar, so the video list scrolls under it.
  // Once the list is scrolled, shrink it to a small video in the corner (like
  // the YouTube app); tapping it scrolls back up to the full player. The
  // element keeps its size and is only scaled, so YouTube's own layout and
  // the audio graph are untouched.
  if (!soundCloud() && !window.__transponoMini) {
    window.__transponoMini = true;
    const style = document.createElement('style');
    style.id = 'transpono-mini-style';
    style.textContent = `
      html.transpono-mini #player-container-id.sticky-player {
        top: auto !important; bottom: 140px !important;
        left: auto !important; right: 10px !important;
        width: 100vw !important;
        transform: scale(.46); transform-origin: right bottom;
        border-radius: 22px; overflow: hidden;
        box-shadow: 0 12px 40px rgba(0, 0, 0, .6);
        z-index: 9999 !important;
        transition: transform .18s ease;
      }`;
    (document.head || document.documentElement).appendChild(style);
    const root = document.documentElement;
    const update = () => {
      const player = document.querySelector('#player-container-id.sticky-player');
      const mini = !!player && window.location.pathname === '/watch' && window.scrollY > 40;
      if (root.classList.contains('transpono-mini') !== mini) {
        root.classList.toggle('transpono-mini', mini);
      }
    };
    window.addEventListener('scroll', update, {passive: true});
    // Tapping the small video brings the full player back instead of
    // pausing it.
    document.addEventListener('click', event => {
      if (!root.classList.contains('transpono-mini')) return;
      const player = document.querySelector('#player-container-id.sticky-player');
      if (!player || !player.contains(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
      window.scrollTo({top: 0, behavior: 'smooth'});
    }, true);
    setInterval(update, 500);
  }
  // WebView can reinject after an SPA navigation. Reuse MediaElementAudioSource
  // ownership: creating a second source for the same element is not supported.
  if (window.TransponoMedia && window.TransponoMedia._activate) {
    window.TransponoMedia._activate();
    return;
  }

  const graphs = new WeakMap();
  const preparing = new WeakMap();
  const allGraphs = new Set();
  // Enabled only by the isolated generated-tone integration fixture.
  const probeEnabled = window.__transponoAudioProbe === true;
  const minLoopSeconds = 0.25;
  let audioContext = null;
  let video = null;
  let videoId = null;
  let pitch = 0;
  let speed = 1;
  let bass = 0;
  let mid = 0;
  let treble = 0;
  let gain = 0;
  let chorus = 0;
  let feedback = 0;
  let delay = 0;
  let reverb = 0;
  let reverbImpulse = null;
  let effectsEpoch = 0;
  let restoringEffectsEpoch = -1;
  const effectIntents = new Map();
  const keyDetector = window.TransponoKeyDetector
    ? new window.TransponoKeyDetector.KeyDetector() : null;
  let keyCapture = null;
  let keyPreparing = false;
  let keyLastAttempt = -Infinity;
  let keyLastSample = -Infinity;
  let keyRoot = null;
  let keyMode = '';
  let keyStatus = 'waiting';
  let pitchStatus = 'idle';
  let pitchMessage = '';
  let loopA = null;
  let loopB = null;
  let loopWanted = false;
  // Completion is an observation, not a seek command acknowledgement. Keep the
  // counter monotonic and change epoch whenever its playback context changes.
  let loopCount = 0;
  let loopEpoch = 0;
  let cycleArmed = false;
  let pendingLoopReturn = null;
  let loopEventElement = null;
  let loopEventHandlers = null;
  let observedSource = '';
  let isAd = false;
  // The current element's source was judged unusable for pitch (see refresh).
  let sourceBlocked = false;
  let revision = 0;
  let timer = null;
  let disposed = false;
  let lastPosted = '';
  let snapshotRevision = 0;
  let timelineSeekEpoch = 0;
  let timelineRateEpoch = 0;
  let timelineSourceEpoch = 0;
  let transportRevision = 0;
  let playbackIntent = null;
  let pitchCommandIntent = null;
  let activeDispatchId = null;
  const commandResults = new Map();
  const maxCommandResults = 64;

  const finite = (value, fallback = 0) => Number.isFinite(value) ? value : fallback;
  const decibelGain = value => Math.pow(10, value / 20);
  function setEffectParam(parameter, value, smooth = false) {
    const time = audioContext.currentTime;
    parameter.cancelScheduledValues(time);
    if (smooth) parameter.setTargetAtTime(value, time, 0.015);
    else parameter.setValueAtTime(value, time);
  }
  const now = () => performance.now();
  const durationOf = (element) => Math.max(0, finite(element && element.duration));
  const positionOf = (element) => Math.max(0, finite(element && element.currentTime));
  const sourceOf = (element) => element ? element.currentSrc || element.src || '' : '';
  // A YouTube video element that left the page is gone; SoundCloud's player
  // element is never in the page, so it is gone only once replaced.
  const gone = (element) => soundCloud()
    ? element !== window.__transponoPlaying
    : element.isConnected === false;
  const playbackReady = () => !!video && !disposed && !isAd && !video.ended &&
    video.readyState >= 3 && !video.seeking;
  const nearLoopStart = () => loopA !== null && loopB !== null &&
    Math.abs(positionOf(video) - loopA) <= Math.min(0.1, (loopB - loopA) / 4);
  const selectedId = () => {
    if (soundCloud()) {
      // The player keeps going across pages: identify the track itself.
      const playing = window.__transponoPlaying;
      const meta = navigator.mediaSession && navigator.mediaSession.metadata;
      if (!playing || !meta || !meta.title) return null;
      const name = `${meta.title}|${meta.artist || ''}`;
      let hash = 0;
      for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0;
      return `soundcloud-${(hash >>> 0).toString(36)}`;
    }
    const url = new URL(window.location.href);
    if (url.pathname === '/watch') return url.searchParams.get('v');
    const match = url.pathname.match(/^\/(?:shorts|live|embed)\/([^/?]+)/);
    return match ? match[1] : null;
  };
  const title = () => {
    // YouTube Music sets Media Session metadata ("Song" + "Artist"); the
    // chord search wants both, like a YouTube "Song - Artist" title.
    const session = navigator.mediaSession && navigator.mediaSession.metadata;
    const sessionTitle = session && session.title
      ? (session.artist ? `${session.title} - ${session.artist}` : session.title)
      : '';
    const candidates = [
      /(^|\.)(music\.youtube|soundcloud)\.com$/i.test(window.location.hostname)
        ? sessionTitle : '',
      document.querySelector('h1.ytd-watch-metadata, .slim-video-metadata-title, h1.title')?.textContent,
      document.querySelector('meta[property="og:title"]')?.getAttribute('content'),
      document.querySelector('meta[name="title"]')?.getAttribute('content'),
      document.title,
    ];
    for (const candidate of candidates) {
      const value = (candidate || '').replace(/\s*[-–]\s*YouTube(?: Music)?\s*$/i, '').trim();
      if (value && !/^(?:youtube(?: music)?|vídeo do youtube)$/i.test(value)) return value;
    }
    return '';
  };

  function timeout(promise, milliseconds, message) {
    let timeoutId;
    return Promise.race([
      Promise.resolve(promise),
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => reject(new Error(message)), milliseconds);
      }),
    ]).finally(() => clearTimeout(timeoutId));
  }

  function setGain(node, value) {
    node.gain.cancelScheduledValues(audioContext.currentTime);
    node.gain.setValueAtTime(value, audioContext.currentTime);
  }

  function dry(graph, stopProcessing = false) {
    if (!graph) return;
    // These switches share the audio-context timestamp: never sum two copies.
    setGain(graph.wet, 0);
    setGain(graph.dry, 1);
    graph.audible = false;
    if (stopProcessing) {
      graph.acknowledged = false;
      if (graph.dspConnected && graph.stretch) {
        graph.input.disconnect(graph.stretch);
        graph.stretch.disconnect();
        graph.output.disconnect();
        graph.dspConnected = false;
      }
      try {
        if (graph.stretch) Promise.resolve(graph.stretch.schedule({active: false})).catch(() => {});
      } catch (_) {
        // A dead processor must never prevent the dry route from being restored.
      }
    }
  }

  function wet(graph) {
    setGain(graph.dry, 0);
    setGain(graph.wet, 1);
    graph.audible = true;
  }

  function impulseResponse() {
    if (reverbImpulse) return reverbImpulse;
    const length = Math.floor(audioContext.sampleRate * 1.15);
    const buffer = audioContext.createBuffer(2, length, audioContext.sampleRate);
    // A short, decaying stereo impulse keeps the reverb local to the page.
    let seed = 2179;
    for (let channel = 0; channel < 2; channel++) {
      const data = buffer.getChannelData(channel);
      for (let i = 0; i < length; i++) {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        const envelope = Math.pow(1 - i / length, 3);
        data[i] = (seed / 2147483648 - 1) * envelope;
      }
    }
    reverbImpulse = buffer;
    return buffer;
  }

  function connectEffects(graph) {
    graph.low.connect(graph.mid).connect(graph.high).connect(graph.master);
    if (graph.probeFinal) graph.master.connect(graph.probeFinal).connect(audioContext.destination);
    else graph.master.connect(audioContext.destination);
    graph.high.connect(graph.echoDelay);
    graph.echoDelay.connect(graph.echoGain).connect(graph.master);
    graph.echoDelay.connect(graph.feedbackGain).connect(graph.echoDelay);
    graph.high.connect(graph.chorusDelay).connect(graph.chorusGain).connect(graph.master);
    graph.chorusLfo.connect(graph.chorusDepth).connect(graph.chorusDelay.delayTime);
    graph.high.connect(graph.convolver).connect(graph.reverbGain).connect(graph.master);
  }

  function retire(graph) {
    if (!graph || graph.retired) return;
    dry(graph, true);
    graph.source.disconnect();
    graph.input.disconnect();
    graph.keyAnalyser.disconnect();
    graph.dry.disconnect();
    graph.wet.disconnect();
    graph.low.disconnect();
    graph.mid.disconnect();
    graph.high.disconnect();
    graph.master.disconnect();
    if (graph.probeFinal) graph.probeFinal.disconnect();
    graph.echoDelay.disconnect();
    graph.echoGain.disconnect();
    graph.feedbackGain.disconnect();
    graph.chorusDelay.disconnect();
    graph.chorusGain.disconnect();
    graph.chorusLfo.disconnect();
    if (graph.lfoStarted) graph.chorusLfo.stop();
    graph.lfoStarted = false;
    graph.chorusDepth.disconnect();
    graph.convolver.disconnect();
    graph.reverbGain.disconnect();
    graph.retired = true;
    allGraphs.delete(graph);
  }

  function revive(graph) {
    if (!graph || !graph.retired) return;
    graph.chorusLfo = audioContext.createOscillator();
    graph.chorusLfo.frequency.value = 0.8;
    graph.input.connect(graph.keyAnalyser).connect(graph.dry).connect(graph.low);
    graph.wet.connect(graph.low);
    connectEffects(graph);
    graph.source.connect(graph.input);
    graph.chorusLfo.start();
    graph.lfoStarted = true;
    graph.retired = false;
    allGraphs.add(graph);
  }

  function preservesPitch(element) {
    if ('preservesPitch' in element) element.preservesPitch = true;
    else if ('webkitPreservesPitch' in element) element.webkitPreservesPitch = true;
    else if ('mozPreservesPitch' in element) element.mozPreservesPitch = true;
    else return false;
    return true;
  }

  function safeSource(element) {
    if (element.mediaKeys) return false;
    try {
      const source = new URL(element.currentSrc || element.src, window.location.href);
      return source.protocol === 'blob:' && source.origin === window.location.origin;
    } catch (_) {
      return false;
    }
  }

  function stopKeyCapture() {
    if (!keyCapture) return;
    keyCapture.source.disconnect();
    keyCapture.analyser.disconnect();
    keyCapture.silent.disconnect();
    keyCapture.stream.getTracks().forEach(track => track.stop());
    keyCapture = null;
  }

  function resetKeyDetection() {
    stopKeyCapture();
    if (keyDetector) keyDetector.reset();
    keyRoot = null;
    keyMode = '';
    keyStatus = 'waiting';
    keyLastAttempt = -Infinity;
    keyLastSample = -Infinity;
  }

  async function startKeyCapture(element) {
    const capture = element.captureStream || element.mozCaptureStream;
    if (!capture) throw new Error('Captura de áudio indisponível.');
    const stream = capture.call(element);
    const track = stream.getAudioTracks()[0];
    if (!track) {
      stream.getTracks().forEach(item => item.stop());
      throw new Error('O vídeo ainda não tem uma faixa de áudio acessível.');
    }
    try {
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) throw new Error('Análise de áudio indisponível.');
      if (!audioContext) audioContext = new Context({latencyHint: 'interactive'});
      await timeout(audioContext.resume(), 4000, 'Áudio ainda não iniciado.');
      if (element !== video || disposed || isAd) throw new Error('O vídeo mudou.');
      const source = audioContext.createMediaStreamSource(stream);
      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 16384;
      analyser.smoothingTimeConstant = 0.7;
      const silent = audioContext.createGain();
      silent.gain.value = 0;
      source.connect(analyser).connect(silent).connect(audioContext.destination);
      keyCapture = {
        element, source, analyser, silent, stream, track,
        spectrum: new Float32Array(analyser.frequencyBinCount), startedAt: now(),
      };
      keyStatus = 'analyzing';
    } catch (error) {
      stream.getTracks().forEach(item => item.stop());
      throw error;
    }
  }

  function updateKeyDetection() {
    if (!keyDetector || !video || isAd || disposed) return;
    if (video.paused || video.ended || video.readyState < 3) return;
    if (keyCapture && (keyCapture.element !== video || keyCapture.track.readyState !== 'live')) {
      stopKeyCapture();
      keyLastAttempt = -Infinity;
    }
    if (!keyCapture && !keyPreparing && now() - keyLastAttempt > 3000) {
      const element = video;
      keyPreparing = true;
      keyLastAttempt = now();
      void startKeyCapture(element).catch(() => {
        if (element === video && !isAd) keyStatus = 'unavailable';
      }).finally(() => { keyPreparing = false; });
      return;
    }
    const graph = graphs.get(video);
    const analyser = keyCapture ? keyCapture.analyser : graph && graph.keyAnalyser;
    const spectrum = keyCapture ? keyCapture.spectrum : graph && graph.keySpectrum;
    if (!analyser || !spectrum || !audioContext || audioContext.state !== 'running') return;
    if (keyCapture && keyCapture.track.muted) {
      if (now() - keyCapture.startedAt > 4000) keyStatus = 'unavailable';
      return;
    }
    if (now() - keyLastSample < 330) return;
    keyLastSample = now();
    analyser.getFloatFrequencyData(spectrum);
    const result = keyDetector.observeSpectrum(spectrum, audioContext.sampleRate, analyser.fftSize);
    if (result) {
      keyRoot = result.root;
      keyMode = result.mode;
      keyStatus = 'ready';
    } else if (keyDetector.frames > 75) {
      keyStatus = 'indeterminate';
    } else {
      keyStatus = 'analyzing';
    }
  }

  function requireSound(element) {
    if (element.muted || element.volume === 0) {
      const error = new Error('Ative o som do vídeo e tente alterar o tom novamente.');
      error.code = 'sound-muted';
      throw error;
    }
  }

  function unavailable(message, element = video) {
    dry(element && graphs.get(element), true);
    pitch = 0;
    pitchStatus = 'unavailable';
    pitchMessage = message;
  }

  function invalidateLoopObservation() {
    loopEpoch += 1;
    discardLoopReturn();
  }

  function discardLoopReturn() {
    cycleArmed = false;
    pendingLoopReturn = null;
  }

  function invalidatePlaybackIntent() {
    transportRevision += 1;
    playbackIntent = null;
  }

  function currentPlaybackIntent(intent) {
    return intent && playbackIntent === intent && intent.revision === transportRevision &&
      !disposed && allowedPage() && video === intent.element && videoId === intent.videoId &&
      sourceOf(video) === intent.source && isAd === intent.isAd;
  }

  async function playCurrentVideo() {
    const intent = {
      revision: ++transportRevision, element: video, videoId,
      source: sourceOf(video), isAd, commandId: activeDispatchId,
    };
    playbackIntent = intent;
    if (audioContext) {
      await timeout(audioContext.resume(), 4000, 'Toque no vídeo para ativar o áudio.');
    }
    // The page can replace its source while AudioContext.resume is pending,
    // including when background timers are throttled. Re-read it before play.
    refresh();
    if (!currentPlaybackIntent(intent)) return;
    await intent.element.play();
    refresh();
    if (!currentPlaybackIntent(intent)) {
      // A cancelled old Play cannot resurrect playback, but it must not stop a
      // newer explicit Play for this same element/context when its promise ends.
      if (!(currentPlaybackIntent(playbackIntent) &&
          playbackIntent.element === intent.element)) intent.element.pause();
    }
  }

  function armCycleAtStart() {
    if (loopWanted && !pendingLoopReturn && playbackReady() &&
        !video.paused && nearLoopStart()) cycleArmed = true;
  }

  function validLoopReturn(pending) {
    return pending && pending.element === video && pending.epoch === loopEpoch &&
      pending.videoId === videoId && pending.source === sourceOf(video) &&
      loopWanted && !disposed && !isAd && pending.a === loopA && pending.b === loopB;
  }

  function bindLoopEvents(element) {
    if (loopEventElement === element) return;
    if (loopEventHandlers) {
      for (const [name, handler] of Object.entries(loopEventHandlers)) {
        loopEventElement.removeEventListener(name, handler);
      }
    }
    loopEventElement = null;
    loopEventHandlers = null;
    if (!element || typeof element.addEventListener !== 'function' ||
        typeof element.removeEventListener !== 'function') return;
    loopEventElement = element;
    loopEventHandlers = {
      seeking() {
        if (element !== video || disposed) return;
        timelineSeekEpoch += 1;
        refresh();
        const pending = pendingLoopReturn;
        // currentTime is changed synchronously, but seeking/seeked are queued.
        // Only the first seek to our exact A target belongs to this return.
        if (validLoopReturn(pending) && !pending.sawSeeking && nearLoopStart()) {
          pending.sawSeeking = true;
        } else {
          invalidateLoopObservation();
          if (loopWanted && (positionOf(video) < loopA || positionOf(video) >= loopB)) {
            loopWanted = false;
          }
        }
        post();
      },
      seeked() {
        if (element !== video || disposed) return;
        refresh();
        const pending = pendingLoopReturn;
        const confirmed = validLoopReturn(pending) && pending.sawSeeking &&
          playbackReady() && !video.paused && nearLoopStart();
        pendingLoopReturn = null;
        if (confirmed && pending.eligible) loopCount += 1;
        // An external seek to A can start a new full pass, but cannot finish one.
        cycleArmed = loopWanted && playbackReady() && !video.paused && nearLoopStart();
        post();
      },
      play() {
        if (element !== video || disposed) return;
        refresh();
        // A paused seek to A must arm before the first 200 ms poll, which can
        // already be beyond the start tolerance even at 0.6x speed.
        armCycleAtStart();
        post();
      },
      playing() {
        if (element !== video || disposed) return;
        refresh();
        // play can precede HAVE_FUTURE_DATA. The readiness event also covers
        // buffering recovery at A, without arming a partial pass in the middle.
        armCycleAtStart();
        post();
      },
      pause() {
        if (element !== video || disposed) return;
        // Native YouTube controls can pause without going through our command
        // bridge. Ignore an already-stale queued pause event after a newer Play.
        if (element.paused) invalidatePlaybackIntent();
        // A normal pause halfway through a pass preserves progress. Pausing a
        // return before confirmation must never add a completed repetition.
        if (pendingLoopReturn) discardLoopReturn();
        post();
      },
      emptied() {
        if (element !== video || disposed) return;
        invalidateLoopObservation();
        post();
      },
      ratechange() {
        if (element !== video || disposed) return;
        timelineRateEpoch += 1;
        post();
      },
    };
    for (const [name, handler] of Object.entries(loopEventHandlers)) {
      element.addEventListener(name, handler);
    }
  }

  function returnLoopToStart() {
    const pending = {
      element: video, videoId, source: sourceOf(video), epoch: loopEpoch,
      a: loopA, b: loopB, eligible: cycleArmed, sawSeeking: false, startedAt: now(),
    };
    cycleArmed = false;
    pendingLoopReturn = pending;
    try {
      video.currentTime = loopA;
    } catch (_) {
      invalidateLoopObservation();
    }
  }

  function resetPractice(previous) {
    effectsEpoch += 1;
    revision += 1;
    invalidatePlaybackIntent();
    invalidateLoopObservation();
    dry(previous && graphs.get(previous), true);
    if (previous) previous.playbackRate = 1;
    pitch = 0;
    speed = 1;
    bass = 0;
    mid = 0;
    treble = 0;
    gain = 0;
    chorus = 0;
    feedback = 0;
    delay = 0;
    reverb = 0;
    resetKeyDetection();
    const graph = previous && graphs.get(previous);
    if (graph) {
      setEffectParam(graph.low.gain, 0);
      setEffectParam(graph.mid.gain, 0);
      setEffectParam(graph.high.gain, 0);
      setEffectParam(graph.master.gain, 1);
      setEffectParam(graph.echoGain.gain, 0);
      setEffectParam(graph.feedbackGain.gain, 0);
      setEffectParam(graph.chorusGain.gain, 0);
      setEffectParam(graph.reverbGain.gain, 0);
    }
    pitchStatus = 'idle';
    pitchMessage = '';
    sourceBlocked = false;
    loopA = null;
    loopB = null;
    loopWanted = false;
  }

  function refresh() {
    if (disposed || !allowedPage()) return;
    const id = selectedId();
    const next = !id
      ? null
      : soundCloud()
      ? window.__transponoPlaying || null
      : document.querySelector('video.html5-main-video') || document.querySelector('video');
    if (id !== videoId) {
      timelineSourceEpoch += 1;
      resetPractice(video);
      videoId = id;
    }
    if (next !== video) {
      timelineSourceEpoch += 1;
      effectsEpoch += 1;
      resetKeyDetection();
      invalidatePlaybackIntent();
      dry(video && graphs.get(video), true);
      if (video && gone(video)) retire(graphs.get(video));
      video = next;
      invalidateLoopObservation();
      bindLoopEvents(video);
      revive(video && graphs.get(video));
      revision += 1;
      if (pitch !== 0) {
        pitchStatus = 'idle';
        pitchMessage = 'O vídeo mudou. Aplique o tom novamente.';
      }
    }
    const nextSource = sourceOf(video);
    if (nextSource !== observedSource) {
      timelineSourceEpoch += 1;
      effectsEpoch += 1;
      observedSource = nextSource;
      invalidatePlaybackIntent();
      invalidateLoopObservation();
    }
    for (const graph of allGraphs) {
      if (graph.element !== video && gone(graph.element)) retire(graph);
    }
    const nextAd = !!document.querySelector('.ad-showing, .ad-interrupting');
    if (nextAd !== isAd) {
      effectsEpoch += 1;
      isAd = nextAd;
      invalidatePlaybackIntent();
      invalidateLoopObservation();
      revision += 1;
      dry(video && graphs.get(video), true);
      const currentGraph = video && graphs.get(video);
      if (currentGraph) {
        setEffectParam(currentGraph.low.gain, isAd ? 0 : bass);
        setEffectParam(currentGraph.mid.gain, isAd ? 0 : mid);
        setEffectParam(currentGraph.high.gain, isAd ? 0 : treble);
        setEffectParam(currentGraph.master.gain, isAd ? 1 : decibelGain(gain));
        setEffectParam(currentGraph.echoGain.gain, isAd ? 0 : delay);
        setEffectParam(currentGraph.feedbackGain.gain, isAd ? 0 : feedback);
        setEffectParam(currentGraph.chorusGain.gain, isAd ? 0 : chorus);
        setEffectParam(currentGraph.reverbGain.gain, isAd ? 0 : reverb);
      }
      if (isAd) {
        if (video) video.playbackRate = 1;
        pitchStatus = 'idle';
        pitchMessage = 'Os controles de prática retomam depois do anúncio.';
      } else if (video) {
        if (preservesPitch(video)) video.playbackRate = speed;
        pitchMessage = '';
        if (pitch !== 0) void applyPitch();
      }
    }
    const graph = video && graphs.get(video);
    // While YouTube swaps the next video into the same element its source is
    // briefly empty or not yet the page's own media stream. Treating that
    // moment as "this video cannot be pitched" left pitchStatus stuck at
    // 'unavailable' for every later video once pitch had been used ("Tom
    // indisponível nesta fonte" until the app was reopened). Judge only a
    // settled source, and clear the block when a usable source returns.
    if (graph && sourceOf(video) && video.readyState >= 1 && !safeSource(video)) {
      if (!sourceBlocked) {
        sourceBlocked = true;
        unavailable('Este vídeo não permite alterar o tom. Reabra o vídeo se o áudio não voltar.');
      }
    } else if (sourceBlocked && video && safeSource(video)) {
      sourceBlocked = false;
      if (pitchStatus === 'unavailable') {
        pitchStatus = 'idle';
        pitchMessage = '';
        revision += 1;
      }
    }
    restoreEffects();
    const duration = durationOf(video);
    if (!isAd && loopB !== null && (duration === 0 || loopB > duration)) {
      loopB = null;
      loopWanted = false;
      invalidateLoopObservation();
    }
  }

  function desiredEffects() {
    return {bass, mid, treble, gain, chorus, feedback, delay, reverb};
  }

  function effectNodes(graph) {
    return {bass: graph.low.gain, mid: graph.mid.gain, treble: graph.high.gain,
      gain: graph.master.gain, chorus: graph.chorusGain.gain,
      feedback: graph.feedbackGain.gain, delay: graph.echoGain.gain,
      reverb: graph.reverbGain.gain};
  }

  function validEffectsContext(epoch, element, id, source) {
    return !disposed && !isAd && effectsEpoch === epoch && video === element &&
      videoId === id && sourceOf(element) === source && safeSource(element);
  }

  function restoreEffects() {
    if (!video || disposed || isAd || !safeSource(video)) return;
    const graph = graphs.get(video);
    if (graph?.effectsFailed || graph?.effectsEpoch === effectsEpoch) return;
    if (!graph && !Object.values(desiredEffects()).some(value => value !== 0)) return;
    if (graph && !graph.retired) {
      const nodes = effectNodes(graph);
      for (const [action, value] of Object.entries(desiredEffects())) {
        setEffectParam(nodes[action], action === 'gain' ? decibelGain(value) : value);
      }
      graph.effectsEpoch = effectsEpoch;
      return;
    }
    if (video.muted || video.volume === 0 || restoringEffectsEpoch === effectsEpoch) return;
    const epoch = effectsEpoch, element = video, id = videoId, source = sourceOf(video);
    restoringEffectsEpoch = epoch;
    void prepareGraph(element, false).then(restored => {
      if (!validEffectsContext(epoch, element, id, source) || restored.effectsFailed) return;
      // Values may have changed while preparation awaited AudioContext.resume.
      restored.effectsEpoch = -1;
      restoreEffects();
      post();
    }).catch(() => {
      // Keep the native route; a new context or explicit adjustment can retry.
      // Snapshots report zero until there is an applicable processing graph.
    });
  }

  function appliedEffects(graph) {
    const values = {bass: 0, mid: 0, treble: 0, gain: 0,
      chorus: 0, feedback: 0, delay: 0, reverb: 0};
    if (!graph || graph.effectsFailed || graph.retired || disposed || isAd ||
        graph.effectsEpoch !== effectsEpoch || !safeSource(video)) return values;
    const nodes = effectNodes(graph);
    for (const action of Object.keys(values)) {
      const value = nodes[action].value;
      values[action] = action === 'gain' ? 20 * Math.log10(value) : value;
    }
    return values;
  }

  function snapshot() {
    refresh();
    const graph = video && graphs.get(video);
    const sampleTimeMs = now();
    const mediaPosition = positionOf(video);
    return {
      snapshotRevision: ++snapshotRevision,
      sampleTimeMs,
      timelineSeekEpoch,
      timelineRateEpoch,
      timelineSourceEpoch,
      videoId,
      title: video ? title() : '',
      hasVideo: !!video && !disposed,
      playing: !!video && !video.paused && !video.ended && !disposed,
      seeking: !!video && video.seeking,
      muted: !!video && (video.muted || video.volume === 0),
      position: mediaPosition,
      duration: durationOf(video),
      speed: video && !isAd ? finite(video.playbackRate, speed) : speed,
      // During a live pitch change, keep showing the tone still audible on
      // the processed route instead of briefly reporting the original tone.
      pitch: graph && graph.audible ? graph.appliedPitch : 0,
      pendingPitch: pitchStatus === 'loading' ? pitch : null,
      pitchStatus,
      pitchMessage,
      audioEffects: appliedEffects(graph),
      keyRoot,
      keyMode,
      keyStatus: keyDetector ? keyStatus : 'unavailable',
      loopA,
      loopB,
      loopEnabled: loopWanted && !isAd && !disposed,
      loopCount,
      loopEpoch,
      loopEventsSupported: !!video && loopEventElement === video &&
        durationOf(video) > 0 && !disposed &&
        // At EOF the page can pause/navigate before the 200 ms loop poll. Do
        // not offer automatic progression where completion is not reliable.
        (loopB === null || loopB < durationOf(video)),
      playbackReady: playbackReady(),
      isAd,
      ...(probeEnabled ? {probe: probeSnapshot()} : {}),
    };
  }

  function post() {
    const json = JSON.stringify(snapshot());
    if (json === lastPosted) return;
    lastPosted = json;
    if (window.TransponoBridge && typeof window.TransponoBridge.postMessage === 'function') {
      window.TransponoBridge.postMessage(json);
    }
  }

  async function prepareGraph(element, needsPitch = true) {
    if (graphs.has(element)) {
      const graph = graphs.get(element);
      revive(graph);
      if (needsPitch && !graph.stretch) await attachStretch(graph);
      return graph;
    }
    if (preparing.has(element)) {
      const graph = await preparing.get(element);
      if (needsPitch && !graph.stretch) await attachStretch(graph);
      return graph;
    }
    const id = videoId;
    const pending = (async () => {
      if (!safeSource(element)) throw new Error('Este vídeo não disponibiliza áudio para alterar o tom neste dispositivo.');
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) throw new Error('O equalizador não está disponível neste navegador.');
      if (!audioContext) audioContext = new Context({latencyHint: 'interactive'});
      await timeout(audioContext.resume(), 4000, 'Toque no vídeo para ativar o áudio e tente novamente.');
      let stretch;
      let connected = false;
      try {
        if (needsPitch) {
          // Worklet/WASM/CSP failure must precede MediaElementAudioSource ownership.
          stretch = await createStretchNode();
          await timeout(stretch.schedule({active: true, semitones: pitch}), 4000,
            'O processador de tom não respondeu.');
        }
        if (disposed || video !== element || videoId !== id || isAd || (needsPitch && pitch === 0))
          throw new Error('A seleção de vídeo mudou. Tente novamente.');
        if (!safeSource(element)) throw new Error('Esta fonte de áudio não permite alterar o tom.');
        requireSound(element);
        const input = audioContext.createAnalyser();
        const output = audioContext.createAnalyser();
        const keyAnalyser = audioContext.createAnalyser();
        keyAnalyser.fftSize = 16384;
        keyAnalyser.smoothingTimeConstant = 0.7;
        input.fftSize = output.fftSize = probeEnabled ? 8192 : 512;
        if (probeEnabled) input.smoothingTimeConstant = output.smoothingTimeConstant = 0;
        const dryGain = audioContext.createGain();
        const wetGain = audioContext.createGain();
        const low = audioContext.createBiquadFilter();
        low.type = 'lowshelf';
        low.frequency.value = 200;
        low.gain.value = bass;
        const high = audioContext.createBiquadFilter();
        high.type = 'highshelf';
        high.frequency.value = 3000;
        high.gain.value = treble;
        const midFilter = audioContext.createBiquadFilter();
        midFilter.type = 'peaking';
        midFilter.frequency.value = 1000;
        midFilter.Q.value = 0.8;
        midFilter.gain.value = mid;
        const echoDelay = audioContext.createDelay(0.6);
        echoDelay.delayTime.value = 0.28;
        const echoGain = audioContext.createGain();
        echoGain.gain.value = delay;
        const feedbackGain = audioContext.createGain();
        feedbackGain.gain.value = feedback;
        const chorusDelay = audioContext.createDelay(0.05);
        chorusDelay.delayTime.value = 0.018;
        const chorusGain = audioContext.createGain();
        chorusGain.gain.value = chorus;
        const chorusLfo = audioContext.createOscillator();
        chorusLfo.frequency.value = 0.8;
        const chorusDepth = audioContext.createGain();
        chorusDepth.gain.value = 0.004;
        const convolver = audioContext.createConvolver();
        convolver.buffer = impulseResponse();
        const reverbGain = audioContext.createGain();
        reverbGain.gain.value = reverb;
        const master = audioContext.createGain();
        master.gain.value = decibelGain(gain);
        // Test-only observation of the actual mixed output, including bypass/EQ.
        const probeFinal = probeEnabled ? audioContext.createAnalyser() : null;
        if (probeFinal) {
          probeFinal.fftSize = 8192;
          probeFinal.smoothingTimeConstant = 0;
        }
        dryGain.gain.value = 1;
        wetGain.gain.value = 0;
        input.connect(keyAnalyser).connect(dryGain).connect(low);
        // EQ/effects may create this graph before pitch is first requested.
        // Keep its wet output wired even when the processor is attached later.
        wetGain.connect(low);
        if (stretch) input.connect(stretch).connect(output).connect(wetGain);
        // Last irreversible operation, after the entire output graph is ready.
        const source = audioContext.createMediaElementSource(element);
        const graph = {
          element, source, input, output, keyAnalyser, probeFinal,
          keySpectrum: new Float32Array(keyAnalyser.frequencyBinCount),
          stretch, dry: dryGain, wet: wetGain,
          low, mid: midFilter, high, master, echoDelay, echoGain, feedbackGain,
          chorusDelay, chorusGain, chorusLfo, chorusDepth, convolver, reverbGain,
          retired: false, lfoStarted: false,
          samples: new Float32Array(512), audible: false, failed: false, dspConnected: !!stretch,
          appliedPitch: pitch, acknowledged: false, silentSince: null,
          effectsEpoch, effectsFailed: false,
          ...(probeEnabled ? {
            probeSpectrum: new Float32Array(4096), probeWave: new Float32Array(8192),
          } : {}),
        };
        graphs.set(element, graph);
        allGraphs.add(graph);
        try {
          connectEffects(graph);
          source.connect(input);
          chorusLfo.start();
          graph.lfoStarted = true;
        } catch (error) {
          source.disconnect();
          source.connect(audioContext.destination);
          graph.failed = true;
          graph.effectsFailed = true;
          throw error;
        }
        connected = true;
        if (stretch) listenForProcessorError(graph);
        return graph;
      } finally {
        if (!connected && stretch) stretch.disconnect();
      }
    })();
    preparing.set(element, pending);
    try {
      return await pending;
    } finally {
      preparing.delete(element);
    }
  }

  async function createStretchNode() {
    const createStretch = window.TransponoCreateStretch || globalThis.SignalsmithStretch || window.SignalsmithStretch;
    if (typeof createStretch !== 'function')
      throw new Error('A alteração de tom não está disponível neste navegador.');
    const creation = Promise.resolve(createStretch(audioContext, {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
    }));
    let expired = false;
    creation.then(node => { if (expired) node.disconnect(); }, () => {});
    try {
      return await timeout(creation, 8000, 'O processamento de tom não pôde ser iniciado.');
    } catch (error) {
      expired = true;
      throw error;
    }
  }

  function listenForProcessorError(graph) {
    graph.stretch.addEventListener('processorerror', () => {
      graph.failed = true;
      dry(graph, true);
      if (graph.element === video)
        unavailable('O processamento parou. O áudio original foi mantido. Reabra o vídeo para tentar novamente.');
      post();
    });
  }

  async function attachStretch(graph) {
    const stretch = await createStretchNode();
    if (disposed || graph.element !== video || isAd || pitch === 0) {
      stretch.disconnect();
      throw new Error('A seleção de vídeo mudou. Aplique o tom novamente.');
    }
    graph.stretch = stretch;
    graph.input.connect(stretch).connect(graph.output).connect(graph.wet);
    graph.dspConnected = true;
    listenForProcessorError(graph);
  }

  async function applyPitch() {
    const element = video;
    const token = ++revision;
    pitchCommandIntent = {commandId: activeDispatchId, token, element};
    const requested = pitch;
    if (!element || isAd || disposed) return;
    if (requested === 0) {
      dry(graphs.get(element), true);
      pitchStatus = 'idle';
      pitchMessage = '';
      return;
    }
    pitchStatus = 'loading';
    pitchMessage = 'A preparar a alteração de tom…';
    const previous = graphs.get(element);
    const keepProcessed = !!previous && previous.audible &&
      previous.acknowledged && previous.dspConnected && !previous.failed;
    if (previous && !keepProcessed) {
      previous.acknowledged = false;
      dry(previous);
    }
    try {
      requireSound(element);
      if (!safeSource(element)) throw new Error('Este vídeo não disponibiliza áudio para alterar o tom neste dispositivo.');
      const graph = await prepareGraph(element);
      if (token !== revision || disposed || element !== video || isAd) return;
      if (graph.failed) throw new Error('O processamento parou. Reabra o vídeo para tentar novamente.');
      await timeout(audioContext.resume(), 4000, 'Toque no vídeo para ativar o áudio e tente novamente.');
      if (!graph.dspConnected) {
        graph.input.connect(graph.stretch);
        graph.stretch.connect(graph.output).connect(graph.wet);
        graph.dspConnected = true;
      }
      const scheduledAt = now();
      await timeout(graph.stretch.schedule({active: true, semitones: requested}), 4000,
        'O processador de tom não respondeu.');
      if (token !== revision || disposed || element !== video || isAd) return;
      graph.appliedPitch = requested;
      graph.acknowledged = true;
      graph.silentSince = null;
      graph.noSignalPlayingMs = 0;
      graph.lastConfirmationTick = null;
      graph.checkAfter = scheduledAt + 250;
      if (keepProcessed && graph === previous && graph.audible) {
        // This processor was already producing audio. Updating its pitch does
        // not require switching back to the unprocessed route or re-priming it.
        pitchStatus = 'active';
        pitchMessage = 'Tom aplicado · processamento experimental';
      } else {
        // First activation still needs real output before leaving the dry route.
        dry(graph);
        pitchMessage = 'Tom preparado; a aguardar sinal de áudio.';
      }
    } catch (error) {
      if (token === revision && !disposed && element === video && !isAd) {
        unavailable(error.message || 'Não foi possível alterar o tom.');
        if (error.code === 'sound-muted') pitchStatus = 'idle';
      }
    }
    post();
  }

  function hasSignal(analyser, samples) {
    analyser.getFloatTimeDomainData(samples);
    return samples.some(sample => Number.isFinite(sample) && Math.abs(sample) > 0.00001);
  }

  function probeMeasurement(analyser, graph) {
    analyser.getFloatFrequencyData(graph.probeSpectrum);
    const bins = graph.probeSpectrum;
    let peak = 1;
    for (let i = 2; i < bins.length - 1; i += 1) {
      if (bins[i] > bins[peak]) peak = i;
    }
    let hz = null;
    if (Number.isFinite(bins[peak]) && bins[peak] > -90) {
      const left = bins[peak - 1];
      const center = bins[peak];
      const right = bins[peak + 1];
      const curvature = left - 2 * center + right;
      const offset = Number.isFinite(curvature) && curvature < 0
        ? Math.max(-0.5, Math.min(0.5, 0.5 * (left - right) / curvature)) : 0;
      hz = (peak + offset) * audioContext.sampleRate / analyser.fftSize;
    }
    analyser.getFloatTimeDomainData(graph.probeWave);
    const energy = graph.probeWave.reduce((total, sample) => total + sample * sample, 0);
    return {hz, rms: Math.sqrt(energy / graph.probeWave.length)};
  }

  function probeSnapshot() {
    const graph = video && graphs.get(video);
    const input = graph ? probeMeasurement(graph.input, graph) : {hz: null, rms: null};
    const output = graph ? probeMeasurement(graph.output, graph) : {hz: null, rms: null};
    const finalOutput = graph && graph.probeFinal
      ? probeMeasurement(graph.probeFinal, graph) : {hz: null, rms: null};
    return {
      inputHz: input.hz, outputHz: output.hz, inputRms: input.rms, outputRms: output.rms,
      finalHz: finalOutput.hz, finalRms: finalOutput.rms,
      sampleRate: audioContext ? audioContext.sampleRate : null,
      contextState: audioContext ? audioContext.state : 'absent',
      dryGain: graph ? graph.dry.gain.value : null,
      wetGain: graph ? graph.wet.gain.value : null,
      dspConnected: graph ? graph.dspConnected : false,
      effects: graph ? {
        gain: graph.master.gain.value,
        chorus: graph.chorusGain.gain.value,
        feedback: graph.feedbackGain.gain.value,
        delay: graph.echoGain.gain.value,
        reverb: graph.reverbGain.gain.value,
      } : null,
      sourceCount: allGraphs.size,
    };
  }

  function tick() {
    refresh();
    if (disposed || !allowedPage()) return;
    updateKeyDetection();
    if (video && !isAd) {
      const graph = graphs.get(video);
      if (pitchStatus === 'loading' && (video.muted || video.volume === 0)) {
        unavailable('Ative o som do vídeo e tente alterar o tom novamente.');
        pitchStatus = 'idle';
      }
      if (graph && (video.paused || audioContext.state !== 'running')) {
        graph.lastConfirmationTick = null;
      }
      if (graph && graph.acknowledged && !graph.failed && pitch !== 0 && graph.appliedPitch === pitch &&
          safeSource(video) && !video.paused && audioContext.state === 'running' &&
          now() >= graph.checkAfter && pitchStatus !== 'unavailable') {
        if (hasSignal(graph.output, graph.samples)) {
          if (!graph.audible) wet(graph);
          graph.silentSince = null;
          graph.noSignalPlayingMs = 0;
          graph.lastConfirmationTick = null;
          pitchStatus = 'active';
          pitchMessage = 'Tom aplicado · processamento experimental';
        } else if (hasSignal(graph.input, graph.samples)) {
          if (graph.silentSince === null) graph.silentSince = now();
          if (now() - graph.silentSince >= 2500) {
            unavailable('O processador não produziu áudio. O áudio original foi mantido.');
          }
        } else {
          graph.silentSince = null; // Genuine quiet passages are not DSP failures.
          if (pitchStatus === 'loading') {
            if (graph.lastConfirmationTick !== null) {
              // Bound elapsed playable time, excluding pauses/background throttling.
              graph.noSignalPlayingMs += Math.min(500, now() - graph.lastConfirmationTick);
            }
            graph.lastConfirmationTick = now();
            if (graph.noSignalPlayingMs >= 10000) {
              unavailable('Não foi possível confirmar áudio processável neste vídeo. Tente novamente durante a reprodução.');
            }
          }
        }
      }
      if (pendingLoopReturn && !validLoopReturn(pendingLoopReturn)) invalidateLoopObservation();
      if (pendingLoopReturn && (video.paused ||
          now() - pendingLoopReturn.startedAt >= 5000)) {
        // A long buffer/paused return lacks timely confirmation, but is not a
        // new source or external seek. Lose this repetition, not the epoch.
        discardLoopReturn();
      }
      if (loopWanted && loopA !== null && loopB !== null && !video.paused &&
          playbackReady() && !pendingLoopReturn) {
        if (positionOf(video) >= loopB) returnLoopToStart();
        else if (nearLoopStart()) cycleArmed = true;
      }
    }
    post();
  }

  function requireVideo() {
    if (!video) throw new Error('Escolha e abra um vídeo primeiro.');
  }

  function requirePractice() {
    requireVideo();
    if (isAd) throw new Error('Aguarde o fim do anúncio para usar os controles de prática.');
  }

  function numberIn(value, min, max, name) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
      throw new RangeError(name + ' fora do intervalo permitido.');
    }
    return value;
  }

  function requireTimeline() {
    requirePractice();
    if (!durationOf(video)) throw new Error('Aguarde a duração do vídeo. Este controle não está disponível em transmissões ao vivo.');
  }

  async function execute(request) {
    if (disposed || !allowedPage()) throw new Error('O navegador de prática está fechado.');
    refresh();
    if (!request || typeof request.action !== 'string') throw new TypeError('Comando inválido.');
    const effectIntent = {epoch: effectsEpoch, element: video, id: videoId,
      source: sourceOf(video), commandId: activeDispatchId};
    if (Object.hasOwn(desiredEffects(), request.action)) effectIntents.set(request.action, effectIntent);
    function checkEffect(graph) {
      refresh();
      if (effectIntents.get(request.action) !== effectIntent || graph.effectsFailed ||
          !validEffectsContext(effectIntent.epoch, effectIntent.element, effectIntent.id, effectIntent.source)) {
        throw new Error('O ajuste de áudio foi substituído ou o vídeo mudou.');
      }
    }
    switch (request.action) {
      case 'pause':
        invalidatePlaybackIntent();
        if (pendingLoopReturn) discardLoopReturn();
        if (video) video.pause();
        break;
      case 'play':
        requireVideo();
        // Flutter sends an explicit intent, never a toggle based on a possibly
        // stale snapshot. Repeated Play preserves playback and the mute state.
        if (video.paused || video.ended) await playCurrentVideo();
        break;
      case 'playPause':
        requireVideo();
        if (video.paused || video.ended) {
          await playCurrentVideo();
        } else {
          invalidatePlaybackIntent();
          video.pause();
        }
        break;
      case 'unmute':
        requireVideo();
        video.muted = false;
        if (video.volume === 0) video.volume = 1;
        await playCurrentVideo();
        pitchMessage = '';
        break;
      case 'pitch':
        requirePractice();
        pitch = numberIn(request.value, -12, 12, 'Tom');
        await applyPitch();
        break;
      case 'bass':
      case 'mid':
      case 'treble': {
        requirePractice();
        const value = numberIn(request.value, -12, 12, 'Equalizador');
        if (!safeSource(video))
          throw new Error('Este vídeo não disponibiliza áudio para o equalizador neste dispositivo.');
        requireSound(video);
        const graph = await prepareGraph(video, false);
        checkEffect(graph);
        if (request.action === 'bass') {
          graph.low.gain.setValueAtTime(value, audioContext.currentTime);
          bass = value;
        } else if (request.action === 'mid') {
          graph.mid.gain.setValueAtTime(value, audioContext.currentTime);
          mid = value;
        } else {
          graph.high.gain.setValueAtTime(value, audioContext.currentTime);
          treble = value;
        }
        break;
      }
      case 'gain':
      case 'chorus':
      case 'feedback':
      case 'delay':
      case 'reverb': {
        requirePractice();
        const limits = {
          gain: [-12, 6], chorus: [0, 0.5], feedback: [0, 0.55],
          delay: [0, 0.35], reverb: [0, 0.4],
        };
        const [minimum, maximum] = limits[request.action];
        const value = numberIn(request.value, minimum, maximum, request.action);
        if (!safeSource(video))
          throw new Error('Este vídeo não disponibiliza áudio para efeitos neste dispositivo.');
        requireSound(video);
        const graph = await prepareGraph(video, false);
        checkEffect(graph);
        switch (request.action) {
          case 'gain':
            setEffectParam(graph.master.gain, decibelGain(value), true);
            gain = value;
            break;
          case 'chorus':
            setEffectParam(graph.chorusGain.gain, value, true);
            chorus = value;
            break;
          case 'feedback':
            setEffectParam(graph.feedbackGain.gain, value, true);
            feedback = value;
            break;
          case 'delay':
            setEffectParam(graph.echoGain.gain, value, true);
            delay = value;
            break;
          case 'reverb':
            setEffectParam(graph.reverbGain.gain, value, true);
            reverb = value;
            break;
        }
        break;
      }
      case 'speed': {
        requirePractice();
        const value = numberIn(request.value, 0.25, 2, 'Velocidade');
        if (value !== 1 && !preservesPitch(video)) throw new Error('Este navegador não consegue preservar o tom ao mudar a velocidade.');
        preservesPitch(video);
        video.playbackRate = value;
        speed = video.playbackRate;
        break;
      }
      case 'seekBy': {
        requireTimeline();
        const delta = numberIn(request.value, -86400, 86400, 'Avanço');
        const target = Math.max(0, Math.min(durationOf(video), positionOf(video) + delta));
        invalidateLoopObservation();
        if (loopWanted && (target < loopA || target >= loopB)) loopWanted = false;
        video.currentTime = target;
        break;
      }
      case 'seekTo': {
        requireTimeline();
        const seconds = numberIn(request.value, -Number.MAX_VALUE, Number.MAX_VALUE, 'Posição');
        const target = Math.max(0, Math.min(durationOf(video), seconds));
        invalidateLoopObservation();
        if (loopWanted && (target < loopA || target >= loopB)) loopWanted = false;
        video.currentTime = target;
        break;
      }
      case 'markA':
        requireTimeline();
        invalidateLoopObservation();
        loopA = Math.min(positionOf(video), durationOf(video));
        if (loopB !== null && loopB - loopA < minLoopSeconds) {
          loopB = null;
          loopWanted = false;
        }
        break;
      case 'markB': {
        requireTimeline();
        const candidate = Math.min(positionOf(video), durationOf(video));
        if (loopA === null || candidate - loopA < minLoopSeconds) {
          throw new Error('Marque A primeiro e coloque B pelo menos 0,25 s depois de A.');
        }
        invalidateLoopObservation();
        loopB = candidate;
        loopWanted = true;
        break;
      }
      case 'toggleLoop':
        requireTimeline();
        if (loopA === null || loopB === null || loopB - loopA < minLoopSeconds) {
          throw new Error('Marque A e B antes de ativar o loop.');
        }
        invalidateLoopObservation();
        loopWanted = !loopWanted;
        if (loopWanted && (positionOf(video) < loopA || positionOf(video) >= loopB)) video.currentTime = loopA;
        break;
      case 'clearLoop':
        invalidateLoopObservation();
        loopWanted = false;
        loopA = loopB = null;
        break;
      default:
        throw new Error('Comando não reconhecido.');
    }
    post();
    return snapshot();
  }

  async function command(request) {
    try {
      return await execute(request);
    } catch (error) {
      pitchMessage = error.message || 'Não foi possível aplicar este controle.';
      post();
      throw error;
    }
  }

  // WebView evaluateJavascript does not await returned JS promises. Dart polls
  // this bounded, page-local acknowledgement instead of treating dispatch as
  // completion. IDs are idempotent while retained; forgetting never resurrects
  // an entry when an old asynchronous command eventually finishes.
  function dispatch(id, request) {
    if (typeof id !== 'string' || id.length === 0 || id.length > 100) {
      throw new TypeError('Identificador de comando inválido.');
    }
    if (commandResults.has(id)) return true;
    if (commandResults.size >= maxCommandResults) {
      for (const [key, result] of commandResults) {
        if (result.status !== 'pending') {
          commandResults.delete(key);
          break;
        }
      }
    }
    if (commandResults.size >= maxCommandResults) {
      throw new Error('Demasiados comandos pendentes.');
    }
    const pending = {status: 'pending'};
    commandResults.set(id, pending);
    // Propagate ownership only through synchronous submission. Keeping this
    // global set during await would misattribute independent user commands.
    const previousDispatchId = activeDispatchId;
    let operation;
    try {
      activeDispatchId = id;
      operation = command(request);
    } finally {
      activeDispatchId = previousDispatchId;
    }
    void operation.then(() => {
      if (commandResults.get(id) === pending) commandResults.set(id, {status: 'done'});
    }, error => {
      if (commandResults.get(id) === pending) {
        commandResults.set(id, {
          status: 'error', error: String(error && error.message || 'Comando falhou.').slice(0, 500),
        });
      }
    });
    return true;
  }

  function commandResult(id) {
    const result = commandResults.get(id);
    return result ? {...result, snapshot: disposed ? null : snapshot()} : null;
  }

  function forgetCommand(id) {
    return commandResults.delete(id);
  }

  function cancelCommand(id) {
    if (commandResults.get(id)?.status !== 'pending') return false;
    commandResults.set(id, {status: 'error', error: 'Comando cancelado.'});
    for (const [action, intent] of effectIntents) {
      if (intent.commandId === id) effectIntents.delete(action);
    }
    if (playbackIntent && playbackIntent.commandId === id) {
      const element = playbackIntent.element;
      invalidatePlaybackIntent();
      element.pause();
    }
    if (pitchCommandIntent && pitchCommandIntent.commandId === id &&
        pitchCommandIntent.token === revision) {
      revision += 1;
      dry(graphs.get(pitchCommandIntent.element), true);
      pitch = 0;
      pitchStatus = 'idle';
      pitchMessage = 'Alteração de tom cancelada. O áudio original foi mantido.';
      pitchCommandIntent = null;
    }
    return true;
  }

  function dispose() {
    revision += 1;
    invalidatePlaybackIntent();
    disposed = true;
    clearInterval(timer);
    timer = null;
    if (video) video.pause();
    resetPractice(video);
    allGraphs.forEach(graph => dry(graph, true));
    // Closing the context would permanently silence already attached elements.
    // Keep their dry routes until this document is destroyed; no playback starts.
  }

  function activate() {
    disposed = false;
    if (timer === null) timer = setInterval(tick, 200);
    tick();
  }

  window.TransponoMedia = Object.freeze({
    command, dispatch, commandResult, cancelCommand, forgetCommand, snapshot, dispose, _activate: activate,
  });
  activate();
})();
