# Mos Homepage Taste Redesign — Design Doc

**Date:** 2026-02-25
**Direction:** Precision Instrument (方案 A)
**Skill Reference:** `DESIGN_VARIANCE: 8`, `MOTION_INTENSITY: 6`, `VISUAL_DENSITY: 4`

---

## Summary

A comprehensive aesthetic upgrade of the Mos homepage.
**Constraints:** Pure monochrome (no color accents), add Framer Motion, keep all existing functionality and i18n.
**New dependencies:** `framer-motion` only.

---

## Section 1 — Visual Foundation & Material System

### globals.css changes
- Noise layer: opacity `0.045` → `0.065`, finer grain
- Orb opacity: `0.18` → `0.10`, blur variance for depth
- Background radial gradients: shift to asymmetric positions (`5% 8%` / `88% 14%`)
- FlowField trail: background fill alpha `0.12` → `0.08` (longer trails, more flow)

### Glass card upgrade
```css
.glass {
  background: rgba(8, 9, 14, 0.60);
  box-shadow:
    0 0 0 1px rgba(255,255,255,0.06) inset,
    0 1px 0 rgba(255,255,255,0.12) inset,   /* top-edge highlight line */
    0 32px 120px rgba(0,0,0,0.8);
}
```

### CSS Token changes
- `--radius-xl`: `22px` → `26px`
- New: `--radius-card: 32px` (large cards)
- `shadow-elevated`: depth from `80px` → `120px`

---

## Section 2 — Typography System

| Element | Before | After |
|---------|--------|-------|
| Hero H1 (mobile) | `42px` | `52px` |
| Hero H1 (tablet) | `72px` | `88px` |
| Hero H1 (desktop) | `84px` | `108px` |
| Hero H1 (large) | – | `124px` |
| H1 tracking | default | `tracking-[-0.02em]` |
| H1 line-height | – | `leading-[0.95]` |
| Kicker tracking | `0.18em` | `0.22em` |
| Kicker color | `white/70` | `white/50` |
| Body line-height | `leading-relaxed` | `leading-[1.7]` |
| Mono numerals | – | `tabular-nums` |

---

## Section 3 — Hero Section Redesign

### Layout (md+ splits into two columns)
```
<section> min-h-[100dvh]
  <div> grid grid-cols-1 md:grid-cols-[1fr_auto] gap-12 lg:gap-20 items-center

    LEFT (55%) — unchanged content, upgraded typography + spring entrance
      Badge → H1 line1 → H1 line2 → Lead → CTA group → requirements

    RIGHT (45%, md+ only) — new HeroCurvePanel component
      Glass card ~340×320px
      Static animated SVG scroll curve (stroke-dashoffset animation)
      3 floating parameter badges: step / gain / duration (default values)
      Framer Motion: initial y:30 opacity:0, spring {stiffness:80, damping:18}
      Subtle rotateY:-6deg → 0 on hover
```

### Spring entrance stagger
| Element | Delay |
|---------|-------|
| Badge | 0ms |
| H1 line 1 | 80ms |
| H1 line 2 | 160ms |
| Lead | 220ms |
| CTAs | 280ms |
| Right panel | 340ms |

Spring params: `{ stiffness: 100, damping: 20 }` (all elements)

---

## Section 4 — Bento Grid Asymmetric Layout

### Before
```
Row 1: [col-span-12: Easing]
Row 2: [col-span-6: Axes] [col-span-6: Per-App]
Row 3: [col-span-12: Buttons]
```

### After (md+)
```
Row 1: [col-span-7: Easing Playground]  [col-span-5: Axes Control]   equal height
Row 2: [col-span-5: Per-App Grid]       [col-span-7: Button Bindings] ~60px taller than row 1
```

Pattern: `7+5` ↔ `5+7` alternating columns, row 2 has greater min-height.

### Card internal upgrades
- **Easing card (7/12):** Graph area taller, sliders wider
- **Axes card (5/12):** Toggle rows with `backdrop-blur` grouping box; active toggle has subtle glow
- **Per-App card (5/12):** 2×3 grid (was 3×2), 48px icons, small `smooth` status badge
- **Buttons card (7/12):** Left-key/right-value alignment; one pulsing placeholder row ("recording...")

---

## Section 5 — Framer Motion Animation System

**New dependency:** `framer-motion` (~70KB gz)

### Spring baseline
```ts
const spring = { type: "spring", stiffness: 100, damping: 20 }
```

### Reveal component (upgraded)
- Replace CSS `.reveal`/`.in-view` with `motion.div` + `useInView` from FM
- Keep same `Reveal` component API (`delayMs`, `className` props)
- Remove `.reveal`, `.reveal.in-view` from `globals.css`

### Card 3D hover
```ts
onMouseMove → compute (rotateX: ±4deg, rotateY: ±6deg) from cursor offset
→ motion.div style={{ rotateX, rotateY, transition: "0.1s ease" }}
→ internal radial-gradient spotlight follows cursor
```

### Bento card stagger
- Trigger: `useInView` with `{ once: true, margin: "-80px" }`
- Each card: `y: 28 → 0`, `opacity: 0 → 1`, stagger interval `120ms`

### Items NOT migrated to Framer Motion
- FlowField canvas (keeps RAF)
- `.orb` floats (keep CSS `float-slow` keyframes)
- `homebrew-pulse` / `homebrew-sheen` (keep CSS keyframes)
- `hero-in` CSS (replaced by FM), `stroke-in` (keep for SVG path)

---

## New Components

| Component | File | Purpose |
|-----------|------|---------|
| `HeroCurvePanel` | `app/components/HeroCurvePanel/HeroCurvePanel.tsx` | Static curve SVG + param badges for hero right side |
| `BentoCard` | `app/components/BentoCard/BentoCard.tsx` | Reusable card wrapper with 3D hover FM effect |

---

## Files to Modify

| File | Change |
|------|--------|
| `app/globals.css` | Material tokens, noise, glass, typography, remove `.reveal` CSS |
| `app/layout.tsx` | Font sizes stay, no change needed |
| `app/home-client.tsx` | Hero split layout, bento grid restructure, FM entrance |
| `app/components/Reveal/Reveal.tsx` | Replace CSS with FM `useInView` |
| `app/components/FlowField/FlowField.tsx` | Reduce fill alpha to 0.08 |
| `package.json` | Add `framer-motion` |

---

## Pre-Flight Checklist (from skill)
- [ ] `min-h-[100dvh]` used (already present as `min-h-[100svh]`, upgrade to `100dvh`)
- [ ] No purple/blue glows (confirmed monochrome)
- [ ] No centered hero (confirmed split layout)
- [ ] No 3-column generic cards (confirmed asymmetric 7+5)
- [ ] Animations use `transform`/`opacity` only (hardware accelerated)
- [ ] `prefers-reduced-motion` respected in FM with `useReducedMotion`
- [ ] Mobile layout tested (single-column fallback)
- [ ] Loading/empty states maintained (existing patterns kept)
