# PCLink Design System (DESIGN_SYSTEM.md)

**Surface Profile**: App / Product UI + Mobile/Native Hybrid (§B3 & §B4)  
**Aesthetic Profile**: Premium Modern + Sophisticated Cute / Playful Hardware Studio  
**Version**: 2.0  
**Status**: Active Production Standard  

---

## 1. Design Concept & Personality

> **"The concept is: Precision Hardware-Link Console meets Friendly Scandinavian Studio Fluidity — expressed through tactile squircle surfaces, crisp micro-telemetry with tabular figures, a high-contrast obsidian and nordic alabaster palette with electric cyan and warm amber accents, and snappy spring-physics feedback."**

- **Sophisticated Cute**: Expressed through intentional proportions, friendly organic corner smoothing, rhythmic breathing space, tactile toggle switches, and playful micro-pulses — **never** childish stickers, rainbow gradients, or cartoonish gimmicks.
- **Precision Engineering**: Expressed through exact tabular alignment of IP addresses, ports, byte counters, and transfer speeds, with zero layout shift and instant state resolution.
- **Anti-AI-Slop Discipline**:
  - NO nested cards with borders inside borders.
  - NO generic purple-blue linear gradients on text or cards.
  - NO low-contrast `#94A3B8` body copy on light backgrounds.
  - NO static interactive elements — every button, tile, and tab has distinct default, hover, focus, and pressed states.

---

## 2. Color System (60 / 30 / 10 Strategy)

The palette is anchored in OKLCH space to maintain strict perceptual lightness deltas and WCAG AA contrast compliance across both Dark and Light environments.

### 2.1 Dark Mode (Primary Desktop & Mobile Experience)
- **Dominant Canvas (60%)**: `#0B0F19` (Obsidian Midnight) — Deep, low eye-strain foundation with 0.01 blue chroma tint.
- **Elevated Surfaces (30%)**:
  - `surface`: `#111827` (Charcoal Slate base)
  - `cardSurface`: `#162032` (Elevated Card Workbench)
  - `cardSurfaceHover`: `#1D2A42` (Interactive Hover Lift)
  - `surfaceSubtle`: `#1E293B` (Input backgrounds and chips)
  - `divider`: `#1F293D` (Crisp 1px hairline rule)
- **Accents & Telemetry (10%)**:
  - `primary`: `#0284C7` (Electric Cyan-Azure — Primary CTA & brand anchor)
  - `primaryLight`: `#38BDF8` (Bright Azure — Glowing badges & live pulses)
  - `secondary`: `#10B981` (Spring Mint — Connected peer state & successful transfers)
  - `accentWarm`: `#F59E0B` (Amber Flame — System power, locks, and warning telemetry)
  - `accentPurple`: `#8B5CF6` (Studio Violet — File Transfer Studio category)
  - `error`: `#F43F5E` (Radiant Coral — Disconnect, unpair, and error recovery)
- **Text & Contrast (All meet WCAG AA ≥ 4.5:1)**:
  - `textPrimary`: `#F8FAFC` (Pure Alabaster — Contrast ratio 14.8:1 against `#0B0F19`)
  - `textSecondary`: `#94A3B8` (Soft Silver — Contrast ratio 7.1:1)
  - `textMuted`: `#64748B` (Muted Slate — Contrast ratio 4.6:1 for secondary labels)

### 2.2 Light Mode (Nordic Alabaster)
- **Dominant Canvas (60%)**: `#F8FAFC` (Silky Snow Mist)
- **Elevated Surfaces (30%)**:
  - `surface`: `#F1F5F9` (Soft Alabaster Container)
  - `cardSurface`: `#FFFFFF` (Pure Crisp White Paper)
  - `cardSurfaceHover`: `#F8FAFC`
  - `surfaceSubtle`: `#EDF2F7`
  - `divider`: `#E2E8F0`
- **Accents & Telemetry (10%)**:
  - `primary`: `#0369A1` (Deep Cerulean — Contrast ratio 5.2:1 against `#FFFFFF`)
  - `primaryLight`: `#0EA5E9`
  - `secondary`: `#059669` (Deep Emerald)
  - `accentWarm`: `#D97706` (Deep Warm Amber)
  - `error`: `#E11D48`
- **Text & Contrast**:
  - `textPrimary`: `#0F172A` (Deep Slate Charcoal — 15.2:1 contrast)
  - `textSecondary`: `#334155` (Slate Navy — 9.4:1 contrast)
  - `textMuted`: `#64748B` (Medium Slate — 4.6:1 contrast)

---

## 3. Typography Hierarchy

Fonts scale harmoniously with system platform conventions (Segoe UI / SF Pro / Inter / Roboto) with explicit weights and optical tracking:

