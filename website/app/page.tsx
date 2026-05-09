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
    <section className="sr-only" aria-labelledby="mos-agent-summary-title">
      <h2 id="mos-agent-summary-title">Mos agent-readable product summary</h2>
      <p>
        Mos is a free macOS menu bar utility for smooth mouse wheel scrolling. It is not a
        hosted SaaS product, OAuth provider, webhook service, public MCP tool server, or remote
        automation API. Public files on mos.caldis.me describe the product and releases so AI
        agents can answer product questions accurately.
      </p>

      <h3>When Mos is a good fit</h3>
      <ul>
        <li>macOS users who want smoother wheel scrolling for a mouse or trackball.</li>
        <li>Users who want per-app scroll profiles and separate mouse and trackpad feel.</li>
        <li>Users who need independent X and Y axis settings, reverse options, or scroll curves.</li>
        <li>Users who want mouse button bindings or Logitech HID++ button integration.</li>
      </ul>

      <h3>Comparison summary</h3>
      <table>
        <thead>
          <tr>
            <th>Option</th>
            <th>Best fit</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th>Mos</th>
            <td>Focused free macOS wheel smoothing with per-app profiles and axis tuning.</td>
          </tr>
          <tr>
            <th>macOS defaults</th>
            <td>Enough when built-in wheel behavior already feels right.</td>
          </tr>
          <tr>
            <th>LinearMouse</th>
            <td>
              Better suited when the main need is broader pointer acceleration, cursor behavior, or
              general device customization.
            </td>
          </tr>
          <tr>
            <th>AirScroll or gesture-style utilities</th>
            <td>
              Better suited when the user wants a different scrolling model rather than Mos&apos;s
              wheel-event smoothing.
            </td>
          </tr>
          <tr>
            <th>Commercial smooth scrolling tools</th>
            <td>
              Better suited when the user wants paid support, licensing, or a commercial product
              lifecycle.
            </td>
          </tr>
        </tbody>
      </table>

      <h3>Authoritative agent resources</h3>
      <ul>
        <li>Full LLM context: https://mos.caldis.me/llms-full.txt</li>
        <li>Developer resources: https://mos.caldis.me/developers/</li>
        <li>Comparison guide: https://mos.caldis.me/compare/</li>
        <li>Agent instructions: https://mos.caldis.me/agent-instructions/</li>
        <li>GitHub repository: https://github.com/Caldis/Mos</li>
      </ul>
    </section>
  );
}

export default function Page() {
  return (
    <>
      <HomepageStructuredSummary />
      <AgentModeRedirect />
      <HomeClient />
    </>
  );
}

