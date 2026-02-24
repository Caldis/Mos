"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import logo512 from "@/assets/image/logo-512.png";
import { FlowField } from "./components/FlowField/FlowField";
import { LanguageSelector } from "./components/LanguageSelector/LanguageSelector";
import { Magnetic } from "./components/Magnetic/Magnetic";
import { Reveal } from "./components/Reveal/Reveal";
import { EasingPlayground } from "./components/EasingPlayground/EasingPlayground";
import { CopyButton } from "./components/CopyButton/CopyButton";
import { useI18n } from "./i18n/context";
import { format } from "./i18n/format";
import { useGithubRelease } from "./services/github";
import { motion, useReducedMotion } from "framer-motion";
import { HeroCurvePanel } from "./components/HeroCurvePanel/HeroCurvePanel";
import { BentoCard } from "./components/BentoCard/BentoCard";

const FALLBACK_RELEASE_LINK = "https://github.com/Caldis/Mos/releases/latest";

type Axis = "X" | "Y";
type AxisSetting = "smooth" | "reverse";

type AppProfile = {
  id: string;
  name: string;
  icon: string;
  curve: { step: number; gain: number; duration: number };
  axes: Record<Axis, Record<AxisSetting, boolean>>;
};

const APP_PROFILES: AppProfile[] = [
  {
    id: "xcode",
    name: "Xcode",
    icon: "/app-icons/xcode.png",
    curve: { step: 28.0, gain: 2.3, duration: 3.4 },
    axes: {
      Y: { smooth: true, reverse: false },
      X: { smooth: false, reverse: false },
    },
  },
  {
    id: "safari",
    name: "Safari",
    icon: "/app-icons/safari.png",
    curve: { step: 33.6, gain: 2.7, duration: 4.35 },
    axes: {
      Y: { smooth: true, reverse: false },
      X: { smooth: true, reverse: false },
    },
  },
  {
    id: "figma",
    name: "Figma",
    icon: "/app-icons/figma.png",
    curve: { step: 26.0, gain: 2.1, duration: 3.8 },
    axes: {
      Y: { smooth: true, reverse: false },
      X: { smooth: true, reverse: true },
    },
  },
  {
    id: "terminal",
    name: "Terminal",
    icon: "/app-icons/terminal.png",
    curve: { step: 18.0, gain: 1.6, duration: 2.0 },
    axes: {
      Y: { smooth: false, reverse: false },
      X: { smooth: false, reverse: false },
    },
  },
  {
    id: "notion",
    name: "Notion",
    icon: "/app-icons/notion.png",
    curve: { step: 30.0, gain: 2.4, duration: 4.8 },
    axes: {
      Y: { smooth: true, reverse: false },
      X: { smooth: false, reverse: false },
    },
  },
  {
    id: "chrome",
    name: "Chrome",
    icon: "/app-icons/chrome.png",
    curve: { step: 33.6, gain: 2.9, duration: 4.1 },
    axes: {
      Y: { smooth: true, reverse: false },
      X: { smooth: true, reverse: false },
    },
  },
];

function MiniToggle({
  checked,
  onToggle,
  ariaLabel,
  disabled = false,
}: {
  checked: boolean;
  onToggle: () => void;
  ariaLabel: string;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-disabled={disabled}
      aria-label={ariaLabel}
      disabled={disabled}
      onClick={() => {
        if (disabled) return;
        onToggle();
      }}
      className={`relative inline-flex h-6 w-11 shrink-0 items-center overflow-hidden rounded-full border p-[2px] transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-white/20 ${
        checked
          ? "border-white/30 bg-white/28"
          : disabled
            ? "border-white/8 bg-white/4"
            : "border-white/8 bg-white/4 hover:border-white/14 hover:bg-white/7"
      } ${disabled ? "cursor-default" : "cursor-pointer"}`}
    >
      <span
        aria-hidden="true"
        className={`h-5 w-5 rounded-full shadow-[0_6px_16px_rgba(0,0,0,0.45)] transition-[transform,background-color] duration-200 ease-out ${
          checked ? "translate-x-5 bg-white" : "translate-x-0 bg-white/50"
        }`}
      />
    </button>
  );
}

