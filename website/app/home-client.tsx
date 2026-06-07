"use client";

import Image from "next/image";
import Link from "next/link";
import { useMemo } from "react";
import logo512 from "@/assets/image/logo-512.png";
import { FlowField } from "./components/FlowField/FlowField";
import { LanguageSelector } from "./components/LanguageSelector/LanguageSelector";
import { Magnetic } from "./components/Magnetic/Magnetic";
import { Reveal } from "./components/Reveal/Reveal";
import { CopyButton } from "./components/CopyButton/CopyButton";
import { SupportButton } from "./components/Donate/SupportButton";
import { SupportLink } from "./components/Donate/SupportLink";
import { Modal } from "./components/Modal/Modal";
import { useModal } from "./components/Modal/hooks";
import { SmoothScrollDemo } from "./components/SmoothScroll/SmoothScrollDemo";
import { CurveDivider, IndexMark, Shot } from "./components/Editorial/Editorial";
import { LogiKeymap } from "./components/LogiKeymap/LogiKeymap";
import { useI18n } from "./i18n/context";
import { format } from "./i18n/format";
import { useGithubRelease } from "./services/github";
import { motion } from "framer-motion";
import { useHydratedReducedMotion } from "./hooks/useHydratedReducedMotion";

const FALLBACK_RELEASE_LINK = "https://github.com/Caldis/Mos/releases/latest";

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
    initial: false as const,
    animate: { opacity: 1, y: 0 },
    transition: shouldReduceMotion ? { duration: 0 } : { ...HERO_SPRING, delay: delayS },
  };
}

const PRIMARY_BTN =
  "inline-flex select-none items-center justify-center rounded-[16px] border border-black/10 px-6 py-3.5 text-sm font-semibold tracking-wide text-black shadow-elevated sm:text-base";
const PRIMARY_BG = "linear-gradient(180deg, #fff 0%, rgba(255,255,255,0.86) 100%)";

const BINDING_ROWS = [
  ["button4", "missionControl"],
  ["button5", "nextSpace"],
  ["wheelClick", "appSwitcher"],
] as const;

