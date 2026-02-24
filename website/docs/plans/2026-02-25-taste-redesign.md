# Mos Homepage Taste Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the Mos homepage to "Precision Instrument" aesthetic — upgraded material quality, asymmetric bento grid, Framer Motion spring entrance/3D-hover, split Hero layout.

**Architecture:** Pure monochrome stays; quality comes from layered glass materials, diffusion shadows, and spring physics. Framer Motion replaces CSS reveal animations; CSS canvas/orb animations stay. A new `BentoCard` wraps all feature cards with 3D hover. A new `HeroCurvePanel` adds a right-column visual to the Hero.

**Tech Stack:** Next.js 16, React 19, Tailwind CSS v3, Framer Motion v11, TypeScript

---

## Task 1: Install framer-motion

**Files:**
- Modify: `package.json`

**Step 1: Install the package**

```bash
cd /Users/caldis/Code/Mos/website
pnpm add framer-motion@^11
```

**Step 2: Verify install**

Run: `grep framer package.json`
Expected output: `"framer-motion": "^11.x.x"`

**Step 3: Commit**

```bash
git add package.json pnpm-lock.yaml
git commit -m "feat: add framer-motion dependency"
```

---

## Task 2: Upgrade globals.css — material tokens, glass, orbs

**Files:**
- Modify: `app/globals.css`

This task upgrades the visual foundation. No JS changes.

**Step 1: Update `:root` tokens**

In `app/globals.css`, replace the `:root` block:

```css
:root {
  --bg0: #000000;
  --bg1: #090909;
  --fg0: rgba(255, 255, 255, 0.92);
  --fg1: rgba(255, 255, 255, 0.72);
  --fg2: rgba(255, 255, 255, 0.52);
  --border: rgba(255, 255, 255, 0.12);

  --accent: #ffffff;
  --accent2: #a1a1aa;
  --accent3: #52525b;

  --radius-xl: 26px;
  --radius-card: 32px;

  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);

  --noise-opacity: 0.065;
}
```

**Step 2: Update body background to asymmetric positions**

Replace the `body` background gradient block:

```css
body {
  color: var(--fg0);
  background:
    radial-gradient(1100px 680px at 5% 8%, rgba(255, 255, 255, 0.10), transparent 55%),
    radial-gradient(900px 620px at 88% 14%, rgba(255, 255, 255, 0.06), transparent 55%),
    radial-gradient(1100px 820px at 45% 92%, rgba(255, 255, 255, 0.045), transparent 60%),
    linear-gradient(180deg, var(--bg0), var(--bg1));
  font-family:
    var(--font-body),
    ui-sans-serif,
    system-ui,
    -apple-system,
    BlinkMacSystemFont,
    "Segoe UI",
    Helvetica,
    Arial,
    "Apple Color Emoji",
    "Segoe UI Emoji";
  text-rendering: geometricPrecision;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
```

**Step 3: Upgrade `.glass` utility**

Replace the `.glass` block inside `@layer utilities`:

```css
.glass {
  background: rgba(8, 9, 14, 0.60);
  border: 1px solid var(--border);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  box-shadow:
    0 0 0 1px rgba(255,255,255,0.06) inset,
    0 1px 0 rgba(255,255,255,0.12) inset,
    0 32px 120px rgba(0,0,0,0.8);
}
```

**Step 4: Upgrade `.shadow-elevated` utility**

```css
.shadow-elevated {
  box-shadow:
    0 32px 120px rgba(0, 0, 0, 0.80),
    0 1px 0 rgba(255, 255, 255, 0.08) inset;
}
```

**Step 5: Update `.orb` opacity**

Change `opacity: 0.18` → `opacity: 0.10` in the `.orb` block.

**Step 6: Remove the `.reveal` and `.reveal.in-view` CSS**

Delete these blocks entirely (they will be replaced by Framer Motion in Task 3):

```css
/* DELETE THESE: */
.reveal { ... }
.reveal.in-view { ... }
```

Also delete the `@media (scripting: none)` block that mentions `.reveal`:
```css
/* DELETE: */
@media (scripting: none) {
  .reveal { ... }
}
```