function pickDownloadUrl(release: unknown): string {
  if (!release || typeof release !== "object") return FALLBACK_RELEASE_LINK;

  const assetsRaw = (release as Record<string, unknown>).assets;
  if (!Array.isArray(assetsRaw) || assetsRaw.length === 0) return FALLBACK_RELEASE_LINK;

  const assets = assetsRaw
    .map((asset) => {
      if (!asset || typeof asset !== "object") return null;
      const record = asset as Record<string, unknown>;
      const name = typeof record.name === "string" ? record.name : null;
      const url =
        typeof record.browser_download_url === "string" ? record.browser_download_url : null;
      if (!name || !url) return null;
      return { name, url };
    })
    .filter(Boolean) as { name: string; url: string }[];

  if (assets.length === 0) return FALLBACK_RELEASE_LINK;

  const byExt = (ext: string) => assets.find((a) => a.name.toLowerCase().endsWith(ext));

  return byExt(".zip")?.url || byExt(".dmg")?.url || assets[0]?.url || FALLBACK_RELEASE_LINK;
}

const HERO_SPRING = { type: "spring" as const, stiffness: 100, damping: 20 };

function heroMotion(delayS: number, shouldReduceMotion: boolean | null) {
  return {
    initial: shouldReduceMotion ? (false as const) : { opacity: 0, y: 24 },
    animate: { opacity: 1, y: 0 },
    transition: { ...HERO_SPRING, delay: delayS },
  };
}

