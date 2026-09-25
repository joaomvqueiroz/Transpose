---
name: PitchCraft Audio Lab
colors:
  surface: '#091421'
  surface-dim: '#091421'
  surface-bright: '#2f3a48'
  surface-container-lowest: '#040f1c'
  surface-container-low: '#111c2a'
  surface-container: '#16202e'
  surface-container-high: '#202b39'
  surface-container-highest: '#2b3544'
  on-surface: '#d8e3f6'
  on-surface-variant: '#bac9cc'
  inverse-surface: '#d8e3f6'
  inverse-on-surface: '#27313f'
  outline: '#849396'
  outline-variant: '#3b494c'
  surface-tint: '#00daf3'
  primary: '#c3f5ff'
  on-primary: '#00363d'
  primary-container: '#00e5ff'
  on-primary-container: '#00626e'
  inverse-primary: '#006875'
  secondary: '#7bd0ff'
  on-secondary: '#00354a'
  secondary-container: '#00a6e0'
  on-secondary-container: '#00374d'
  tertiary: '#e6edff'
  on-tertiary: '#263143'
  tertiary-container: '#c6d1e9'
  on-tertiary-container: '#4f5a6e'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#9cf0ff'
  primary-fixed-dim: '#00daf3'
  on-primary-fixed: '#001f24'
  on-primary-fixed-variant: '#004f58'
  secondary-fixed: '#c4e7ff'
  secondary-fixed-dim: '#7bd0ff'
  on-secondary-fixed: '#001e2c'
  on-secondary-fixed-variant: '#004c69'
  tertiary-fixed: '#d8e3fb'
  tertiary-fixed-dim: '#bcc7de'
  on-tertiary-fixed: '#111c2d'
  on-tertiary-fixed-variant: '#3c475a'
  background: '#091421'
  on-background: '#d8e3f6'
  surface-variant: '#2b3544'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-xl-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 26px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  metric-xl:
    fontFamily: JetBrains Mono
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.03em
  metric-lg:
    fontFamily: JetBrains Mono
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.02em
  metric-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: -0.01em
  metric-sm:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.02em
  label-caps:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.06em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system expresses the precision, immersion, and technical mastery of a world-class audio workstation. Built specifically for sound engineers, producers, and synthesis designers, it balances deep optical focus with surgical clarity. The atmosphere evokes late-night master control rooms: low-light environments illuminated by tactical displays, metering arrays, and responsive hardware controllers.

The design style combines **Technical Modernism** with **Dark Tonal Layering**. It moves intentionally away from generic carbon-grey dark modes, replacing them with layered, ink-like midnight blues that reduce eye fatigue during 10-hour mixing sessions. Tactile affordances mimic studio rackmount gear—crisp borders, exact metrics, and responsive states—while maintaining a clean digital posture. Accents of electric cyan are applied with absolute discipline, cutting through the shadows solely to communicate system state, playback head positions, and critical interactive triggers.

## Colors

The palette establishes an acoustic hierarchy through luminance steps in deep oceanic blue and cyan:

- **Base Surfaces & Backgrounds:**
  - Canvas Deep: `#051424` (Outer canvas, non-active screen canvas, backdrop)
  - Surface Primary: `#07121F` (Main work areas, track lane backdrops)
  - Surface Raised: `#0A111B` (Inspector panels, modal containers, rack units)
  - Surface Elevated: `#0F1D2E` (Popovers, floating utility bars, active card surfaces)

- **Accents & Active Feedback:**
  - Primary (`#00E5FF`): Reserved strictly for active toggles, cursor playheads, armed record tracks, primary buttons, and selected waveform highlights. Never used for decorative washes or low-priority background fills.
  - Secondary (`#38BDF8`): Sub-selections, secondary routing lines, and active parameter envelopes.
  - Signal Warn / Clip: `#FF4D4D` (Overload metering, audio clipping, record status).
  - Signal Safe: `#00FF9D` (RMS green range, calibrated inputs).

- **Borders & Separators:**
  - Hairline dividers and rack borders utilize `#16283D` (Subtle) and `#1E3A5F` (Focused / Hovered).

## Typography

The type system splits cleanly into two distinct disciplines: **Structural UI** and **Precision Metrics**.

1. **Structural UI (Inter):** Handles application framing, tooltips, channel headers, modal titles, and configuration forms. Weights are kept at 400 (regular) for descriptions and 600–700 (semi-bold/bold) for hierarchical clarity. `label-caps` is always rendered in uppercase to label panel quadrants and hardware knobs without visually competing with data.
2. **Precision Metrics (JetBrains Mono):** Monospaced, tabular numbers are non-negotiable for musical interfaces. Every instance of pitch values (e.g., `A4 440.00Hz`), tempo (`128.00 BPM`), timecode (`01:23:45.08`), phase alignment, and dBFS meters must use JetBrains Mono. This eliminates jitter during real-time modulation and scrubber movement.

