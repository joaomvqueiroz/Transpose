---
name: Obsidian & Argent
colors:
  surface: '#131315'
  surface-dim: '#131315'
  surface-bright: '#39393b'
  surface-container-lowest: '#0e0e10'
  surface-container-low: '#1b1b1d'
  surface-container: '#201f21'
  surface-container-high: '#2a2a2c'
  surface-container-highest: '#353437'
  on-surface: '#e5e1e4'
  on-surface-variant: '#c4c7c9'
  inverse-surface: '#e5e1e4'
  inverse-on-surface: '#303032'
  outline: '#8e9193'
  outline-variant: '#444749'
  surface-tint: '#c6c6c7'
  primary: '#ffffff'
  on-primary: '#2f3132'
  primary-container: '#e2e2e3'
  on-primary-container: '#636466'
  inverse-primary: '#5d5e60'
  secondary: '#c6c6cf'
  on-secondary: '#2f3037'
  secondary-container: '#45464e'
  on-secondary-container: '#b4b4bd'
  tertiary: '#ffffff'
  on-tertiary: '#2f3038'
  tertiary-container: '#e3e1ec'
  on-tertiary-container: '#63646c'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e2e2e3'
  primary-fixed-dim: '#c6c6c7'
  on-primary-fixed: '#1a1c1d'
  on-primary-fixed-variant: '#454748'
  secondary-fixed: '#e2e1eb'
  secondary-fixed-dim: '#c6c6cf'
  on-secondary-fixed: '#1a1b22'
  on-secondary-fixed-variant: '#45464e'
  tertiary-fixed: '#e3e1ec'
  tertiary-fixed-dim: '#c6c5cf'
  on-tertiary-fixed: '#1a1b22'
  on-tertiary-fixed-variant: '#46464e'
  background: '#131315'
  on-background: '#e5e1e4'
  surface-variant: '#353437'
typography:
  display-lg:
    fontFamily: Geist
    fontSize: 3.5rem
    fontWeight: '600'
    lineHeight: 4rem
    letterSpacing: -0.04em
  display-lg-mobile:
    fontFamily: Geist
    fontSize: 2.25rem
    fontWeight: '600'
    lineHeight: 2.75rem
    letterSpacing: -0.03em
  headline-xl:
    fontFamily: Geist
    fontSize: 2.5rem
    fontWeight: '500'
    lineHeight: 3rem
    letterSpacing: -0.03em
  headline-xl-mobile:
    fontFamily: Geist
    fontSize: 1.75rem
    fontWeight: '500'
    lineHeight: 2.25rem
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Geist
    fontSize: 1.5rem
    fontWeight: '500'
    lineHeight: 2rem
    letterSpacing: -0.02em
  title-md:
    fontFamily: Geist
    fontSize: 1.125rem
    fontWeight: '500'
    lineHeight: 1.625rem
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Geist
    fontSize: 1rem
    fontWeight: '400'
    lineHeight: 1.625rem
    letterSpacing: -0.01em
  body-md:
    fontFamily: Geist
    fontSize: 0.875rem
    fontWeight: '400'
    lineHeight: 1.375rem
    letterSpacing: 0em
  body-sm:
    fontFamily: Geist
    fontSize: 0.75rem
    fontWeight: '400'
    lineHeight: 1.125rem
    letterSpacing: 0.01em
  label-md:
    fontFamily: Inter
    fontSize: 0.8125rem
    fontWeight: '500'
    lineHeight: 1rem
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Inter
    fontSize: 0.6875rem
    fontWeight: '600'
    lineHeight: 0.875rem
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1.5rem
  gutter-mobile: 1rem
  margin: 2.5rem
  margin-mobile: 1rem
  margin-tablet: 1.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system channels an uncompromising, luxury atelier aesthetic anchored in deep OLED blacks, brushed argent metals, and crisp architectural precision. Built for high-tier professional tooling, audio-visual creative suites, and exclusive digital artifacts, it prioritizes optical clarity, focus, and structural permanence over decorative ornamentation.

