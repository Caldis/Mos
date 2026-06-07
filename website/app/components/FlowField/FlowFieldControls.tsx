"use client";

import { useState, useSyncExternalStore, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { FLOW_FIELD_CONTROLS, type FlowFieldConfig } from "./config";

// SSR-safe "are we on the client yet" check without calling setState in an
// effect: the server snapshot is false, the client snapshot is true.
const emptySubscribe = () => () => {};

type Props = {
  config: FlowFieldConfig;
  onChange: <K extends keyof FlowFieldConfig>(key: K, value: FlowFieldConfig[K]) => void;
  onReset: () => void;
};

function format(value: number) {
  if (Number.isInteger(value)) return String(value);
  return value
    .toFixed(5)
    .replace(/0+$/, "")
    .replace(/\.$/, "");
}

/**
 * Dev-only floating panel for live-tuning the FlowField particle effect.
 * Rendered through a portal to <body> so it escapes the background layer's
 * negative z-index stacking context (otherwise it would paint behind the page).
 */
export function FlowFieldControls({ config, onChange, onReset }: Props) {
  const isClient = useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false,
  );
  const [open, setOpen] = useState(true);
  const [copied, setCopied] = useState(false);

  if (!isClient) return null;

  const copyJson = async () => {
    try {
      await navigator.clipboard.writeText(JSON.stringify(config, null, 2));
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1200);
    } catch {
      /* clipboard unavailable — ignore */
    }
  };

  const panel = (
    <div style={wrapperStyle}>
      <div style={headerStyle}>
        <button type="button" onClick={() => setOpen((o) => !o)} style={titleBtn}>
          {open ? "▾" : "▸"} 粒子流场
        </button>
        <div style={{ display: "flex", gap: 6 }}>
          <button type="button" onClick={copyJson} style={ghostBtn}>
            {copied ? "已复制" : "复制"}
          </button>
          <button type="button" onClick={onReset} style={ghostBtn}>
            重置
          </button>
        </div>
      </div>

      {open && (
        <div style={bodyStyle}>
          {FLOW_FIELD_CONTROLS.map((group) => (
            <div key={group.group} style={{ marginBottom: 10 }}>
              <div style={groupLabel}>{group.group}</div>
              {group.items.map((item) => {
                const value = config[item.key];
                return (
                  <label key={item.key} style={rowStyle}>
                    <span style={rowLabel}>
                      <span>{item.label}</span>
                      <span style={valueStyle}>{format(value)}</span>
                    </span>
                    <input
                      type="range"
                      min={item.min}
                      max={item.max}
                      step={item.step}
                      value={value}
                      onChange={(e) => onChange(item.key, Number(e.target.value))}
                      style={rangeStyle}
                    />
                    <span style={descStyle}>{item.desc}</span>
                  </label>
                );
              })}
            </div>
          ))}
        </div>
      )}
    </div>
  );

  return createPortal(panel, document.body);
}

const wrapperStyle: CSSProperties = {
  position: "fixed",
  left: 12,
  bottom: 12,
  zIndex: 2147483647,
  width: 260,
  maxHeight: "min(74vh, 680px)",
  display: "flex",
  flexDirection: "column",
  // Inherit the site font: portaled into <body>, this resolves to the page's
  // own --font-body + --font-cjk stack, so Chinese renders with the right face.
  fontFamily: "inherit",
  fontSize: 11,
  lineHeight: 1.4,
  color: "rgba(255,255,255,0.82)",
  background: "rgba(10,11,14,0.82)",
  border: "1px solid rgba(255,255,255,0.10)",
  borderRadius: 12,
  boxShadow: "0 12px 40px -16px rgba(0,0,0,0.8)",
  backdropFilter: "blur(12px)",
  WebkitBackdropFilter: "blur(12px)",
  overflow: "hidden",
};

const headerStyle: CSSProperties = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  padding: "8px 10px",
  borderBottom: "1px solid rgba(255,255,255,0.08)",
};

const bodyStyle: CSSProperties = {
  padding: "8px 10px",
  overflowY: "auto",
};

const titleBtn: CSSProperties = {
  background: "transparent",
  border: "none",
  color: "rgba(255,255,255,0.92)",
  fontWeight: 600,
  fontSize: 11,
  letterSpacing: "0.04em",
  cursor: "pointer",
  padding: 0,
};

const ghostBtn: CSSProperties = {
  background: "rgba(255,255,255,0.06)",
  border: "1px solid rgba(255,255,255,0.10)",
  color: "rgba(255,255,255,0.7)",
  borderRadius: 6,
  padding: "2px 8px",
  fontSize: 10,
  cursor: "pointer",
};

const groupLabel: CSSProperties = {
  textTransform: "uppercase",
  letterSpacing: "0.08em",
  fontSize: 9,
  color: "rgba(255,255,255,0.4)",
  margin: "2px 0 6px",
};

const rowStyle: CSSProperties = {
  display: "block",
  marginBottom: 10,
};

const descStyle: CSSProperties = {
  display: "block",
  marginTop: 3,
  fontSize: 9.5,
  lineHeight: 1.35,
  color: "rgba(255,255,255,0.38)",
};

const rowLabel: CSSProperties = {
  display: "flex",
  justifyContent: "space-between",
  marginBottom: 2,
};

const valueStyle: CSSProperties = {
  color: "rgba(255,255,255,0.55)",
  fontVariantNumeric: "tabular-nums",
};

const rangeStyle: CSSProperties = {
  width: "100%",
  accentColor: "rgba(255,255,255,0.85)",
  cursor: "pointer",
  height: 14,
};