Keep `@keyframes hero-in` for now (removed in Task 6).
Keep `.ring-accent`, `.hairline`, `.orb`, `.homebrew-highlight`, etc.

**Step 7: Remove the `prefers-reduced-motion` `.reveal` rule**

The `@media (prefers-reduced-motion: reduce)` block at the bottom has no `.reveal` rules, so nothing to delete there. Keep `homebrew-highlight` reduced-motion rules.

**Step 8: Start dev server and visually verify**

```bash
pnpm dev
```

Open http://localhost:3000. The page should look the same in structure but with:
- Slightly denser noise texture
- Deeper card shadows
- Top-edge highlight line visible on glass cards (nav bar)
- Note: the page may look broken because Reveal CSS was removed — that's OK, Task 3 fixes it.

**Step 9: Commit**

```bash
git add app/globals.css
git commit -m "style: upgrade material tokens, glass highlight, deeper shadows"
```

---

## Task 3: Upgrade Reveal.tsx to Framer Motion

**Files:**
- Modify: `app/components/Reveal/Reveal.tsx`

The old implementation uses `IntersectionObserver` + CSS class toggling. Replace with Framer Motion `useInView` + `motion.div`.

**Step 1: Replace the entire file content**

```tsx
"use client";

import { motion, useInView, useReducedMotion } from "framer-motion";
import { ReactNode, useRef } from "react";

const SPRING = { type: "spring" as const, stiffness: 100, damping: 20 };

const variants = {
  hidden: { opacity: 0, y: 24, filter: "blur(12px)" },
  visible: { opacity: 1, y: 0, filter: "blur(0px)" },
};

export function Reveal({
  children,
  className = "",
  delayMs = 0,
}: {
  children: ReactNode;
  className?: string;
  delayMs?: number;
}) {
  const ref = useRef<HTMLDivElement | null>(null);
  const shouldReduceMotion = useReducedMotion();
  const inView = useInView(ref, {
    once: true,
    margin: "40px 0px -10% 0px",
  });

  return (
    <motion.div
      ref={ref}
      className={className}
      variants={variants}
      initial={shouldReduceMotion ? "visible" : "hidden"}
      animate={inView ? "visible" : "hidden"}
      transition={{ ...SPRING, delay: delayMs / 1000 }}
    >
      {children}
    </motion.div>
  );
}
```

**Step 2: Verify dev server**

```bash
pnpm dev
```

Open http://localhost:3000. Scroll through the page — all sections should fade+slide in with spring motion. No broken layout.

**Step 3: Commit**

```bash
git add app/components/Reveal/Reveal.tsx
git commit -m "feat: replace CSS reveal with Framer Motion spring useInView"
```

---

## Task 4: Create BentoCard component with 3D hover

**Files:**
- Create: `app/components/BentoCard/BentoCard.tsx`

This wraps bento feature cards with a 3D hover tilt effect. The card rotates slightly toward the cursor, and a spotlight follows the cursor inside the card.

**Step 1: Create the file**

```tsx
"use client";

import {
  motion,
  useMotionTemplate,
  useMotionValue,
  useReducedMotion,
  useSpring,
  useTransform,
} from "framer-motion";
import { MouseEvent, ReactNode } from "react";

const SPRING = { stiffness: 150, damping: 30 };

export function BentoCard({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  const shouldReduceMotion = useReducedMotion();

  const mouseX = useMotionValue(0.5);
  const mouseY = useMotionValue(0.5);

  const rawRotateX = useTransform(mouseY, [0, 1], [4, -4]);
  const rawRotateY = useTransform(mouseX, [0, 1], [-6, 6]);
  const rotateX = useSpring(rawRotateX, SPRING);
  const rotateY = useSpring(rawRotateY, SPRING);

  const spotX = useTransform(mouseX, [0, 1], [0, 100]);
  const spotY = useTransform(mouseY, [0, 1], [0, 100]);
  const spotlight = useMotionTemplate`radial-gradient(480px circle at ${spotX}% ${spotY}%, rgba(255,255,255,0.08), transparent 60%)`;

  const handleMouseMove = (e: MouseEvent<HTMLDivElement>) => {
    if (shouldReduceMotion) return;
    const rect = e.currentTarget.getBoundingClientRect();
    mouseX.set((e.clientX - rect.left) / rect.width);
    mouseY.set((e.clientY - rect.top) / rect.height);
  };

  const handleMouseLeave = () => {
    mouseX.set(0.5);
    mouseY.set(0.5);
  };

  return (
    <motion.div
      className={`group relative h-full rounded-[var(--radius-card)] glass shadow-elevated overflow-hidden border border-white/10 ${className}`}
      style={
        shouldReduceMotion
          ? {}
          : { rotateX, rotateY, transformPerspective: 1200 }
      }
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
    >
      {/* Cursor-following spotlight */}
      <motion.div
        className="pointer-events-none absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500"
        style={{ background: spotlight }}
      />
      {children}
    </motion.div>
  );
}
```

