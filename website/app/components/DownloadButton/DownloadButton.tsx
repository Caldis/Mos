"use client"

import { useGithubRelease } from "@/app/services/github";
import { ShinyText } from "../ShinyText";

const DETAULT_RELEASE_LINK = 'https://github.com/Caldis/Mos/releases/latest'

export function DownloadButton() {
  const { data } = useGithubRelease();
  return (
    <a
      href={data?.assets?.[0]?.browser_download_url || DETAULT_RELEASE_LINK}
      target="_blank"
      rel="noopener noreferrer"
    >
      <button className="px-6 py-2.5 bg-zinc-800 text-white dark:bg-zinc-800 dark:text-white rounded-lg font-bold text-sm tracking-wider hover:bg-zinc-700 dark:hover:bg-zinc-700 transition-all hover:scale-105">
        <ShinyText text="Download for Mac" speed={3} />
      </button>
    </a>
  );
}
