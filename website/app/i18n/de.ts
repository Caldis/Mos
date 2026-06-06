import type { Translations } from "./context";

export const de: Translations = {
  donate: {
    trigger: "Mos unterstützen",
    footerLink: "Spenden",
    title: "Mos unterstützen",
    intro: "Mos ist kostenlos und quelloffen — und bleibt es auch. Ein kleiner Beitrag ist völlig freiwillig, freut mich aber riesig.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "Festlandchina",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "{app} öffnen und scannen",
    meowWall: "Lust auf ein paar Katzenbilder?",
  },
  languageSelector: {
    title: "Sprache auswählen",
  },
  a11y: {
    skipToContent: "Zum Inhalt springen",
    closeDialog: "Dialog schließen",
    githubAria: "Mos auf GitHub",
    appIconAlt: "Mos App-Icon",
    appProfileIconAlt: "{app} App-Icon für ein Mos Scrollprofil pro App",
    scrollCurveGraph: "Scrollkurven-Diagramm",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "Sanftes Scrollen mit dem Mausrad unter macOS",
    badgeLine2: "App-Profile · getrennte Achsen · Buttons & Shortcuts",
    titleLine1: "Mach aus der Maus",
    titleLine2Before: "einen ",
    titleLine2Highlight: "Flow",
    titleLine2After: ".",
    lead:
      "Mos ist ein kostenloses Open-Source-Tool für macOS. Es macht das Scrollen mit dem Mausrad so glatt wie beim Trackpad, ohne dir die Kontrolle zu nehmen. Kurven anpassen, Achsen trennen und Regeln pro App überschreiben.",
    ctaDownload: "Mos herunterladen",
    ctaViewGitHub: "Auf GitHub ansehen",
    ctaInstallHomebrew: "Mit Homebrew installieren",
    requirementsLine1: "macOS 10.13+ erforderlich",
    requirementsLine2: "Kostenlos · Open Source",
    scrollHint: "Scrollen zum Entdecken",
  },
  sectionFeel: {
    title: "Deterministisch scrollen. Gefühl feinjustieren.",
    lead:
      "Mos verwandelt rohe Mausrad-Deltas in vorhersehbare Bewegung. Behalte in allen Apps dasselbe Gefühl und überschreibe es nur dort, wo du es brauchst.",
    cards: {
      curves: {
        kicker: "Kurven & Beschleunigung",
        title: "Das Gefühl formen.",
        body:
          "Smoothness ist eine Kurve. Stell Step, Gain und Duration ein und sieh, wie rohe Deltas in kontrollierte Bewegung werden.",
      },
      axes: {
        kicker: "Unabhängige Achsen",
        title: "X und Y trennen.",
        body:
          "Vertikal und horizontal sind getrennte Achsen. Glätten und Invert kannst du pro Achse an- und ausschalten.",
        smooth: "Glätten",
        reverse: "Invert",
        on: "An",
        off: "Aus",
      },
      perApp: {
        kicker: "Profile pro App",
        title: "Andere Apps, anderes Gefühl.",
        body:
          "Jede App kann die Defaults übernehmen oder Scroll- und Button-Regeln überschreiben. Präzise, wo’s zählt, smooth überall sonst.",
      },
      buttons: {
        kicker: "Buttons & Shortcuts",
        title: "Binden, aufnehmen, wiederholen.",
        body:
          "Maus- oder Tastatur-Events aufnehmen und an System-Shortcuts binden. Im Live-Monitor siehst du, was deine Geräte senden.",
        quickBind: "Schnell binden",
        rows: {
          button4: "Taste 4",
          button5: "Taste 5",
          wheelClick: "Radklick",
          missionControl: "Mission Control",
          nextSpace: "Nächster Bereich",
          appSwitcher: "App-Umschalter",
        },
      },
    },
  },
  download: {
    title: "Mos herunterladen. Scrollen nach deinem Geschmack.",
    body:
      "In Sekunden installiert, in deinem Tempo eingestellt. Und das Scroll-Gefühl bleibt in deinen Apps konsistent.",
    ctaDownload: "Herunterladen",
    releaseNotes: "Release Notes",
    docs: "Doku",
  },
  homebrew: {
    title: "Homebrew",
    copy: "Kopieren",
    copied: "Kopiert",
    tip: "Tipp: Wenn du die Beta nutzt, heißt dein Cask vielleicht {cask}.",
  },
  footer: {
    latestRelease: "Neuester Release",
    latestVersion: "Neueste {version}",
    requiresMacos: "macOS 10.13+ erforderlich",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "Scrollkurven-Diagramm",
    step: {
      label: "Step",
      aria: "Step",
      help: "Quantisierungs-Untergrenze für Mausrad-Deltas.",
    },
    gain: {
      label: "Gain",
      aria: "Gain",
      help: "Skaliert die Strecke pro Tick und wie schnell die Kurve anzieht.",
    },
    duration: {
      label: "Duration",
      aria: "Duration",
      help: "Zeitkonstante fürs Glätten (höher = längerer Nachlauf).",
    },
    footer: "ScrollCore curve",
  },
  wall: {
    back: "Mos",
    title: "The Wall",
    tagline: "hinterlass einen Zettel",
    empty: "sei die erste Person, die eine Notiz hinterlässt",
    trayHint: "Zieh einen Zettel auf die Wand",
    trayDragAria: "Zieh einen {color} Zettel auf die Wand",
    bodyPlaceholder: "Schreib was…",
    namePlaceholder: "Dein Name (optional)",
    colorAria: "Farbe {color}",
    cancel: "Abbrechen",
    submit: "Anpinnen ↗",
    submitting: "Wird gepinnt…",
    anonymous: "anonym",
    verifyHint: "Kurz bestätigen, dass du ein Mensch bist…",
    errorGeneric: "Notiz konnte nicht gepostet werden. Bitte nochmal versuchen.",
    errorRate: "Du postest zu schnell — bitte warte eine Minute.",
    errorTurnstile: "Bitte Überprüfung abschließen und nochmal versuchen.",
    errorLinks: "Zu viele Links in deiner Notiz.",
  },
};
