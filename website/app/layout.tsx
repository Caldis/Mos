import Script from "next/script";
import { IBM_Plex_Mono, Space_Grotesk, Syne } from "next/font/google";
import "./globals.css";
import { SITE_DESCRIPTION, SITE_NAME, SITE_TITLE, SITE_URL } from "./site";
import { Providers } from "./providers";

const fontDisplay = Syne({
  variable: "--font-display",
  subsets: ["latin"],
  weight: ["400", "600", "700", "800"],
});

const fontBody = Space_Grotesk({
  variable: "--font-body",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const fontMono = IBM_Plex_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const GA_ID = "G-9M7WPLB8BR";

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": `${siteOrigin}/#organization`,
        name: "Caldis",
        url: `${siteOrigin}/`,
        email: "mail@caldis.me",
        foundingDate: "2017",
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
      {
        "@type": "WebSite",
        "@id": `${siteOrigin}/#website`,
        url: `${siteOrigin}/`,
        name: SITE_NAME,
        description: SITE_DESCRIPTION,
        inLanguage: "en",
        potentialAction: {
          "@type": "ReadAction",
          target: [
            `${siteOrigin}/index.md`,
            `${siteOrigin}/llms.txt`,
            `${siteOrigin}/llms-full.txt`,
            `${siteOrigin}/developers/`,
            `${siteOrigin}/api-docs/`,
            `${siteOrigin}/auth/`,
            `${siteOrigin}/webhooks/`,
            `${siteOrigin}/mcp/`,
          ],
        },
        publisher: {
          "@id": `${siteOrigin}/#organization`,
        },
      },
      {
        "@type": "WebPage",
        "@id": `${siteOrigin}/#webpage`,
        url: `${siteOrigin}/`,
        name: SITE_TITLE,
        description: SITE_DESCRIPTION,
        isPartOf: {
          "@id": `${siteOrigin}/#website`,
        },
        about: {
          "@id": `${siteOrigin}/#software`,
        },
        speakable: {
          "@type": "SpeakableSpecification",
          cssSelector: ["main h1", "main section h2", "main section p"],
        },
      },
      {
        "@type": "SoftwareApplication",
        "@id": `${siteOrigin}/#software`,
        name: SITE_NAME,
        url: `${siteOrigin}/`,
        operatingSystem: "macOS",
        applicationCategory: "UtilitiesApplication",
        description: SITE_DESCRIPTION,
        downloadUrl: "https://github.com/Caldis/Mos/releases/latest",
        softwareHelp: "https://github.com/Caldis/Mos/wiki",
        sameAs: [
          "https://github.com/Caldis/Mos",
          "https://www.producthunt.com/products/mos",
          "https://alternativeto.net/software/caldis-mos/",
          `${siteOrigin}/developers/`,
          `${siteOrigin}/.well-known/agent.json`,
        ],
        publisher: {
          "@id": `${siteOrigin}/#organization`,
        },
        license: "https://creativecommons.org/licenses/by-nc/4.0/",
        offers: {
          "@type": "Offer",
          price: "0",
          priceCurrency: "USD",
        },
      },
      {
        "@type": "Service",
        "@id": `${siteOrigin}/#static-discovery-service`,
        name: "Mos public documentation and discovery resources",
        serviceType: "Static documentation and agent discovery endpoints",
        provider: {
          "@id": `${siteOrigin}/#organization`,
        },
        areaServed: "Worldwide",
        audience: {
          "@type": "Audience",
          audienceType: "AI agents, search crawlers, and developers",
        },
        description:
          "Static public resources for understanding Mos. This service does not provide remote control over local Mos settings, OAuth access, webhooks, or a hosted MCP tool server.",
        url: `${siteOrigin}/developers/`,
      },
      {
        "@type": "FAQPage",
        "@id": `${siteOrigin}/#faq`,
        mainEntity: [
          {
            "@type": "Question",
            name: "What is Mos?",
            acceptedAnswer: {
              "@type": "Answer",
              text: "Mos is a local macOS menu bar utility that smooths mouse wheel scrolling and supports per-app profiles, axis settings, and mouse button bindings.",
            },
          },
          {
            "@type": "Question",
            name: "Does Mos provide a public API or MCP server?",
            acceptedAnswer: {
              "@type": "Answer",
              text: "No. Mos publishes static discovery and documentation files, but it does not provide a hosted API, OAuth service, webhook service, or public MCP tool server.",
            },
          },
        ],
      },
      {
        "@type": "BreadcrumbList",
        "@id": `${siteOrigin}/#breadcrumb`,
        itemListElement: [
          {
            "@type": "ListItem",
            position: 1,
            name: "Home",
            item: `${siteOrigin}/`,
          },
        ],
      },
    ],
  };

  return (
    <html lang="en" className="js">
      <head>
        <link rel="sitemap" type="application/xml" href="/sitemap.xml" />
        <link rel="alternate" type="text/markdown" href="/index.md" title="Mos markdown homepage" />
        <link rel="alternate" type="text/plain" href="/llms.txt" title="Mos llms.txt" />
        <link rel="alternate" type="text/plain" href="/llms-full.txt" title="Mos full LLM context" />
        <link rel="help" href="/developers/" title="Mos developer resources" />
        <link rel="help" href="/api-docs/" title="Mos API docs" />
        <link rel="help" href="/auth/" title="Mos auth docs" />
        <link rel="help" href="/webhooks/" title="Mos webhooks status" />
        <link rel="help" href="/mcp/" title="Mos MCP status" />
        <link rel="alternate" type="text/markdown" href="/api-docs.md" title="Mos API docs markdown" />
        <link rel="alternate" type="text/markdown" href="/auth.md" title="Mos auth docs markdown" />
        <link rel="alternate" type="text/markdown" href="/webhooks.md" title="Mos webhooks markdown" />
        <link rel="alternate" type="text/markdown" href="/mcp.md" title="Mos MCP status markdown" />
        <link rel="alternate" type="application/json" href="/.well-known/agent.json" title="Mos agent discovery file" />
        <link rel="alternate" type="application/json" href="/.well-known/agent-card.json" title="Mos A2A agent card" />
        <link rel="alternate" type="application/linkset+json" href="/.well-known/api-catalog" title="Mos API catalog" />
        <link rel="alternate" type="application/json" href="/.well-known/oauth-protected-resource" title="Mos zero-auth protected resource metadata" />
        <link rel="service-desc" type="application/openapi+json" href="/api/openapi.json" title="Mos OpenAPI service description" />
        <script
          type="application/ld+json"
          // JSON-LD should be static, machine-readable, and identical for bots & users.
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        <noscript>
          <style>{`html.js .reveal{opacity:1!important;transform:none!important;filter:none!important}`}</style>
        </noscript>
      </head>
      <body className={`${fontDisplay.variable} ${fontBody.variable} ${fontMono.variable} antialiased`}>
        <Providers>{children}</Providers>
        <Script
          src={`https://www.googletagmanager.com/gtag/js?id=${GA_ID}`}
          strategy="afterInteractive"
        />
        <Script id="ga4" strategy="afterInteractive">
          {`
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', '${GA_ID}');
          `}
        </Script>
      </body>
    </html>
  );
}
