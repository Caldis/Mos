"use client";

import { ReactNode, useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";

function getFocusableElements(root: HTMLElement | null): HTMLElement[] {
  if (!root) return [];

  const nodes = Array.from(
    root.querySelectorAll<HTMLElement>(
      [
        'a[href]',
        'button:not([disabled])',
        'input:not([disabled])',
        'select:not([disabled])',
        'textarea:not([disabled])',
        '[tabindex]:not([tabindex="-1"])',
      ].join(",")
    )
  );

  return nodes.filter((el) => {
    // Filter out hidden elements.
    const style = window.getComputedStyle(el);
    return style.display !== "none" && style.visibility !== "hidden";
  });
}

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  width?: string;
  closeLabel?: string;
}

export function Modal({
  isOpen,
  onClose,
  title,
  children,
  width = "max-w-sm",
  closeLabel = "Close dialog",
}: ModalProps) {
  const [portalRoot, setPortalRoot] = useState<HTMLElement | null>(null);
  const titleId = useId();
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const lastActiveElementRef = useRef<HTMLElement | null>(null);
  const reduce = useReducedMotion();

  const label = useMemo(() => ({ titleId }), [titleId]);

  useEffect(() => {
    setPortalRoot(document.body);
  }, []);

  useEffect(() => {
    if (!isOpen) return;

    lastActiveElementRef.current =
      document.activeElement instanceof HTMLElement ? document.activeElement : null;

    // Lock scroll on the scrolling element (html) so `scrollbar-gutter: stable`
    // engages and the reserved scrollbar space prevents a layout-width jump.
    const prevOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";

    const raf = window.requestAnimationFrame(() => {
      const focusables = getFocusableElements(dialogRef.current);
      (closeButtonRef.current ?? focusables[0] ?? dialogRef.current)?.focus?.();
    });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;

      const dialogEl = dialogRef.current;
      if (!dialogEl) return;

      const focusables = getFocusableElements(dialogEl);
      if (focusables.length === 0) {
        event.preventDefault();
        dialogEl.focus();
        return;
      }

      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;

      if (event.shiftKey) {
        if (!active || !dialogEl.contains(active) || active === first) {
          event.preventDefault();
          last.focus();
        }
        return;
      }

      if (!active || !dialogEl.contains(active) || active === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", onKeyDown);

    return () => {
      window.cancelAnimationFrame(raf);
      document.documentElement.style.overflow = prevOverflow;
      document.removeEventListener("keydown", onKeyDown);

      try {
        lastActiveElementRef.current?.focus?.();
      } catch {
        // Ignore focus restore failures (e.g. element unmounted).
      } finally {
        lastActiveElementRef.current = null;
      }
    };
  }, [isOpen, onClose]);

  if (!portalRoot) return null;

  const dur = reduce ? 0 : 0.22;

  return createPortal(
    <AnimatePresence>
      {isOpen && (
        <motion.div
          className="fixed inset-0 z-[80] grid place-items-center px-4 py-6 bg-black/70 supports-[backdrop-filter:blur(0)]:bg-black/45 supports-[-webkit-backdrop-filter:blur(0)]:bg-black/45 backdrop-blur-xl"
          role="presentation"
          onClick={(e) => {
            if (e.target === e.currentTarget) onClose();
          }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: dur }}
        >
          <motion.div
            ref={dialogRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby={label.titleId}
            tabIndex={-1}
            className={`w-full ${width} max-h-[calc(100vh-3rem)] max-h-[calc(100svh-3rem)] overflow-auto rounded-[22px] border border-white/10 bg-[rgba(10,11,16,0.72)] shadow-elevated backdrop-blur-xl`}
            initial={{ opacity: 0, scale: 0.95, y: 12 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.94, y: 12 }}
            transition={{ duration: dur, ease: [0.16, 1, 0.3, 1] }}
          >
            <div className="flex justify-between items-center px-5 sm:px-6 pt-5 sm:pt-6">
              <h3 id={label.titleId} className="font-display text-lg sm:text-xl text-white">
                {title}
              </h3>
              <button
                ref={closeButtonRef}
                type="button"
                onClick={onClose}
                className="rounded-xl p-2 text-white/55 hover:text-white/85 hover:bg-white/5 transition-colors"
                aria-label={closeLabel}
              >
                <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <div className="px-5 sm:px-6 pb-5 sm:pb-6 pt-4">{children}</div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>,
    portalRoot
  );
}
