import type { Metadata } from "next";
import { InfoList, InfoListItem, InfoPage, InfoSection, TextLink } from "../components/InfoPage";
import { SITE_URL } from "../site";

const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: SITE_URL,
  title: "Mos auth docs and access model",
  description:
    "Authentication and access documentation for Mos public resources. Mos website discovery files are zero-auth and Mos does not provide hosted OAuth accounts.",
  alternates: {
    canonical: "/auth/",
  },
};

export default function AuthPage() {
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    headline: "Mos auth docs and access model",
    url: `${siteOrigin}/auth/`,
    dateModified: "2026-05-09",
    about: {
      "@type": "SoftwareApplication",
      name: "Mos",
      url: `${siteOrigin}/`,
    },
  };

  return (
    <InfoPage
      eyebrow="Auth docs"
      title="Mos auth docs"
      lead="Mos is a local macOS utility. Public website resources are static and do not require OAuth, API keys, sessions, or user accounts."
    >
      <InfoSection title="Public resource access">
        <p>
          The homepage, markdown documents, OpenAPI description, agent discovery files, schema feeds,
          appcast, and release links are public. Agents can read them without authentication.
        </p>
        <p>
          The machine-readable metadata at{" "}
          <TextLink href="/.well-known/oauth-protected-resource">
            /.well-known/oauth-protected-resource
          </TextLink>{" "}
          records this zero-auth status.
        </p>
      </InfoSection>

      <InfoSection title="No OAuth surface">
        <InfoList>
          <InfoListItem>Mos does not host user accounts.</InfoListItem>
          <InfoListItem>Mos does not issue OAuth client IDs, access tokens, or refresh tokens.</InfoListItem>
          <InfoListItem>Mos does not define OAuth scopes for remote actions.</InfoListItem>
          <InfoListItem>Mos does not expose account, billing, or settings APIs.</InfoListItem>
        </InfoList>
      </InfoSection>

      <InfoSection title="Local macOS permission">
        <p>
          Mos may require macOS Accessibility permission so the local app can observe and process
          input events. This is a local operating-system permission, not a Mos web account or OAuth
          login.
        </p>
      </InfoSection>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
    </InfoPage>
  );
}
