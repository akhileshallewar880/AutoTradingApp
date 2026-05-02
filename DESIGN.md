---
name: VanTrade
description: >
  AI-powered swing trading assistant for Indian equity markets (NSE/BSE).
  The interface is a clean, data-dense Material 3 dashboard that surfaces
  real-time Zerodha portfolio data, AI-generated trade recommendations, and
  holding analytics with confident, colour-coded financial signals.

colors:
  # ── Primary brand – trading action green ───────────────────────────────
  primary:          "#388E3C"   # green-700  AppBar, CTA buttons, BUY badges
  primary-light:    "#43A047"   # green-600  hover / active tint
  primary-surface:  "#E8F5E9"   # green-50   filled badge backgrounds, progress fills
  primary-border:   "#A5D6A7"   # green-200  outline badges, progress tracks

  # ── Danger – loss / SELL ────────────────────────────────────────────────
  danger:           "#E53935"   # red-600    SELL badges, loss text, decline icons
  danger-light:     "#EF5350"   # red-400    hover tint
  danger-surface:   "#FFEBEE"   # red-50     loss tile backgrounds
  danger-border:    "#EF9A9A"   # red-200    outline borders

  # ── Info – neutral statistics ───────────────────────────────────────────
  info:             "#1976D2"   # blue-700   informational icons, stats, links
  info-light:       "#1E88E5"   # blue-600
  info-surface:     "#E3F2FD"   # blue-50    info tile backgrounds
  info-border:      "#90CAF9"   # blue-200

  # ── Secondary brand – holdings screen ──────────────────────────────────
  secondary:        "#303F9F"   # indigo-700 Holdings AppBar, header gradient start
  secondary-mid:    "#3949AB"   # indigo-600 gradient end
  secondary-surface:"#E8EAF6"   # indigo-50  light tints
  secondary-border: "#C5CAE9"   # indigo-100

  # ── Warning – charges, caution ──────────────────────────────────────────
  warning:          "#F57C00"   # orange-700 charge tiles, caution badges
  warning-surface:  "#FFF8E1"   # amber-50   demo-mode banner, info boxes
  warning-border:   "#FFE082"   # amber-200

  # ── Neutrals ────────────────────────────────────────────────────────────
  surface:          "#FFFFFF"
  background:       "#FFFFFF"
  divider:          "#E0E0E0"   # grey-300
  outline:          "#BDBDBD"   # grey-400
  on-surface-low:   "#9E9E9E"   # grey-500   captions, secondary labels
  on-surface-mid:   "#757575"   # grey-600   body text
  on-surface-high:  "#616161"   # grey-700   subheadings
  on-surface:       "#212121"   # grey-900   primary text
  on-primary:       "#FFFFFF"

  # ── AI loading overlay (full-screen dark gradient) ─────────────────────
  overlay-dark-1:   "#0A0E1A"   # deep navy
  overlay-dark-2:   "#0D1F12"   # dark forest green
  overlay-dark-3:   "#0A1628"   # deep ocean blue
  ai-accent-green:  "#00E676"   # bright neon green   AI core glow
  ai-accent-teal:   "#00BCD4"   # cyan   AI shimmer
  ai-accent-yellow: "#FFD740"   # gold   particle sparks
  ai-accent-red:    "#FF5252"   # coral red   alert particles

typography:
  font-family: "Roboto, system-ui, sans-serif"   # Flutter default Material font

  # Size scale (all values in logical pixels)
  size-xs:    9
  size-sm:   10
  size-sm2:  11
  size-base: 12
  size-md:   13
  size-md2:  14
  size-lg:   15
  size-lg2:  16
  size-xl:   18
  size-xl2:  20
  size-2xl:  22
  size-3xl:  24
  size-4xl:  28
  size-5xl:  32
  size-6xl:  38

  # Weight aliases
  weight-regular:   400
  weight-medium:    500
  weight-semibold:  600
  weight-bold:      700
  weight-black:     900

  # Line heights
  line-tight:    1.3
  line-normal:   1.4
  line-relaxed:  1.5

  # Letter spacing (sp)
  tracking-tight:  0.4
  tracking-normal: 0.5
  tracking-wide:   0.8
  tracking-wider:  1.4
  tracking-widest: 3.0

  # Role scale
  roles:
    appbar-title:    { size: 20, weight: 700 }
    section-header:  { size: 16, weight: 700 }
    card-title:      { size: 16, weight: 700 }
    body:            { size: 14, weight: 400, color: on-surface-mid }
    label:           { size: 12, weight: 500, color: on-surface-low }
    caption:         { size: 11, weight: 400, color: on-surface-low }
    badge:           { size: 11, weight: 600 }
    stat-value:      { size: 18, weight: 700 }
    large-number:    { size: 22, weight: 700 }
    screen-heading:  { size: 24, weight: 700, color: on-surface }
    hero-heading:    { size: 28, weight: 700 }
    overlay-title:   { size: 22, weight: 900, tracking: 3.0 }

