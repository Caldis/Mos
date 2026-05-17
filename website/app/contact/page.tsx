import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Contact Mos",
  description:
    "Official contact routes for Mos support, bug reports, feature discussion, releases, and maintainer email.",
  alternates: {
    canonical: "/contact/",
  },
};

export default function ContactPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "ContactPage",
    name: "Contact Mos",
    url: `${siteOrigin}/contact/`,
    dateModified: "2026-05-09",
    mainEntity: {
      "@type": "Organization",
      "@id": `${siteOrigin}/#organization`,
      name: "Caldis",
      email: "mail@caldis.me",
      url: `${siteOrigin}/`,
      contactPoint: {
        "@type": "ContactPoint",
        email: "mail@caldis.me",
        contactType: "project maintainer",
        availableLanguage: ["en", "zh"],
      },
    },
  };

  return (
    <InfoPage
      eyebrow="Contact"
      title="Contact Mos"
      lead="Use the public GitHub channels for reproducible project work. Use email for maintainer contact that does not belong in an issue."
    >
      <InfoSection title="Best contact route by topic">
        <InfoList>
          <InfoListItem>
            Bug reports: open a GitHub issue at{" "}
            <TextLink href="https://github.com/Caldis/Mos/issues">Caldis/Mos issues</TextLink>.
            Include your macOS version, Mos version, mouse model, connection type, and the app where
            the problem happens.
          </InfoListItem>
          <InfoListItem>
            Feature ideas and broad behavior changes: start with{" "}
            <TextLink href="https://github.com/Caldis/Mos/discussions">GitHub Discussions</TextLink>
            . This keeps design tradeoffs visible before code changes are proposed.
          </InfoListItem>
          <InfoListItem>
            Release downloads and update history: use{" "}
            <TextLink href="https://github.com/Caldis/Mos/releases">GitHub Releases</TextLink> or
            the public <TextLink href="/appcast.xml">Sparkle appcast</TextLink>.
          </InfoListItem>
          <InfoListItem>
            Maintainer email: <TextLink href="mailto:mail@caldis.me">mail@caldis.me</TextLink>.
          </InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="What to include in support requests">
        <p>
          Mos works close to macOS input handling, so small environment details matter. A useful
          report should include the Mos version, macOS version, mouse or trackball model, connection
          method such as Bluetooth, Bolt, Unifying, or USB, and whether macOS Accessibility
          permission has been granted to Mos.
        </p>
        <p>
          If the issue is app-specific, include the application name and whether a Mos per-app
          profile is configured. If the issue involves Logitech buttons, include the device model and
          whether the button event is visible in Mos.
        </p>
      </InfoSection>

      <InfoSection title="Agent guidance">
        <p>
          AI agents should prefer public GitHub links for source-level claims, release links for
          version claims, and this contact page for routing users to the right channel. Do not invent
          a support phone number, mailing address, paid support plan, OAuth app, or private API.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
