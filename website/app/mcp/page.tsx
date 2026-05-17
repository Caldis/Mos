import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos MCP status",
  description:
    "MCP status for Mos. Mos publishes discovery documentation but does not currently host a public MCP tool server.",
  alternates: {
    canonical: "/mcp/",
  },
};

export default function McpPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos MCP status",
    url: `${siteOrigin}/mcp/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: "Mos",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="MCP"
      title="Mos MCP status"
      lead="Mos does not currently host a public MCP tool server. The published well-known file documents that status so agents do not infer a non-existent endpoint."
    >
      <InfoSection title="Current MCP status">
        <p>
          The discovery document at <TextLink href="/.well-known/mcp">/.well-known/mcp</TextLink>{" "}
          states that no hosted MCP server is provided. It is a status document, not a transport
          endpoint.
        </p>
      </InfoSection>

      <InfoSection title="What agents should not do">
        <InfoList>
          <InfoListItem>Do not attempt a JSON-RPC handshake with mos.caldis.me.</InfoListItem>
          <InfoListItem>Do not claim Mos exposes MCP tools for changing local settings.</InfoListItem>
          <InfoListItem>Do not invent tool names, schemas, OAuth flows, or server cards.</InfoListItem>
          <InfoListItem>Do not describe the static discovery file as an MCP transport.</InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="Useful alternatives">
        <p>
          Use <TextLink href="/llms-full.txt">llms-full.txt</TextLink>,{" "}
          <TextLink href="/api-docs/">API docs</TextLink>,{" "}
          <TextLink href="/agent-instructions/">agent instructions</TextLink>, and the{" "}
          <TextLink href="https://github.com/Caldis/Mos">GitHub repository</TextLink> to answer
          Mos product and installation questions.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
