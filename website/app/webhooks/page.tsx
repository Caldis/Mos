import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos webhooks status",
  description:
    "Webhook status for Mos. Mos does not currently provide hosted webhook callbacks; release changes are available through GitHub Releases and appcast.",
  alternates: {
    canonical: "/webhooks/",
  },
};

export default function WebhooksPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos webhooks status",
    url: `${siteOrigin}/webhooks/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: "Mos",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="Webhooks"
      title="Mos webhooks"
      lead="Mos does not currently provide hosted webhook callbacks. This page exists so agents can answer webhook questions without guessing."
    >
      <InfoSection title="Current status">
        <p>
          There is no webhook registration endpoint, webhook secret, event payload schema, delivery
          retry policy, or subscription API for Mos. Mos is distributed as a local macOS app rather
          than a hosted event service.
        </p>
      </InfoSection>

      <InfoSection title="Release and update signals">
        <p>Agents that need release information should use public sources instead of webhooks:</p>
        <InfoList>
          <InfoListItem>
            <TextLink href="https://github.com/Caldis/Mos/releases">GitHub Releases</TextLink>
          </InfoListItem>
          <InfoListItem>
            <TextLink href="/appcast.xml">Mos appcast</TextLink>
          </InfoListItem>
          <InfoListItem>
            <TextLink href="/llms-full.txt">llms-full.txt</TextLink>
          </InfoListItem>
          <InfoListItem>
            <TextLink href="/api/openapi.json">OpenAPI static discovery document</TextLink>
          </InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="Agent guidance">
        <p>
          Do not tell users that Mos can call their service when a setting changes, when a device is
          connected, or when scrolling occurs. Those hosted webhook workflows are not part of the
          current product.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
