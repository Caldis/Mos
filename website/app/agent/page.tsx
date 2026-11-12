import type { Metadata } from "next";
import { SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

const agentProfile = {
  name: SITE_NAME,
  url: `${siteOrigin}/agent/`,
  homepage: `${siteOrigin}/`,
  description: SITE_DESCRIPTION,
  authentication: {
    type: "none",
    notes: "Public discovery and documentation endpoints require no account, OAuth flow, API key, or cookie.",
  },
  capabilities: [
    "Explain what Mos does and what platforms it supports.",
    "Find install and update links for Mos.",
    "Locate GitHub issues, discussions, releases, wiki pages, and appcast metadata.",
    "Read the public AI discovery files, markdown homepage, and schema feed.",
  ],
  endpoints: {
    llms: `${siteOrigin}/llms.txt`,
    llmsFull: `${siteOrigin}/llms-full.txt`,
    markdownHomepage: `${siteOrigin}/index.md`,
    developerResources: `${siteOrigin}/developers/`,
    openapi: `${siteOrigin}/api/openapi.json`,
    agentDiscovery: `${siteOrigin}/.well-known/agent.json`,
    a2aAgentCard: `${siteOrigin}/.well-known/agent-card.json`,
    mcpDiscovery: `${siteOrigin}/.well-known/mcp`,
    schemaMap: `${siteOrigin}/schema-map.xml`,
  },
  serviceStatus: {
    publicRestApi: "static-discovery-only",
    oauth: "not_provided",
    webhooks: "not_provided",
    hostedMcpServer: "not_provided",
  },
};

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos agent mode view",
  description:
    "Structured agent-readable view for Mos capabilities, public endpoints, authentication status, and AI discovery files.",
  alternates: {
    canonical: "/agent/",
  },
};

export default function AgentPage() {
  return (
    <main className="mx-auto max-w-5xl px-5 py-12 sm:py-16 text-white/86">
      <p className="font-mono text-xs uppercase tracking-[0.22em] text-white/46">
        Agent mode
      </p>
      <h1 className="mt-4 font-display text-4xl sm:text-6xl leading-none text-white">
        Mos agent mode view
      </h1>
      <p className="mt-5 max-w-3xl text-white/66 leading-7">
        This page is the structured view for AI agents. It lists Mos capabilities, public
        machine-readable endpoints, authentication status, and unavailable integration surfaces
        without requiring JavaScript.
      </p>

      <section aria-labelledby="capabilities" className="mt-10">
        <h2 id="capabilities" className="font-display text-2xl text-white">
          Key capabilities
        </h2>
        <ul className="mt-4 grid gap-3 text-white/70">
          {agentProfile.capabilities.map((item) => (
            <li key={item} className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
              {item}
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="endpoints" className="mt-10">
        <h2 id="endpoints" className="font-display text-2xl text-white">
          API endpoints and discovery files
        </h2>
        <dl className="mt-4 grid gap-3">
          {Object.entries(agentProfile.endpoints).map(([name, href]) => (
            <div
              key={name}
              className="grid gap-1 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 sm:grid-cols-[180px_1fr]"
            >
              <dt className="font-mono text-xs text-white/50">{name}</dt>
              <dd>
                <a className="break-all text-white/78 underline decoration-white/20 underline-offset-4" href={href}>
                  {href}
                </a>
              </dd>
            </div>
          ))}
        </dl>
      </section>

      <section aria-labelledby="auth" className="mt-10">
        <h2 id="auth" className="font-display text-2xl text-white">
          Authentication and integration status
        </h2>
        <table className="mt-4 w-full border-collapse overflow-hidden rounded-2xl text-left text-sm">
          <tbody>
            {Object.entries(agentProfile.serviceStatus).map(([name, status]) => (
              <tr key={name} className="border-b border-white/10 last:border-b-0">
                <th className="bg-white/5 px-4 py-3 font-mono text-xs text-white/58">{name}</th>
                <td className="bg-white/[0.03] px-4 py-3 text-white/72">{status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section aria-labelledby="json" className="mt-10">
        <h2 id="json" className="font-display text-2xl text-white">
          Machine-readable profile
        </h2>
        <pre className="mt-4 overflow-x-auto rounded-2xl border border-white/10 bg-black/50 p-4 text-xs leading-6 text-white/76">
          {JSON.stringify(agentProfile, null, 2)}
        </pre>
      </section>

      <script
        type="application/json"
        id="mos-agent-profile"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(agentProfile) }}
      />
    </main>
  );
}
