import { useI18n } from "@/app/i18n/context";

export function SysRequireButton() {
  const { t } = useI18n();
  return (
    <span className="cursor-pointer hover:text-white/90 transition-colors flex items-center gap-1.5">
    <svg
        viewBox="0 0 1000 1000"
        className="w-2.5 h-2.5"
        fill="currentColor"
    >
      <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
    </svg>
    <a
        href="https://en.wikipedia.org/wiki/MacOS_High_Sierra"
        target="_blank"
        rel="noopener noreferrer"
        className="hover:text-white/90 transition-colors"
    >
        {t.footer_systemRequirement}
    </a>
    </span>
  )
}