**Step 2: Verify (no visual change yet, just ensure no TypeScript errors)**

```bash
pnpm build 2>&1 | head -40
```

Expected: no TypeScript errors related to BentoCard.

**Step 3: Commit**

```bash
git add app/components/BentoCard/BentoCard.tsx
git commit -m "feat: add BentoCard with 3D cursor-tilt and spotlight hover"
```

---

## Task 5: Create HeroCurvePanel component

**Files:**
- Create: `app/components/HeroCurvePanel/HeroCurvePanel.tsx`

A purely presentational right-column panel for the Hero section. Shows an animated SVG scroll curve (no sliders) with three floating parameter badges.

**Step 1: Create the file**

```tsx
"use client";

import { motion, useReducedMotion } from "framer-motion";

const SPRING = { type: "spring" as const, stiffness: 80, damping: 18 };

// Pre-computed path representing a typical Mos smooth-scroll curve:
// fast rise to peak, then smooth exponential decay.
// ViewBox: 0 0 400 200 (y=200 is baseline, y=0 is max speed)
const CURVE_D =
  "M 0 192 C 8 192 18 28 48 16 S 96 14 128 22 S 192 52 248 102 S 320 162 400 188";

const PARAMS = [
  { label: "STEP", value: "33.6" },
  { label: "GAIN", value: "×2.7" },
  { label: "DURATION", value: "4.35s" },
];

export function HeroCurvePanel() {
  const shouldReduceMotion = useReducedMotion();

  return (
    <motion.div
      className="hidden md:block w-[280px] lg:w-[320px] xl:w-[340px] shrink-0"
      initial={shouldReduceMotion ? false : { opacity: 0, y: 30 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ ...SPRING, delay: 0.34 }}
    >
      <motion.div
        className="relative rounded-[var(--radius-card)] glass shadow-elevated border border-white/10 overflow-hidden p-5"
        style={{ transformPerspective: 1200 }}
        whileHover={shouldReduceMotion ? {} : { rotateY: -3 }}
        transition={SPRING}
      >
        {/* Panel label */}
        <div className="font-display text-[10px] tracking-[0.22em] uppercase text-white/45 mb-4">
          Smooth Scroll Curve
        </div>

        {/* Animated SVG curve */}
        <div className="rounded-2xl border border-white/8 bg-black/30 overflow-hidden">
          <svg
            viewBox="0 0 400 200"
            className="block w-full h-auto"
            aria-hidden="true"
          >
            <defs>
              <linearGradient id="heroCurveFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="rgba(255,255,255,0.14)" />
                <stop offset="100%" stopColor="rgba(255,255,255,0)" />
              </linearGradient>
            </defs>

            {/* Grid lines */}
            <g stroke="rgba(255,255,255,0.06)" strokeWidth="1">
              {[0, 1, 2, 3].map((i) => (
                <line
                  key={`vl-${i}`}
                  x1={i * 133}
                  y1="8"
                  x2={i * 133}
                  y2="196"
                />
              ))}
              {[0, 1, 2, 3].map((i) => (
                <line
                  key={`hl-${i}`}
                  x1="0"
                  y1={8 + i * 62}
                  x2="400"
                  y2={8 + i * 62}
                />
              ))}
            </g>

            {/* Area fill under curve */}
            <path
              d={`${CURVE_D} L 400 192 L 0 192 Z`}
              fill="url(#heroCurveFill)"
              opacity="0.9"
            />

            {/* Animated stroke */}
            <path
              d={CURVE_D}
              fill="none"
              stroke="rgba(255,255,255,0.90)"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              pathLength={1}
              strokeDasharray={1}
              strokeDashoffset={1}
              style={{
                animation: "stroke-in 1200ms var(--ease-out) 500ms both",
              }}
            />
          </svg>
        </div>

        {/* Parameter badges */}
        <div className="mt-4 grid grid-cols-3 gap-2">
          {PARAMS.map((p) => (
            <div
              key={p.label}
              className="rounded-xl border border-white/8 bg-white/4 px-2.5 py-2"
            >
              <div className="font-display text-[9px] tracking-[0.18em] uppercase text-white/40">
                {p.label}
              </div>
              <div className="mt-1 font-mono text-sm tabular-nums text-white/80">
                {p.value}
              </div>
            </div>
          ))}
        </div>
      </motion.div>
    </motion.div>
  );
}
```

