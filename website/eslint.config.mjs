import nextCoreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

const config = [
  ...nextCoreWebVitals,
  ...typescript,
  {
    ignores: [
      "archive/**",
      // Cloudflare Worker backend — its own toolchain/tsconfig, not part of the
      // Next app. Excluded from Next build typecheck (tsconfig) and lint here.
      "server/**",
    ],
  },
];

export default config;
