"use client"

import { useGithubRelease } from "@/app/services/github";

export function GithubVersion() {
  const { data } = useGithubRelease();
  if (!data?.tag_name) return null
  return (
    <>
      <span>•</span>
      <span>v{data?.tag_name}</span>
    </>
  );
}