**Step 2: Verify no TypeScript errors**

```bash
pnpm build 2>&1 | head -40
```

**Step 3: Commit**

```bash
git add app/components/HeroCurvePanel/HeroCurvePanel.tsx
git commit -m "feat: add HeroCurvePanel static SVG curve for Hero right column"
```

---

## Task 6: Hero layout — split grid + FM entrance, upgraded typography

**Files:**
- Modify: `app/home-client.tsx`

This is the largest change. We:
1. Import FM and HeroCurvePanel
2. Replace CSS `motion-safe:animate-[hero-in_...]` on every hero element with `motion.div` FM stagger
3. Upgrade hero font sizes
4. Add the two-column grid wrapper
5. Remove `min-h-screen` (keep only `min-h-[100dvh]`)

**Step 1: Add imports at the top of home-client.tsx**

After the existing imports, add:
```tsx
import { motion, useReducedMotion } from "framer-motion";
import { HeroCurvePanel } from "./components/HeroCurvePanel/HeroCurvePanel";
```

Also add `useReducedMotion` to the top-level component — add this inside `HomeClient()`:
```tsx
const shouldReduceMotion = useReducedMotion();
```

**Step 2: Define hero spring at module level (above `HomeClient`)**

```tsx
const HERO_SPRING = { type: "spring" as const, stiffness: 100, damping: 20 };

function heroMotion(delayS: number, shouldReduceMotion: boolean | null) {
  return {
    initial: shouldReduceMotion ? false : ({ opacity: 0, y: 24 } as const),
    animate: { opacity: 1, y: 0 } as const,
    transition: { ...HERO_SPRING, delay: delayS },
  };
}
```

**Step 3: Replace the hero `<section>` in the JSX**

Find the hero section (starts at `<section className="relative min-h-screen min-h-[100svh] ...`).

Replace the entire section with the code below. Key changes:
- `min-h-screen min-h-[100svh]` → `min-h-[100dvh]`
- inner `<div className="w-full">` → `<div className="w-full grid grid-cols-1 md:grid-cols-[1fr_auto] gap-12 lg:gap-20 items-center">`
- All hero elements wrapped in `<motion.div {...heroMotion(delay, shouldReduceMotion)}>`
- Font sizes on `<h1>` upgraded
- `<HeroCurvePanel />` added as second grid column

