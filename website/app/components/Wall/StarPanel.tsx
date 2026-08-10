"use client";

import { useState } from "react";
import { DEFAULT_STAR_CONFIG, type StarfieldConfig } from "./Starfield";

// Live tuning panel for the starfield backdrop — toggle real colour / Milky Way and
// scrub the magnitude curve + density to compare looks. Desktop-only, collapsed by
// default so it stays out of the way.
export function StarPanel({ config, onChange }: { config: StarfieldConfig; onChange: (c: StarfieldConfig) => void }) {
  const [open, setOpen] = useState(false);
  const set = (patch: Partial<StarfieldConfig>) => onChange({ ...config, ...patch });

  return (
    <div className="pointer-events-auto absolute left-6 top-20 z-40 hidden sm:block">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="glass flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs text-white/70 shadow-lg transition-colors hover:text-white"
      >
        <span aria-hidden>✦</span> 星空
      </button>

      {open && (
        <div className="glass mt-2 w-60 rounded-2xl p-4 text-white/80 shadow-xl">
          <Toggle label="真实恒星颜色" hint="B-V 色指数 → 蓝白/黄/橙红" on={config.color} onClick={() => set({ color: !config.color })} />
          <Toggle label="银河带" hint="沿银道面的弥散光" on={config.milkyWay} onClick={() => set({ milkyWay: !config.milkyWay })} />
          <Slider label="星等对比" value={config.gamma} min={0.8} max={2.5} step={0.1} fmt={(v) => v.toFixed(1)} onChange={(v) => set({ gamma: v })} />
          <Slider label="星空密度" value={config.density} min={0} max={1} step={0.05} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => set({ density: v })} />
          <button
            type="button"
            onClick={() => onChange(DEFAULT_STAR_CONFIG)}
            className="mt-1 w-full rounded-lg border border-white/10 py-1.5 text-[11px] text-white/55 transition-colors hover:text-white/80"
          >
            重置默认
          </button>
        </div>
      )}
    </div>
  );
}

function Toggle({ label, hint, on, onClick }: { label: string; hint: string; on: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="mb-3 flex w-full items-center justify-between gap-3 text-left">
      <span>
        <span className="block text-xs">{label}</span>
        <span className="block text-[10px] text-white/40">{hint}</span>
      </span>
      <span
        className="relative h-5 w-9 shrink-0 rounded-full transition-colors"
        style={{ background: on ? "rgba(120,170,255,0.8)" : "rgba(255,255,255,0.14)" }}
      >
        <span
          className="absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform"
          style={{ transform: on ? "translateX(18px)" : "translateX(2px)" }}
        />
      </span>
    </button>
  );
}

function Slider({
  label,
  value,
  min,
  max,
  step,
  fmt,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  fmt: (v: number) => string;
  onChange: (v: number) => void;
}) {
  return (
    <label className="mb-3 block">
      <span className="mb-1 flex items-center justify-between text-xs">
        <span>{label}</span>
        <span className="font-mono text-[10px] text-white/45">{fmt(value)}</span>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="h-1 w-full cursor-pointer appearance-none rounded-full bg-white/15 accent-[#7aa6ff]"
      />
    </label>
  );
}
