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

  try {
    port = browser.runtime.connectNative('transpono');
  } catch (_) {
    port = null;
    return;
  }
  port.onDisconnect.addListener(() => { port = null; });
  port.onMessage.addListener(message => {
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
})();
