import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos error responses and recovery",
  description:
    "Error-response documentation for Mos public static resources. Mos does not provide a hosted JSON API error envelope.",
  alternates: {
    canonical: "/errors/",
  },
};

export default function ErrorsPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos error responses and recovery",
    url: `${siteOrigin}/errors/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: "Mos",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="Errors"
      title="Mos error responses"
      lead="Mos does not expose a hosted JSON API, so there is no product-specific JSON error envelope for agents to parse."
    >
      <InfoSection title="Static website behavior">
        <p>
          Public Mos resources are static files and pages. Existing files return normal HTTP 200
          responses. Missing URLs are handled by the static host and may return an HTML 404 page
          rather than a JSON error document.
        </p>
      </InfoSection>

      <InfoSection title="Agent recovery guidance">
        <InfoList>
          <InfoListItem>Use <TextLink href="/sitemap.xml">/sitemap.xml</TextLink> and <TextLink href="/llms.txt">/llms.txt</TextLink> to discover supported URLs.</InfoListItem>
          <InfoListItem>Use <TextLink href="/api-docs/">/api-docs/</TextLink> for the current static discovery surface.</InfoListItem>
          <InfoListItem>Do not retry nonexistent API paths such as account, billing, settings, webhook registration, or MCP tool endpoints.</InfoListItem>
          <InfoListItem>If a public static URL is unavailable, fall back to the GitHub repository and release pages.</InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="No remote action errors">
        <p>
          Mos has no remote action API for changing local settings. Agents should not expect JSON
          errors for validation failures, permission failures, or rate limits from mos.caldis.me.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
