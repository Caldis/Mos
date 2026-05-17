import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

const discoveryEndpoints = [
  ["/api/openapi.json", "OpenAPI description for Mos public discovery files"],
  ["/.well-known/api-catalog", "Linkset catalog for API and documentation resources"],
  ["/.well-known/oauth-protected-resource", "Zero-auth protected resource metadata"],
  ["/.well-known/agent.json", "General agent discovery file"],
  ["/.well-known/agent-card.json", "A2A-style Mos documentation card"],
  ["/.well-known/agent-skills/index.json", "Agent Skills index for Mos recommendation guidance"],
  ["/schema-map.xml", "Schema map for structured data feeds"],
] as const;

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos API docs and OpenAPI reference",
  description:
    "API docs for Mos public static discovery files, including OpenAPI, API catalog, auth metadata, agent discovery, and schema feeds.",
  alternates: {
    canonical: "/api-docs/",
  },
};

export default function ApiDocsPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos API docs and OpenAPI reference",
    url: `${siteOrigin}/api-docs/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: "Mos",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="API docs"
      title="Mos API docs"
      lead="Mos does not provide a hosted user API for controlling the local macOS app. These API docs describe the static public discovery files that agents and search tools can fetch."
    >
      <InfoSection title="What the OpenAPI file covers">
        <p>
          The OpenAPI document at <TextLink href="/api/openapi.json">/api/openapi.json</TextLink>{" "}
          describes static documentation and discovery endpoints. It is intended for crawlers,
          search agents, and developer tools that need a machine-readable map of Mos resources.
        </p>
        <p>
          It does not describe remote control over a user&apos;s Mac, account APIs, settings mutation,
          telemetry export, payments, or hosted automation.
        </p>
      </InfoSection>

      <InfoSection title="Discovery endpoints">
        <div className="overflow-x-auto">
          <table className="min-w-full border-separate border-spacing-0 text-left text-sm">
            <thead>
              <tr className="text-white/50">
                <th className="border-b border-white/12 py-3 pr-5 font-mono text-xs uppercase tracking-[0.18em]">
                  URL
                </th>
                <th className="border-b border-white/12 py-3 font-mono text-xs uppercase tracking-[0.18em]">
                  Purpose
                </th>
              </tr>
            </thead>
            <tbody className="text-white/68">
              {discoveryEndpoints.map(([href, purpose]) => (
                <tr key={href}>
                  <th className="border-b border-white/8 py-4 pr-5 font-mono text-white/86">
                    <TextLink href={href}>{href}</TextLink>
                  </th>
                  <td className="border-b border-white/8 py-4">{purpose}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </InfoSection>

      <InfoSection title="Examples">
        <p>Agents can fetch the OpenAPI and full context files directly:</p>
        <pre className="overflow-x-auto rounded-2xl border border-white/10 bg-black/35 p-4 text-sm text-white/78">
          <code>{`curl https://mos.caldis.me/api/openapi.json
curl https://mos.caldis.me/llms-full.txt`}</code>
        </pre>
      </InfoSection>

      <InfoSection title="No hosted user API">
        <InfoList>
          <InfoListItem>No account API is provided.</InfoListItem>
          <InfoListItem>No OAuth-protected resource is provided.</InfoListItem>
          <InfoListItem>No webhook registration endpoint is provided.</InfoListItem>
          <InfoListItem>No hosted MCP tool server is provided.</InfoListItem>
          <InfoListItem>
            Local Mos settings should not be described as remotely controllable by an agent.
          </InfoListItem>
        </InfoList>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