```tsx
<section className="relative min-h-[100dvh] pt-28 sm:pt-36 pb-10 sm:pb-12 flex flex-col">
  <div className="flex-1 flex items-center">
    <div className="w-full grid grid-cols-1 md:grid-cols-[1fr_auto] gap-12 lg:gap-20 items-center">

      {/* Left column */}
      <div>
        <motion.div
          className="inline-flex items-center gap-3 rounded-full border border-white/10 bg-black/40 px-4 py-2 text-xs text-white/70 shadow-elevated"
          {...heroMotion(0, shouldReduceMotion)}
        >
          <span className="inline-flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-[color:var(--accent)] shadow-[0_0_22px_rgba(255,255,255,0.35)]" />
            {t.hero.badgeLine1}
          </span>
          <span className="hidden sm:inline text-white/35">•</span>
          <span className="hidden sm:inline font-mono text-white/45">
            {t.hero.badgeLine2}
          </span>
        </motion.div>

        <motion.h1
          className="mt-7 font-display text-balance text-[52px] leading-[0.95] tracking-[-0.02em] sm:text-[88px] md:text-[108px] lg:text-[124px] text-white"
          {...heroMotion(0.08, shouldReduceMotion)}
        >
          {t.hero.titleLine1}
          <span className="block">
            {t.hero.titleLine2Before}
            <span
              className="inline-block text-flow"
              style={{ textShadow: "0 0 42px rgba(255,255,255,0.08)" }}
            >
              {t.hero.titleLine2Highlight}
            </span>
            {t.hero.titleLine2After}
          </span>
        </motion.h1>

        <motion.p
          className="mt-5 max-w-2xl text-balance text-[15px] sm:text-lg text-white/72 leading-[1.7]"
          {...heroMotion(0.18, shouldReduceMotion)}
        >
          {t.hero.lead}
        </motion.p>

        <motion.div
          className="mt-8 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-4"
          {...heroMotion(0.26, shouldReduceMotion)}
        >
          <div className="flex flex-col items-start w-fit">
            <Magnetic strength={22}>
              <a
                href={downloadUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="group relative overflow-hidden rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-black shadow-elevated border border-black/10 inline-flex items-center justify-center"
                style={{
                  background:
                    "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                }}
              >
                <span className="relative z-10">{t.hero.ctaDownload}</span>
                <span className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 [background:radial-gradient(800px_240px_at_30%_0%,rgba(0,0,0,0.18),transparent_55%)]" />
              </a>
            </Magnetic>
            <a
              href="#homebrew"
              onClick={(e) => {
                e.preventDefault();
                scrollToHomebrew();
              }}
              className="mt-2 self-center text-xs font-mono text-white/50 hover:text-white/75 transition-colors underline decoration-white/15 hover:decoration-white/35 underline-offset-4"
            >
              {t.hero.ctaInstallHomebrew}
            </a>
          </div>

          <Magnetic strength={14}>
            <a
              href="https://github.com/Caldis/Mos"
              target="_blank"
              rel="noopener noreferrer"
              className="group inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
            >
              <span className="mr-2 opacity-70 group-hover:opacity-100 transition-opacity">↗</span>
              <span>{t.hero.ctaViewGitHub}</span>
            </a>
          </Magnetic>

          <div className="sm:ml-auto sm:self-center text-xs text-white/45">
            <div className="font-mono tabular-nums">{t.hero.requirementsLine1}</div>
            <div className="font-mono">{t.hero.requirementsLine2}</div>
          </div>
        </motion.div>
      </div>

      {/* Right column — visible md+ only (hidden on mobile via HeroCurvePanel internals) */}
      <HeroCurvePanel />
    </div>
  </div>

  <div className="mt-8 sm:mt-10 flex items-center gap-3 text-white/40">
    <div className="h-[1px] flex-1 hairline" />
    <div className="font-mono text-[11px] tracking-[0.18em] uppercase">
      {t.hero.scrollHint}
    </div>
    <div className="h-[1px] flex-1 hairline" />
  </div>
</section>
```

**Step 4: Remove `@keyframes hero-in` from globals.css**

Now that hero elements use Framer Motion, the `hero-in` keyframe is unused. Open `app/globals.css` and delete the `@keyframes hero-in` block:

```css
/* DELETE THIS: */
@keyframes hero-in {
  from { ... }
  to { ... }
}
```

**Step 5: Visual verify on dev server**

```bash
pnpm dev
```

- Hero should show two columns on desktop: left has large text + CTAs, right shows the curve panel
- Each hero element should spring-in with stagger on page load
- Mobile: curve panel is hidden, single column layout
- Font sizes should be noticeably larger on desktop

