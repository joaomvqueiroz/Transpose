'use strict';
const api = globalThis.browser || globalThis.chrome;
const TAG = 'transpono-ext';

// Same actions and ranges as TransponoMedia.execute (transpono_media.js).
const EFFECTS = [
  {key: 'gain', label: 'Ganho', min: -12, max: 6, step: 0.5, show: v => fmtSigned(v, 1)},
  {key: 'bass', label: 'Graves', min: -12, max: 12, step: 1, show: v => fmtSigned(v, 0)},
  {key: 'mid', label: 'Médios', min: -12, max: 12, step: 1, show: v => fmtSigned(v, 0)},
  {key: 'treble', label: 'Agudos', min: -12, max: 12, step: 1, show: v => fmtSigned(v, 0)},
  {key: 'chorus', label: 'Chorus', min: 0, max: 0.5, step: 0.01, show: percentOf(0.5)},
  {key: 'feedback', label: 'Feedback', min: 0, max: 0.55, step: 0.01, show: percentOf(0.55)},
  {key: 'delay', label: 'Delay', min: 0, max: 0.35, step: 0.01, show: percentOf(0.35)},
  {key: 'reverb', label: 'Reverb', min: 0, max: 0.4, step: 0.01, show: percentOf(0.4)},
];
const DEFAULTS = {pitch: 0, speed: 1, gain: 0, bass: 0, mid: 0, treble: 0, chorus: 0, feedback: 0, delay: 0, reverb: 0};

function fmtSigned(v, digits) {
  const n = Number(v) || 0;
  const s = n.toFixed(digits);
  return n > 0 ? '+' + s : s;
}
function percentOf(max) { return v => Math.round((Number(v) || 0) / max * 100) + '%'; }

const $ = id => document.getElementById(id);
function el(tag, props) { return Object.assign(document.createElement(tag), props); }
const statusEl = $('status');
const dragging = new Set();
let tabId = null;
let lastState = null;
let wantedPitch = 0;
let queue = Promise.resolve();

function setStatus(text, kind) {
  statusEl.textContent = text || '';
  statusEl.className = 'status' + (kind ? ' ' + kind : '');
}

async function send(kind, request) {
  if (tabId === null) throw new Error('Abre um vídeo do YouTube neste separador.');
  const reply = await api.tabs.sendMessage(tabId, {tag: TAG, kind, request});
  if (!reply) throw new Error('A página do YouTube não respondeu. Recarrega a página.');
  if (reply.state) render(reply.state);
  if (!reply.ok) throw new Error(reply.error || 'O controlo falhou.');
  return reply.state;
}

function command(action, value) {
  queue = queue.then(async () => {
    try {
      setStatus(action === 'pitch' ? 'A preparar o tom…' : '');
      await send('command', {action, value});
      if (action !== 'pitch') setStatus('');
    } catch (error) {
      const msg = String(error.message || error);
      // A newer adjustment replaced this one: not an error for the user.
      if (!/substitu/i.test(msg)) setStatus(msg, 'error');
    }
  });
  return queue;
}

function buildEffects() {
  const card = $('effects');
  for (const fx of EFFECTS) {
    const row = el('div', {className: 'row'});
    const input = el('input', {type: 'range', id: 'fx-' + fx.key, min: fx.min, max: fx.max,
      step: fx.step, value: DEFAULTS[fx.key]});
    input.setAttribute('aria-label', fx.label);
    const output = el('output', {id: 'fxv-' + fx.key, className: 'value', textContent: fx.show(DEFAULTS[fx.key])});
    const ctrl = el('div', {className: 'ctrl'});
    ctrl.append(input, output);
    const reset = el('button', {className: 'reset'});
    reset.dataset.reset = fx.key;
    reset.setAttribute('aria-label', 'Repor ' + fx.label.toLowerCase());
    row.append(el('span', {className: 'label', textContent: fx.label}), ctrl, reset);
    card.appendChild(row);
    input.addEventListener('pointerdown', () => dragging.add(fx.key));
    input.addEventListener('input', () => { $('fxv-' + fx.key).textContent = fx.show(input.value); });
    input.addEventListener('change', () => {
      dragging.delete(fx.key);
      command(fx.key, Number(input.value));
    });
  }
}

