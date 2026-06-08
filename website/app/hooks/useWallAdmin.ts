"use client";

import { useCallback, useEffect, useState } from "react";
import {
  WALL_ADMIN_EVENT,
  isAdminUnlocked,
  lockAdmin,
  verifyAdmin,
} from "@/app/services/wall";

// Shared admin (panel moderation) state for the wall. sessionStorage is the source
// of truth (written in services/wall.ts); this hook mirrors it into React and
// keeps the sibling WallHeader (which unlocks) and WallClient (which shows the
// delete affordances) in sync via a window event. Lighter than a Context
// provider — which page.tsx can't host, being a server component that owns the
// static `metadata` required by the static export.
export function useWallAdmin() {
  // Start false on both server and first client render to avoid an SSR/hydration
  // mismatch; the real value is read from sessionStorage after mount.
  const [admin, setAdmin] = useState(false);

  useEffect(() => {
    const sync = () => setAdmin(isAdminUnlocked());
    sync();
    window.addEventListener(WALL_ADMIN_EVENT, sync); // same-tab unlock/lock
    window.addEventListener("storage", sync); // other tabs
    return () => {
      window.removeEventListener(WALL_ADMIN_EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  // Resolves to whether the token was accepted, so callers can surface a result.
  const unlock = useCallback((token: string) => verifyAdmin(token), []);
  const lock = useCallback(() => lockAdmin(), []);

  return { admin, unlock, lock };
}