The visual direction fuses **Dark Minimalism** with **Precision Glassmorphism**:
- Extreme contrast ratios ensuring absolute legibility and tactile focus.
- Monochromatic hierarchy driven strictly by luminescence, surface reflectivity, and micro-sheens rather than chromatic hues.
- Whisper-thin structural framing (subtle 1px brushed silver keylines) simulating precision-milled aluminum hardware.
- Restrained, cinematic micro-interactions engineered with strict `prefers-reduced-motion` fallbacks to respect user context and ergonomic focus.

## Colors

The palette is strictly achromatic and metallic, eliminating distracting saturations in favor of deep value layers and reflective silver finishes.

### Surface Tiers
- **Void (Base Canvas):** `#000000` (True OLED pitch black) to `#080808` (App foundation).
- **Surface Level 1 (Card/Container):** `#121214` (Deep graphite).
- **Surface Level 2 (Elevated Panels):** `#18181B` (Rich charcoal).
- **Surface Level 3 (Float / Flyouts):** `#202023` (Refined dark alloy).

### Accent & Textures
- **Primary Metal (Specular Silver):** `#F4F4F5` used for primary focal triggers, active states, and specular glints.
- **Secondary Metal (Brushed Argent):** `#E4E4E7` down to `#D4D4D8` for standard button surfaces and prominent borders.
- **Cool Steel (Muted Metallic):** `#A1A1AA` for secondary icons, helper text, and inactive toggles.
- **Deep Steel:** `#71717A` for tertiary captions, inactive borders, and structural dividing rules.

### Typography Contrast
- **Primary Text:** `#FFFFFF` (Pure optic white for uncompromised luminance and focus).
- **Secondary Text:** `#A1A1AA` (Balanced low-eyestrain reading value).
- **Disabled / Subtle:** `#52525B` (Minimum compliant contrast for dormant states).

## Typography

The typography pairs **Geist** for clean neo-grotesque display and editorial body rhythm with **Inter** for micro-labels, technical telemetry, and metadata.

- **Tracking Strategy:** Headings employ tight, negative tracking (`-0.02em` to `-0.04em`) to simulate engineered industrial typesetting. Compact UI labels enforce positive tracking (`0.02em` to `0.05em`) in uppercase or small-caps contexts to ensure scanning speed.
- **Vertical Rhythm:** Strict baseline alignments with proportional line heights tuned for dark backdrops to prevent halation and visual fatigue.
- **Rendering:** Anti-aliasing must be forced via `-webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale;` to maintain crisp letterforms against pure black foundations.

## Layout & Spacing

The layout is built upon an 8pt architectural rhythm, utilizing a fluid grid that collapses seamlessly across three core viewport thresholds:

- **Desktop (1200px+):** 12-column layout, outer `margin: 2.5rem`, `gutter: 1.5rem`. Max layout containment set at `1440px` for sustained ergonomic gaze.
- **Tablet (768px - 1199px):** 8-column layout, outer `margin: 1.5rem`, `gutter: 1.25rem`. Complex side rails collapse into persistent drawer triggers.
- **Mobile (Up to 767px):** 4-column layout, outer `margin: 1rem`, `gutter: 1rem`. High-density vertical stacking with fixed bottom action strips.

All spacing units define strict empty clearance between bounding frames. Dense data modules scale using `space-xs` and `space-sm`, while top-level structural separation relies on `space-lg` and `space-xl`.

## Elevation & Depth

Depth is articulated through optical luminosity, specular outlines, and frosted transmission, avoiding traditional diffuse drop shadows:

- **Surface Layering:** Rather than lifting objects with heavy black dropshadows, elevation inverts: higher surfaces become slightly more luminous (`#080808` → `#121214` → `#18181B` → `#202023`).
- **Silver Sheen Perimeter:** Containers feature a 1px solid perimeter:
  - Base resting state: `1px solid rgba(228, 228, 231, 0.08)`.
  - Focused or elevated state: `1px solid rgba(244, 244, 245, 0.22)`.
  - Specular top rim: Linear gradient borders fading from `rgba(255, 255, 255, 0.35)` at the top edge to `rgba(255, 255, 255, 0.03)` at the bottom edge.
