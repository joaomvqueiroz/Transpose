import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'spotify_browser.dart';
import 'spotify_library.dart';
import 'spotify_library_view.dart';
import 'studio_appearance.dart';

/// Experiment, iPhone only: «Sua Biblioteca» opens a screen with two
/// segments, «Spotify» (Spotify's DESKTOP web player, in a second WKWebView
/// with a Mac user agent: its mobile page refuses the library with «Baixar
/// app», the desktop one is said to show it) and «Transpono» (the app's own
/// library, unchanged). False: only the app's own library, as before.
const bool spotifyDesktopLibraryExperiment = true;

/// Safari on a Mac: Spotify serves its full (desktop) web player to it.
const String spotifyDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.0 Safari/605.1.15';

/// Where the desktop library opens.
final Uri spotifyDesktopLibraryStart = Uri.https(
  'open.spotify.com',
  '/collection/playlists',
);

/// Run in the desktop page on load and every second (idempotent):
/// - its sound never plays: every audio/video element muted and paused, and
///   `play()` refused, so this page never sounds nor starts a playback
///   (which would also stop the one in the main page);
/// - only Spotify's own library list on screen, restyled like Transpono's
///   (CSS plus classes on the page's own elements; nothing is read out of
///   it nor stored): the sidebar's «Your Library» panel at device width,
///   full screen, or, for «Músicas» (`window.__tpWant`, set by the app
///   before each run), the main view's Músicas Curtidas; without a sidebar
///   list, the fallback: the 820 px desktop layout scaled down, its main
///   view styled. Top bar, home, search, right panel, player, footer and
///   banners hidden;
/// - the app's chips click Spotify's own filter chips (hidden in the page);
/// - taps on artist, album, playlist and song links (and on play buttons,
///   and double taps on rows) go to the app (`open:URL`) instead of opening
///   here; an in-page route to one of them is reported and undone too;
/// - answers what the page shows, for the note and the diagnostic (`box`:
///   `sidebar`, `grid` or `nenhum`; `rows`: the rows styled).
const String _desktopLibraryScript = r'''
(() => {
  const post = (t) => {
    try { if (window.TransponoDesktop) window.TransponoDesktop.postMessage(t); } catch (_) {}
  };
  const KIND = /^\/(?:intl-[a-z-]+\/)?(track|album|playlist|artist|show|episode)\/([A-Za-z0-9]{8,40})/i;
  const itemOf = (href) => {
    try {
      const u = new URL(href || '', location.href);
      if (u.host !== 'open.spotify.com') return '';
      const m = u.pathname.match(KIND);
      return m ? 'https://open.spotify.com/' + m[1].toLowerCase() + '/' + m[2] : '';
    } catch (_) { return ''; }
  };
  const quiet = (m) => {
    try { m.muted = true; m.volume = 0; if (!m.paused) m.pause(); } catch (_) {}
  };
  const ROWS = '[data-testid="tracklist-row"],[role="row"],[data-testid="list-row"],' +
    '[data-encore-id="listRow"],[data-encore-id="card"],[data-testid="card"],[role="listitem"],li';
  // The item a row or card stands for: its first non-artist link, else any
  // item link, else a «spotify:kind:id» in its markup (the sidebar rows).
  const itemIn = (box) => {
    if (!box || !box.querySelectorAll) return '';
    let any = '';
    for (const a of box.querySelectorAll('a[href]')) {
      const u = itemOf(a.getAttribute('href'));
      if (!u) continue;
      if (u.indexOf('/artist/') < 0) return u;
      if (!any) any = u;
    }
    if (any) return any;
    const m = (box.outerHTML || '').slice(0, 20000)
      .match(/spotify:(track|album|playlist|artist|show|episode):([A-Za-z0-9]{8,40})/);
    return m ? 'https://open.spotify.com/' + m[1] + '/' + m[2] : '';
  };
  if (!window.__tpDesk) {
    window.__tpDesk = true;
    window.__tpDeskMedia = new Set();
    try {
      HTMLMediaElement.prototype.play = function () {
        window.__tpDeskMedia.add(this);
        quiet(this);
        return Promise.reject(new DOMException('No sound in this view', 'NotAllowedError'));
      };
    } catch (_) {}
    const PLAY = '[data-testid="play-button"],[data-testid="control-button-playpause"]';
    // A play button (not «Playlists»: the whole first word).
    const playOf = (t) => {
      const p = t.closest(PLAY);
      if (p) return p;
      const b = t.closest('button[aria-label]');
      return b && /^(tocar|reproduzir|play)(\s|$)/i.test(b.getAttribute('aria-label') || '') ? b : null;
    };
    document.addEventListener('click', (event) => {
      const t = event.target;
      if (!t || !t.closest) return;
      let url = '';
      const play = playOf(t);
      if (play) {
        // Never played here: the item goes to the main page, which plays it.
        event.preventDefault();
        event.stopPropagation();
        url = itemIn(play.closest(ROWS)) || itemOf(location.pathname);
        if (url) post('open:' + url);
        return;
      }
      const a = t.closest('a[href]');
      if (a) url = itemOf(a.getAttribute('href'));
      if (!url && !t.closest('button,[role="button"],input,[role="tab"],[role="checkbox"]')) {
        url = itemIn(t.closest(ROWS));
      }
      if (!url) return;
      event.preventDefault();
      event.stopPropagation();
      post('open:' + url);
    }, true);
    // A double tap on a song row plays it on the desktop page: not here.
    document.addEventListener('dblclick', (event) => {
      const t = event.target;
      if (!t || !t.closest) return;
      const row = t.closest(ROWS);
      if (!row) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
  }
  for (const m of document.querySelectorAll('audio, video')) quiet(m);
  for (const m of (window.__tpDeskMedia || [])) quiet(m);
  const W = window;
  // Whether a box shows text, not counting the text of buttons inside it
  // (a cover's play button).
  const has = (el) => {
    if (!el || !(el.textContent || '').trim()) return false;
    const walk = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let n = walk.nextNode(); n; n = walk.nextNode()) {
      if (!(n.nodeValue || '').trim()) continue;
      const b = n.parentElement ? n.parentElement.closest('button,style,script') : null;
      if (!b || b === el || !el.contains(b)) return true;
    }
    return false;
  };
  // The nearest element holding both a and b.
  const common = (a, b) => {
    let p = a.parentElement;
    while (p && !p.contains(b)) p = p.parentElement;
    return p;
  };
  const SIDE_ROWS = ['[role="row"]', '[data-testid="rootlist-item"]',
    'li[role="listitem"]', '[role="listitem"]'];
  const MAIN_ROWS = ['[data-testid="tracklist-row"]', '[data-encore-id="card"]',
    '[data-testid="card"]', '[role="row"]'];
  // The rows of a list (the first kind found), without header rows.
  const rowsIn = (root, sels) => {
    for (const s of sels) {
      const found = [];
      for (const r of root.querySelectorAll(s)) {
        if (r.querySelector('[role="columnheader"]')) continue;
        found.push(r);
      }
      if (found.length) return found;
    }
    return [];
  };
  const LIB = '[aria-label="Sua Biblioteca" i],[aria-label="A tua biblioteca" i],' +
    '[aria-label="Your Library" i]';
  const SIDE = '#Desktop_LeftSidebar_Id,[data-testid="left-sidebar"],nav[aria-label]';
  const IN_MAIN = 'main,[role="main"],[data-testid="main-view-container"]';
  // The «Your Library» panel of the left sidebar, with its rows.
  const findSide = () => {
    const cands = [];
    for (const el of document.querySelectorAll(LIB)) {
      cands.push(el);
      const sec = el.closest('section,[role="region"]');
      if (sec) cands.push(sec);
      const side = el.closest(SIDE);
      if (side) cands.push(side);
    }
    for (const el of document.querySelectorAll(SIDE)) cands.push(el);
    for (const el of document.querySelectorAll('[class*="main-yourLibraryX"]')) {
      const side = el.closest(SIDE);
      if (side) cands.push(side);
    }
    for (const el of cands) {
      if (el.closest(IN_MAIN)) continue;
      const rows = rowsIn(el, SIDE_ROWS);
      if (rows.length) return { el: el, rows: rows };
    }
    return null;
  };
  // The main view (a /collection/* page), with its track rows or cards.
  const findMain = () => {
    for (const el of document.querySelectorAll(
        '[data-testid="main-view-container"],.main-view-container,main,[role="main"]')) {
      const rows = rowsIn(el, MAIN_ROWS);
      if (rows.length) return { el: el, rows: rows };
    }
    return null;
  };
  const INNER = ['tp-main', 'tp-line', 'tp-multi', 'tp-cover', 'tp-round', 'tp-text',
    'tp-name', 'tp-sub', 'tp-hide', 'tp-span'];
  const OUTER = ['tp-root', 'tp-side', 'tp-grid', 'tp-path', 'tp-fill', 'tp-scroller',
    'tp-list', 'tp-row', 'tp-wrap', 'tp-abs', 'tp-out'];
  // Transpono's subtitle prefix, from the kind in the row's link.
  const KIND_LABEL = { track: 'Música', album: 'Álbum', playlist: 'Playlist',
    artist: 'Artista', show: 'Podcast', episode: 'Episódio' };
  const KIND_TEXT = /^(música|musica|song|álbum|album|playlist|artista|artist|podcast|episódio|episodio|episode|single|ep)(\s|$|[•·,])/i;
  const kindOf = (row) => {
    const m = itemIn(row).match(/^https:\/\/open\.spotify\.com\/([a-z]+)\//);
    return m && KIND_LABEL[m[1]] ? KIND_LABEL[m[1]] : '';
  };
  // Prefixes the row's subtitle with its kind, as Transpono's «Kind • …»
  // (CSS ::before, from data-tp-pre); a row with a name only gets the kind
  // as its subtitle (data-tp-only). Not when the subtitle already says it.
  const prefix = (row, textBox) => {
    const kind = kindOf(row);
    if (!kind) return;
    const sub = row.querySelector('.tp-sub');
    if (sub) {
      if (!KIND_TEXT.test((sub.textContent || '').trim())) sub.setAttribute('data-tp-pre', kind + ' • ');
    } else if (textBox) {
      textBox.setAttribute('data-tp-only', kind);
    }
  };
  const unmark = (box, names) => {
    for (const c of names) {
      for (const e of Array.from(box.getElementsByClassName(c))) e.classList.remove(c);
    }
  };
  // Name and subtitle inside a row's text box.
  const label = (box) => {
    let kids = Array.from(box.children).filter(has);
    while (kids.length === 1 && kids[0].children.length) {
      box = kids[0];
      kids = Array.from(box.children).filter(has);
    }
    if (kids.length >= 2) {
      kids[0].classList.add('tp-name');
      for (let i = 1; i < kids.length; i++) kids[i].classList.add('tp-sub');
    } else {
      box.classList.add('tp-name');
    }
  };
  // One row like Transpono's: cover, name and subtitle; the rest hidden.
  const markRow = (row) => {
    const pic = row.querySelector('img') || row.querySelector('svg');
    const key = (row.textContent || '') + '|' +
      (pic ? (pic.getAttribute('src') || pic.tagName) : '');
    if (row.__tpKey === key && row.classList.contains('tp-row') &&
        (!pic || row.querySelector('.tp-cover'))) return;
    row.__tpKey = key;
    unmark(row, INNER);
    for (const e of Array.from(row.querySelectorAll('[data-tp-pre],[data-tp-only]'))) {
      e.removeAttribute('data-tp-pre');
      e.removeAttribute('data-tp-only');
    }
    row.classList.add('tp-row');
    // A row the virtual list places itself (absolute, at its own stride):
    // its own height kept, no Transpono minimum.
    const pos = getComputedStyle(row).position;
    row.classList.toggle('tp-abs', pos === 'absolute' || pos === 'fixed');
    if (!pic) return;
    let cover = pic;
    while (cover.parentElement && cover.parentElement !== row && !has(cover.parentElement)) {
      cover = cover.parentElement;
    }
    const line = cover.parentElement;
    if (!line) return;
    cover.classList.add('tp-cover');
    if (itemIn(row).indexOf('/artist/') >= 0) cover.classList.add('tp-round');
    if (line !== row) {
      line.classList.add('tp-line');
      // Boxes between the row and the line: no padding, start-aligned.
      for (let el = line.parentElement; el && el !== row; el = el.parentElement) {
        el.classList.add('tp-span');
      }
      // Desktop columns (date added, album, duration, index...): hidden.
      for (const cell of row.children) {
        cell.classList.add(cell.contains(cover) ? 'tp-main' : 'tp-hide');
      }
      for (let el = line; el.parentElement && el.parentElement !== row; el = el.parentElement) {
        for (const sib of el.parentElement.children) {
          if (sib !== el && !has(sib)) sib.classList.add('tp-hide');
        }
      }
    }
    const texts = [];
    for (const sib of line.children) {
      if (sib === cover) continue;
      if (has(sib)) texts.push(sib); else sib.classList.add('tp-hide');
    }
    if (texts.length === 1) {
      texts[0].classList.add('tp-text');
      label(texts[0]);
      prefix(row, texts[0]);
    } else if (texts.length > 1) {
      line.classList.add('tp-multi');
      texts[0].classList.add('tp-name');
      for (let i = 1; i < texts.length; i++) texts[i].classList.add('tp-sub');
      prefix(row, null);
    }
  };
  // Only the list on screen: the root fills it, everything around it is
  // hidden (top bar, home, search, right panel, player, banners), and so is
  // what sits above the rows inside it (the panel's header and chips).
  const isolate = (root, rows) => {
    root.classList.add('tp-root');
    for (let el = root; el.parentElement && el !== document.body; el = el.parentElement) {
      const p = el.parentElement;
      if (p !== document.body && p !== document.documentElement) p.classList.add('tp-path');
      for (const sib of p.children) {
        if (sib === el || /^(SCRIPT|STYLE|LINK|META|TEMPLATE)$/.test(sib.tagName)) continue;
        sib.classList.add('tp-hide');
      }
    }
    const lower = rows.length > 1 ? common(rows[0], rows[rows.length - 1]) : rows[0].parentElement;
    if (!lower) return;
    lower.classList.add('tp-list');
    // From the list up to the root: no insets, no backgrounds.
    for (let el = lower; el && el !== root; el = el.parentElement) el.classList.add('tp-wrap');
    for (let el = lower; el !== root && el.parentElement; el = el.parentElement) {
      for (const sib of el.parentElement.children) {
        if (sib === el || sib.classList.contains('tp-hide')) continue;
        // Empty boxes are kept: they may be the list's spacers, or the size
        // sensors the page measures itself with (hidden, the sidebar folds
        // to covers only and the virtual list draws no rows). Painted ones
        // (the header gradient) are flattened by the CSS instead.
        if (!sib.children.length && !has(sib)) continue;
        let holds = false;
        for (const r of rows) if (sib.contains(r)) { holds = true; break; }
        if (!holds) sib.classList.add('tp-hide');
      }
    }
    let scroller = null;
    for (let el = lower; el; el = el.parentElement) {
      const o = getComputedStyle(el).overflowY;
      if (o === 'auto' || o === 'scroll') { scroller = el; break; }
      if (el === root) break;
    }
    if (scroller) {
      scroller.classList.add('tp-scroller');
      for (let el = scroller; el && el !== root; el = el.parentElement) el.classList.add('tp-fill');
    } else {
      root.classList.add('tp-scroller');
    }
    for (const h of root.querySelectorAll('[role="row"]')) {
      if (h.querySelector('[role="columnheader"]')) h.classList.add('tp-hide');
    }
    for (const r of rows) markRow(r);
  };
  // The kind of link each chip keeps («Tudo» and «Músicas»: every row).
  const KIND_OF_CHIP = { playlists: '/playlist/', albums: '/album/', artists: '/artist/' };
  // Transpono's empty note, over the list, when a chip leaves no rows. In
  // <html>, out of the body, which the observer and isolate() never touch.
  const empty = (on) => {
    let note = document.getElementById('tp-empty');
    if (!on) {
      if (note) note.remove();
      return;
    }
    if (!note) {
      note = document.createElement('div');
      note.id = 'tp-empty';
      note.textContent = 'Nada nesta categoria.';
      document.documentElement.appendChild(note);
    }
  };
  // Which list is styled: the sidebar's (any filter but «Músicas»), else
  // the main view's (Músicas Curtidas, or the fallback without a sidebar).
  const apply = () => {
    const want = String(W.__tpWant || 'all');
    let mode = 'nenhum';
    let found = null;
    const side = findSide();
    if (want !== 'tracks' && side && side.rows.some(has)) {
      mode = 'sidebar';
      found = side;
    } else if (want === 'tracks' || W.__tpNoSide) {
      const main = findMain();
      if (main) { mode = 'grid'; found = main; }
    }
    const root = found ? found.el : null;
    if (root !== W.__tpRoot) {
      unmark(document, OUTER.concat(INNER));
      W.__tpRoot = root;
    }
    W.__tpMode = mode;
    W.__tpSide = side ? side.el : null;
    document.documentElement.classList.toggle('tp-on', !!root);
    if (!root) { empty(false); return { mode: mode, rows: 0, side: side }; }
    root.classList.toggle('tp-side', mode === 'sidebar');
    root.classList.toggle('tp-grid', mode === 'grid');
    isolate(root, found.rows);
    // The chip on our side too (Spotify's may be missing or not applied):
    // a row whose link is not of the chip's kind is left out. Rows with no
    // item link (Músicas Curtidas) belong to «Tudo» and «Músicas» only.
    const kind = KIND_OF_CHIP[want] || '';
    let shown = 0;
    for (const r of found.rows) {
      const out = !!kind && itemIn(r).indexOf(kind) < 0;
      if (r.classList.contains('tp-out') !== out) r.classList.toggle('tp-out', out);
      if (!out) shown++;
    }
    empty(!!kind && shown === 0);
    return { mode: mode, rows: found.rows.length, shown: shown, side: side };
  };
  W.__tpApply = apply;
  // Rows the page adds (scrolling, filters) are styled at once.
  if (!W.__tpObs && document.body) {
    try {
      W.__tpObs = new MutationObserver(() => {
        if (W.__tpRaf) return;
        W.__tpRaf = requestAnimationFrame(() => {
          W.__tpRaf = 0;
          try { if (W.__tpApply) W.__tpApply(); } catch (_) {}
        });
      });
      W.__tpObs.observe(document.body, { childList: true, subtree: true });
    } catch (_) {}
  }
  // The app's chips work Spotify's own filter chips (they stay in the page,
  // hidden): «Tudo» clears them, «Músicas» opens Músicas Curtidas.
  const CHIPS = {
    playlists: /^playlists?$/i,
    artists: /^(artistas|artists)$/i,
    albums: /^(álbuns|albuns|albums)$/i
  };
  const STATES = ['aria-checked', 'aria-pressed', 'aria-selected'];
  const filter = () => {
    const want = String(W.__tpWant || 'all');
    if (W.__tpApplied === want) return;
    if (W.__tpTryFor !== want) { W.__tpTryFor = want; W.__tpTries = 0; }
    if (W.__tpTries >= 4) { W.__tpApplied = want; return; }
    if (want === 'tracks') {
      if (/^\/collection\/tracks/.test(location.pathname)) { W.__tpApplied = want; return; }
      W.__tpTries++;
      const a = document.querySelector('a[href$="/collection/tracks"]');
      if (a && W.__tpTries < 3) a.click(); else location.assign('/collection/tracks');
      return;
    }
    const scope = W.__tpSide && W.__tpSide.isConnected ? W.__tpSide : document;
    const c = {};
    for (const b of scope.querySelectorAll('button,[role="checkbox"],[role="option"],[role="radio"]')) {
      if (b.closest('.tp-row')) continue;
      const t = (b.textContent || '').trim();
      for (const k of Object.keys(CHIPS)) if (!c[k] && CHIPS[k].test(t)) c[k] = b;
    }
    const keys = Object.keys(c);
    const known = keys.some((k) => STATES.some((n) => c[k].hasAttribute(n)));
    const cur = known
      ? (keys.filter((k) => STATES.some((n) => c[k].getAttribute(n) === 'true'))[0] || '')
      : (W.__tpChip || '');
    const off = () => {
      let x = null;
      for (const b of scope.querySelectorAll('button[aria-label]')) {
        if (/(limpar|clear|remover|remove).*(filtro|filter)/i.test(b.getAttribute('aria-label') || '')) {
          x = b;
          break;
        }
      }
      const b = x || c[cur];
      if (b) b.click();
      W.__tpChip = '';
    };
    if (want === 'all') {
      if (!cur) {
        if (keys.length || W.__tpMode === 'sidebar') W.__tpApplied = want;
        return;
      }
      W.__tpTries++;
      off();
      if (!known) W.__tpApplied = want;
      return;
    }
    if (cur === want) { W.__tpApplied = want; return; }
    if (cur) { W.__tpTries++; off(); return; }
    if (c[want]) {
      W.__tpTries++;
      c[want].click();
      W.__tpChip = want;
      if (!known) W.__tpApplied = want;
    }
  };
  const want = String(W.__tpWant || 'all');
  let box = { mode: 'nenhum', rows: 0, side: null };
  try { box = apply(); } catch (_) {}
  try { filter(); } catch (_) {}
  const playlists = document.querySelectorAll('a[href*="/playlist/"]').length;
  let items = 0;
  for (const a of document.querySelectorAll('a[href]')) if (itemOf(a.getAttribute('href'))) items++;
  const labelled = document.querySelectorAll('[aria-labelledby*="spotify:"]').length;
  // A collapsed sidebar (covers only: no names, no filter chips, and only
  // the first rows drawn) is reopened with its own button. Spotify keeps
  // that state between visits, so it is checked on every run, not only
  // when no list was found: collapsed, the sidebar still has rows (the
  // covers), so it used to be styled as it was. Collapsed means: no
  // «Recolher/Collapse» button, and an «Abrir/Expandir/Expand» one (not
  // «Mostrar mais», which widens the open panel). A few tries, 1.5 s apart.
  let closed = false;
  if (want !== 'tracks' && box.side && (W.__tpOpenTries || 0) < 5) {
    let shut = null;
    let open = false;
    for (const b of document.querySelectorAll('button[aria-label]')) {
      const l = b.getAttribute('aria-label') || '';
      if (!/(biblioteca|library)/i.test(l)) continue;
      if (/(recolher|collapse|fechar|close|ocultar|hide)/i.test(l)) open = true;
      else if (!shut && /(abrir|open|expandir|expand)/i.test(l)) shut = b;
    }
    closed = !open && !!shut;
    const now = Date.now();
    if (closed && now - (W.__tpOpenAt || 0) > 1500) {
      W.__tpOpenAt = now;
      W.__tpOpenTries = (W.__tpOpenTries || 0) + 1;
      W.__tpOpened = true;
      // The chips come back with the open panel: Spotify's is tried again.
      W.__tpApplied = '';
      W.__tpTryFor = '';
      shut.click();
    }
  }
  // A sidebar with rows but no names is collapsed: opened once. With no
  // sidebar list after 8 runs, the fallback: the desktop layout at 820 px,
  // scaled down, and its main view styled.
  if (!W.__tpNoSide && want !== 'tracks' && box.mode !== 'sidebar' &&
      document.readyState === 'complete' && (items > 0 || labelled > 0)) {
    if (box.side && !W.__tpOpened) {
      W.__tpOpened = true;
      for (const b of document.querySelectorAll('button[aria-label]')) {
        if (/(abrir|open|expandir|expand|mostrar|show).*(biblioteca|library)/i
            .test(b.getAttribute('aria-label') || '')) { b.click(); break; }
      }
    }
    W.__tpMiss = (W.__tpMiss || 0) + 1;
    if (W.__tpMiss >= 8) W.__tpNoSide = true;
  }
  if (document.head) {
    let vp = document.querySelector('meta[name="viewport"]');
    const vpWant = W.__tpNoSide
      ? 'width=820, user-scalable=yes'
      : 'width=device-width, initial-scale=1, maximum-scale=1';
    if (!vp) {
      vp = document.createElement('meta');
      vp.setAttribute('name', 'viewport');
      document.head.appendChild(vp);
    }
    if (vp.getAttribute('content') !== vpWant) vp.setAttribute('content', vpWant);
    if (!document.getElementById('tp-desk-css')) {
      const css = document.createElement('style');
      css.id = 'tp-desk-css';
      css.textContent = [
        '[data-testid="now-playing-bar"],footer[data-testid="now-playing-bar"]{display:none!important}',
        'html{-webkit-text-size-adjust:100%!important}',
        'html:not(.tp-on),html:not(.tp-on) body{overflow-x:auto!important}',
        'html.tp-on,html.tp-on body{background:#121212!important;overflow:hidden!important}',
        '.tp-hide.tp-hide.tp-hide.tp-hide{display:none!important}',
        'html.tp-on [data-testid*="banner" i],html.tp-on [data-testid*="upsell" i],' +
          'html.tp-on [data-testid*="download" i],html.tp-on a[href*="/download"]{display:none!important}',
        '.tp-path{transform:none!important;filter:none!important;contain:none!important;will-change:auto!important;' +
          'background-color:#121212!important;background-image:none!important}',
        '.tp-root{position:fixed!important;top:0!important;left:0!important;right:0!important;bottom:0!important;' +
          'width:auto!important;height:auto!important;min-width:0!important;max-width:none!important;' +
          'max-height:none!important;margin:0!important;padding:0!important;border:0!important;' +
          'border-radius:0!important;transform:none!important;z-index:2147483000!important;' +
          'background:#121212!important;background-image:none!important;display:flex!important;' +
          'flex-direction:column!important;overflow:hidden!important}',
        // Flat #121212: no gradient nor colour on anything but the covers.
        '.tp-root *:not(img):not(.tp-cover):not(.tp-cover *){background-color:transparent!important;' +
          'background-image:none!important}',
        '.tp-root *::before{background:none!important}',
        '.tp-root.tp-scroller{overflow-y:auto!important;-webkit-overflow-scrolling:touch!important}',
        '.tp-fill{display:flex!important;flex-direction:column!important;flex:1 1 auto!important;' +
          'width:100%!important;max-width:none!important;min-width:0!important;height:auto!important;' +
          'min-height:0!important;max-height:none!important;margin:0!important;padding:0!important;' +
          'border-radius:0!important}',
        '.tp-fill.tp-scroller{display:block!important;overflow-y:auto!important;-webkit-overflow-scrolling:touch!important}',
        '.tp-root .tp-wrap{margin:0!important;padding-left:0!important;padding-right:0!important;' +
          'width:100%!important;max-width:none!important;min-width:0!important;box-sizing:border-box!important}',
        '.tp-root .tp-list{display:flex!important;flex-direction:column!important;grid-template-columns:none!important;' +
          'gap:0!important;width:100%!important;min-width:0!important;padding:0!important;margin:0!important}',
        // Transpono's row (spotify_library_view.dart): padding 16/6/4/6, a
        // 56 cover (radius 4, round for artists), 12 gap, name 16 w500
        // white, 2 gap, subtitle 13 #b3b3b3, a 48 wide ⋯ button: 68 high.
        '.tp-root .tp-row{display:flex!important;flex-direction:row!important;align-items:center!important;' +
          'justify-content:flex-start!important;width:100%!important;max-width:none!important;min-width:0!important;' +
          'box-sizing:border-box!important;min-height:68px!important;' +
          'padding:6px 4px 6px 16px!important;margin:0!important;border:0!important;border-radius:0!important;' +
          'grid-template-columns:none!important;gap:0!important;text-align:left!important;' +
          '-webkit-tap-highlight-color:rgba(255,255,255,0.08)}',
        // Rows the virtual list places itself keep its height (its stride):
        // a forced one would overlap them.
        '.tp-root .tp-row.tp-abs{min-height:0!important;padding-top:0!important;padding-bottom:0!important}',
        // Rows of another kind than the chip's.
        '.tp-root .tp-row.tp-out.tp-out{display:none!important}',
        '#tp-empty{position:fixed;left:0;right:0;top:0;bottom:0;z-index:2147483001;display:flex;' +
          'align-items:center;justify-content:center;padding:0 32px;box-sizing:border-box;' +
          'pointer-events:none;color:#b3b3b3;font-size:15px;line-height:1.4;text-align:center;' +
          'font-family:-apple-system,system-ui,sans-serif;background:transparent}',
        '.tp-root .tp-row *{text-align:left!important}',
        '.tp-root .tp-row::after{content:"⋯";flex:0 0 48px;width:48px;height:48px;display:flex;' +
          'align-items:center;justify-content:center;color:#b3b3b3;font-size:24px;line-height:1;' +
          'background:none!important}',
        '.tp-root .tp-main,.tp-root .tp-span{display:flex!important;flex-direction:row!important;' +
          'align-items:center!important;justify-content:flex-start!important;flex:1 1 auto!important;' +
          'min-width:0!important;width:auto!important;max-width:none!important;margin:0!important;' +
          'padding:0!important;gap:0!important;grid-template-columns:none!important;align-self:stretch!important;' +
          'justify-self:stretch!important}',
        '.tp-root .tp-line{display:flex!important;flex-direction:row!important;align-items:center!important;' +
          'justify-content:flex-start!important;flex:1 1 auto!important;width:100%!important;min-width:0!important;' +
          'gap:0!important;margin:0!important;padding:0!important;grid-template-columns:none!important}',
        '.tp-root .tp-line.tp-multi{display:grid!important;grid-template-columns:auto minmax(0,1fr)!important;' +
          'align-content:center!important;justify-items:start!important;justify-content:start!important;' +
          'row-gap:2px!important}',
        '.tp-root .tp-multi>.tp-cover{grid-row:1 / span 2!important}',
        '.tp-root .tp-multi>:not(.tp-cover){grid-column:2!important;justify-self:stretch!important}',
        '.tp-root .tp-cover{width:56px!important;height:56px!important;min-width:56px!important;' +
          'max-width:56px!important;min-height:56px!important;max-height:56px!important;flex:0 0 56px!important;' +
          'margin:0 12px 0 0!important;padding:0!important;border-radius:4px!important;overflow:hidden!important;' +
          'position:relative!important;inset:auto!important;align-self:center!important}',
        '.tp-root .tp-cover.tp-round{border-radius:50%!important}',
        '.tp-root .tp-cover img{width:100%!important;height:100%!important;object-fit:cover!important;' +
          'border-radius:inherit!important}',
        '.tp-root img.tp-cover{object-fit:cover!important}',
        '.tp-root .tp-cover button,.tp-root .tp-cover [role="button"]{display:none!important}',
        '.tp-root .tp-text{display:flex!important;flex-direction:column!important;justify-content:center!important;' +
          'align-items:stretch!important;flex:1 1 auto!important;min-width:0!important;overflow:hidden!important;' +
          'margin:0!important;padding:0!important;gap:2px!important}',
        '.tp-root .tp-text[data-tp-only]::after{content:attr(data-tp-only);display:block;color:#b3b3b3;' +
          'font-size:13px;font-weight:400;line-height:1.3;white-space:nowrap;overflow:hidden;' +
          'text-overflow:ellipsis;text-align:left;font-family:-apple-system,system-ui,sans-serif}',
        '.tp-root .tp-name,.tp-root .tp-sub{display:block!important;white-space:nowrap!important;overflow:hidden!important;' +
          'text-overflow:ellipsis!important;width:100%!important;max-width:100%!important;min-width:0!important;' +
          'margin:0!important;padding:0!important;align-self:stretch!important;justify-self:stretch!important;' +
          'text-align:left!important;font-family:-apple-system,system-ui,sans-serif!important}',
        '.tp-root .tp-name *,.tp-root .tp-sub *{display:inline!important;white-space:nowrap!important;' +
          'text-decoration:none!important;margin:0!important;padding:0!important;' +
          'font-family:-apple-system,system-ui,sans-serif!important}',
        '.tp-root .tp-name,.tp-root .tp-name *{color:#fff!important;font-size:16px!important;font-weight:500!important;' +
          'line-height:1.25!important}',
        '.tp-root .tp-sub,.tp-root .tp-sub *{color:#b3b3b3!important;font-size:13px!important;font-weight:400!important;' +
          'line-height:1.3!important}',
        '.tp-root .tp-sub[data-tp-pre]::before{content:attr(data-tp-pre)}',
        '.tp-root .tp-sub svg,.tp-root .tp-name svg{display:none!important}'
      ].join('\n');
      document.head.appendChild(css);
    }
  }
  // Moved to an item's page inside the page (no navigation): the app opens
  // it, and this page goes back.
  const here = itemOf(location.pathname);
  if (here && window.__tpDeskLast !== here) {
    window.__tpDeskLast = here;
    post('open:' + here);
    try { history.back(); } catch (_) {}
  }
  let gate = false;
  let login = false;
  if (items === 0 && labelled === 0 && box.rows === 0) {
    const text = ((document.body && document.body.innerText) || '').slice(0, 8000);
    gate = /(baixar|obter|get|download)( o| a| the)? app\b|aproveite a sua biblioteca|enjoy your library/i.test(text);
    login = location.host === 'accounts.spotify.com' || /^\/login/.test(location.pathname) ||
      !!document.querySelector('[data-testid="login-button"]');
  }
  return JSON.stringify({
    host: location.host, path: location.pathname, playlists: playlists,
    items: items, rows: box.rows, box: box.mode, gate: gate, login: login,
    // Ready to be seen: the list styled, the sidebar open, and the chip
    // applied (the app keeps its cover over the page until then).
    settled: box.mode !== 'nenhum' && box.rows > 0 && !closed && W.__tpApplied === want,
    ready: document.readyState === 'complete'
  });
})()
''';