export default function HomeClient() {
  const { t } = useI18n();
  const shouldReduceMotion = useReducedMotion();
  const { data: release } = useGithubRelease();

  const [axesDemo, setAxesDemo] = useState<Record<Axis, Record<AxisSetting, boolean>>>(() => ({
    Y: { smooth: true, reverse: false },
    X: { smooth: false, reverse: true },
  }));

  const toggleAxis = useCallback((axis: Axis, setting: AxisSetting) => {
    setAxesDemo((prev) => ({
      ...prev,
      [axis]: { ...prev[axis], [setting]: !prev[axis][setting] },
    }));
  }, []);


  const versionLabel = useMemo(() => {
    const tag = release?.tag_name;
    return typeof tag === "string" && tag.trim() ? `v${tag.replace(/^v/i, "")}` : null;
  }, [release?.tag_name]);

  const downloadUrl = useMemo(() => pickDownloadUrl(release), [release]);

  const homebrewRef = useRef<HTMLDivElement | null>(null);
  const pendingHomebrewFlashRef = useRef(false);
  const homebrewFlashStartTimerRef = useRef<number | null>(null);
  const homebrewFlashTimerRef = useRef<number | null>(null);

  const flashHomebrew = useCallback((delayMs = 0) => {
    const el = homebrewRef.current;
    if (!el) return;

    if (homebrewFlashStartTimerRef.current) {
      window.clearTimeout(homebrewFlashStartTimerRef.current);
      homebrewFlashStartTimerRef.current = null;
    }
    if (homebrewFlashTimerRef.current) {
      window.clearTimeout(homebrewFlashTimerRef.current);
      homebrewFlashTimerRef.current = null;
    }

    const start = () => {
      el.classList.remove("homebrew-highlight");
      // Force reflow so the animation restarts reliably.
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      el.offsetWidth;
      el.classList.add("homebrew-highlight");

      homebrewFlashTimerRef.current = window.setTimeout(() => {
        el.classList.remove("homebrew-highlight");
        homebrewFlashTimerRef.current = null;
      }, 1200);
    };

    if (delayMs > 0) {
      homebrewFlashStartTimerRef.current = window.setTimeout(() => {
        homebrewFlashStartTimerRef.current = null;
        start();
      }, delayMs);
    } else {
      start();
    }
  }, []);

  useEffect(() => {
    const el = homebrewRef.current;
    if (!el) return;

    const io = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (!entry?.isIntersecting) return;
        if (!pendingHomebrewFlashRef.current) return;
        pendingHomebrewFlashRef.current = false;
        flashHomebrew(500);
      },
      { threshold: 0.35 }
    );

    io.observe(el);

    return () => {
      io.disconnect();
      if (homebrewFlashStartTimerRef.current) {
        window.clearTimeout(homebrewFlashStartTimerRef.current);
        homebrewFlashStartTimerRef.current = null;
      }
      if (homebrewFlashTimerRef.current) {
        window.clearTimeout(homebrewFlashTimerRef.current);
        homebrewFlashTimerRef.current = null;
      }
    };
  }, [flashHomebrew]);

  const scrollToHomebrew = () => {
    const el = homebrewRef.current ?? document.getElementById("homebrew");
    if (!el) return;

    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;

    const rect = el.getBoundingClientRect();
    const inView = rect.top < window.innerHeight * 0.78 && rect.bottom > window.innerHeight * 0.22;
    if (inView) {
      pendingHomebrewFlashRef.current = false;
      flashHomebrew(500);
    } else {
      pendingHomebrewFlashRef.current = true;
    }

    el.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" });
  };

  return (
    <div className="min-h-[100dvh] text-[color:var(--fg0)]">
      <a
        href="#content"
        className="sr-only focus:not-sr-only focus:fixed focus:z-[100] focus:top-4 focus:left-4 focus:px-4 focus:py-2 focus:rounded-xl focus:bg-black/70 focus:text-white focus:outline-none"
      >
        {t.a11y.skipToContent}
      </a>

      <div className="fixed inset-0 -z-10 overflow-hidden">
        <FlowField className="absolute inset-0" />
        <div className="orb left-[-140px] top-[-120px] w-[380px] h-[380px] bg-[color:var(--accent)]" />
        <div className="orb right-[-180px] top-[10vh] w-[420px] h-[420px] bg-[color:var(--accent3)] [animation-delay:-1.2s]" />
        <div className="orb left-[12vw] bottom-[-220px] w-[520px] h-[520px] bg-[color:var(--accent2)] [animation-delay:-2.1s]" />
      </div>

      <header className="fixed left-0 right-0 top-0 z-50 px-4 sm:px-6">
        <nav className="mx-auto mt-4 sm:mt-6 max-w-6xl rounded-[var(--radius-xl)] glass ring-accent">
          <div className="flex items-center justify-between px-4 sm:px-5 py-3">
            <div className="flex items-center gap-3">
              <Image
                src={logo512}
                alt={t.a11y.appIconAlt}
                width={40}
                height={40}
                className="object-contain rounded-[14px]"
                priority
              />
              <div className="text-lg sm:text-xl font-extrabold tracking-[0.015em] text-white">
                Mos
              </div>
            </div>

            <div className="flex items-center gap-3">
              <LanguageSelector />
              <Magnetic strength={14}>
                <a
                  href="https://github.com/Caldis/Mos"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group grid h-11 w-11 place-items-center rounded-2xl border border-white/5 bg-white/4 hover:bg-white/7 hover:border-white/9 transition-colors"
                  aria-label={t.a11y.githubAria}
                  title={t.nav.githubTitle}
                >
                  <svg
                    aria-hidden="true"
                    viewBox="0 0 24 24"
                    className="h-5 w-5 text-white/82 group-hover:text-white/92 transition-colors"
                    fill="currentColor"
                  >
                    <path d="M12 2c-5.52 0-10 4.58-10 10.23 0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.48 0-.24-.01-.88-.01-1.72-2.78.62-3.37-1.37-3.37-1.37-.45-1.18-1.11-1.49-1.11-1.49-.91-.64.07-.63.07-.63 1.01.07 1.54 1.06 1.54 1.06.9 1.57 2.35 1.12 2.92.86.09-.67.35-1.12.64-1.38-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.04 1.03-2.76-.1-.26-.45-1.3.1-2.72 0 0 .84-.28 2.75 1.05.8-.23 1.65-.35 2.5-.35.85 0 1.7.12 2.5.35 1.9-1.33 2.75-1.05 2.75-1.05.55 1.42.2 2.46.1 2.72.64.72 1.03 1.64 1.03 2.76 0 3.93-2.34 4.8-4.58 5.05.36.32.69.96.69 1.94 0 1.4-.01 2.52-.01 2.86 0 .26.18.58.69.48A10.3 10.3 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z" />
                  </svg>
                </a>
              </Magnetic>
            </div>
          </div>
        </nav>
      </header>

      <main id="content" className="mx-auto max-w-6xl px-4 sm:px-6">
        <section className="relative min-h-[100dvh] pt-28 sm:pt-36 pb-10 sm:pb-12 flex flex-col">
          <div className="flex-1 flex items-center">
            <div className="w-full grid grid-cols-1 md:grid-cols-[1fr_auto] gap-12 lg:gap-20 items-center">

              {/* Left column */}
              <div>
                <motion.div
                  className="inline-flex items-center gap-3 rounded-full border border-white/10 bg-black/40 px-4 py-2 text-xs text-white/70 shadow-elevated"
                  {...heroMotion(0, shouldReduceMotion)}
                >
                  <span className="inline-flex items-center gap-2">
                    <span className="h-2 w-2 rounded-full bg-[color:var(--accent)] shadow-[0_0_22px_rgba(255,255,255,0.35)]" />
                    {t.hero.badgeLine1}
                  </span>
                  <span className="hidden sm:inline text-white/35">•</span>
                  <span className="hidden sm:inline font-mono text-white/45">
                    {t.hero.badgeLine2}
                  </span>
                </motion.div>

                <motion.h1
                  className="mt-7 font-display text-balance text-[52px] leading-[0.95] tracking-[-0.02em] sm:text-[88px] md:text-[108px] lg:text-[124px] text-white"
                  {...heroMotion(0.08, shouldReduceMotion)}
                >
                  {t.hero.titleLine1}
                  <span className="block">
                    {t.hero.titleLine2Before}
                    <span
                      className="inline-block text-flow"
                      style={{ textShadow: "0 0 42px rgba(255,255,255,0.08)" }}
                    >
                      {t.hero.titleLine2Highlight}
                    </span>
                    {t.hero.titleLine2After}
                  </span>
                </motion.h1>

                <motion.p
                  className="mt-5 max-w-2xl text-balance text-[15px] sm:text-lg text-white/72 leading-[1.7]"
                  {...heroMotion(0.18, shouldReduceMotion)}
                >
                  {t.hero.lead}
                </motion.p>

                <motion.div
                  className="mt-8 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-4"
                  {...heroMotion(0.26, shouldReduceMotion)}
                >
                  <div className="flex flex-col items-start w-fit">
                    <Magnetic strength={22}>
                      <a
                        href={downloadUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="group relative overflow-hidden rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-black shadow-elevated border border-black/10 inline-flex items-center justify-center"
                        style={{
                          background:
                            "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                        }}
                      >
                        <span className="relative z-10">{t.hero.ctaDownload}</span>
                        <span className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 [background:radial-gradient(800px_240px_at_30%_0%,rgba(0,0,0,0.18),transparent_55%)]" />
                      </a>
                    </Magnetic>
                    <a
                      href="#homebrew"
                      onClick={(e) => {
                        e.preventDefault();
                        scrollToHomebrew();
                      }}
                      className="mt-2 self-center text-xs font-mono text-white/50 hover:text-white/75 transition-colors underline decoration-white/15 hover:decoration-white/35 underline-offset-4"
                    >
                      {t.hero.ctaInstallHomebrew}
                    </a>
                  </div>

                  <Magnetic strength={14}>
                    <a
                      href="https://github.com/Caldis/Mos"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="group inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
                    >
                      <span className="mr-2 opacity-70 group-hover:opacity-100 transition-opacity">↗</span>
                      <span>{t.hero.ctaViewGitHub}</span>
                    </a>
                  </Magnetic>

                  <div className="sm:ml-auto sm:self-center text-xs text-white/45">
                    <div className="font-mono tabular-nums">{t.hero.requirementsLine1}</div>
                    <div className="font-mono">{t.hero.requirementsLine2}</div>
                  </div>
                </motion.div>
              </div>

              {/* Right column — HeroCurvePanel is hidden md: internally */}
              <HeroCurvePanel />
            </div>
          </div>

          <div className="mt-8 sm:mt-10 flex items-center gap-3 text-white/40">
            <div className="h-[1px] flex-1 hairline" />
            <div className="font-mono text-[11px] tracking-[0.18em] uppercase">
              {t.hero.scrollHint}
            </div>
            <div className="h-[1px] flex-1 hairline" />
          </div>
        </section>

        <section className="py-16 sm:py-24">
          <Reveal>
            <h2 className="font-display text-balance text-3xl sm:text-5xl text-white leading-[0.95] tracking-[-0.01em]">
              {t.sectionFeel.title}
            </h2>
          </Reveal>
          <Reveal delayMs={90}>
            <p className="mt-4 max-w-3xl text-white/68 leading-[1.7]">
              {t.sectionFeel.lead}
            </p>
          </Reveal>

          <div className="mt-10 grid grid-cols-1 md:grid-cols-12 gap-4">
            {/* Row 1: Easing (7) + Axes (5) */}
            <Reveal className="md:col-span-7 h-full" delayMs={140}>
              <BentoCard>
                <div className="relative p-6 sm:p-8">
                  <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
                    {t.sectionFeel.cards.curves.kicker}
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    {t.sectionFeel.cards.curves.title}
                  </div>
                  <p className="mt-3 text-white/62 leading-[1.7]">
                    {t.sectionFeel.cards.curves.body}
                  </p>
                  <EasingPlayground className="mt-6" />
                </div>
              </BentoCard>
            </Reveal>

            <Reveal className="md:col-span-5 h-full" delayMs={200}>
              <BentoCard>
                <div className="relative p-6 sm:p-8">
                  <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
                    {t.sectionFeel.cards.axes.kicker}
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    {t.sectionFeel.cards.axes.title}
                  </div>
                  <p className="mt-3 text-white/62 leading-[1.7]">
                    {t.sectionFeel.cards.axes.body}
                  </p>

                  <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5">
                    <div className="space-y-3">
                      {(["Y", "X"] as const).map((axis) => {
                        const row = axesDemo[axis];
                        return (
                          <div key={axis} className="flex items-center gap-3">
                            <div className="h-10 w-10 rounded-2xl border border-white/10 bg-white/5 grid place-items-center">
                              <span className="font-mono text-xs text-white/60">{axis}</span>
                            </div>

                            <div className="flex flex-1 flex-wrap gap-2">
                              <div className="flex min-w-[150px] flex-1 items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2">
                                <span className="font-mono text-[11px] text-white/60">
                                  {t.sectionFeel.cards.axes.smooth}
                                </span>
                                <MiniToggle
                                  checked={row.smooth}
                                  onToggle={() => toggleAxis(axis, "smooth")}
                                  ariaLabel={`${axis} ${t.sectionFeel.cards.axes.smooth}`}
                                />
                              </div>

                              <div className="flex min-w-[150px] flex-1 items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2">
                                <span className="font-mono text-[11px] text-white/60">
                                  {t.sectionFeel.cards.axes.reverse}
                                </span>
                                <MiniToggle
                                  checked={row.reverse}
                                  onToggle={() => toggleAxis(axis, "reverse")}
                                  ariaLabel={`${axis} ${t.sectionFeel.cards.axes.reverse}`}
                                />
                              </div>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              </BentoCard>
            </Reveal>

            {/* Row 2: Per-App (5) + Buttons (7) — taller than row 1 */}
            <Reveal className="md:col-span-5 h-full" delayMs={260}>
              <BentoCard>
                <div className="relative p-6 sm:p-8 min-h-[360px]">
                  <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
                    {t.sectionFeel.cards.perApp.kicker}
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    {t.sectionFeel.cards.perApp.title}
                  </div>
                  <p className="mt-3 text-white/62 leading-[1.7]">
                    {t.sectionFeel.cards.perApp.body}
                  </p>

                  {/* 2-column grid with larger 48px icons + smooth badge */}
                  <div className="mt-6 grid grid-cols-2 gap-3">
                    {APP_PROFILES.map((a) => (
                      <div
                        key={a.id}
                        className="rounded-2xl border border-white/10 bg-white/5 p-3 flex items-center gap-3"
                      >
                        <div className="h-12 w-12 shrink-0 rounded-xl border border-white/10 bg-black/20 overflow-hidden">
                          <Image
                            src={a.icon}
                            alt=""
                            width={48}
                            height={48}
                            className="h-full w-full object-cover"
                          />
                        </div>
                        <div>
                          <div className="font-mono text-[11px] text-white/65">{a.name}</div>
                          {a.axes.Y.smooth && (
                            <div className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-white/8 border border-white/10 px-1.5 py-0.5">
                              <span className="h-1.5 w-1.5 rounded-full bg-white/60" />
                              <span className="font-mono text-[9px] text-white/50">smooth</span>
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </BentoCard>
            </Reveal>

            <Reveal className="md:col-span-7 h-full" delayMs={320}>
              <BentoCard>
                <div className="relative p-6 sm:p-8 min-h-[360px]">
                  <div className="font-display text-[11px] tracking-[0.22em] uppercase text-white/50">
                    {t.sectionFeel.cards.buttons.kicker}
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    {t.sectionFeel.cards.buttons.title}
                  </div>
                  <p className="mt-3 text-white/62 leading-[1.7]">
                    {t.sectionFeel.cards.buttons.body}
                  </p>

                  <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5">
                    <div className="font-mono text-xs text-white/45">
                      {t.sectionFeel.cards.buttons.quickBind}
                    </div>
                    <div className="mt-3 grid gap-2">
                      {[
                        {
                          k: t.sectionFeel.cards.buttons.rows.button4,
                          v: t.sectionFeel.cards.buttons.rows.missionControl,
                        },
                        {
                          k: t.sectionFeel.cards.buttons.rows.button5,
                          v: t.sectionFeel.cards.buttons.rows.nextSpace,
                        },
                        {
                          k: t.sectionFeel.cards.buttons.rows.wheelClick,
                          v: t.sectionFeel.cards.buttons.rows.appSwitcher,
                        },
                      ].map((row) => (
                        <div
                          key={row.k}
                          className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2"
                        >
                          <div className="font-mono text-xs text-white/75">{row.k}</div>
                          <div className="font-mono text-xs text-white/45">{row.v}</div>
                        </div>
                      ))}
                      {/* Pulsing "recording" placeholder row */}
                      <div className="flex items-center justify-between rounded-xl border border-white/8 bg-white/3 px-3 py-2 opacity-60">
                        <div className="flex items-center gap-2">
                          <span className="relative flex h-1.5 w-1.5">
                            <span className="motion-safe:animate-ping absolute inline-flex h-full w-full rounded-full bg-white/60 opacity-75" />
                            <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-white/40" />
                          </span>
                          <div className="font-mono text-xs text-white/45">—</div>
                        </div>
                        <div className="font-mono text-[10px] text-white/30 italic">recording…</div>
                      </div>
                    </div>
                  </div>
                </div>
              </BentoCard>
            </Reveal>
          </div>
        </section>

        <section className="pt-0 pb-16 sm:pb-24">
          <div className="rounded-[28px] glass shadow-elevated border border-white/10 overflow-hidden">
            <div className="px-6 sm:px-10 py-10 sm:py-14">
              <Reveal>
                <h3 className="font-display text-balance text-3xl sm:text-6xl text-white leading-[0.95] tracking-[-0.015em]">
                  {t.download.title}
                </h3>
              </Reveal>
              <Reveal delayMs={90}>
                <p className="mt-4 max-w-3xl text-white/68 leading-[1.7]">
                  {t.download.body}
                </p>
              </Reveal>

              <Reveal delayMs={160}>
                <div className="mt-8 flex flex-col sm:flex-row sm:items-center gap-3">
                  <Magnetic strength={22}>
                    <a
                      href={downloadUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="group relative overflow-hidden rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-black shadow-elevated border border-black/10 inline-flex items-center justify-center"
                      style={{
                        background:
                          "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                      }}
                    >
                      <span className="relative z-10">
                        {t.download.ctaDownload}
                      </span>
                      <span className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 [background:radial-gradient(900px_260px_at_30%_0%,rgba(0,0,0,0.18),transparent_55%)]" />
                    </a>
                  </Magnetic>

                  <Magnetic strength={14}>
                    <a
                      href="https://github.com/Caldis/Mos/releases"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
                    >
                      {t.download.releaseNotes}
                    </a>
                  </Magnetic>

                  <Magnetic strength={14}>
                    <a
                      href="https://github.com/Caldis/Mos/wiki"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
                    >
                      {t.download.docs}
                    </a>
                  </Magnetic>
                </div>
              </Reveal>

              <Reveal delayMs={220}>
                <div
                  id="homebrew"
                  ref={homebrewRef}
                  className="mt-8 scroll-mt-28 rounded-[22px] border border-white/10 bg-black/35 p-5 sm:p-6"
                >
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                    <div>
                      <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                        {t.homebrew.title}
                      </div>
                      <div className="mt-2 font-mono text-sm text-white/75">
                        brew install --cask mos
                      </div>
                    </div>
                    <CopyButton
                      value="brew install --cask mos"
                      className="self-start sm:self-auto rounded-2xl px-4 py-2.5 text-sm font-semibold border border-white/12 bg-white/5 hover:bg-white/8 transition-colors text-white/85"
                      copiedLabel={t.homebrew.copied}
                    >
                      {t.homebrew.copy}
                    </CopyButton>
                  </div>
                  <div className="mt-4 font-mono text-xs text-white/45">
                    {(() => {
                      const tpl = t.homebrew.tip;
                      const marker = "{cask}";
                      const idx = tpl.indexOf(marker);
                      if (idx === -1) return tpl;
                      const before = tpl.slice(0, idx);
                      const after = tpl.slice(idx + marker.length);
                      return (
                        <>
                          {before}
                          <span className="text-white/70">mos@beta</span>
                          {after}
                        </>
                      );
                    })()}
                  </div>
                </div>
              </Reveal>
            </div>

            <div className="px-6 sm:px-10 py-6 border-t border-white/10 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-white/45">
              <div className="font-mono text-xs">
                {(versionLabel
                  ? format(t.footer.latestVersion, { version: versionLabel })
                  : t.footer.latestRelease) +
                  " · " +
                  t.footer.requiresMacos}
              </div>
              <div className="flex items-center gap-4 font-mono text-xs">
                <a
                  href="https://github.com/Caldis/Mos"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white/80 transition-colors"
                >
                  {t.footer.github}
                </a>
                <a
                  href="https://github.com/Caldis/Mos/wiki"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white/80 transition-colors"
                >
                  {t.footer.wiki}
                </a>
                <a
                  href="https://github.com/Caldis/Mos/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white/80 transition-colors"
                >
                  {t.footer.releases}
                </a>
              </div>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