spacing:
  # 4-point base grid
  0:   0
  1:   2
  2:   4
  3:   6
  4:   8
  5:  10
  6:  12
  7:  14
  8:  16
  9:  20
  10: 24
  11: 32
  12: 40
  13: 48

  # Semantic aliases
  gap-xs:    4
  gap-sm:    6
  gap-md:    8
  gap-lg:   12
  gap-xl:   16
  gap-2xl:  20
  gap-3xl:  24
  gap-4xl:  32

  # Standard insets
  inset-card:    16   # all sides – default card padding
  inset-compact:  8
  inset-screen:  16   # horizontal page margin
  inset-dialog:  24

radii:
  none:    0
  xs:      2
  sm:      4
  md:      6
  lg:      8
  xl:     10
  2xl:    12
  3xl:    14
  card:   16   # primary card radius
  pill:   20   # badge / chip pill
  circle: 9999

elevation:
  flat:      0
  low:       1
  default:   2   # Card default
  raised:    3
  modal:     8

shadows:
  subtle: "0 1px 4px rgba(0,0,0,0.04)"
  card:   "0 2px 8px rgba(0,0,0,0.08)"
  raised: "0 4px 16px rgba(0,0,0,0.12)"

motion:
  # Durations (ms)
  instant:       150
  fast:          200
  normal:        300
  moderate:      400
  slow:          600
  deliberate:    800

  # Named interaction timings
  toggle:        200   # period-pill / tab switches
  card-expand:   300   # StockCard expand/collapse
  loading-step:  400   # AI loading bar increments
  pulse:        1400   # confidence / glow pulses
  orbit:        6000   # AI particle orbit loop

  # Curves
  ease-in:      "easeIn"
  ease-out:     "easeOut"
  ease-in-out:  "easeInOut"
  overshoot:    "easeOutBack"
  bounce:       "elasticOut"
  default:      "easeInOut"

icons:
  set:          "Material Design Icons"
  size-micro:    7
  size-tiny:    12
  size-small:   16
  size-default: 20
  size-medium:  24
  size-large:   32
  size-xl:      48
  size-hero:    60
---

# VanTrade — Design System

## Brand Identity

VanTrade is an **AI-assisted equity trading companion** for Indian retail investors. The visual language is intentionally professional and data-forward — closer to a Bloomberg terminal than a consumer fintech app — but kept warm enough for individual investors through consistent use of full-color financial signals (green = profit/buy, red = loss/sell) rather than abstract corporate blues.

The interface rewards expertise: it shows maximum information density on the home dashboard while keeping each individual screen scannable via clear typographic hierarchy and colour-coded semantic groups.

---

## Colour System

### Semantic Colour Logic

The palette is built around **financial signal conventions** that every Indian equity trader already knows:

