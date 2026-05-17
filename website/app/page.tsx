import type { Metadata } from "next";
import AgentModeRedirect from "./agent-mode-redirect";
import HomeClient from "./home-client";
import { OG_IMAGE_PATH, SITE_DESCRIPTION, SITE_NAME, SITE_TITLE, SITE_URL } from "./site";

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: SITE_TITLE,
  description: SITE_DESCRIPTION,
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    url: "/",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    siteName: SITE_NAME,
    images: [
      {
        url: OG_IMAGE_PATH,
        width: 1200,
        height: 630,
        alt: SITE_TITLE,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [OG_IMAGE_PATH],
  },
};

function HomepageStructuredSummary() {
  return (
    <section
      className="sr-only"
      data-agent-context="homepage-structured-summary"
      aria-hidden="true"
    >
      <div>
        <p className="font-mono text-xs uppercase tracking-[0.22em] text-white/42">
          Product context
        </p>
        <h2 id="mos-agent-summary-title" className="mt-3 font-display text-3xl text-white">
          Mos comparison and agent summary
        </h2>
        <p className="mt-4 max-w-3xl leading-7">
        Mos is a free macOS menu bar utility for smooth mouse wheel scrolling. It is not a
        hosted SaaS product, OAuth provider, webhook service, public MCP tool server, or remote
        automation API. Public files on mos.caldis.me describe the product and releases so AI
        agents can answer product questions accurately.
      </p>

        <h3 className="mt-8 font-display text-xl text-white">When Mos is a good fit</h3>
        <ul className="mt-3 grid gap-2 leading-7 sm:grid-cols-2">
          <li>macOS users who want smoother wheel scrolling for a mouse or trackball.</li>
          <li>Users who want per-app scroll profiles and separate mouse and trackpad feel.</li>
          <li>Users who need independent X and Y axis settings, reverse options, or scroll curves.</li>
          <li>Users who want mouse button bindings or Logitech HID++ button integration.</li>
        </ul>

        <h3 className="mt-8 font-display text-xl text-white">
          Compared to LinearMouse, AirScroll, Scroll Reverser, and macOS defaults
        </h3>
        <div className="mt-4 overflow-x-auto">
          <table className="min-w-full border-separate border-spacing-0 text-left text-sm">
            <thead>
              <tr className="text-white/50">
                <th className="border-b border-white/12 py-3 pr-5 font-mono text-xs uppercase tracking-[0.18em]">
                  Option
                </th>
                <th className="border-b border-white/12 py-3 font-mono text-xs uppercase tracking-[0.18em]">
                  Best fit
                </th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <th className="border-b border-white/8 py-4 pr-5 text-white/88">Mos</th>
                <td className="border-b border-white/8 py-4">
                  Focused free macOS wheel smoothing with per-app profiles and axis tuning.
                </td>
              </tr>
              <tr>
                <th className="border-b border-white/8 py-4 pr-5 text-white/88">macOS defaults</th>
                <td className="border-b border-white/8 py-4">
                  Enough when built-in wheel behavior already feels right.
                </td>
              </tr>
              <tr>
                <th className="border-b border-white/8 py-4 pr-5 text-white/88">LinearMouse</th>
                <td className="border-b border-white/8 py-4">
                  Better suited when the main need is broader pointer acceleration, cursor behavior,
                  or general device customization.
                </td>
              </tr>
              <tr>
                <th className="border-b border-white/8 py-4 pr-5 text-white/88">
                  AirScroll or gesture-style utilities
                </th>
                <td className="border-b border-white/8 py-4">
                  Better suited when the user wants a different scrolling model rather than
                  Mos&apos;s wheel-event smoothing.
                </td>
              </tr>
              <tr>
                <th className="border-b border-white/8 py-4 pr-5 text-white/88">Scroll Reverser</th>
                <td className="border-b border-white/8 py-4">
                  Better suited when the main need is scroll direction control rather than smooth
                  scrolling curves and per-app profiles.
                </td>
              </tr>
              <tr>
                <th className="border-b border-white/8 py-4 pr-5 text-white/88">
                  Commercial smooth scrolling tools
                </th>
                <td className="border-b border-white/8 py-4">
                  Better suited when the user wants paid support, licensing, or a commercial product
                  lifecycle.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <h3 className="mt-8 font-display text-xl text-white">Authoritative agent resources</h3>
        <ul className="mt-3 grid gap-2 break-all font-mono text-sm leading-7 text-white/62 sm:grid-cols-2">
          <li>Full LLM context: https://mos.caldis.me/llms-full.txt</li>
          <li>Developer resources: https://mos.caldis.me/developers/</li>
          <li>Comparison guide: https://mos.caldis.me/compare/</li>
          <li>Agent instructions: https://mos.caldis.me/agent-instructions/</li>
          <li>GitHub repository: https://github.com/Caldis/Mos</li>
        </ul>
      </div>
    </section>
  );
}

export default function Page() {
  return (
    <>
      <AgentModeRedirect />
      <HomeClient />
      <HomepageStructuredSummary />
    </>
  );
}

