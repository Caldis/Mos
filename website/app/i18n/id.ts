import type { Translations } from "./context";

export const id: Translations = {
  donate: {
    trigger: "Dukung Mos",
    footerLink: "Donasi",
    title: "Dukung Mos",
    intro: "Mos gratis dan open source — dan akan selalu begitu. Sedikit donasi sepenuhnya opsional, tetapi sangat menyenangkan hati saya.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "Tiongkok Daratan",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "Buka {app} lalu pindai",
    meowWall: "Mau lihat foto-foto kucing?",
  },
  languageSelector: {
    title: "Pilih Bahasa",
  },
  a11y: {
    skipToContent: "Lewati ke konten",
    closeDialog: "Tutup dialog",
    githubAria: "Mos di GitHub",
    appIconAlt: "Ikon aplikasi Mos",
    appProfileIconAlt: "Ikon aplikasi {app} untuk profil scroll per aplikasi Mos",
    scrollCurveGraph: "Grafik kurva scroll",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "Scroll halus untuk roda mouse di macOS",
    badgeLine2: "profil per aplikasi · sumbu terpisah · tombol & pintasan",
    titleLine1: "Ubah mouse",
    titleLine2Before: "menjadi ",
    titleLine2Highlight: "flow",
    titleLine2After: ".",
    lead:
      "Mos adalah utilitas macOS gratis dan open-source yang membuat scroll roda mouse terasa lebih seperti trackpad, tanpa mengurangi kontrol. Atur kurva, pisahkan sumbu, dan override perilaku per aplikasi.",
    ctaDownload: "Unduh Mos",
    ctaViewGitHub: "Lihat di GitHub",
    ctaInstallHomebrew: "Instal via Homebrew",
    requirementsLine1: "Butuh macOS 10.13+",
    requirementsLine2: "Gratis · Open source",
    scrollHint: "Scroll untuk melihat",
  },
  sectionFeel: {
    title: "Scroll yang konsisten. Rasa yang bisa diatur.",
    lead:
      "Mos mengubah delta roda mentah menjadi gerakan yang bisa diprediksi. Pertahankan rasa yang sama di berbagai aplikasi, dan override saat perlu.",
    cards: {
      curves: {
        kicker: "Kurva & akselerasi",
        title: "Bentuk rasanya.",
        body:
          "Kehalusan adalah kurva. Ubah step, gain, dan duration, lalu lihat bagaimana delta mentah menjadi gerakan yang terkontrol.",
      },
      axes: {
        kicker: "Sumbu terpisah",
        title: "Pisahkan X dan Y.",
        body:
          "Anggap scroll vertikal dan horizontal sebagai dua sumbu terpisah. Kehalusan dan reverse bisa dinyalakan/dimatikan secara independen untuk tiap sumbu.",
        smooth: "Kehalusan",
        reverse: "Reverse",
        on: "Nyala",
        off: "Mati",
      },
      perApp: {
        kicker: "Profil per aplikasi",
        title: "Aplikasi berbeda, rasa berbeda.",
        body:
          "Setiap aplikasi bisa memakai default atau meng-override aturan scroll dan tombol. Presisi saat dibutuhkan, halus di tempat lain.",
      },
      buttons: {
        kicker: "Tombol & pintasan",
        title: "Ikat, rekam, ulangi.",
        body:
          "Rekam event mouse atau keyboard lalu ikat ke pintasan sistem. Dengan live monitor kamu bisa melihat apa yang dikirim perangkatmu.",
        quickBind: "Quick Bind",
        rows: {
          button4: "Button 4",
          button5: "Button 5",
          wheelClick: "Wheel Click",
          missionControl: "Mission Control",
          nextSpace: "Next Space",
          appSwitcher: "App Switcher",
        },
      },
    },
  },
  download: {
    title: "Unduh Mos. Atur scroll sesuai kamu.",
    body:
      "Instal dalam hitungan detik, atur saat perlu, dan jaga perilaku scroll tetap konsisten di aplikasi yang kamu pakai setiap hari.",
    ctaDownload: "Unduh",
    releaseNotes: "Catatan rilis",
    docs: "Dokumentasi",
  },
  homebrew: {
    title: "Homebrew",
    copy: "Salin",
    copied: "Disalin",
    tip: "Tips: jika kamu memakai beta, cask-nya mungkin {cask}.",
  },
  footer: {
    latestRelease: "Rilis terbaru",
    latestVersion: "Terbaru {version}",
    requiresMacos: "Butuh macOS 10.13+",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "Grafik kurva scroll",
    step: {
      label: "Step",
      aria: "Step",
      help: "Batas kuantisasi untuk delta roda.",
    },
    gain: {
      label: "Gain",
      aria: "Gain",
      help: "Mengalikan jarak per tick dan seberapa cepat kurva naik.",
    },
    duration: {
      label: "Duration",
      aria: "Duration",
      help: "Konstanta waktu smoothing (lebih besar = tail lebih panjang).",
    },
    footer: "ScrollCore curve",
  },
};
