import type { Translations } from "./context";

export const tr: Translations = {
  donate: {
    trigger: "Mos'a destek ol",
    footerLink: "Bağış",
    title: "Mos'a destek ol",
    intro: "Mos ücretsiz ve açık kaynaklıdır — ve öyle kalacak. Küçük bir bağış tamamen isteğe bağlı, ama beni çok mutlu eder.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "Çin Anakarası",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "{app} uygulamasını açıp tarat",
    meowWall: "Biraz kedi fotoğrafı ister misin?",
  },
  languageSelector: {
    title: "Dil seç",
  },
  a11y: {
    skipToContent: "İçeriğe atla",
    closeDialog: "İletişim penceresini kapat",
    githubAria: "GitHub'da Mos",
    appIconAlt: "Mos uygulama simgesi",
    appProfileIconAlt: "Mos uygulama bazlı kaydırma profili için {app} simgesi",
    scrollCurveGraph: "Kaydırma eğrisi grafiği",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "macOS'ta mouse tekeri için akıcı kaydırma",
    badgeLine2: "uygulama profilleri · bağımsız eksenler · tuşlar ve kısayollar",
    titleLine1: "Fareyi",
    titleLine2Before: "",
    titleLine2Highlight: "flow",
    titleLine2After: "'a çevir.",
    lead:
      "Mos, macOS için ücretsiz ve açık kaynak bir araç. Mouse tekeri kaydırmasını trackpad'e daha yakın hissettirir, kontrolü elinden almaz. Eğrileri ayarla, X/Y eksenlerini ayır ve uygulama bazında davranışı geçersiz kıl.",
    ctaDownload: "Mos'u indir",
    ctaViewGitHub: "GitHub'da gör",
    ctaInstallHomebrew: "Homebrew ile yükle",
    requirementsLine1: "macOS 10.13+ gerekir",
    requirementsLine2: "Ücretsiz · Açık kaynak",
    scrollHint: "Keşfetmek için kaydır",
  },
  sectionFeel: {
    title: "Tahmin edilebilir kaydırma. Ayarlanabilir his.",
    lead:
      "Mos, ham teker delta değerlerini öngörülebilir harekete çevirir. Uygulamalar arasında aynı hissi koru, gerektiğinde uygulama bazında geçersiz kıl.",
    cards: {
      curves: {
        kicker: "Eğriler ve hızlanma",
        title: "Hissi şekillendir.",
        body:
          "Akıcılık bir eğridir. Step, Gain ve Duration'ı ayarla; ham delta değerlerinin nasıl kontrollü harekete dönüştüğünü gör.",
      },
      axes: {
        kicker: "Bağımsız eksenler",
        title: "X ve Y'yi ayır.",
        body:
          "Dikey ve yatay kaydırmayı ayrı eksenler olarak düşün. Akıcılığı ve ters çevirmeyi her eksen için ayrı ayrı aç/kapat.",
        smooth: "Akıcılık",
        reverse: "Ters çevir",
        on: "Açık",
        off: "Kapalı",
      },
      perApp: {
        kicker: "Uygulama profilleri",
        title: "Farklı uygulamalar, farklı his.",
        body:
          "Her uygulama varsayılanları devralabilir ya da kaydırma ve tuş kurallarını geçersiz kılabilir. Gerekli yerde hassas, diğer her yerde akıcı.",
      },
      buttons: {
        kicker: "Tuşlar ve kısayollar",
        title: "Bağla, kaydet, tekrar et.",
        body:
          "Mouse veya klavye olaylarını kaydet ve sistem kısayollarına bağla. Canlı monitörle cihazlarının ne gönderdiğini görebilirsin.",
        quickBind: "Hızlı bağla",
        rows: {
          button4: "Tuş 4",
          button5: "Tuş 5",
          wheelClick: "Teker tıklaması",
          missionControl: "Mission Control",
          nextSpace: "Sonraki alan",
          appSwitcher: "Uygulama değiştirici",
        },
      },
    },
  },
  download: {
    title: "Mos'u indir. Kaydırmanı kendine göre ayarla.",
    body:
      "Saniyeler içinde kur. İhtiyacın olduğunda ayarla ve kullandığın uygulamalarda kaydırma davranışını tutarlı tut.",
    ctaDownload: "İndir",
    releaseNotes: "Sürüm notları",
    docs: "Dokümanlar",
  },
  homebrew: {
    title: "Homebrew",
    copy: "Kopyala",
    copied: "Kopyalandı",
    tip: "İpucu: beta kullanıyorsan cask'in {cask} olabilir.",
  },
  footer: {
    latestRelease: "En son sürüm",
    latestVersion: "En son {version}",
    requiresMacos: "macOS 10.13+ gerekir",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "Kaydırma eğrisi grafiği",
    step: {
      label: "Adım",
      aria: "Adım",
      help: "Teker delta değerleri için kuantizasyon eşiği.",
    },
    gain: {
      label: "Kazanç",
      aria: "Kazanç",
      help: "Tick başına mesafeyi ve eğrinin ne kadar hızlı yükseldiğini ölçekler.",
    },
    duration: {
      label: "Süre",
      aria: "Süre",
      help: "Yumuşatma zaman sabiti (daha yüksek = daha uzun kuyruk).",
    },
    footer: "ScrollCore eğrisi",
  },
  wall: {
    back: "Mos",
    title: "Duvar",
    tagline: "bir not bırak",
    empty: "ilk notu bırakan sen ol",
    trayHint: "Bir yapışkanı duvara sürükle",
    trayDragAria: "{color} yapışkanı duvara sürükle",
    bodyPlaceholder: "Bir şeyler yaz…",
    namePlaceholder: "Adın (isteğe bağlı)",
    colorAria: "{color} rengi",
    cancel: "İptal",
    submit: "Yapıştır ↗",
    submitting: "Yapıştırılıyor…",
    anonymous: "anonim",
    delete: "Notu sil",
    verifyHint: "İnsan olduğunu doğrulamak için hızlı bir kontrol…",
    errorGeneric: "Notun gönderilemedi. Lütfen tekrar dene.",
    errorRate: "Çok hızlı gönderiyorsun — bir dakika sonra tekrar dene.",
    errorTurnstile: "Lütfen doğrulamayı tamamla ve tekrar dene.",
    errorLinks: "Notunda çok fazla link var.",
  },
};
