# Transpono — mobile design system

## Product

Transpono is a Portuguese-language music practice app for Android and iPhone.
Its main surface combines a large YouTube video with optional practice tools.
The design should feel calm, modern, musician-focused, and easy to read while
performing. Redesign presentation only; preserve existing Flutter behavior.

## Brand and tokens

- Dark navy background: `#0B1826`
- Main cards: `#142435`; alternate cards: `#102132`
- Accent cyan: `#19D9F1`
- Secondary text: `#ADB9C7`; primary text: near-white
- Rounded card corners: approximately 12–18 dp
- Touch targets: at least 44–48 dp where possible
- Use a clear, consistent type hierarchy and accessible contrast.

## Structure

- One player, not separate main/fullscreen players.
- Closed state: large video, then one centered “Abrir ajustes” button.
- Open state: video keeps the same size. Below it, horizontally accessible
  Cifra, Treino, Setlist and Áudio columns; “Fechar ajustes” at the bottom.
- The YouTube video provides its own play/pause and seeking controls. Do not
  duplicate those controls in Transpono.
- Do not add a left sidebar, fullscreen action, “Tempos” button, or automatic
  restoration of closed videos.

## Cifra

- A chosen chord sheet appears in a rounded frame. As the panel scrolls, its
  controls move away naturally; the frame stops directly below the video and
  only its text keeps scrolling inside.
- “Escolher cifra” shows a native search/results list inside the Cifra column.
  Prefill the search with the video title. Each result contains only its title:
  at most two lines, compact type and inner spacing, with a modest gap between
  separate results. Do not repeat the source website on every row.
- Chord text must adapt to narrow screens without clipping long lines.

## Treino, Setlist and Áudio

- Treino: video pitch, one draggable speed line from 0.25× to 2×, A–B loop;
  saved segments, metronome and speed progression reveal on demand.
- Setlist: compact video thumbnail plus title of at most two lines/55 chars.
- Áudio: bass, mids, treble, delay, and a guitar tuner inside this column.

## Deliverables

Create coordinated mobile portrait concepts for the player closed/open, chord
search results, expanded chord sheet, Treino, Setlist, and Áudio. Keep all
labels in Portuguese. Prioritize legibility, visual rhythm, responsive
behavior, and smooth state transitions. Treat generated code as visual
reference; the production app remains Flutter.
