import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos privacy notes",
  description:
    "Privacy notes for the Mos macOS app and mos.caldis.me website, including local app behavior and website analytics.",
  alternates: {
    canonical: "/privacy/",
  },
};

export default function PrivacyPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "PrivacyPolicy",
    name: "Mos privacy notes",
    url: `${siteOrigin}/privacy/`,
    dateModified: "2026-05-09",
    publisher: {
      "@type": "Organization",
      "@id": `${siteOrigin}/#organization`,
      name: "Caldis",
      email: "mail@caldis.me",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="Privacy"
      title="Mos privacy notes"
      lead="Mos is a local macOS utility. These notes describe the public project surface and the current website behavior."
    >
      <InfoSection title="Mos app">
        <p>
          Mos runs locally on macOS to process scrolling and mouse button behavior. It needs macOS
          Accessibility permission for input handling. The app is not a hosted account service, and
          the public discovery files do not create a remote control channel into a user&apos;s Mac.
        </p>
        <p>
          Configuration such as scroll tuning, per-app profiles, shortcuts, and button bindings is
          part of the local app behavior. Users should review the public source code when they need a
          precise implementation-level answer about how a setting is stored or used.
        </p>
      </InfoSection>

      <InfoSection title="Website">
        <p>
          The website at mos.caldis.me publishes the homepage, release metadata, markdown files,
          schema feeds, and agent discovery documents. The site currently loads Google Analytics 4
          using measurement ID <span className="font-mono text-white/78">G-9M7WPLB8BR</span> for
          aggregate website analytics.
        </p>
        <p>
          Public static files such as <TextLink href="/llms.txt">llms.txt</TextLink>,{" "}
          <TextLink href="/llms-full.txt">llms-full.txt</TextLink>, and{" "}
          <TextLink href="/api/openapi.json">OpenAPI metadata</TextLink> are intended for humans,
          search crawlers, and AI agents. They do not expose private user data.
        </p>
      </InfoSection>

      <InfoSection title="Third-party surfaces">
        <InfoList>
          <InfoListItem>
            Source code, issues, discussions, and releases are hosted on GitHub.
          </InfoListItem>
          <InfoListItem>
            Homebrew installation uses the Homebrew cask ecosystem.
          </InfoListItem>
          <InfoListItem>
            Website analytics are provided through Google Analytics 4.
          </InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="Contact">
        <p>
          Privacy questions or corrections can be sent to{" "}
          <TextLink href="mailto:mail@caldis.me">mail@caldis.me</TextLink>. Bug reports that can be
          discussed publicly should use{" "}
          <TextLink href="https://github.com/Caldis/Mos/issues">GitHub Issues</TextLink>.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