## Layout & Spacing

This design system uses a flexible 12-column layout grid anchored by rigid toolbar and inspector rail dimensions. 

- **Studio Workbench Philosophy:** Audio software requires dense information architecture alongside immediate accessibility. Layout containers maintain consistent structural spacing:
  - Mobile (< 768px): Single-column rack stack with fixed 48px sticky transport bar at the base; outer margins set to `margin` (1rem).
  - Tablet (768px – 1199px): 8-column layout with collapsable browser sidebar and flexible track lane region; gutters set to `gutter` (1rem).
  - Desktop (≥ 1200px): Full 12-column grid layout with dedicated left inspector (280px fixed), center multi-track array (fluid), and right metering/master strip (320px fixed). Gutters scale to `gutter-desktop` (1.5rem).

- **Touch & Accessibility Standards:** Every interactive element—including small bypass knobs, mute/solo flags, and disclosure chevron targets—must provide a minimum bounding hitbox of 48px × 48px, even if the underlying visual glyph is compact (e.g., 20px).

## Elevation & Depth

Visual depth is achieved through **Tonal Surface Stacking** combined with micro-luminescent ambient glows, rather than heavy drop shadows:

- **Level 0 (Canvas Base):** Flat `#051424`. No shadow, pure absorbing midnight backplane.
- **Level 1 (Card & Module Shells):** `#07121F` surface framed with a 1px solid border of `#16283D`. Elevation is indicated by a razor-thin internal top-edge highlight: `inset 0 1px 0 0 rgba(255, 255, 255, 0.05)`.
- **Level 2 (Active Modules & Popovers):** `#0A111B` surface with a diffuse ambient shadow: `0 12px 32px -4px rgba(2, 6, 12, 0.70)`.
- **Level 3 (Focused / Live Elements):** When a module, fader channel, or card becomes active, its border shifts to `#00E5FF` at 50% opacity, accompanied by an electric aura: `0 0 16px -2px rgba(0, 229, 255, 0.25)`.

## Shapes

The geometric signature balances tactile hardware enclosures with clean software boundaries:

- **Cards and Panels:** Standardized to `rounded-lg` (12px / 0.75rem to 1rem visual boundary), balancing modern soft curves with dense space efficiency.
- **Micro-Controls (Faders, Knobs, Flags):** Radii scale proportionally down to 4px–6px to avoid looking toy-like or pill-shaped inside high-density audio racks.
- **Interactive Pill Toggles:** Mode triggers (e.g., Pitch / Formant / Spectral modes) utilize continuous stadium curves (9999px) for clear differentiation against rectangular audio modules.

## Components

### Buttons & Transport Triggers
- **Primary Action (Render / Apply / Master Arm):** High-voltage visual target. Background `#00E5FF`, label `#051424` (Inter 600), zero border, radius 8px. Hover shifts to `#38BDF8` with a soft cyan bloom. Minimum touch target: 48px.
- **Secondary (Bypass / Reset):** Transparent background, 1px border in `#1E3A5F`, text `#94A3B8`. Hover transitions text and border to `#00E5FF`.
- **Transport Flags (Mute / Solo):** 48px touch cells holding 32px visual tiles. Inactive: `#0A111B` with subtle text. Solo Active: Amber/Yellow glow. Mute Active: Red glow.

### Cards & Rack Enclosures
- Enclosed with 12px border radius, `#07121F` fill, 1px `#16283D` perimeter stroke.
- Header row contains track identification, drag handle, and progressive disclosure chevron with unified 48px touch target.
- Waveform and frequency analyzer readouts are inset by 8px with a darkened well fill (`#051424`).

### Progressive Disclosure Toggles
- Used for expanding advanced DSP parameters (LFO depth, oversampling filters, envelope decay curves).
- Chevron rotates 90 degrees with an easing curve of `cubic-bezier(0.16, 1, 0.3, 1)`. 
- Expanding tray reveals child controls on surface `#0A111B` without causing sudden canvas jitter.

### Input Fields & Scrubbers
- Pitch shift and BPM inputs: Container height 48px, background `#051424`, border 1px `#1E3A5F`. 
- Text rendered strictly in `metric-md` (JetBrains Mono).
- Double-clicking opens manual numeric editing; dragging horizontally scrubs the value with real-time numeric updates and electric cyan progress underline.

### Checkboxes & Segmented Selectors
- Checkboxes: 20px box within a 48px touch target. Unchecked: `#0A111B` with `#1E3A5F` border. Checked: `#00E5FF` fill with midnight blue checkmark.
- Segmented Pitch Mode Selector: Horizontal container housing mutually exclusive pills (e.g., "Manual", "Chromatic", "Scale Detect"). Active segment transitions with an ink-blue fill and sharp electric cyan typography.