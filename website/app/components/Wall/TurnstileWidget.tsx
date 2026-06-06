"use client";

import { useEffect, useRef } from "react";

// Cloudflare Turnstile site key. Empty in dev / when the backend isn't wired
// up yet — in that case the wall falls back to the local seed and we render no
// widget at all (see WALL_TURNSTILE_ENABLED below).
export const TURNSTILE_SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? "";
export const WALL_TURNSTILE_ENABLED = TURNSTILE_SITE_KEY.length > 0;

const SCRIPT_SRC = "https://challenges.cloudflare.com/turnstile/v0/api.js";

// Minimal shape of the global the Cloudflare script installs. We only use the
// explicit-render subset (render / reset / remove).
interface TurnstileApi {
  render: (
    el: HTMLElement,
    opts: {
      sitekey: string;
      callback: (token: string) => void;
      "expired-callback"?: () => void;
      "error-callback"?: () => void;
      theme?: "light" | "dark" | "auto";
      size?: "normal" | "flexible" | "compact";
    }
  ) => string;
  reset: (id?: string) => void;
  remove: (id?: string) => void;
}

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

// Load the Turnstile script exactly once across the whole app and resolve when
// the global `turnstile` API is ready. Subsequent callers reuse the promise.
let scriptPromise: Promise<TurnstileApi> | null = null;
function loadTurnstile(): Promise<TurnstileApi> {
  if (typeof window === "undefined") {
    // SSR / static export — never resolves, but we never call it there either.
    return new Promise<TurnstileApi>(() => {});
  }
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (scriptPromise) return scriptPromise;

  scriptPromise = new Promise<TurnstileApi>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${SCRIPT_SRC}"]`);
    const onReady = () => {
      if (window.turnstile) resolve(window.turnstile);
      else reject(new Error("turnstile script loaded but global missing"));
    };
    if (existing) {
      if (window.turnstile) resolve(window.turnstile);
      else existing.addEventListener("load", onReady, { once: true });
      return;
    }
    const s = document.createElement("script");
    s.src = SCRIPT_SRC;
    s.async = true;
    s.defer = true;
    s.addEventListener("load", onReady, { once: true });
    s.addEventListener("error", () => reject(new Error("failed to load turnstile")), { once: true });
    document.head.appendChild(s);
  });
  return scriptPromise;
}

interface TurnstileWidgetProps {
  // Called with a fresh token when the challenge passes, and with "" whenever
  // the token is no longer valid (expired / errored / reset).
  onToken: (token: string) => void;
  className?: string;
}

// Renders an explicit Turnstile widget inside the compose card. Self-contained:
// loads the script on mount, renders once the canvas is ready, and cleans up on
// unmount. Renders nothing when no site key is configured.
export function TurnstileWidget({ onToken, className }: TurnstileWidgetProps) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  // Keep the latest onToken without re-rendering the widget on every parent render.
  const onTokenRef = useRef(onToken);
  onTokenRef.current = onToken;

  useEffect(() => {
    if (!WALL_TURNSTILE_ENABLED) return;
    let widgetId: string | undefined;
    let cancelled = false;
    let api: TurnstileApi | undefined;

    loadTurnstile()
      .then((t) => {
        if (cancelled || !hostRef.current) return;
        api = t;
        widgetId = t.render(hostRef.current, {
          sitekey: TURNSTILE_SITE_KEY,
          theme: "dark",
          size: "flexible",
          callback: (token) => onTokenRef.current(token),
          // Any of these invalidates the current token — clear it and let the
          // widget re-issue a new one on its own.
          "expired-callback": () => onTokenRef.current(""),
          "error-callback": () => onTokenRef.current(""),
        });
      })
      .catch(() => {
        // Script failed to load — leave the token empty so submit stays gated.
        if (!cancelled) onTokenRef.current("");
      });

    return () => {
      cancelled = true;
      try {
        if (api && widgetId) api.remove(widgetId);
      } catch {
        // widget already gone — ignore
      }
    };
  }, []);

  if (!WALL_TURNSTILE_ENABLED) return null;
  return <div ref={hostRef} className={className} />;
}
