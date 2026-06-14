"use client";

import { useEffect, useState } from "react";

// Dev-only stress-test console: spin up N read-only mock notes (which all land on the
// NoteCanvas layer) and watch DOM count / canvas count / FPS / memory. Interactive
// notes (yours / admin / the draft) stay in the DOM regardless.
export interface SimConfig {
  /** Mock note count; 0 = real data. */
  count: number;
}

export const DEFAULT_SIM: SimConfig = { count: 0 };

export function SimPanel({
  cfg,
  onChange,
  total,
  domCount,
  canvasCount,
}: {
  cfg: SimConfig;
  onChange: (c: SimConfig) => void;
  total: number;
  domCount: number;
  canvasCount: number;
}) {
  const [open, setOpen] = useState(true);
  const [fps, setFps] = useState(0);
  const [memMB, setMemMB] = useState(0);

  useEffect(() => {
    let raf = 0;
    let last = 0;
    let acc = 0;
    let n = 0;
    const tick = (now: number) => {
      if (last) {
        acc += now - last;
        n++;
        if (n >= 15) {
          setFps(Math.round(1000 / (acc / n)));
          acc = 0;
          n = 0;
          const m = (performance as Performance & { memory?: { usedJSHeapSize: number } }).memory;
          if (m) setMemMB(Math.round(m.usedJSHeapSize / 1048576));
        }
      }
      last = now;
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div className="pointer-events-auto absolute right-4 top-20 z-50 hidden w-60 sm:block">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="glass mb-2 flex w-full items-center justify-between rounded-full px-3 py-1.5 text-xs text-white/75 shadow-lg"
      >
        <span>⚙ 压力测试</span>
        <span className="font-mono text-[10px] text-white/45">{open ? "收起" : "展开"}</span>
      </button>

      {open && (
        <div className="glass rounded-2xl p-4 text-white/80 shadow-xl">
          <div className="mb-3 grid grid-cols-2 gap-x-3 gap-y-1 rounded-lg bg-black/20 p-2 font-mono text-[10px]">
            <Stat label="总卡片" value={total.toLocaleString()} />
            <Stat label="FPS" value={`${fps}`} warn={fps > 0 && fps < 50} good={fps >= 58} />
            <Stat label="Canvas" value={canvasCount.toLocaleString()} />
            <Stat label="DOM" value={domCount.toLocaleString()} warn={domCount > 200} />
            <Stat label="JS 内存" value={memMB ? `${memMB}MB` : "—"} warn={memMB > 400} />
          </div>

          <Slider label="模拟卡片数" value={cfg.count} min={0} max={30000} step={100} fmt={(v) => v.toLocaleString()} onChange={(v) => onChange({ count: v })} />
          <div className="flex gap-1">
            {[0, 1000, 5000, 12000, 30000].map((v) => (
              <button
                key={v}
                type="button"
                onClick={() => onChange({ count: v })}
                className={`flex-1 rounded border py-1 text-[10px] transition-colors ${cfg.count === v ? "border-[#7aa6ff] text-white" : "border-white/10 text-white/45 hover:text-white/70"}`}
              >
                {v === 0 ? "真实" : v >= 1000 ? `${v / 1000}k` : v}
              </button>
            ))}
          </div>
          <p className="mt-3 text-[9px] leading-snug text-white/35">
            模拟卡片均为只读 → 全部走 canvas;DOM 只保留你自己的/可编辑的卡片。
          </p>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, warn, good }: { label: string; value: string; warn?: boolean; good?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-white/40">{label}</span>
      <span style={{ color: warn ? "#fca5a5" : good ? "#86efac" : "rgba(255,255,255,0.8)" }}>{value}</span>
    </div>
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
