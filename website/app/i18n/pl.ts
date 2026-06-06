import type { Translations } from "./context";

export const pl: Translations = {
  donate: {
    trigger: "Wesprzyj Mos",
    footerLink: "Wesprzyj",
    title: "Wesprzyj Mos",
    intro: "Mos jest darmowy i open source — i taki pozostanie. Napiwek jest całkowicie dobrowolny, ale bardzo mnie ucieszy.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "Chiny kontynentalne",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "Otwórz {app} i zeskanuj",
    meowWall: "Chcesz zobaczyć kocie fotki?",
  },
  languageSelector: {
    title: "Wybierz język",
  },
  a11y: {
    skipToContent: "Przejdź do treści",
    closeDialog: "Zamknij okno dialogowe",
    githubAria: "Mos na GitHubie",
    appIconAlt: "Ikona aplikacji Mos",
    appProfileIconAlt: "Ikona aplikacji {app} dla profilu przewijania Mos",
    scrollCurveGraph: "Wykres krzywej przewijania",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "Płynne przewijanie kółkiem myszy w macOS",
    badgeLine2: "profile per aplikacja · niezależne osie · przyciski i skróty",
    titleLine1: "Zamień mysz",
    titleLine2Before: "w ",
    titleLine2Highlight: "flow",
    titleLine2After: ".",
    lead:
      "Mos to darmowe, otwartoźródłowe narzędzie dla macOS. Sprawia, że przewijanie kółkiem jest bliższe wrażeniu z trackpada, bez odbierania kontroli. Dostosuj krzywe, rozdziel osie i nadpisuj zachowanie dla poszczególnych aplikacji.",
    ctaDownload: "Pobierz Mos",
    ctaViewGitHub: "Zobacz na GitHubie",
    ctaInstallHomebrew: "Zainstaluj przez Homebrew",
    requirementsLine1: "Wymaga macOS 10.13+",
    requirementsLine2: "Darmowe · Open source",
    scrollHint: "Przewiń, aby zobaczyć więcej",
  },
  sectionFeel: {
    title: "Przewidywalne przewijanie. Odczucie do ustawienia.",
    lead:
      "Mos zamienia surowe delty kółka w przewidywalny ruch. Zachowaj to samo odczucie w aplikacjach i nadpisuj je tylko tam, gdzie trzeba.",
    cards: {
      curves: {
        kicker: "Krzywe i przyspieszenie",
        title: "Ułóż odczucie.",
        body:
          "Płynność to krzywa. Zmieniaj Step, Gain i Duration i zobacz, jak surowe delty stają się kontrolowanym ruchem.",
      },
      axes: {
        kicker: "Niezależne osie",
        title: "Rozdziel X i Y.",
        body:
          "Pion i poziom to niezależne osie. Wygładzanie i odwrócenie możesz włączać osobno dla każdej z nich.",
        smooth: "Wygładzanie",
        reverse: "Odwróć",
        on: "Wł.",
        off: "Wył.",
      },
      perApp: {
        kicker: "Profile per aplikacja",
        title: "Inne aplikacje, inne odczucie.",
        body:
          "Każda aplikacja może dziedziczyć ustawienia domyślne albo nadpisywać reguły przewijania i przycisków. Precyzja tam, gdzie trzeba, płynność wszędzie indziej.",
      },
      buttons: {
        kicker: "Przyciski i skróty",
        title: "Przypnij, nagraj, powtórz.",
        body:
          "Nagraj zdarzenia myszy lub klawiatury i przypisz je do skrótów systemowych. W monitorze na żywo sprawdzisz, co wysyłają urządzenia.",
        quickBind: "Szybkie przypisanie",
        rows: {
          button4: "Przycisk 4",
          button5: "Przycisk 5",
          wheelClick: "Klik kółka",
          missionControl: "Mission Control",
          nextSpace: "Następna przestrzeń",
          appSwitcher: "Przełącznik aplikacji",
        },
      },
    },
  },
  download: {
    title: "Pobierz Mos. Ustaw przewijanie pod siebie.",
    body:
      "Instalacja w kilka sekund. Dopasuj, kiedy potrzebujesz, i utrzymaj spójne przewijanie w aplikacjach, z których korzystasz na co dzień.",
    ctaDownload: "Pobierz",
    releaseNotes: "Informacje o wydaniu",
    docs: "Dokumentacja",
  },
  homebrew: {
    title: "Homebrew",
    copy: "Kopiuj",
    copied: "Skopiowano",
    tip: "Wskazówka: jeśli używasz bety, twój cask może nazywać się {cask}.",
  },
  footer: {
    latestRelease: "Najnowsze wydanie",
    latestVersion: "Najnowsza {version}",
    requiresMacos: "Wymaga macOS 10.13+",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "Wykres krzywej przewijania",
    step: {
      label: "Krok",
      aria: "Krok",
      help: "Dolny próg kwantyzacji dla delt kółka.",
    },
    gain: {
      label: "Wzmocnienie",
      aria: "Wzmocnienie",
      help: "Skaluje dystans na тик i szybkość narastania krzywej.",
    },
    duration: {
      label: "Czas",
      aria: "Czas",
      help: "Stała czasowa wygładzania (większa = dłuższy ogon).",
    },
    footer: "Krzywa ScrollCore",
  },
  wall: {
    back: "Mos",
    title: "Ściana",
    tagline: "zostaw karteczkę",
    empty: "bądź pierwszą osobą, która zostawi notatkę",
    trayHint: "Przeciągnij karteczkę na ścianę",
    trayDragAria: "Przeciągnij {color} karteczkę na ścianę",
    bodyPlaceholder: "Napisz coś…",
    namePlaceholder: "Twoje imię (opcjonalnie)",
    colorAria: "kolor {color}",
    cancel: "Anuluj",
    submit: "Przyklej ↗",
    submitting: "Przyklejam…",
    anonymous: "anonim",
    delete: "Usuń karteczkę",
    verifyHint: "Chwila — sprawdzamy, czy jesteś człowiekiem…",
    errorGeneric: "Nie udało się opublikować notatki. Spróbuj ponownie.",
    errorRate: "Publikujesz zbyt szybko — spróbuj za minutę.",
    errorTurnstile: "Proszę ukończyć weryfikację i spróbować ponownie.",
    errorLinks: "W notatce jest zbyt wiele linków.",
  },
};
