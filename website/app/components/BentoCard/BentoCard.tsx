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
