"use client"

import { useGithubRelease } from "@/app/services/github";

export function GithubVersion() {
  const { data } = useGithubRelease();
  if (!data?.tag_name) return null
  return (
    <>
      <span>•</span>
      <button className="text-white/60 hover:text-white/90 transition-colors flex items-center gap-1.5">
        <svg
          viewBox="0 0 24 24"
          className="w-3 h-3"
          fill="currentColor"
        >
          <path d="M17.63 5.84C17.27 5.33 16.67 5 16 5L5 5.01C3.9 5.01 3 5.9 3 7v10c0 1.1.9 1.99 2 1.99L16 19c.67 0 1.27-.33 1.63-.84L22 12l-4.37-6.16zM16 17H5V7h11l3.55 5L16 17z" />
        </svg>
        <span>v{data?.tag_name}</span>
      </button>
    </>
  );
}
