/* Content-script side: forwards popup messages to the page world and back.
 * If the browser ignores "world": "MAIN", injects the same packaged scripts
 * from the extension itself (never from a remote URL). */
(function () {
  'use strict';
  const api = globalThis.browser || globalThis.chrome;
  const TAG = 'transpono-ext';
  const origin = window.location.origin;
  const pending = new Map();
  let counter = 0;
  let injecting = null;

  window.addEventListener('message', event => {
    const data = event.data;
    if (event.source !== window || !data || data.tag !== TAG || data.dir !== 'toExt') return;
    const resolve = pending.get(data.id);
    if (!resolve) return;
    pending.delete(data.id);
    resolve({ok: !!data.ok, error: data.error || null, state: data.state || null});
  });

  function toPage(kind, request, timeoutMs) {
    return new Promise(resolve => {
      const id = 'm' + Date.now().toString(36) + '-' + (counter += 1);
      pending.set(id, resolve);
      window.postMessage({tag: TAG, dir: 'toPage', id, kind, request}, origin);
      setTimeout(() => {
        if (pending.delete(id)) resolve({ok: false, timeout: true, error: 'A página não respondeu.', state: null});
      }, timeoutMs);
    });
  }

  function loadScript(file) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = api.runtime.getURL(file);
      script.onload = () => { script.remove(); resolve(); };
      script.onerror = () => { script.remove(); reject(new Error('Não foi possível carregar ' + file)); };
      (document.head || document.documentElement).appendChild(script);
    });
  }

  async function ensurePageBridge() {
    const ping = await toPage('ping', null, 800);
    if (!ping.timeout) return;
    if (!injecting) {
      injecting = (async () => {
        for (const file of [
          'web/SignalsmithStretch.js',
          'web/transpono_stretch.js',
          'web/transpono_key_detector.js',
          'web/transpono_media.js',
          'src/page_shim.js',
        ]) await loadScript(file);
      })().catch(error => { injecting = null; throw error; });
    }
    await injecting;
  }

  api.runtime.onMessage.addListener(message => {
    if (!message || message.tag !== TAG) return undefined;
    return (async () => {
      try {
        await ensurePageBridge();
      } catch (error) {
        return {ok: false, error: String(error.message || error), state: null};
      }
      // Pitch preparation may take a few seconds (worklet/WASM start-up).
      return toPage(message.kind, message.request || null, message.kind === 'command' ? 9000 : 2000);
    })();
  });
})();
