import Script from "next/script";
import { IBM_Plex_Mono, Space_Grotesk, Syne } from "next/font/google";
import "./globals.css";
import { SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "./site";
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
          ],
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
          `${siteOrigin}/developers/`,
          `${siteOrigin}/.well-known/agent.json`,
        ],
        license: "https://creativecommons.org/licenses/by-nc/4.0/",
        offers: {
          "@type": "Offer",
          price: "0",
          priceCurrency: "USD",
        },
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
        <link rel="alternate" type="application/json" href="/.well-known/agent.json" title="Mos agent discovery file" />
        <link rel="alternate" type="application/json" href="/.well-known/agent-card.json" title="Mos A2A agent card" />
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