- **Backdrop Diffusion:** Floating chrome panels, modals, and toolbars apply `backdrop-filter: blur(16px) saturate(140%)` with a `rgba(18, 18, 20, 0.72)` background fill.
- **Specular Glow:** Active interactions or critical focus rings utilize a cold silver ambient bloom: `box-shadow: 0 0 0 1px rgba(244, 244, 245, 0.4), 0 0 20px -4px rgba(244, 244, 245, 0.15)`.

## Shapes

The design system adopts a **Soft (`1`)** shape language, prioritizing an understated, machined technical feel over organic or playful curvature:

- **Base Radius:** `0.25rem` (4px) applied to compact controls: tags, inputs, checkboxes, and segmented items.
- **Medium / Large Radius (`rounded-lg`):** `0.5rem` (8px) for cards, dialog windows, and standard modals.
- **Structural Framing (`rounded-xl`):** `0.75rem` (12px) applied solely to top-level app containers and ambient canvas viewports.
- **Full Radius:** Strictly limited to status pills, tooltips, and circular icon triggers.

## Components

### Buttons
- **Primary (Argent Solid):** Background `#F4F4F5`, text `#000000` (semi-bold). Hover shifts to pure `#FFFFFF` with a tight silver specular halo (`0 0 12px rgba(244, 244, 245, 0.35)`). Active state shifts to `#E4E4E7`.
- **Secondary (Milled Alloy):** Background `#18181B`, border `1px solid rgba(228, 228, 231, 0.12)`, text `#F4F4F5`. Hover escalates border to `rgba(244, 244, 245, 0.3)` and background to `#202023`.
- **Ghost / Tertiary:** Transparent background, text `#A1A1AA`. Hover reveals `#121214` surface and `#FFFFFF` text.

### Form Inputs & Selectors
- **Text Inputs:** Background `#080808`, border `1px solid rgba(113, 113, 122, 0.3)`, text `#FFFFFF`, placeholder `#71717A`.
- **Focus State:** 1px border `#E4E4E7` with zero offset outline and a faint silver specular glow (`0 0 0 1px #E4E4E7`).
- **Checkboxes & Radios:** Sharp 4px geometry (`rounded-sm`). Unselected states carry a `1px solid #71717A` rim against `#121214`. Selected states fill with `#F4F4F5` displaying a contrasting `#000000` glyph.

### Cards & Surfaces
- Structural surface `#121214` with a constant `1px solid rgba(228, 228, 231, 0.08)` border.
- Interactive cards feature an edge sheen transition: hovering increases border opacity to `rgba(244, 244, 245, 0.25)` alongside a subtle top specular gradient highlight (`linear-gradient(180deg, rgba(255,255,255,0.06) 0%, rgba(255,255,255,0) 100%)`).

### Chips & Badges
- Low-profile status tags using `Inter` label typography.
- Filled variant: `#18181B` surface, `1px solid rgba(228, 228, 231, 0.15)`, text `#E4E4E7`.
- Accent/Active variant: `#F4F4F5` fill with `#000000` text for unmissable state confirmation.

### Lists & Data Tables
- Flush, borders-only architecture using `#000000` or `#080808` row baselines.
- Row separators: `1px solid rgba(113, 113, 122, 0.12)`.
- Row hover: `#121214` background tint with an immediate, instant cross-fade.

### Micro-Interactions & Reduced Motion
- Micro-interactions follow high-velocity, precision easing curves (`cubic-bezier(0.16, 1, 0.3, 1)`) with durations bounded between `120ms` and `200ms`.
- **Reduced Motion Mode:** Under `@media (prefers-reduced-motion: reduce)`, all transforms and translation animations are disabled; transitions are instantly replaced with immediate opacity fades (`duration: 50ms`).