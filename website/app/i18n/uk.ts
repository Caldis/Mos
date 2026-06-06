import type { Translations } from "./context";

export const uk: Translations = {
  donate: {
    trigger: "Підтримати Mos",
    footerLink: "Підтримати",
    title: "Підтримати Mos",
    intro: "Mos безкоштовний і з відкритим кодом — і таким залишиться. Невеликий внесок цілком необов'язковий, але дуже мене потішить.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "Материковий Китай",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "Відкрийте {app} і відскануйте",
    meowWall: "Хочеш подивитися котячі фото?",
  },
  languageSelector: {
    title: "Вибір мови",
  },
  a11y: {
    skipToContent: "Перейти до вмісту",
    closeDialog: "Закрити діалог",
    githubAria: "Mos на GitHub",
    appIconAlt: "Іконка Mos",
    appProfileIconAlt: "Іконка {app} для профілю прокручування Mos для застосунку",
    scrollCurveGraph: "Графік кривої прокручування",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "Плавне прокручування коліщатком миші в macOS",
    badgeLine2: "профілі для програм · незалежні осі · кнопки й скорочення",
    titleLine1: "Перетвори мишу",
    titleLine2Before: "на ",
    titleLine2Highlight: "flow",
    titleLine2After: ".",
    lead:
      "Mos — безкоштовна утиліта з відкритим кодом для macOS. Вона робить прокручування коліщатком ближчим до відчуття трекпада, не забираючи контроль. Налаштовуй криві, розділяй осі та перевизначай поведінку для кожного застосунку.",
    ctaDownload: "Завантажити Mos",
    ctaViewGitHub: "Переглянути на GitHub",
    ctaInstallHomebrew: "Встановити через Homebrew",
    requirementsLine1: "Потрібна macOS 10.13+",
    requirementsLine2: "Безкоштовно · Відкритий код",
    scrollHint: "Прокрути вниз",
  },
  sectionFeel: {
    title: "Передбачуване прокручування. Налаштовуване відчуття.",
    lead:
      "Mos перетворює сирі дельти коліщатка на передбачуваний рух. Зберігай однакове відчуття між застосунками і роби override там, де потрібно.",
    cards: {
      curves: {
        kicker: "Криві й прискорення",
        title: "Сформуй відчуття.",
        body:
          "Плавність — це крива. Налаштуй step, gain і duration та подивись, як сирі дельти стають керованим рухом.",
      },
      axes: {
        kicker: "Незалежні осі",
        title: "Розділи X і Y.",
        body:
          "Вертикальне й горизонтальне прокручування — окремі осі. Плавність і реверс можна вмикати та вимикати для кожної осі незалежно.",
        smooth: "Плавність",
        reverse: "Реверс",
        on: "Увімк.",
        off: "Вимк.",
      },
      perApp: {
        kicker: "Профілі для програм",
        title: "Різні застосунки, різне відчуття.",
        body:
          "Нехай кожен застосунок успадковує налаштування за замовчуванням або перевизначуй правила прокручування й кнопок. Точність там, де треба, плавність всюди інде.",
      },
      buttons: {
        kicker: "Кнопки й скорочення",
        title: "Прив’яжи, запиши, повтори.",
        body:
          "Записуй події миші або клавіатури та прив’язуй їх до системних скорочень. У живому моніторі видно, що надсилають твої пристрої.",
        quickBind: "Швидка прив’язка",
        rows: {
          button4: "Кнопка 4",
          button5: "Кнопка 5",
          wheelClick: "Натиск коліщатка",
          missionControl: "Mission Control",
          nextSpace: "Наступний простір",
          appSwitcher: "Перемикач програм",
        },
      },
    },
  },
  download: {
    title: "Завантаж Mos. Налаштуй прокручування під себе.",
    body:
      "Встановлюється за секунди. Налаштовуй, коли потрібно, і тримай однакову поведінку прокручування у своїх застосунках.",
    ctaDownload: "Завантажити",
    releaseNotes: "Нотатки до релізу",
    docs: "Документація",
  },
  homebrew: {
    title: "Homebrew",
    copy: "Копіювати",
    copied: "Скопійовано",
    tip: "Порада: якщо ти на beta, твій cask може бути {cask}.",
  },
  footer: {
    latestRelease: "Останній реліз",
    latestVersion: "Остання {version}",
    requiresMacos: "Потрібна macOS 10.13+",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "Графік кривої прокручування",
    step: {
      label: "Крок",
      aria: "Крок",
      help: "Нижній поріг квантування для дельт коліщатка.",
    },
    gain: {
      label: "Підсилення",
      aria: "Підсилення",
      help: "Масштабує відстань за тик і швидкість наростання кривої.",
    },
    duration: {
      label: "Тривалість",
      aria: "Тривалість",
      help: "Часова константа згладжування (вище = довший хвіст).",
    },
    footer: "Крива ScrollCore",
  },
  wall: {
    back: "Mos",
    title: "Стіна",
    tagline: "залиш стікер",
    empty: "будь першим, хто залишить нотатку",
    trayHint: "Перетягни стікер на стіну",
    trayDragAria: "Перетягни {color} стікер на стіну",
    bodyPlaceholder: "Напиши щось…",
    namePlaceholder: "Твоє ім'я (необов'язково)",
    colorAria: "колір {color}",
    cancel: "Скасувати",
    submit: "Приклеїти ↗",
    submitting: "Клеїмо…",
    anonymous: "анонім",
    verifyHint: "Секунда — перевіримо, що ти людина…",
    errorGeneric: "Не вдалося опублікувати нотатку. Спробуй ще раз.",
    errorRate: "Занадто швидко — спробуй через хвилину.",
    errorTurnstile: "Пройди перевірку і спробуй знову.",
    errorLinks: "У нотатці занадто багато посилань.",
  },
};
