import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'export',
  // GitHub Pages (static hosting) serves /foo/ as /foo/index.html; avoid /foo.html URLs.
  trailingSlash: true,
  images: { unoptimized: true },
  // Dev-only proxy so the wall's debug "Live data" toggle can read the production
  // API (mos-api.caldis.me) without CORS. `output: export` drops rewrites in the
  // production build, and we return none there anyway, so this stays local-only.
  async rewrites() {
    if (process.env.NODE_ENV !== "development") return [];
    return [{ source: "/__live/:path*", destination: "https://mos-api.caldis.me/:path*" }];
  },
};

export default nextConfig;