**Step 6: Commit**

```bash
git add app/home-client.tsx app/globals.css
git commit -m "feat: hero split layout with FM spring stagger, upgraded typography"
```

---

## Task 7: Bento grid asymmetric layout — 7+5 ↔ 5+7

**Files:**
- Modify: `app/home-client.tsx`

Change the features section from `[12] / [6,6] / [12]` to `[7,5] / [5,7]`.
Wrap each card's inner `<div>` with `<BentoCard>`.

**Step 1: Add BentoCard import at top of home-client.tsx**

```tsx
import { BentoCard } from "./components/BentoCard/BentoCard";
```

**Step 2: Replace the bento grid section**

Find the `<div className="mt-10 grid grid-cols-1 md:grid-cols-12 gap-4">` block and replace it with:

```tsx
<div className="mt-10 grid grid-cols-1 md:grid-cols-12 gap-4">
  {/* Row 1: Easing (7) + Axes (5) */}
  <Reveal className="md:col-span-7" delayMs={140}>
    <BentoCard>
      <div className="relative p-6 sm:p-8">
        <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
          {t.sectionFeel.cards.curves.kicker}
        </div>
        <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
          {t.sectionFeel.cards.curves.title}
        </div>
        <p className="mt-3 text-white/62 leading-[1.7]">
          {t.sectionFeel.cards.curves.body}
        </p>
        <EasingPlayground className="mt-6" />
      </div>
    </BentoCard>
  </Reveal>

  <Reveal className="md:col-span-5" delayMs={200}>
    <BentoCard>
      <div className="relative p-6 sm:p-8">
        <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
          {t.sectionFeel.cards.axes.kicker}
        </div>
        <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
          {t.sectionFeel.cards.axes.title}
        </div>
        <p className="mt-3 text-white/62 leading-[1.7]">
          {t.sectionFeel.cards.axes.body}
        </p>

        <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5">
          <div className="space-y-3">
            {(["Y", "X"] as const).map((axis) => {
              const row = axesDemo[axis];
              return (
                <div key={axis} className="flex items-center gap-3">
                  <div className="h-10 w-10 rounded-2xl border border-white/10 bg-white/5 grid place-items-center">
                    <span className="font-mono text-xs text-white/60">{axis}</span>
                  </div>

                  <div className="flex flex-1 flex-wrap gap-2">
                    <div className="flex min-w-[150px] flex-1 items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2">
                      <span className="font-mono text-[11px] text-white/60">
                        {t.sectionFeel.cards.axes.smooth}
                      </span>
                      <MiniToggle
                        checked={row.smooth}
                        onToggle={() => toggleAxis(axis, "smooth")}
                        ariaLabel={`${axis} ${t.sectionFeel.cards.axes.smooth}`}
                      />
                    </div>

                    <div className="flex min-w-[150px] flex-1 items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2">
                      <span className="font-mono text-[11px] text-white/60">
                        {t.sectionFeel.cards.axes.reverse}
                      </span>
                      <MiniToggle
                        checked={row.reverse}
                        onToggle={() => toggleAxis(axis, "reverse")}
                        ariaLabel={`${axis} ${t.sectionFeel.cards.axes.reverse}`}
                      />
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </BentoCard>
  </Reveal>

  {/* Row 2: Per-App (5) + Buttons (7) — min-height taller than row 1 */}
  <Reveal className="md:col-span-5" delayMs={260}>
    <BentoCard>
      <div className="relative p-6 sm:p-8 min-h-[360px]">
        <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
          {t.sectionFeel.cards.perApp.kicker}
        </div>
        <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
          {t.sectionFeel.cards.perApp.title}
        </div>
        <p className="mt-3 text-white/62 leading-[1.7]">
          {t.sectionFeel.cards.perApp.body}
        </p>

        {/* 2×3 grid (was 3×2) with larger icons */}
        <div className="mt-6 grid grid-cols-2 gap-3">
          {APP_PROFILES.map((a) => (
            <div
              key={a.id}
              className="rounded-2xl border border-white/10 bg-white/5 p-3 flex items-center gap-3"
            >
              <div className="h-12 w-12 shrink-0 rounded-xl border border-white/10 bg-black/20 overflow-hidden">
                <Image
                  src={a.icon}
                  alt=""
                  width={48}
                  height={48}
                  className="h-full w-full object-cover"
                />
              </div>
              <div>
                <div className="font-mono text-[11px] text-white/65">{a.name}</div>
                {a.axes.Y.smooth && (
                  <div className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-white/8 border border-white/10 px-1.5 py-0.5">
                    <span className="h-1.5 w-1.5 rounded-full bg-white/60" />
                    <span className="font-mono text-[9px] text-white/50">smooth</span>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </BentoCard>
  </Reveal>

  <Reveal className="md:col-span-7" delayMs={320}>
    <BentoCard>
      <div className="relative p-6 sm:p-8 min-h-[360px]">
        <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
          {t.sectionFeel.cards.buttons.kicker}
        </div>
        <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
          {t.sectionFeel.cards.buttons.title}
        </div>
        <p className="mt-3 text-white/62 leading-[1.7]">
          {t.sectionFeel.cards.buttons.body}
        </p>

        <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5">
          <div className="font-mono text-xs text-white/45">
            {t.sectionFeel.cards.buttons.quickBind}
          </div>
          <div className="mt-3 grid gap-2">
            {[
              {
                k: t.sectionFeel.cards.buttons.rows.button4,
                v: t.sectionFeel.cards.buttons.rows.missionControl,
              },
              {
                k: t.sectionFeel.cards.buttons.rows.button5,
                v: t.sectionFeel.cards.buttons.rows.nextSpace,
              },
              {
                k: t.sectionFeel.cards.buttons.rows.wheelClick,
                v: t.sectionFeel.cards.buttons.rows.appSwitcher,
              },
            ].map((row) => (
              <div
                key={row.k}
                className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2"
              >
                <div className="font-mono text-xs text-white/75">{row.k}</div>
                <div className="font-mono text-xs text-white/45">{row.v}</div>
              </div>
            ))}
            {/* Pulsing "recording" placeholder row */}
            <div className="flex items-center justify-between rounded-xl border border-white/8 bg-white/3 px-3 py-2 opacity-60">
              <div className="flex items-center gap-2">
                <span className="relative flex h-1.5 w-1.5">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-white/60 opacity-75" />
                  <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-white/40" />
                </span>
                <div className="font-mono text-xs text-white/45">—</div>
              </div>
              <div className="font-mono text-[10px] text-white/30 italic">recording…</div>
            </div>
          </div>
        </div>
      </div>
    </BentoCard>
  </Reveal>
</div>
```

