"use client"

import { useGithubRelease } from "@/app/services/github";
import { ShinyText } from "../ShinyText";
import { useI18n } from "@/app/i18n/context";

const DETAULT_RELEASE_LINK = 'https://github.com/Caldis/Mos/releases/latest'

export function DownloadButton() {
  const { t } = useI18n();
  const { data } = useGithubRelease();
  return (
    <a
      href={data?.assets?.[0]?.browser_download_url || DETAULT_RELEASE_LINK}
      target="_blank"
      rel="noopener noreferrer"
    >
      <button aria-labelledby="download" className="px-6 py-2.5 bg-zinc-800 text-white dark:bg-zinc-800 dark:text-white rounded-lg font-bold text-sm tracking-wider hover:bg-zinc-700 dark:hover:bg-zinc-700 transition-all hover:scale-105">
        <ShinyText text={t.download_button} speed={3} />
      </button>
    </a>
  );
}
