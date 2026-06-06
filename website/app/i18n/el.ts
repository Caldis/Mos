import type { Translations } from "./context";

export const el: Translations = {
  donate: {
    trigger: "Υποστήριξε το Mos",
    footerLink: "Δωρεά",
    title: "Υποστήριξε το Mos",
    intro: "Το Mos είναι δωρεάν και ανοιχτού κώδικα — και θα παραμείνει. Μια μικρή δωρεά είναι εντελώς προαιρετική, αλλά θα με χαροποιούσε ιδιαίτερα.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "Ηπειρωτική Κίνα",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "Άνοιξε το {app} και σάρωσε",
    meowWall: "Θες να δεις μερικές γατο-φωτογραφίες;",
  },
  languageSelector: {
    title: "Επιλογή γλώσσας",
  },
  a11y: {
    skipToContent: "Μετάβαση στο περιεχόμενο",
    closeDialog: "Κλείσιμο διαλόγου",
    githubAria: "Mos στο GitHub",
    appIconAlt: "Εικονίδιο εφαρμογής Mos",
    appProfileIconAlt: "Εικονίδιο {app} για προφίλ κύλισης Mos ανά εφαρμογή",
    scrollCurveGraph: "Γράφημα καμπύλης κύλισης",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "Ομαλό scrolling με ροδέλα ποντικιού στο macOS",
    badgeLine2: "προφίλ ανά εφαρμογή · ανεξάρτητοι άξονες · κουμπιά & shortcuts",
    titleLine1: "Κάνε το ποντίκι",
    titleLine2Before: "να ",
    titleLine2Highlight: "ρέει",
    titleLine2After: ".",
    lead:
      "Το Mos είναι ένα δωρεάν, open-source εργαλείο για macOS. Κάνει το scrolling με ροδέλα να θυμίζει trackpad, χωρίς να χάνεις τον έλεγχο. Ρύθμισε καμπύλες, χώρισε άξονες και βάλε εξαιρέσεις ανά εφαρμογή.",
    ctaDownload: "Λήψη Mos",
    ctaViewGitHub: "Δες το στο GitHub",
    ctaInstallHomebrew: "Εγκατάσταση με Homebrew",
    requirementsLine1: "Απαιτεί macOS 10.13+",
    requirementsLine2: "Δωρεάν · Open source",
    scrollHint: "Κάνε scroll για συνέχεια",
  },
  sectionFeel: {
    title: "Προβλέψιμο scrolling. Ρυθμιζόμενη αίσθηση.",
    lead:
      "Το Mos μετατρέπει τις ωμές μεταβολές της ροδέλας σε προβλέψιμη κίνηση. Κράτα την ίδια αίσθηση σε όλες τις εφαρμογές και κάνε override όπου χρειάζεται.",
    cards: {
      curves: {
        kicker: "Καμπύλες & επιτάχυνση",
        title: "Διαμόρφωσε την αίσθηση.",
        body:
          "Η ομαλότητα είναι καμπύλη. Ρύθμισε step, gain και duration και δες πώς οι ωμές μεταβολές γίνονται ελεγχόμενη κίνηση.",
      },
      axes: {
        kicker: "Ανεξάρτητοι άξονες",
        title: "Χώρισε X και Y.",
        body:
          "Κάνε την κάθετη και την οριζόντια κύλιση ξεχωριστούς άξονες. Ενεργοποίησε/απενεργοποίησε την ομαλότητα και την αντιστροφή ανεξάρτητα για τον καθένα.",
        smooth: "Ομαλότητα",
        reverse: "Αντιστροφή",
        on: "ON",
        off: "OFF",
      },
      perApp: {
        kicker: "Προφίλ ανά εφαρμογή",
        title: "Άλλες εφαρμογές, άλλη αίσθηση.",
        body:
          "Άφησε κάθε εφαρμογή να κληρονομεί τα default ή κάνε override κανόνες κύλισης και κουμπιών. Ακρίβεια όπου χρειάζεται, ομαλότητα παντού αλλού.",
      },
      buttons: {
        kicker: "Κουμπιά & shortcuts",
        title: "Δέσε, γράψε, επανάλαβε.",
        body:
          "Κατέγραψε events από ποντίκι ή πληκτρολόγιο και δέσε τα σε system shortcuts. Με το live monitor βλέπεις τι στέλνουν οι συσκευές σου.",
        quickBind: "Γρήγορη δέσμευση",
        rows: {
          button4: "Κουμπί 4",
          button5: "Κουμπί 5",
          wheelClick: "Κλικ ροδέλας",
          missionControl: "Mission Control",
          nextSpace: "Επόμενος χώρος",
          appSwitcher: "Εναλλαγή εφαρμογών",
        },
      },
    },
  },
  download: {
    title: "Λήψη Mos. Ρύθμισε το scrolling σου.",
    body:
      "Εγκατάσταση σε δευτερόλεπτα, ρύθμιση με τον ρυθμό σου, και σταθερή συμπεριφορά κύλισης στις εφαρμογές που χρησιμοποιείς καθημερινά.",
    ctaDownload: "Λήψη",
    releaseNotes: "Σημειώσεις έκδοσης",
    docs: "Οδηγίες",
  },
  homebrew: {
    title: "Homebrew",
    copy: "Αντιγραφή",
    copied: "Αντιγράφηκε",
    tip: "Συμβουλή: αν είσαι σε beta, το cask μπορεί να είναι {cask}.",
  },
  footer: {
    latestRelease: "Τελευταία έκδοση",
    latestVersion: "Τελευταίο {version}",
    requiresMacos: "Απαιτεί macOS 10.13+",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "Γράφημα καμπύλης κύλισης",
    step: {
      label: "Βήμα",
      aria: "Βήμα",
      help: "Κατώφλι κβαντοποίησης για τις μεταβολές της ροδέλας.",
    },
    gain: {
      label: "Κέρδος",
      aria: "Κέρδος",
      help: "Κλιμακώνει την απόσταση ανά tick και το πόσο γρήγορα ανεβαίνει η καμπύλη.",
    },
    duration: {
      label: "Διάρκεια",
      aria: "Διάρκεια",
      help: "Χρονική σταθερά εξομάλυνσης (μεγαλύτερη = μεγαλύτερη ουρά).",
    },
    footer: "Καμπύλη ScrollCore",
  },
  wall: {
    back: "Mos",
    title: "Ο Τοίχος",
    tagline: "άφησε ένα post-it",
    empty: "γίνε ο πρώτος που αφήνει σημείωμα",
    trayHint: "Σύρε ένα post-it στον τοίχο",
    trayDragAria: "Σύρε ένα {color} post-it στον τοίχο",
    bodyPlaceholder: "Γράψε κάτι…",
    namePlaceholder: "Το όνομά σου (προαιρετικό)",
    colorAria: "χρώμα {color}",
    cancel: "Ακύρωση",
    submit: "Κόλλα το ↗",
    submitting: "Κολλάει…",
    anonymous: "ανώνυμος",
    delete: "Διαγραφή σημειώματος",
    deleteConfirm: "Διαγραφή;",
    verifyHint: "Γρήγορος έλεγχος ότι είσαι άνθρωπος…",
    errorGeneric: "Δεν ήταν δυνατή η ανάρτηση. Παρακαλώ δοκίμασε ξανά.",
    errorRate: "Ανεβάζεις πολύ γρήγορα — δοκίμασε ξανά σε ένα λεπτό.",
    errorTurnstile: "Παρακαλώ ολοκλήρωσε την επαλήθευση και δοκίμασε ξανά.",
    errorLinks: "Πάρα πολλά links στο σημείωμά σου.",
  },
};
