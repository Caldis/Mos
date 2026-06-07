"use client";

import { motion } from "framer-motion";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";

// Logitech's G-series side buttons (G4–G7) — a recognizable nod to Logi's
// proprietary keys without leaning on a trademarked logo. A soft white highlight
// sweeps left-to-right across the caps, suggesting each special key gets picked
// up and mapped. Single-colour glow to stay in the page's monochrome key.
const KEYS = ["G4", "G5", "G6", "G7"];

export function LogiKeymap({ label }: { label: string }) {
  const reduce = useHydratedReducedMotion();
  return (
    <div className="mt-6 inline-flex items-center gap-3 rounded-full border border-white/10 bg-[#000000c9] py-2 pl-2.5 pr-4">
      <div className="flex gap-1" aria-hidden>
        {KEYS.map((k, i) => (
          <motion.span
            key={k}
            className="grid h-6 w-7 place-items-center rounded-[6px] border border-white/12 bg-white/[0.05] font-mono text-[10px] leading-none text-white/55"
            initial={false}
            animate={
              reduce
                ? undefined
                : {
                    borderColor: [
                      "rgba(255,255,255,0.12)",
                      "rgba(255,255,255,0.5)",
                      "rgba(255,255,255,0.12)",
                    ],
                    color: [
                      "rgba(255,255,255,0.55)",
                      "rgba(255,255,255,0.96)",
                      "rgba(255,255,255,0.55)",
                    ],
                    boxShadow: [
                      "0 0 0 0 rgba(255,255,255,0)",
                      "0 0 14px 0 rgba(255,255,255,0.22)",
                      "0 0 0 0 rgba(255,255,255,0)",
                    ],
                  }
            }
            transition={
              reduce
                ? undefined
                : {
                    duration: 1.6,
                    times: [0, 0.4, 1],
                    repeat: Infinity,
                    repeatDelay: 1.3,
                    delay: i * 0.16,
                    ease: "easeInOut",
                  }
            }
          >
            {k}
          </motion.span>
        ))}
      </div>
      <span className="font-mono text-[11px] tracking-wide text-white/60">{label}</span>
    </div>
  );
}
