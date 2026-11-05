/* Page-world side of the Transpono extension. Relays popup requests to the
 * page-local TransponoMedia bridge (apps/mobile/assets/web/transpono_media.js).
 * No media is captured, fetched or exported. */
(function () {
  'use strict';
  if (window.__transponoExtShim) return;
  window.__transponoExtShim = true;

  const TAG = 'transpono-ext';
  const origin = window.location.origin;

  function state() {
    const media = window.TransponoMedia;
    return media && typeof media.snapshot === 'function' ? media.snapshot() : null;
  }

  window.addEventListener('message', async event => {
    const data = event.data;
    if (event.source !== window || !data || data.tag !== TAG || data.dir !== 'toPage') return;
    let reply;
    try {
      if (data.kind === 'command') {
        const media = window.TransponoMedia;
        if (!media) throw new Error('A ponte de áudio ainda não carregou nesta página.');
        await media.command(data.request);
      }
      reply = {ok: true, state: state()};
    } catch (error) {
      reply = {ok: false, error: String((error && error.message) || error).slice(0, 300), state: state()};
    }
    window.postMessage({tag: TAG, dir: 'toExt', id: data.id, ...reply}, origin);
  });
})();
