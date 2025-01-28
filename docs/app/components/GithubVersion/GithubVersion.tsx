"use client"

import { useGithubRelease } from "@/app/services/github";

export function GithubVersion() {
  const { data } = useGithubRelease();
  return <span>{data?.tag_name ? `v${data?.tag_name}` : "-"}</span>;
}