export default function HomeClient({ initialRelease }: { initialRelease?: unknown }) {
  const { language, t } = useI18n();
  const shouldReduceMotion = useHydratedReducedMotion();
  const { data: release } = useGithubRelease(initialRelease);
  const brew = useModal();

  const downloadUrl = useMemo(() => pickDownloadUrl(release), [release]);
  const readmeLocale: "en-us" | "zh-cn" =
    language === "zh" || language === "zh-Hant" ? "zh-cn" : "en-us";

  const versionLabel = useMemo(() => {
    const tag = release?.tag_name;
    return typeof tag === "string" && tag.trim() ? `v${tag.replace(/^v/i, "")}` : null;
  }, [release?.tag_name]);

  // Shared "latest version · system requirement" line — hero note and footer
  // render the exact same value, sourced from the live GitHub latest release.
  const releaseLine =
    (versionLabel ? `${format(t.footer.latestVersion, { version: versionLabel })} · ` : "") +
    t.footer.requiresMacos;

  // Hero is a deliberate English block; the close section below stays localized.
  // Both buttons open the same Homebrew modal.
  const renderBrewButton = (label: string) => (
    <Magnetic strength={14}>
      <button
        type="button"
        onClick={brew.handleOpen}
        className="inline-flex items-center justify-center gap-2 rounded-[16px] border border-white/12 bg-white/5 px-6 py-3.5 text-sm font-semibold tracking-wide text-white/85 transition-colors hover:bg-white/10 sm:text-base"
      >
        <svg aria-hidden="true" viewBox="0 0 24 24" className="h-4 w-4 opacity-70" fill="none" stroke="currentColor" strokeWidth={1.8}>
          <rect x="3" y="4" width="18" height="16" rx="2.5" />
          <path strokeLinecap="round" strokeLinejoin="round" d="M7.5 9.5 10 12l-2.5 2.5M13 14.5h4" />
        </svg>
        {label}
      </button>
    </Magnetic>
  );

  return (
    <div className="min-h-[100dvh] text-[color:var(--fg0)]">
      <a
        href="#content"
        className="sr-only focus:not-sr-only focus:fixed focus:z-[100] focus:top-4 focus:left-4 focus:px-4 focus:py-2 focus:rounded-xl focus:bg-black/70 focus:text-white focus:outline-none"
      >
        {t.a11y.skipToContent}
      </a>

      {/* background: lift off pure black, then the flow field */}
      <div className="fixed inset-0 -z-10 overflow-hidden">
        <div
          aria-hidden="true"
          className="absolute inset-0"
          style={{ background: "radial-gradient(120% 80% at 50% -8%, rgba(58,60,72,0.22), transparent 56%)" }}
        />
        <FlowField className="absolute inset-0" />
      </div>

      <header className="fixed left-0 right-0 top-0 z-50 px-4 sm:px-6">
        <nav
          className="mx-auto mt-4 flex max-w-6xl items-center justify-between rounded-2xl border border-white/[0.06] px-4 py-2.5 backdrop-blur-xl sm:mt-5 sm:px-5"
          style={{
            background: "rgba(10,11,14,0.55)",
            boxShadow: "0 1px 0 rgba(255,255,255,0.05) inset, 0 12px 40px -16px rgba(0,0,0,0.75)",
          }}
        >
          <div className="flex items-center gap-1">
            <Image src={logo512} alt={t.a11y.appIconAlt} width={36} height={36} className="rounded-[12px] object-contain" priority />
            <div className="text-2xl font-extrabold tracking-[0.015em] text-white" style={{ fontFamily: "math" }}>
              Mos
            </div>
          </div>

          <div className="flex items-center gap-2 sm:gap-3">
            <Magnetic strength={14}>
              <Link
                href="/wall/"
                title={t.wall.title}
                className="inline-flex h-10 items-center gap-1.5 rounded-2xl border border-white/5 bg-white/4 px-3.5 font-mono text-xs text-white/75 transition-colors hover:border-white/9 hover:bg-white/7 hover:text-white"
              >
                <span aria-hidden>✎</span> {t.wall.title}
              </Link>
            </Magnetic>
            <LanguageSelector />
            <Magnetic strength={14}>
              <a
                href="https://github.com/Caldis/Mos"
                target="_blank"
                rel="noopener noreferrer"
                className="group grid h-10 w-10 place-items-center rounded-2xl border border-white/5 bg-white/4 transition-colors hover:border-white/9 hover:bg-white/7"
                aria-label={t.a11y.githubAria}
                title={t.nav.githubTitle}
              >
                <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5 text-white/82 transition-colors group-hover:text-white/92" fill="currentColor">
                  <path d="M12 2c-5.52 0-10 4.58-10 10.23 0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.48 0-.24-.01-.88-.01-1.72-2.78.62-3.37-1.37-3.37-1.37-.45-1.18-1.11-1.49-1.11-1.49-.91-.64.07-.63.07-.63 1.01.07 1.54 1.06 1.54 1.06.9 1.57 2.35 1.12 2.92.86.09-.67.35-1.12.64-1.38-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.04 1.03-2.76-.1-.26-.45-1.3.1-2.72 0 0 .84-.28 2.75 1.05.8-.23 1.65-.35 2.5-.35.85 0 1.7.12 2.5.35 1.9-1.33 2.75-1.05 2.75-1.05.55 1.42.2 2.46.1 2.72.64.72 1.03 1.64 1.03 2.76 0 3.93-2.34 4.8-4.58 5.05.36.32.69.96.69 1.94 0 1.4-.01 2.52-.01 2.86 0 .26.18.58.69.48A10.3 10.3 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z" />
                </svg>
              </a>
            </Magnetic>
            <SupportButton />
          </div>
        </nav>
      </header>

      <main id="content" className="mx-auto max-w-5xl px-4 sm:px-6">
        {/* ---------- hero (English) ---------- */}
        <section className="flex min-h-[100dvh] flex-col justify-center pt-28 sm:pt-36">
          <motion.h1
            className="max-w-4xl font-display text-[14vw] leading-[1.02] tracking-[-0.02em] text-white sm:text-[96px]"
            {...heroMotion(0, shouldReduceMotion)}
          >
            {t.hero.titleLine1}
            <br />
            {t.hero.titleLine2Before}
            <span className="relative inline-block">
              {t.hero.titleLine2Highlight}
              <svg className="absolute -bottom-2 left-0 h-4 w-full overflow-visible" viewBox="0 0 100 14" preserveAspectRatio="none" aria-hidden="true">
                <path
                  d="M1 8 C 26 14, 54 1, 99 7"
                  fill="none"
                  stroke="rgba(255,255,255,0.92)"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  vectorEffect="non-scaling-stroke"
                  pathLength={1}
                  strokeDasharray={1}
                  strokeDashoffset={1}
                  style={{ animation: "stroke-in 900ms var(--ease-out) 350ms both" }}
                />
              </svg>
            </span>
            {t.hero.titleLine2After}
          </motion.h1>

          <motion.p
            className="mt-8 max-w-2xl text-pretty text-base leading-[1.7] text-white/65 sm:text-lg"
            {...heroMotion(0.18, shouldReduceMotion)}
          >
            {t.hero.lead}
          </motion.p>

          <motion.div className="mt-9 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center" {...heroMotion(0.26, shouldReduceMotion)}>
            <Magnetic strength={22}>
              <a href={downloadUrl} target="_blank" rel="noopener noreferrer" className={PRIMARY_BTN} style={{ background: PRIMARY_BG }}>
                {t.hero.ctaDownload}
              </a>
            </Magnetic>
            {renderBrewButton(t.hero.ctaInstallHomebrew)}
            <Magnetic strength={14}>
              <a
                href="https://github.com/Caldis/Mos"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center justify-center gap-2 rounded-[16px] border border-white/12 bg-white/5 px-6 py-3.5 text-sm font-semibold tracking-wide text-white/85 transition-colors hover:bg-white/10 sm:text-base"
              >
                <svg aria-hidden="true" viewBox="0 0 24 24" className="h-4 w-4" fill="currentColor">
                  <path d="M12 2c-5.52 0-10 4.58-10 10.23 0 4.52 2.87 8.35 6.84 9.7.5.1.68-.22.68-.48 0-.24-.01-.88-.01-1.72-2.78.62-3.37-1.37-3.37-1.37-.45-1.18-1.11-1.49-1.11-1.49-.91-.64.07-.63.07-.63 1.01.07 1.54 1.06 1.54 1.06.9 1.57 2.35 1.12 2.92.86.09-.67.35-1.12.64-1.38-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.04 1.03-2.76-.1-.26-.45-1.3.1-2.72 0 0 .84-.28 2.75 1.05.8-.23 1.65-.35 2.5-.35.85 0 1.7.12 2.5.35 1.9-1.33 2.75-1.05 2.75-1.05.55 1.42.2 2.46.1 2.72.64.72 1.03 1.64 1.03 2.76 0 3.93-2.34 4.8-4.58 5.05.36.32.69.96.69 1.94 0 1.4-.01 2.52-.01 2.86 0 .26.18.58.69.48A10.3 10.3 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z" />
                </svg>
                GitHub
              </a>
            </Magnetic>
          </motion.div>

          <motion.p
            className="mt-4 font-mono text-[11px] text-white/40"
            {...heroMotion(0.34, shouldReduceMotion)}
          >
            {releaseLine}
          </motion.p>

          <div className="mt-16 font-mono text-[11px] uppercase tracking-[0.3em] text-white/30">scroll ↓</div>
        </section>

        {/* ---------- 01 · scroll it yourself ---------- */}
        <CurveDivider label={t.scroll.kickerFeel} />

        <section className="py-8 sm:py-12">
          <Reveal>
            <IndexMark n="01" label={t.scroll.kickerFeel} />
            <h2 className="font-display text-4xl leading-[0.95] tracking-[-0.01em] text-white sm:text-6xl">
              {t.scroll.heading}
            </h2>
            <p className="mt-5 max-w-xl text-pretty leading-[1.7] text-white/65">{t.scroll.lead}</p>
          </Reveal>

          <Reveal className="mt-8" delayMs={140}>
            <SmoothScrollDemo />
          </Reveal>
        </section>

        {/* ---------- 02 · per-app ---------- */}
        <CurveDivider />

        <section className="py-8 sm:py-12">
          <div className="grid gap-8 md:grid-cols-12 md:items-center">
            <Reveal className="md:col-span-7 md:-ml-6">
              <Shot
                locale={readmeLocale}
                name="application-settings"
                alt="Mos per-application settings window"
              />
            </Reveal>
            <Reveal className="md:col-span-5" delayMs={120}>
              <IndexMark n="02" label={t.scroll.kickerProfiles} />
              <h2 className="font-display text-4xl leading-[0.95] tracking-[-0.01em] whitespace-pre-line text-white sm:text-5xl">
                {t.sectionFeel.cards.perApp.title}
              </h2>
              <p className="mt-5 text-pretty leading-[1.7] text-white/65">{t.sectionFeel.cards.perApp.body}</p>
            </Reveal>
          </div>
        </section>

        {/* ---------- 03 · buttons ---------- */}
        <CurveDivider />

        <section className="py-8 sm:py-12">
          <div className="grid gap-8 md:grid-cols-12 md:items-center">
            <Reveal className="md:col-span-5">
              <IndexMark n="03" label={t.scroll.kickerButtons} />
              <h2 className="font-display text-4xl leading-[0.95] tracking-[-0.01em] whitespace-pre-line text-white sm:text-5xl">
                {t.sectionFeel.cards.buttons.title}
              </h2>
              <p className="mt-5 text-pretty leading-[1.7] text-white/65">{t.sectionFeel.cards.buttons.body}</p>

              <dl className="mt-7 divide-y divide-white/8 border-y border-white/8 bg-[#000000c9]">
                {BINDING_ROWS.map(([k, v]) => (
                  <div key={k} className="flex items-center justify-between p-3">
                    <dt className="font-mono text-xs text-white/75">{t.sectionFeel.cards.buttons.rows[k]}</dt>
                    <dd className="font-mono text-xs text-white/45">{t.sectionFeel.cards.buttons.rows[v]}</dd>
                  </div>
                ))}
              </dl>

              <LogiKeymap label={t.sectionFeel.cards.buttons.logi} />
            </Reveal>
            <Reveal className="md:col-span-7 md:-mr-6" delayMs={120}>
              <Shot locale={readmeLocale} name="buttons-action" alt="Mos action library window" />
            </Reveal>
          </div>
        </section>

        {/* ---------- close ---------- */}
        <CurveDivider />

        <section className="py-12 sm:py-20">
          <Reveal>
            <h2 className="max-w-3xl font-display text-4xl leading-[0.95] tracking-[-0.015em] text-white sm:text-6xl">
              {t.download.title}
            </h2>
          </Reveal>
          <Reveal delayMs={120}>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
              <Magnetic strength={22}>
                <a href={downloadUrl} target="_blank" rel="noopener noreferrer" className={PRIMARY_BTN} style={{ background: PRIMARY_BG }}>
                  {t.download.ctaDownload}
                </a>
              </Magnetic>
              {renderBrewButton(t.hero.ctaInstallHomebrew)}
              <Magnetic strength={14}>
                <a
                  href="https://github.com/Caldis/Mos/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center justify-center rounded-[16px] border border-white/12 bg-white/5 px-6 py-3.5 text-sm font-semibold tracking-wide text-white/85 transition-colors hover:bg-white/10 sm:text-base"
                >
                  {t.download.releaseNotes}
                </a>
              </Magnetic>
            </div>
          </Reveal>
        </section>

        {/* ---------- footer ---------- */}
        <footer className="border-t border-white/[0.08] pt-8 pb-40 sm:pt-10">
          <div className="flex flex-col gap-5 font-mono text-xs text-white/45 sm:flex-row sm:items-center sm:justify-between">
            <div>{releaseLine}</div>
            <nav className="flex flex-wrap items-center gap-x-5 gap-y-2">
              <Link href="/about/" className="transition-colors hover:text-white/85">{t.footer.about}</Link>
              <Link href="/compare/" className="transition-colors hover:text-white/85">{t.footer.compare}</Link>
              <Link href="/privacy/" className="transition-colors hover:text-white/85">{t.footer.privacy}</Link>
              <a href="https://github.com/Caldis/Mos/wiki" target="_blank" rel="noopener noreferrer" className="transition-colors hover:text-white/85">{t.footer.wiki}</a>
              <a href="https://github.com/Caldis/Mos/releases" target="_blank" rel="noopener noreferrer" className="transition-colors hover:text-white/85">{t.footer.releases}</a>
              <span aria-hidden="true" className="h-3 w-px shrink-0 bg-white/15" />
              <Link href="/wall/" className="transition-colors hover:text-white/85">{t.wall.title}</Link>
              <LanguageSelector variant="link" className="font-mono text-xs text-white/45 hover:text-white/85" />
              <a href="https://github.com/Caldis/Mos" target="_blank" rel="noopener noreferrer" className="transition-colors hover:text-white/85">{t.footer.github}</a>
              <SupportLink className="font-mono text-xs text-white/45 hover:text-white/85" />
            </nav>
          </div>
        </footer>
      </main>

      {/* Homebrew install — modal */}
      <Modal isOpen={brew.isOpen} onClose={brew.handleClose} title={t.hero.ctaInstallHomebrew} closeLabel={t.a11y.closeDialog}>
        <div className="flex items-center justify-between gap-3 rounded-2xl border border-white/10 bg-black/40 px-4 py-3">
          <code className="font-mono text-sm text-white/85">brew install --cask mos</code>
          <CopyButton
            value="brew install --cask mos"
            className="shrink-0 rounded-xl border border-white/12 bg-white/5 px-3 py-1.5 text-xs font-semibold text-white/85 transition-colors hover:bg-white/10"
            copiedLabel={t.homebrew.copied}
          >
            {t.homebrew.copy}
          </CopyButton>
        </div>
      </Modal>
    </div>
  );
}
