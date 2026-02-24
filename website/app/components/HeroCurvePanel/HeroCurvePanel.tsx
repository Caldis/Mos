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
              strokeDashoffset={shouldReduceMotion ? 0 : 1}
              style={
                shouldReduceMotion
                  ? {}
                  : { animation: "stroke-in 1200ms var(--ease-out) 500ms both" }
              }
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
