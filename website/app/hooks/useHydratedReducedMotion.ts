"use client";

import { useReducedMotion } from "framer-motion";
import { useSyncExternalStore } from "react";

function subscribe(callback: () => void) {
  const timeout = window.setTimeout(callback, 0);
  return () => window.clearTimeout(timeout);
}

function getClientSnapshot() {
  return true;
}

function getServerSnapshot() {
  return false;
}

export function useHydratedReducedMotion() {
  const prefersReducedMotion = useReducedMotion();
  const isHydrated = useSyncExternalStore(
    subscribe,
    getClientSnapshot,
    getServerSnapshot
  );

  return isHydrated && prefersReducedMotion === true;
}
