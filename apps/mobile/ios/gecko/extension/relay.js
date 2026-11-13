/* Transpono Gecko bridge (built-in extension content script).
 *
 * Plays the role of WKWebView's evaluateJavaScript for the Transpono app:
 * the app sends script text through a native port and this content script
 * evaluates it in its own sandbox, so the app's existing YouTube bridge
 * (assets/web/transpono_media.js and friends) runs unchanged. Scripts share
 * this sandbox, see the page DOM through Xray wrappers, and are not subject
 * to the page's CSP. No media is captured, fetched or exported.
 */
'use strict';
(() => {
  if (window.top !== window) return;

  const indirectEval = eval;
  let port = null;

  // Same contract as WKWebView: plain JSON-like values; promises are not awaited.
  function plain(value) {
    if (value === undefined || value === null) return null;
    switch (typeof value) {
      case 'string':
      case 'boolean':
        return value;
      case 'number':
        return Number.isFinite(value) ? value : null;
      case 'function':
      case 'symbol':
      case 'bigint':
        return null;
    }
    if (typeof value.then === 'function') return null;
    try {
      return JSON.parse(JSON.stringify(value));
    } catch (_) {
      return String(value);
    }
  }

  function send(message) {
    try {
      if (port) port.postMessage(message);
    } catch (_) {
      port = null;
    }
  }

  // The app's bridge posts snapshots through window.TransponoBridge, like a
  // WebView JavaScript channel.
  window.TransponoBridge = Object.freeze({
    postMessage(json) {
      send({type: 'channel', name: 'TransponoBridge', message: String(json)});
    },
  });
  // Spotify's page buttons and the finger on its open player.
  window.TransponoSpotify = Object.freeze({
    postMessage(text) {
      send({type: 'channel', name: 'TransponoSpotify', message: String(text)});
    },
  });

  try {
    port = browser.runtime.connectNative('transpono');
  } catch (_) {
    port = null;
    return;
  }
  port.onDisconnect.addListener(() => { port = null; });
  port.onMessage.addListener(message => {
    // Google session copied from Safari's engine: only the background
    // script may set cookies (cookies API), so hand it over.
    if (message && message.type === 'setCookies') {
      browser.runtime.sendMessage({type: 'setCookies', cookies: message.cookies}).then(
        done => send({type: 'cookiesSet', ok: (done && done.ok) || 0, failed: (done && done.failed) || 0}),
        error => send({type: 'cookiesSet', ok: 0, failed: -1, error: String(error).slice(0, 200)}));
      return;
    }
    // iPhone's small window (experimental): its buttons act on the video.
    if (message && message.type === 'pipCommand') {
      pipCommand(message);
      return;
    }
    if (!message || message.type !== 'eval') return;
    let reply;
    try {
      reply = {type: 'result', id: message.id, ok: true, value: plain(indirectEval(String(message.code)))};
    } catch (error) {
      reply = {type: 'result', id: message.id, ok: false,
        error: String((error && error.message) || error).slice(0, 500)};
    }
    send(reply);
  });
  send({type: 'ready', url: window.location.href});

  // iPhone's small window (experimental, Ajustes → Mais). Only while the
  // app says so for this page (window.__transponoPipFrames: the playing
  // video's page, setting on): a small copy of the video's current picture,
  // a few times a second, goes to the app, which shows it in the system's
  // picture-in-picture. Nothing is stored or sent anywhere else.
  const pipVideo = () =>
    document.querySelector('video.html5-main-video') || document.querySelector('video');
  let pipCanvas = null;
  let pipContext = null;
  let pipPausedSent = 0;
  function pipTick() {
    if (!window.__transponoPipFrames || !port) return;
    try {
      const video = pipVideo();
      if (!video || !video.videoWidth || !video.videoHeight || video.readyState < 2) return;
      const playing = !video.paused && !video.ended;
      // Paused: one picture a second is enough.
      if (!playing) {
        const now = Date.now();
        if (now - pipPausedSent < 1000) return;
        pipPausedSent = now;
      }
      const width = 360;
      const height = Math.max(2, Math.round(width * video.videoHeight / video.videoWidth / 2) * 2);
      if (!pipCanvas) {
        pipCanvas = document.createElement('canvas');
        pipContext = pipCanvas.getContext('2d', {alpha: false});
      }
      if (pipCanvas.width !== width) pipCanvas.width = width;
      if (pipCanvas.height !== height) pipCanvas.height = height;
      pipContext.drawImage(video, 0, 0, width, height);
      const url = pipCanvas.toDataURL('image/jpeg', 0.62);
      send({
        type: 'pipFrame',
        image: url.slice(url.indexOf(',') + 1),
        playing,
        time: Number.isFinite(video.currentTime) ? video.currentTime : 0,
        duration: Number.isFinite(video.duration) ? video.duration : 0,
      });
    } catch (_) {}
  }
  setInterval(pipTick, 100);

  function pipCommand(message) {
    try {
      const video = pipVideo();
      if (!video) return;
      if (message.action === 'play') {
        const started = video.play();
        if (started && typeof started.catch === 'function') started.catch(() => {});
      } else if (message.action === 'pause') {
        video.pause();
      } else if (message.action === 'skip') {
        const by = Number(message.seconds) || 0;
        const end = Number.isFinite(video.duration) ? video.duration : Infinity;
        video.currentTime = Math.max(0, Math.min(end, video.currentTime + by));
      }
    } catch (_) {}
  }
})();
