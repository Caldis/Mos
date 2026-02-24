"use client";

import { motion, useInView, useReducedMotion } from "framer-motion";
import { ReactNode, useRef } from "react";

const SPRING = { type: "spring" as const, stiffness: 100, damping: 20 };

const variants = {
  hidden: { opacity: 0, y: 24 },
  visible: { opacity: 1, y: 0 },
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
