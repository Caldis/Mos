import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos rate limits and request budget",
  description:
    "Rate-limit documentation for Mos public static resources. Mos does not provide a hosted API with product-level quotas.",
  alternates: {
    canonical: "/rate-limits/",
  },
};

export default function RateLimitsPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos rate limits and request budget",
    url: `${siteOrigin}/rate-limits/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: "Mos",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="Rate limits"
      title="Mos rate limits"
      lead="Mos does not provide a hosted API with product-level quotas. Public documentation and discovery files are static resources served by the website."
    >
      <InfoSection title="Current status">
        <p>
          There are no Mos API rate-limit headers, account quotas, paid tiers, request budgets, or
          Retry-After rules because there is no hosted Mos user API.
        </p>
      </InfoSection>

      <InfoSection title="Agent request guidance">
        <InfoList>
          <InfoListItem>Fetch <TextLink href="/llms-full.txt">llms-full.txt</TextLink> first when full product context is needed.</InfoListItem>
          <InfoListItem>Use section files such as <TextLink href="/api/llms.txt">/api/llms.txt</TextLink> for narrower context.</InfoListItem>
          <InfoListItem>Cache static resources within the current task instead of repeatedly fetching the same URL.</InfoListItem>
          <InfoListItem>Do not infer API quotas, billing limits, or user-specific request budgets.</InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="Hosting boundary">
        <p>
          Generic CDN or GitHub Pages throttling may apply outside Mos&apos;s control. That is hosting
          infrastructure behavior, not a Mos product API contract.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