function snapSpeed(v) {
  const n = Number(v);
  return Math.abs(n - 1) < 0.04 ? 1 : Math.round(n * 100) / 100;
}

function wireControls() {
  $('pitchDown').addEventListener('click', () => setPitch(wantedPitch - 1));
  $('pitchUp').addEventListener('click', () => setPitch(wantedPitch + 1));
  const speed = $('speed');
  speed.addEventListener('pointerdown', () => dragging.add('speed'));
  speed.addEventListener('input', () => {
    const v = snapSpeed(speed.value);
    $('speedValue').textContent = v.toFixed(2).replace(/\.?0+$/, '') + 'x';
  });
  speed.addEventListener('change', () => {
    dragging.delete('speed');
    const v = snapSpeed(speed.value);
    speed.value = v;
    command('speed', v);
  });
  document.body.addEventListener('click', event => {
    const key = event.target && event.target.dataset && event.target.dataset.reset;
    if (!key) return;
    if (key === 'pitch') return setPitch(0);
    if (key === 'speed') { speed.value = 1; $('speedValue').textContent = '1x'; return command('speed', 1); }
    const input = $('fx-' + key);
    input.value = DEFAULTS[key];
    $('fxv-' + key).textContent = EFFECTS.find(f => f.key === key).show(DEFAULTS[key]);
    command(key, DEFAULTS[key]);
  });
}

function setPitch(value) {
  wantedPitch = Math.max(-12, Math.min(12, Math.round(value)));
  $('pitchValue').textContent = fmtSigned(wantedPitch, 0);
  command('pitch', wantedPitch);
}

function render(state) {
  lastState = state;
  const hasVideo = !!state.hasVideo;
  $('title').textContent = hasVideo ? (state.title || 'Vídeo do YouTube') : 'Abre um vídeo do YouTube.';
  document.querySelectorAll('button, input').forEach(el => { el.disabled = !hasVideo || !!state.isAd; });
  if (state.isAd) setStatus('Aguarda o fim do anúncio.');
  const shownPitch = state.pendingPitch !== null && state.pendingPitch !== undefined ? state.pendingPitch : state.pitch;
  if (state.pitchStatus !== 'loading') wantedPitch = Number(shownPitch) || 0;
  $('pitchValue').textContent = fmtSigned(wantedPitch, 0);
  if (state.pitchMessage && !statusEl.classList.contains('error')) {
    setStatus(state.pitchMessage, state.pitchStatus === 'active' ? 'ok' : (state.pitchStatus === 'unavailable' ? 'error' : ''));
  }
  if (!dragging.has('speed') && typeof state.speed === 'number') {
    $('speed').value = state.speed;
    $('speedValue').textContent = Number(state.speed).toFixed(2).replace(/\.?0+$/, '') + 'x';
  }
  const fx = state.audioEffects || {};
  for (const f of EFFECTS) {
    if (dragging.has(f.key) || typeof fx[f.key] !== 'number') continue;
    $('fx-' + f.key).value = fx[f.key];
    $('fxv-' + f.key).textContent = f.show(fx[f.key]);
  }
}

async function init() {
  buildEffects();
  wireControls();
  try {
    const [tab] = await api.tabs.query({active: true, currentWindow: true});
    tabId = tab ? tab.id : null;
    await send('ping');
  } catch (error) {
    setStatus('Abre um vídeo em youtube.com e volta a abrir o Transpono.', 'error');
    document.querySelectorAll('button, input').forEach(el => { el.disabled = true; });
    return;
  }
  setInterval(() => { send('ping').catch(() => {}); }, 1000);
}

init();
