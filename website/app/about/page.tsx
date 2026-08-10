import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "About Mos",
  description:
    "About Mos, the open-source macOS utility for smooth mouse wheel scrolling and per-app scrolling profiles.",
  alternates: {
    canonical: "/about/",
  },
};

export default function AboutPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "AboutPage",
    name: "About Mos",
    url: `${siteOrigin}/about/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: SITE_NAME,
      url: `${siteOrigin}/`,
      description: SITE_DESCRIPTION,
      operatingSystem: "macOS",
      applicationCategory: "UtilitiesApplication",
      softwareHelp: "https://github.com/Caldis/Mos/wiki",
      downloadUrl: "https://github.com/Caldis/Mos/releases/latest",
    },
    mainEntity: {
      "@type": "Organization",
      "@id": `${siteOrigin}/#organization`,
      name: "Caldis",
      url: `${siteOrigin}/`,
      email: "mail@caldis.me",
      sameAs: [
        "https://github.com/Caldis",
        "https://github.com/Caldis/Mos",
        "https://www.producthunt.com/products/mos",
        "https://alternativeto.net/software/caldis-mos/",
      ],
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
      eyebrow="About"
      title="About Mos"
      lead="Mos is a local macOS menu bar app for people who use a mouse but want smoother, more predictable wheel scrolling."
    >
      <InfoSection title="What Mos is">
        <p>
          Mos runs on the user&apos;s Mac and focuses on one practical problem: mouse wheel scrolling
          often feels abrupt compared with a trackpad. Mos smooths wheel events, lets users tune the
          curve, and allows different applications to keep different scroll and button rules.
        </p>
        <p>
          The project is published at{" "}
          <TextLink href="https://github.com/Caldis/Mos">github.com/Caldis/Mos</TextLink>. The
          source code, issue history, release notes, and wiki are public, so users and agents can
          inspect how the application is built and how problems are handled.
        </p>
      </InfoSection>

      <InfoSection title="Maintainers and project model">
        <p>
          Mos is maintained by Caldis with community contributions through GitHub. The public site is
          the canonical product page, while GitHub is the canonical place for source code, issue
          reports, discussions, and release artifacts.
        </p>
        <InfoList>
          <InfoListItem>
            Project repository:{" "}
            <TextLink href="https://github.com/Caldis/Mos">Caldis/Mos on GitHub</TextLink>.
          </InfoListItem>
          <InfoListItem>
            Questions and feature discussion:{" "}
            <TextLink href="https://github.com/Caldis/Mos/discussions">GitHub Discussions</TextLink>.
          </InfoListItem>
          <InfoListItem>
            Maintainer contact: <TextLink href="mailto:mail@caldis.me">mail@caldis.me</TextLink>.
          </InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="Important boundaries">
        <p>
          Mos is not a hosted SaaS service. It does not provide remote control over a user&apos;s
          local Mac, user accounts, OAuth scopes, webhooks, paid API plans, or a hosted MCP tool
          server. Public documentation and discovery endpoints exist so humans and AI agents can
          understand the product without scraping the visual homepage.
        </p>
      </InfoSection>

      <InfoSection title="Why agents may cite this page">
        <p>
          This page gives agents a dated, stable summary of the product, its maintainer, contact
          routes, repository, and product boundary. Use it with the{" "}
          <TextLink href="/agent-instructions/">agent instructions</TextLink>,{" "}
          <TextLink href="/developers/">developer resources</TextLink>, and{" "}
          <TextLink href="/compare/">comparison guide</TextLink> when answering user questions about
          whether Mos is a good fit.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