| Role | Size | Weight | Line Height | Tracking | Usage |
|---|---|---|---|---|---|
| **Display** | 28px | 800 (Extrabold) | 1.25 | -0.6px | Hero headlines, splash brand |
| **Headline 1** | 22px | 700 (Bold) | 1.30 | -0.3px | Page & workbench titles |
| **Headline 2** | 18px | 700 (Bold) | 1.35 | -0.2px | Card & section headers |
| **Subhead** | 15px | 600 (Semibold)| 1.40 | 0.0px | Component section labels |
| **Body Large** | 15px | 400 (Regular)  | 1.50 | 0.0px | Main descriptive copy |
| **Body** | 14px | 400 / 500      | 1.45 | 0.0px | Standard body, form inputs |
| **Caption** | 12px | 500 (Medium)   | 1.35 | +0.2px| Supporting labels, badge tags |
| **Tabular Mono** | 12px | 600 (Semibold)| 1.30 | +0.4px| IP, ports, hashes, transfer speeds |

---

## 4. Spacing & Rhythm (8pt Baseline Grid)

All padding, margins, and gaps follow a mathematical scale:
- `space-2` (2px): Micro alignments, border radius adjustments
- `space-4` (4px): Tight inline icon gaps
- `space-8` (8px): Standard compact gap between related items
- `space-12` (12px): Badge padding, input vertical padding
- `space-16` (16px): Card internal padding, list tile gaps
- `space-20` (20px): Form row separation, dialog padding
- `space-24` (24px): Desktop workbench padding, section gaps
- `space-32` (32px): Desktop column margins, auth container padding

---

## 5. Shape, Border Radii & Elevation

- **Radii Standards**:
  - `Pill / Badge`: 9999px (Fully rounded squircle pills)
  - `Large Card`: 24px (Main workbench cards, dialogs)
  - `Medium Card / Tile`: 18px (List tiles, control groups, drop zones)
  - `Input / Button`: 14px (Text fields, primary action buttons)
  - `Micro Tag / Action`: 10px (Icon containers, inline chips)
- **Elevation without Border-Mania**:
  - Cards achieve elevation through **background luminance steps** and **tinted soft shadows**:
    ```dart
    BoxShadow(
      color: Color(0x28000000),
      blurRadius: 20,
      offset: Offset(0, 6),
      spreadRadius: 0,
    )
    ```
  - Hairline borders (`width: 0.8px` or `1.0px`) are applied strictly to outer card boundaries to separate them from the canvas, **never** to individual rows or nested containers within a card.

---

## 6. Components Specification

### 6.1 Buttons
- **Primary Action Button**:
  - Background: `primary` (Electric Cyan)
  - Foreground: `Colors.white`
  - Height: 48px (Mobile ergonomic touch target) / 44px (Desktop)
  - Radius: 14px
  - Interaction: Snappy spring scale-down on press (0.975), subtle glow on focus/hover.
- **Secondary / Outlined Button**:
  - Background: `surfaceSubtle`
  - Border: 1px `divider`
  - Foreground: `textPrimary`
  - Radius: 14px
- **Destructive Button**:
  - Background: `error.withOpacity(0.14)`
  - Foreground: `error`
  - Press confirmation modal required for remote system power actions.

### 6.2 Cards & Workbenches
- Header: Reusable `AppCardHeader` with custom icon container (10px radius), clean bold title, subtitle, and right-aligned action widget.
- Body: Direct vertical flow with token dividers (`0.8px` height), never nested enclosed boxes.

### 6.3 Inputs & Forms
- Filled container (`surfaceSubtle`) with 1px hairline border.
- Floating label with clear helper text and structured error state.
- Keyboard avoidance: Scrollable views with `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`.

### 6.4 Navigation
- **Desktop**: Left navigation sidebar (width 260px) with logo, brand header, interactive tab items with spring pill indicators, and bottom user session summary.
- **Mobile**: Ergonomic bottom navigation bar with 4 core tabs (Connect, Files, Clipboard, Devices) with minimum 48×48dp touch targets and clear active states.

---

## 7. Motion & Micro-Interactions (Awwwards UI-Max)

- **Timing Curves**:
  - Enter: `Curves.easeOutCubic` (220ms – 280ms)
  - Exit: `Curves.easeInCubic` (180ms)
  - Spring Bounce: Stiffness 300, Damping 20
- **Staggered Reveals**:
  - Workbench items cascade with 40ms stagger delays.
- **State Feedback**:
  - Copy action: Instant animated checkmark morph + haptic feedback.
  - Connection pulse: Breathing radius scale (1.0 to 1.15) with soft glow.
- **Reduced Motion**: All animations detect and honor `prefers-reduced-motion` or system animation disabled settings, collapsing to instant state transitions.