**Step 3: Visual verify**

```bash
pnpm dev
```

- Desktop: two rows with 7+5 and 5+7 column spans
- Per-app card shows 2×2 grid with larger icons + smooth badges
- Buttons card has a pulsing "recording..." row at the bottom
- Each card should tilt slightly when you hover over it (3D effect)
- Spotlight follows cursor inside each card

**Step 4: Commit**

```bash
git add app/home-client.tsx
git commit -m "feat: asymmetric bento grid 7+5/5+7, BentoCard 3D hover, per-app 2col, buttons pulse"
```

---

## Task 8: Update section header typography

**Files:**
- Modify: `app/home-client.tsx`

Upgrade the "Feel" section header and download section header with new kicker tracking.

**Step 1: Update section kicker tracking in Feel section**

Find the `<h2>` block in the Feel section:
```tsx
<h2 className="font-display text-balance text-3xl sm:text-5xl text-white leading-tight">
```
Change to:
```tsx
<h2 className="font-display text-balance text-3xl sm:text-5xl text-white leading-[0.95] tracking-[-0.01em]">
```

Find the lead `<p>` in the Feel section:
```tsx
<p className="mt-4 max-w-3xl text-white/68 leading-relaxed">
```
Change to:
```tsx
<p className="mt-4 max-w-3xl text-white/68 leading-[1.7]">
```

**Step 2: Update download section header**

