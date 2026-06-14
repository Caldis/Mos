"use client";

import { useEffect, useRef } from "react";
import { NOTE_COLORS, WORLD_H, WORLD_NOTE_SIZE, WORLD_W, type WallNote } from "@/app/services/wall";
import type { UseViewport } from "@/app/wall/useViewport";

// WebGL color-tile layer (PixiJS). Every read-only note becomes one tinted, rotated
// rounded-rect sprite — all sharing a single texture so they batch into ~one GPU draw
// call. Pan/zoom is just the world container's transform (matched to the viewport),
// so tens of thousands of tiles stay at 60fps where Canvas 2D janked. The readable,
// interactive notes are layered on top as real DOM (see wall-client).
const TINTS: Record<string, number> = Object.fromEntries(
  Object.entries(NOTE_COLORS).map(([k, v]) => [k, parseInt(v.bg.slice(1), 16)]),
);

type Pixi = typeof import("pixi.js");
interface Live {
  PIXI: Pixi;
  app: import("pixi.js").Application;
  world: import("pixi.js").Container;
  tex: import("pixi.js").Texture;
}

export function PixiNoteLayer({ vp, notes }: { vp: UseViewport; notes: WallNote[] }) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const liveRef = useRef<Live | null>(null);
  const notesRef = useRef(notes);
  notesRef.current = notes;

  // Init Pixi once (per viewport instance). Let Pixi create its OWN canvas (appended to
  // our host div) rather than handing it an existing one — otherwise dev StrictMode's
  // double-mount points two WebGL contexts at the same canvas and the second one is lost.
  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    let destroyed = false;

    (async () => {
      const PIXI = await import("pixi.js");
      const app = new PIXI.Application();
      await app.init({
        resizeTo: host,
        backgroundAlpha: 0, // transparent — starfield shows through
        antialias: true,
        autoDensity: true,
        resolution: Math.min(window.devicePixelRatio || 1, 2),
        powerPreference: "high-performance",
      });
      if (destroyed) {
        app.destroy(true);
        return;
      }
      const cv = app.canvas;
      cv.className = "pointer-events-none absolute inset-0 h-full w-full";
      host.appendChild(cv);
      const g = new PIXI.Graphics().roundRect(0, 0, WORLD_NOTE_SIZE, WORLD_NOTE_SIZE, 14).fill(0xffffff);
      const tex = app.renderer.generateTexture(g);
      g.destroy();
      const world = new PIXI.Container();
      app.stage.addChild(world);
      liveRef.current = { PIXI, app, world, tex };

      buildSprites();

      // Match the world container to the viewport transform every rendered frame.
      app.ticker.add(() => {
        world.x = vp.tx.get();
        world.y = vp.ty.get();
        world.scale.set(vp.scale.get());
      });
    })();

    return () => {
      destroyed = true;
      const live = liveRef.current;
      if (live) {
        live.app.destroy(true);
        live.tex.destroy(true);
        liveRef.current = null;
      }
    };
  }, [vp]);

  // Rebuild the sprite set whenever the note array changes.
  function buildSprites() {
    const live = liveRef.current;
    if (!live) return;
    const { PIXI, world, tex } = live;
    world.removeChildren().forEach((c) => c.destroy());
    const ns = notesRef.current;
    for (let i = 0; i < ns.length; i++) {
      const n = ns[i];
      const sp = new PIXI.Sprite(tex);
      sp.anchor.set(0.5);
      sp.x = n.x * WORLD_W;
      sp.y = n.y * WORLD_H;
      sp.tint = TINTS[n.color] ?? 0xffffff;
      sp.rotation = (n.rot * Math.PI) / 180;
      world.addChild(sp);
    }
  }

  useEffect(() => {
    buildSprites();
  }, [notes]);

  return <div ref={hostRef} className="pointer-events-none absolute inset-0 h-full w-full" aria-hidden />;
}