| Signal | Color | Usage |
|--------|-------|-------|
| BUY / Profit / Up | `primary` (#388E3C green-700) | Action buttons, win indicators, positive P&L |
| SELL / Loss / Down | `danger` (#E53935 red-600) | Short badges, loss tiles, red candles |
| Neutral data | `info` (#1976D2 blue-700) | Trade counts, days-to-target, index prices |
| Holdings identity | `secondary` (#303F9F indigo-700) | Holdings AppBar + header gradient |
| Charges / caution | `warning` (#F57C00 orange-700) | Brokerage charges, caution notices |

Never use green for anything other than positive-financial signals, and never use red for decorative purposes. These colours carry strong semantic weight and breaking that contract destroys user trust at a glance.

### Tint System

Each semantic colour has a corresponding **surface** (5% opacity tint) and **border** (light outline shade) used for filled badge backgrounds and container outlines. These prevent visual noise — a full `primary` tile next to another `primary` tile is jarring; a `primary-surface` tile with a `primary-border` outline at 20% opacity reads clearly without competing with action elements.

### AI Overlay Palette

The full-screen AI analysis loading screen uses a separate dark gradient palette (`overlay-dark-*`) with neon accent colours (`ai-accent-*`) to signal that the device is doing something computationally significant. This dark mode island inside the otherwise light app creates a powerful "working" state — do not use these colours anywhere else.

---

## Typography

The app uses Flutter's default **Roboto** (rendered as the system font on both Android and iOS). No custom typeface is loaded; this is intentional — it keeps the APK lean and leverages native rendering.

### Hierarchy

```
Screen titles (28–32px, w700)     ← Holdings header, empty-state headings
Section headers (16px, w700)      ← "Open Positions", "Active GTTs"
Card titles (16px, w700)          ← "Portfolio Overview"
Body / values (14px, w400–500)    ← Prices, quantities, descriptions
Labels (12–13px, w500–600)        ← Field names, stat labels
Captions (10–11px, w400)          ← Timestamps, footnotes, badge text
```

Font weight increases by one tier when text appears on a coloured background (e.g., white text on the indigo Holdings header uses w700, not w500) to compensate for the reduced contrast.

The AI loading overlay title uses **weight-900 with 3.0 letter-spacing** for a distinctive machine-vision aesthetic, isolated entirely to that screen.

---

## Spacing & Layout

All spacing derives from a **4-point grid**. The most common token is `gap-xl` (16px), which serves as both the standard card padding and the horizontal screen margin.

```
Horizontal screen margin:  16px (inset-screen)
Card internal padding:     16px all sides (inset-card)
Between cards in a list:   12px (gap-lg)
Between label and value:   4–6px
Between related sections:  16–20px
Between unrelated sections:24–32px
```

The holdings header card uses `inset-card: 20px` to give the summary figures more breathing room — the only deliberate exception to the 16px default.

---

## Cards & Surfaces

Cards are the primary layout primitive. Every data group lives in a `Card` with:

- **Elevation:** 2 (default Material shadow)
- **Radius:** 16px (`radii.card`) — noticeably rounded but not bubbly
- **Background:** white surface
- **Padding:** 16px all sides

Cards never have explicit outlines in their default state — elevation and white fill provide enough visual separation against the light grey scaffold background. The only cards with explicit borders are **status/info tiles** (confidence banner, GTT protection section) where a coloured border reinforces the semantic meaning of the fill colour.

### Card Variants

| Variant | Distinguishing traits |
|---------|----------------------|
| Default data card | elevation 2, white fill, 16px radius |
| Holdings header | indigo-700 → indigo-500 gradient, white text, 16px radius |
| Info/status tile | coloured border + 8% tint fill, no elevation |
| Empty-state container | no border, no elevation; centred icon circle 120px |

---

## Buttons

### Primary Action (ElevatedButton)
- Background: `primary` (#388E3C)
- Text: white, 14–16px, w600
- Radius: 12px
- Padding: 16px horizontal, 8px vertical
- Used for: "Run Analysis", "Confirm & Execute", "View Holdings"

### Secondary Action (OutlinedButton)
- Border: `primary` 2px
- Text: `primary`, same size/weight
- Radius: 12px
- Used for: "Cancel", "Back"

### Pill Toggle (Custom)
- Selected: `info` (#1976D2) fill, white text
- Unselected: grey-100 fill, grey-700 text, grey-300 border
- Radius: 20px (pill)
- Padding: 12px horizontal, 5px vertical
- Font: 12px, w600
- Transition: 200ms easeInOut (`motion.toggle`)

### Quantity Stepper Button (Custom)
- Size: 28×28px circle
- Active: `primary` fill, white icon 18px
- Disabled: grey-300 fill, grey-500 icon

---

## Badges & Chips

### Action Badge (BUY / SELL)
- BUY: `primary-surface` fill + `primary-border` outline, `primary` text, 8px radius
- SELL: `danger-surface` fill + `danger-border` outline, `danger` text, 8px radius
- Font: 11–12px, w600
- Padding: 8px horizontal, 6px vertical

### Status Pill (Market Open / Closed)
- Radius: 20px pill
- Live indicator dot: 7×7px circle, same colour as text
- Padding: 10px horizontal, 5px vertical

### Hold Duration Badge
- `info-surface` fill + `info-border` outline
- Icon: `timer_outlined`, 13px, `info` colour
- Font: 12px, w600, `info` colour

### Sector Chip
- `primary-surface` fill + `primary-border` 1px outline
- Font: 11px, w400
- Uses Flutter `Chip` with zero label padding (compact)

---

## Data Visualisation

### Confidence Progress Bar
The overall confidence banner is the most prominent data visualisation on the results screen:

- Full-width linear progress bar, 6px tall, radius 4px
- Track: 15% opacity of the signal colour
- Fill: solid signal colour
- Colour-coded thresholds: ≥80% → `primary`, 70–79% → `warning`, <70% → `danger`
- Label: "High / Moderate / Low" in signal colour, 13px, w600
- Large percentage number: 22px, w700, right-aligned

### Win/Loss Progress Bar (Home Screen)
- 6px tall, `primary` fill on `danger-surface` track
- Always shown when trade count > 0
- Win count left-aligned in `primary` text; loss count right-aligned in `danger` text

---

## Financial Signal Conventions

These rules must never be broken:

1. **Positive P&L / profit / wins** → always rendered in `primary` (green)
2. **Negative P&L / loss / losses** → always rendered in `danger` (red)
3. **Neutral counts (trades, positions)** → `info` (blue)
4. **Charges / costs** → `warning` (orange)
5. **Unrealised vs realised** → same colours but labelled explicitly; unrealised values may be shown in a slightly muted tint

Arrows accompany P&L values: `arrow_upward` for positive, `arrow_downward` for negative. These arrows must match the text colour — never use a green arrow next to red text.

---

## Iconography

Material Design Icons throughout (Flutter's `Icons.*` namespace). No custom icon pack.

| Size | Context |
|------|---------|
| 7px  | Live indicator dots |
| 12px | Inline label icons |
| 16–20px | Card header icons |
| 24px | Section header icons, AppBar actions |
| 48–60px | Empty-state illustration icons |

Icons always inherit the colour of their surrounding semantic context — a BUY card's icon is `primary`, a SELL card's icon is `danger`. Icons are never decorative in isolation; they always reinforce the adjacent text signal.

---

## Motion & Animation

### Interaction Transitions
- Tab / pill switches: 200ms `easeInOut` — fast enough to feel instant but visible
- Card expand / collapse: 300ms `easeInOut`
- All `AnimatedContainer` transitions: 200ms

### AI Loading Overlay
The full-screen AI analysis overlay has a carefully sequenced animation:

1. **0ms** — Dark gradient background fades in
2. **600ms** — Circular progress arc draws itself
3. **600→1100ms** — Central AI icon fades in
4. **1100→1500ms** — Stat counters count up
5. **0–28s** — Progress bar advances; step dots cycle at 2800ms intervals
6. **Indefinite** — Particle orbits rotate at 6000ms per revolution; core pulses at 1400ms

This sequence is intentionally theatrical — it signals that the AI is doing real work, not just a spinner.

### Confidence / Status Pulses
Confidence indicators and GTT protection badges pulse gently at 1400ms to signal "live" data without being distracting.

---

## Screen-Level Themes

Most screens use the **primary green** AppBar (`#388E3C`). The Holdings screen deliberately breaks this with an **indigo** AppBar (`#303F9F`) and an indigo gradient header card — this visual shift helps users immediately orient themselves when they navigate to their portfolio, separating it from the analysis/trading flow.

The AI loading overlay is the only full-screen dark-mode surface. All other screens are light.

---

## Accessibility Principles

- All body text meets WCAG AA on white backgrounds (grey-600 #757575 on white = 4.6:1)
- Semantic colours are always paired with icons and labels — colour alone never conveys meaning
- Touch targets: minimum 44×44px for all interactive controls
- Quantity stepper buttons are 28px but padded to ≥44px tap area
- Disabled states use grey-300 fill + grey-500 text (never just opacity reduction)
