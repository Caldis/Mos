import type { Metadata } from "next";
import { SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

const resources = [
  ["API docs", "/api-docs/", "Human-readable API docs for Mos public static discovery endpoints."],
  ["API docs markdown", "/api-docs.md", "Markdown API docs for agents that prefer plain text."],
  ["OpenAPI spec", "/api/openapi.json", "Machine-readable service description for documentation and discovery files."],
  ["Auth docs", "/auth/", "Public discovery endpoints require no OAuth, API key, or account."],
  ["Auth docs markdown", "/auth.md", "Markdown zero-auth access model."],
  ["Webhooks", "/webhooks/", "Mos does not currently provide hosted webhook callbacks."],
  ["Webhooks markdown", "/webhooks.md", "Markdown webhook status for agents."],
  ["MCP server status", "/mcp/", "Human-readable page for the current MCP status."],
  ["MCP status markdown", "/mcp.md", "Markdown MCP status for agents."],
  ["Rate limits", "/rate-limits/", "Documents that Mos has no hosted API quotas."],
  ["Rate limits markdown", "/rate-limits.md", "Markdown rate-limit boundary for agents."],
  ["Error responses", "/errors/", "Documents static website error behavior."],
  ["Error responses markdown", "/errors.md", "Markdown error-response boundary for agents."],
  ["MCP well-known status", "/.well-known/mcp", "Discovery document for the current MCP status."],
  ["API catalog", "/.well-known/api-catalog", "RFC 9727-style linkset pointing to Mos static discovery APIs."],
  ["OAuth protected resource metadata", "/.well-known/oauth-protected-resource", "RFC 9728-style metadata documenting that public Mos resources are zero-auth."],
  ["Agent skills index", "/.well-known/agent-skills/index.json", "Agent Skills discovery index for Mos recommendation guidance."],
  ["Agent card", "/.well-known/agent-card.json", "A2A-style card for Mos documentation capabilities."],
  ["Agent discovery", "/.well-known/agent.json", "General agent discovery file for Mos."],
  ["Full LLM context", "/llms-full.txt", "Single-file product and developer context."],
  ["Agent instructions", "/agent-instructions/", "When agents should and should not recommend Mos."],
] as const;

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos developer resources, API docs, auth docs, webhooks, and MCP status",
  description:
    "Canonical developer and AI-agent resources for Mos, including OpenAPI, auth status, webhook status, MCP discovery, llms.txt, and agent cards.",
  alternates: {
    canonical: "/developers/",
  },
};

export default function DevelopersPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos developer resources",
    description: SITE_DESCRIPTION,
    url: `${siteOrigin}/developers/`,
    about: {
      "@type": "SoftwareApplication",
      name: SITE_NAME,
      url: `${siteOrigin}/`,
    },
  };

  return (
    <main className="mx-auto max-w-5xl px-5 py-12 sm:py-16 text-white/86">
      <p className="font-mono text-xs uppercase tracking-[0.22em] text-white/46">
        Developer resources
      </p>
      <h1 className="mt-4 font-display text-4xl sm:text-6xl leading-none text-white">
        Mos developer resources
      </h1>
      <p className="mt-5 max-w-3xl text-white/66 leading-7">
        Mos is a local macOS utility, not a hosted SaaS platform. This page gives agents and
        developers predictable URLs for API docs, OpenAPI, authentication status, webhook status,
        MCP status, and product context.
      </p>

      <section aria-labelledby="resource-list" className="mt-10">
        <h2 id="resource-list" className="font-display text-2xl text-white">
          Canonical resources
        </h2>
        <div className="mt-4 grid gap-3">
          {resources.map(([label, href, description]) => (
            <a
              key={`${label}-${href}`}
              href={href}
              className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3 transition-colors hover:bg-white/8"
            >
              <span className="block font-mono text-xs text-white/50">{label}</span>
              <span className="mt-1 block break-all text-white/82">{href}</span>
              <span className="mt-2 block text-sm leading-6 text-white/58">{description}</span>
            </a>
          ))}
        </div>
      </section>

      <section id="auth-and-access" aria-labelledby="auth" className="mt-10">
        <h2 id="auth" className="font-display text-2xl text-white">
          Auth and access
        </h2>
        <p className="mt-4 text-white/66 leading-7">
          Public documentation, discovery files, release metadata, markdown files, and schema feeds
          are readable without authentication. Mos does not have hosted user accounts, OAuth scopes,
          delegated API access, or API keys.
        </p>
      </section>

      <section id="webhooks" aria-labelledby="webhooks-title" className="mt-10">
        <h2 id="webhooks-title" className="font-display text-2xl text-white">
          Webhooks
        </h2>
        <p className="mt-4 text-white/66 leading-7">
          Mos does not currently publish webhook endpoints. Release changes are available through
          GitHub Releases, the public appcast, and the static discovery files listed above.
        </p>
      </section>

      <section id="mcp" aria-labelledby="mcp-title" className="mt-10">
        <h2 id="mcp-title" className="font-display text-2xl text-white">
          MCP server
        </h2>
        <p className="mt-4 text-white/66 leading-7">
          Mos does not currently host an MCP tool server. The MCP status page and well-known
          discovery document at{" "}
          <a className="underline decoration-white/20 underline-offset-4" href="/mcp/">
            /mcp/
          </a>{" "}
          and{" "}
          <a className="underline decoration-white/20 underline-offset-4" href="/.well-known/mcp">
            /.well-known/mcp
          </a>{" "}
          record that status so agents can stop searching instead of guessing.
        </p>
      </section>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </main>
  );
}