Map<Object?, Object?>? _decode(Object? raw) {
  Object? value = raw;
  for (var i = 0; value is String && i < 2; i++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value is Map ? value : null;
}

int _int(Object? value) => value is num && value.isFinite ? value.toInt() : 0;

enum _LibrarySource { spotify, transpono }

/// The library screen of the experiment: «Spotify» (the desktop web
/// player's library, in its own WKWebView) and «Transpono» ([transpono],
/// the app's own library). A tap on an item of the Spotify one hands its
/// address to [onOpenLink] (the main, mobile Spotify page opens it).
class SpotifyLibraryScreen extends StatefulWidget {
  const SpotifyLibraryScreen({
    super.key,
    required this.transpono,
    required this.onOpenLink,
  });

  final Widget transpono;
  final ValueChanged<String> onOpenLink;

  /// The header, as Transpono's ([SpotifyLibraryView.title]).
  static const String title = SpotifyLibraryView.title;
  static const String note = 'Da tua conta Spotify.';

  static const String gateNote =
      'O Spotify não mostrou a biblioteca nesta versão. Usa o separador '
      'Transpono.';

  @override
  State<SpotifyLibraryScreen> createState() => _SpotifyLibraryScreenState();
}

class _SpotifyLibraryScreenState extends State<SpotifyLibraryScreen> {
  _LibrarySource _source = _LibrarySource.spotify;
  // The chips, Transpono's segments: their [Enum.name] is the filter the
  // page script applies (`window.__tpWant`).
  SpotifyLibrarySegment _filter = SpotifyLibrarySegment.all;
  late final WebViewController _controller;
  Timer? _poll;
  bool _reading = false;
  DateTime? _lastOpen;
  int _progress = 0;
  String _host = '';
  String _path = '';
  int _playlists = 0;
  int _items = 0;
  int _rows = 0;
  String _box = 'nenhum';
  bool _gate = false;
  bool _login = false;
  String? _error;
  // The page stays under a cover until its list is styled (`settled`), so
  // Spotify's own layout is never seen turning into Transpono's. Shown
  // again on each chip change; lifted after [_coverLimit] whatever happens.
  bool _settled = false;
  DateTime _coverSince = DateTime.now();
  int _tick = 0;
  static const Duration _coverLimit = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    // Its own controller (the main page's scripts never run here), with
    // the default website data store, the main page's: the same sign-in.
    // Media keep needing a user gesture to play (the default).
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
          )
        : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(spotifyBase);
      await _controller.setUserAgent(spotifyDesktopUserAgent);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (String _) => unawaited(_read()),
          onWebResourceError: (WebResourceError failure) {
            if (failure.isForMainFrame != true) return;
            if (failure.errorCode == -999 || failure.errorCode == 102) return;
            if (mounted) {
              setState(() {
                _error = 'Não foi possível carregar a biblioteca do Spotify.';
                _progress = 100;
              });
            }
          },
          onNavigationRequest: _decide,
        ),
      );
      await _controller.addJavaScriptChannel(
        'TransponoDesktop',
        onMessageReceived: (JavaScriptMessage message) {
          final String text = message.message;
          if (text.startsWith('open:')) _open(text.substring(5));
        },
      );
      if (!mounted) return;
      // Every 250 ms while covered (the cover lifts as soon as the list
      // is ready), every second after.
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _tick++;
        if (_covered || _tick % 4 == 0) unawaited(_read());
      });
      await _controller.loadRequest(spotifyDesktopLibraryStart);
    } on Object catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    }
  }

  /// Item pages never open here: the main page opens them.
  NavigationDecision _decide(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null || !isSpotifyBrowserUri(uri)) {
      return NavigationDecision.prevent;
    }
    if (uri.host == 'open.spotify.com' &&
        canonicalSpotifyItemUrl(request.url) != null) {
      _open(request.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _open(String url) {
    if (!mounted) return;
    final canonical = canonicalSpotifyItemUrl(url);
    if (canonical == null) return;
    // One tap may arrive twice (the click and the in-page route).
    final DateTime now = DateTime.now();
    final DateTime? last = _lastOpen;
    if (last != null && now.difference(last).inMilliseconds < 1500) return;
    _lastOpen = now;
    widget.onOpenLink(canonical.url);
  }

  Future<void> _read() async {
    if (_reading || !mounted) return;
    _reading = true;
    // A chip changed during this read: its answer is about the old one.
    final SpotifyLibrarySegment asked = _filter;
    try {
      final Object? raw = await _controller.runJavaScriptReturningResult(
        'window.__tpWant=${jsonEncode(_filter.name)};$_desktopLibraryScript',
      );
      final Map<Object?, Object?>? values = _decode(raw);
      if (!mounted || values == null) return;
      setState(() {
        final String path = '${values['path'] ?? ''}';
        // Músicas Curtidas opened from the list (its row): its chip lights.
        const String tracks = '/collection/tracks';
        if (!_path.startsWith(tracks) && path.startsWith(tracks)) {
          _filter = SpotifyLibrarySegment.tracks;
        }
        _host = '${values['host'] ?? ''}';
        _path = path;
        _box = '${values['box'] ?? 'nenhum'}';
        _playlists = _int(values['playlists']);
        _items = _int(values['items']);
        _rows = _int(values['rows']);
        if (values['settled'] == true && asked == _filter) _settled = true;
        _gate = values['gate'] == true;
        _login = values['login'] == true;
      });
    } on Object {
      // No page yet; the next poll reads it.
    } finally {
      _reading = false;
    }
  }

  /// Covers the page until its list is styled again.
  void _cover() {
    _settled = false;
    _coverSince = DateTime.now();
  }

  bool get _covered =>
      !_settled && DateTime.now().difference(_coverSince) < _coverLimit;

  Future<void> _reload() async {
    setState(() {
      _cover();
      _error = null;
      _gate = false;
      _login = false;
    });
    try {
      await _controller.loadRequest(spotifyDesktopLibraryStart);
    } on Object catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final bool spotify = _source == _LibrarySource.spotify;
    return Material(
      color: spotifyBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top + 8),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                _segment('Spotify', _LibrarySource.spotify),
                const SizedBox(width: 8),
                _segment('Transpono', _LibrarySource.transpono),
                const Spacer(),
                if (spotify)
                  IconButton(
                    tooltip: 'Recarregar',
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () => unawaited(_reload()),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Spotify's list, with Transpono's header and chips (the same
          // widgets, at the same offsets as in [widget.transpono], whose
          // top gap is 12 under the segments).
          if (spotify) ...[
            const SizedBox(height: 12),
            const SpotifyLibraryHeader(
              title: SpotifyLibraryScreen.title,
              note: SpotifyLibraryScreen.note,
            ),
            const SizedBox(height: 12),
            SpotifyLibraryChips(
              selected: _filter,
              onSelected: (SpotifyLibrarySegment filter) {
                if (filter == _filter) return;
                setState(() {
                  _filter = filter;
                  _cover();
                });
                unawaited(_read());
              },
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: IndexedStack(
              index: spotify ? 0 : 1,
              sizing: StackFit.expand,
              children: [
                _spotifyPane(),
                // The app's library under the segments: no status-bar gap.
                MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: widget.transpono,
                ),
              ],
            ),
          ),
          // Only when something failed, for the owner's reports.
          if (spotify &&
              defaultTargetPlatform == TargetPlatform.iOS &&
              _showDiagnostic)
            _diagnostic(),
        ],
      ),
    );
  }

  Widget _segment(String label, _LibrarySource source) {
    final bool on = source == _source;
    return Material(
      color: on ? spotifyGreen : const Color(0x1AFFFFFF),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _source = source),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: on ? Colors.black : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _spotifyPane() {
    final String? error = _error;
    final bool note = _gate || _login || error != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(
          key: const Key('spotifyDesktopLibrary'),
          controller: _controller,
        ),
        // Until the list is styled: Transpono's background and a spinner,
        // never Spotify's page half-way through its restyling.
        if (_covered && !note)
          const ColoredBox(
            key: Key('spotifyDesktopLibraryCover'),
            color: spotifyBase,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: spotifyGreen,
                ),
              ),
            ),
          ),
        if (_progress < 100)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 2,
              color: spotifyGreen,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (note)
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Material(
              color: const Color(0xF0282828),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error == null
                            ? SpotifyLibraryScreen.gateNote
                            : '$error ${SpotifyLibraryScreen.gateNote}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_reload()),
                      child: const Text(
                        'Recarregar',
                        style: TextStyle(color: spotifyGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The diagnostic shows only on a gate, a sign-in, an error, or a loaded
  /// page with no rows styled.
  bool get _showDiagnostic =>
      _gate || _login || _error != null || (_progress >= 100 && _rows == 0);

  /// For the owner's screenshots: where the desktop page is and whether it
  /// shows a library.
  Widget _diagnostic() {
    final String where = _path.isEmpty
        ? '-'
        : (_host == 'open.spotify.com' ? _path : '$_host$_path');
    final String flags = [
      if (_gate) 'gate',
      if (_login) 'login',
    ].join(' ');
    final String text =
        'Diag: $where · $_box: $_rows linhas · playlists: $_playlists · '
        'itens: $_items${flags.isEmpty ? '' : ' · $flags'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: spotifySubdued, fontSize: 11),
      ),
    );
  }
}
