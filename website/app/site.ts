const rawSiteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://mos.caldis.me";

// Ensure a trailing slash so `new URL("/path", SITE_URL)` behaves predictably.
export const SITE_URL = new URL(rawSiteUrl.endsWith("/") ? rawSiteUrl : `${rawSiteUrl}/`);

export const SITE_NAME = "Mos";

export const SITE_TITLE = "Mos | Smooth scrolling for mouse wheels on macOS";

export const SITE_DESCRIPTION =
  "Mos is a free macOS utility that makes mouse wheel scrolling smooth, with per-app settings, independent axis tuning, and button/shortcut bindings.";

export const OG_IMAGE_PATH = "/og.svg";