Find the `<h3>` in the download section:
```tsx
<h3 className="font-display text-balance text-3xl sm:text-6xl text-white leading-tight">
```
Change to:
```tsx
<h3 className="font-display text-balance text-3xl sm:text-6xl text-white leading-[0.95] tracking-[-0.015em]">
```

Find the download lead `<p>`:
```tsx
<p className="mt-4 max-w-3xl text-white/68 leading-relaxed">
```
Change to:
```tsx
<p className="mt-4 max-w-3xl text-white/68 leading-[1.7]">
```

**Step 3: Commit**

```bash
git add app/home-client.tsx
git commit -m "style: tighten section header leading and tracking"
```

---

## Task 9: FlowField — longer particle trails

**Files:**
- Modify: `app/components/FlowField/FlowField.tsx`

**Step 1: Reduce fill alpha for longer trails**

In `FlowField.tsx`, find the line inside the `tick` function:
```tsx
ctx.fillStyle = `rgba(0, 0, 0, ${0.12 + scroll * 0.06})`;
```

Change to:
```tsx
ctx.fillStyle = `rgba(0, 0, 0, ${0.08 + scroll * 0.05})`;
```

This reduces the background erase alpha, making particle trails persist longer and creating a more fluid, flowing look.

**Step 2: Commit**

```bash
git add app/components/FlowField/FlowField.tsx
git commit -m "style: longer FlowField particle trails (fill alpha 0.12→0.08)"
```

---

## Task 10: Pre-flight verification

**Files:**
- Modify: `app/home-client.tsx` (dvh check)
- Run: `pnpm build`

**Step 1: Verify `min-h-[100dvh]` is used**

Search the file for any remaining `min-h-screen` or `min-h-[100svh]`:
```bash
grep -n "min-h-screen\|100svh" /Users/caldis/Code/Mos/website/app/home-client.tsx
```

Expected: no matches (the hero section should already use `100dvh` from Task 6). If any found, replace with `min-h-[100dvh]`.

**Step 2: Verify useReducedMotion is used in FM components**

All three FM components (Reveal, BentoCard, HeroCurvePanel) use `useReducedMotion`. Confirm:
```bash
grep -n "useReducedMotion" \
  /Users/caldis/Code/Mos/website/app/components/Reveal/Reveal.tsx \
  /Users/caldis/Code/Mos/website/app/components/BentoCard/BentoCard.tsx \
  /Users/caldis/Code/Mos/website/app/components/HeroCurvePanel/HeroCurvePanel.tsx
```

Expected: one match per file.

**Step 3: Production build — verify no TypeScript/build errors**

```bash
cd /Users/caldis/Code/Mos/website && pnpm build
```

Expected: `✓ Compiled successfully`. Fix any TypeScript errors before committing.

**Step 4: Verify no purple/blue colors crept in**

```bash
grep -rn "purple\|violet\|indigo\|blue" /Users/caldis/Code/Mos/website/app/globals.css
```

Expected: no matches (monochrome constraint satisfied).

**Step 5: Final commit**

```bash
git add app/home-client.tsx
git commit -m "feat: taste redesign pre-flight — dvh, reduced-motion, build verified"
```

---

## Summary of All Changes

| File | Change |
|------|--------|
| `package.json` | Add `framer-motion@^11` |
| `app/globals.css` | Material tokens, glass highlight, deeper shadows, remove `.reveal` CSS |
| `app/components/Reveal/Reveal.tsx` | FM `useInView` + spring animation |
| `app/components/BentoCard/BentoCard.tsx` | **New** — 3D hover tilt + cursor spotlight |
| `app/components/HeroCurvePanel/HeroCurvePanel.tsx` | **New** — static SVG curve panel for hero |
| `app/home-client.tsx` | Hero split grid, FM stagger entrance, asymmetric bento, typography |
| `app/components/FlowField/FlowField.tsx` | Longer trails (fill alpha) |

## Execution Order

Tasks must run in order (each task builds on the previous):
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10

Tasks 4 and 5 (BentoCard and HeroCurvePanel) are independent of each other and can be parallelized if using subagent-driven development.
