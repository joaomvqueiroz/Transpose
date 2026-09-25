# Browser audio dependency

Signalsmith Stretch Web 1.3.2, copyright 2022 Geraint Luff / Signalsmith Audio Ltd.
MIT license; full text accompanies this file in `SIGNALSMITH_LICENSE.txt`.

- Upstream: https://github.com/Signalsmith-Audio/signalsmith-stretch
- Vendored release: https://cdn.jsdelivr.net/npm/signalsmith-stretch@1.3.2/SignalsmithStretch.js
- Upstream SHA-256: `FE0E23B6BB5DBFFB231A91E7DC39F9D2A7D10C7F793FB0237D819CA748F7F778`
- Bundled SHA-256: `2B052A348C824AE35E0CDBE087769CD83777D3B851EFB94CD8A7F158159FCECF`
- Local change: expose `createNode.wasmModuleFactory = Module` for the page-local
  compatibility adapter. The WASM binary and DSP algorithm are unchanged.

The UMD bundle contains its WASM/AudioWorklet implementation. It is bundled with
the app and does not load a DSP script from a CDN at runtime. Its license is
independent of the terms of any media service viewed in the browser.

`transpono_stretch.js` prefers AudioWorklet. When a document disallows its Blob
module but permits WASM, the adapter runs the same DSP with ScriptProcessorNode
(2048-frame buffer, UI thread). It neither weakens CSP nor injects a remote URL.
This compatibility path has more latency and greater UI-load sensitivity than
AudioWorklet; it is experimental, not a low-latency quality guarantee.
