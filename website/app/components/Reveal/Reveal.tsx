"use client";

import { motion, useInView } from "framer-motion";
import { ReactNode, useRef } from "react";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";

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
  const shouldReduceMotion = useHydratedReducedMotion();
  const inView = useInView(ref, {
    once: true,
    margin: "40px 0px -10% 0px",
  });

  return (
    <motion.div
      ref={ref}
      className={className}
      variants={variants}
      initial={false}
      animate={shouldReduceMotion || inView ? "visible" : "hidden"}
      transition={shouldReduceMotion ? { duration: 0 } : { ...SPRING, delay: delayMs / 1000 }}
    >
      {children}
    </motion.div>
  );
}
