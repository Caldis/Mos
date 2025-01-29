"use client";

import Image from "next/image";
import logoM from "@/assets/image/logo-64.png";
import { Space_Mono, Poppins } from "next/font/google";
import { Squares } from "./components/SquaresBackground";
import { GithubVersion } from "./components/GithubVersion";
import { HomebrewButton } from "./components/HomebrewButton";
import { DownloadButton } from "./components/DownloadButton";
import { ShinyText } from "./components/ShinyText";
import { useI18n } from "./i18n/context";
import { LanguageSelector } from "./components/LanguageSelector";
import { SysRequireButton } from "./components/SysRequireButton";

const spaceMono = Space_Mono({
  weight: ["400", "700"],
  subsets: ["latin"],
});

const poppins = Poppins({
  weight: ["400", "600", "700"],
  subsets: ["latin"],
});

export default function Home() {
  const { t } = useI18n();

  return (
    <div className={`w-screen h-screen relative ${poppins.className}`}>
      {/* 导航栏 */}
      <nav className="fixed top-0 left-1/2 -translate-x-1/2 w-[90vw] h-16 mt-6 px-6 flex items-center justify-between backdrop-blur-md bg-black/30 z-50 rounded-2xl border border-white/10 shadow-lg shadow-black/5">
        <div className="flex items-center gap-3">
          {/* Logo */}
          <Image
            src={logoM}
            alt="logo"
            width={32}
            height={32}
            className="rounded-lg object-contain"
          />
          <span className="text-lg font-bold text-white">
            Mos
          </span>
        </div>
        {/* 导航链接 */}
        <div className="flex items-center gap-6">
          {/* docs */}
          <a
            href="https://github.com/Caldis/Mos/wiki"
            target="_blank"
            rel="noopener noreferrer"
            className="text-white/60 hover:text-white/90 transition-colors text-sm font-bold flex items-center gap-1.5"
          >
            <svg
              viewBox="0 0 24 24"
              className="w-5 h-5"
              fill="currentColor"
            >
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm4 18H6V4h7v5h5v11zM8 15h8v2H8v-2zm0-4h8v2H8v-2z"/>
            </svg>
            <span>{t.nav_docs}</span>
          </a>
          {/* GitHub */}
          <a
            href="https://github.com/Caldis/Mos"
            target="_blank"
            rel="noopener noreferrer"
            className="text-white/60 hover:text-white/90 transition-colors text-sm font-bold flex items-center gap-1.5"
          >
            <svg
              viewBox="0 0 24 24"
              className="w-5 h-5"
              fill="currentColor"
            >
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
            </svg>
            <span>{t.nav_github}</span>
          </a>
        </div>
      </nav>

      {/* 主要内容区域 */}
      <main className="w-full h-full flex flex-col items-center justify-center p-6 relative">
        {/* 背景动画 */}
        <div className="absolute inset-0 overflow-hidden bg-black">
          <Squares
            direction="up"
            speed={0.2}
            borderColor="#222"
            squareSize={20}
            hoverFillColor="#444"
          />
        </div>

        {/* 内容 */}
        <div className="relative z-10 text-center w-[65vw]">
          <h1 className="text-5xl sm:text-6xl font-bold mb-6 text-[#ebebebcc]">
            {t.hero_title}
          </h1>
          <p className="text-xl text-gray-300 mb-8">
            {t.hero_description}
          </p>
        </div>
      </main>

      {/* Footer 区域 */}
      <footer className="fixed bottom-0 left-0 right-0 flex flex-col items-center justify-center p-8 z-50">
        <div className="flex flex-col gap-1 justify-center mb-6">
          <DownloadButton />
          <a
            href="https://github.com/Caldis/Mos/releases"
            target="_blank"
            rel="noopener noreferrer"
            className={`text-white/40 hover:text-white/60 transition-colors text-xs text-center scale-90 ${spaceMono.className}`}
          >
            {t.download_releaseNotes}
          </a>
        </div>
        <div
          className={`flex items-center text-xs tracking-wide text-gray-400 space-x-4 ${spaceMono.className}`}
        >
          <SysRequireButton/>
          <HomebrewButton />
          <GithubVersion />
          <LanguageSelector />
        </div>
      </footer>
    </div>
  );
}
