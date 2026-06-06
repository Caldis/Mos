import type { Translations } from "./context";

export const zhHant: Translations = {
  donate: {
    trigger: "支持 Mos",
    footerLink: "贊賞",
    title: "支持 Mos",
    intro: "Mos 一直都是免費且開源的,以後也會如此。贊賞完全出於自願,但若有的話,我會非常開心。",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "中國大陸",
    alipay: "支付寶",
    wechat: "微信支付",
    scanHint: "開啟{app}掃一掃",
    meowWall: "想看點貓片嗎?",
  },
  languageSelector: {
    title: "選擇語言",
  },
  a11y: {
    skipToContent: "跳到內容",
    closeDialog: "關閉對話框",
    githubAria: "Mos 的 GitHub",
    appIconAlt: "Mos 應用程式圖示",
    appProfileIconAlt: "{app} 應用程式圖示，用於展示 Mos 按 App 捲動設定",
    scrollCurveGraph: "捲動曲線圖",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "讓 macOS 上的滑鼠滾輪捲動更順",
    badgeLine2: "按 App 設定 · X/Y 軸獨立 · 按鍵與快捷鍵",
    titleLine1: "讓滑鼠",
    titleLine2Before: "變得",
    titleLine2Highlight: "順滑",
    titleLine2After: "。",
    lead:
      "Mos 是一個免費、開源的 macOS 小工具，讓滾輪捲動更接近觸控板手感，同時不影響你的控制。你可以調曲線、分離 X/Y，也能針對不同 App 覆寫行為。",
    ctaDownload: "下載 Mos",
    ctaViewGitHub: "在 GitHub 查看",
    ctaInstallHomebrew: "透過 Homebrew 安裝",
    requirementsLine1: "需要 macOS 10.13+",
    requirementsLine2: "免費 · 開源",
    scrollHint: "往下滑看看",
  },
  sectionFeel: {
    title: "捲動更可控。手感可調。",
    lead:
      "Mos 會把原始滾輪增量變成更可預測的動作。不同 App 也能維持同樣的手感，需要時再按應用覆寫。",
    cards: {
      curves: {
        kicker: "曲線與加速",
        title: "調出你喜歡的手感。",
        body:
          "順滑其實是一條曲線。調整步進、增益與時長，看看原始滾輪增量如何變成更可控的捲動。",
      },
      axes: {
        kicker: "軸向獨立",
        title: "X 與 Y 分開調。",
        body:
          "把垂直/水平當成兩條獨立的軸：平滑與反向都可以按軸單獨開關。",
        smooth: "平滑",
        reverse: "反向",
        on: "開",
        off: "關",
      },
      perApp: {
        kicker: "按 App 設定",
        title: "不同 App，不同規則。",
        body:
          "每個 App 可以繼承預設值，也可以單獨覆寫捲動與按鍵規則。需要精準就精準，其餘保持順滑。",
      },
      buttons: {
        kicker: "按鍵與快捷鍵",
        title: "綁定、記錄、重複。",
        body:
          "把滑鼠或鍵盤事件錄下來，綁定到系統快捷鍵。也能用即時監視器看看裝置到底送了什麼。",
        quickBind: "快速綁定",
        rows: {
          button4: "按鍵 4",
          button5: "按鍵 5",
          wheelClick: "滾輪按下",
          missionControl: "控制中心",
          nextSpace: "下一個空間",
          appSwitcher: "App 切換器",
        },
      },
    },
  },
  download: {
    title: "下載 Mos。按你的習慣調。",
    body: "幾秒就能裝好，需要時再慢慢調參數，讓常用 App 裡的捲動手感保持一致。",
    ctaDownload: "下載",
    releaseNotes: "更新紀錄",
    docs: "文件",
  },
  homebrew: {
    title: "Homebrew",
    copy: "複製",
    copied: "已複製",
    tip: "提示：如果你在用 beta 版，cask 可能是 {cask}。",
  },
  footer: {
    latestRelease: "最新發佈",
    latestVersion: "最新 {version}",
    requiresMacos: "需要 macOS 10.13+",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "捲動曲線圖",
    step: {
      label: "步進",
      aria: "步進",
      help: "滾輪增量的量化下限。",
    },
    gain: {
      label: "增益",
      aria: "增益",
      help: "決定每次捲動的距離，以及曲線爬升的速度。",
    },
    duration: {
      label: "時長",
      aria: "時長",
      help: "平滑時間常數（越大尾巴越長）。",
    },
    footer: "ScrollCore 曲線",
  },
  wall: {
    back: "Mos",
    title: "留言牆",
    tagline: "貼張便條紙",
    empty: "來當第一個留言的人吧",
    trayHint: "把便條紙拖到牆上",
    trayDragAria: "將{color}便條紙拖到牆上",
    bodyPlaceholder: "寫點什麼…",
    namePlaceholder: "你的名字（選填）",
    colorAria: "{color}色",
    cancel: "取消",
    submit: "貼上去 ↗",
    submitting: "貼中…",
    anonymous: "匿名",
    delete: "刪除便條",
    deleteConfirm: "刪除?",
    verifyHint: "先確認一下你是真人…",
    errorGeneric: "便條紙沒有發出去，請再試一次。",
    errorRate: "發得有點快——稍等一分鐘再試。",
    errorTurnstile: "請完成驗證後再試。",
    errorLinks: "便條紙裡連結太多了。",
  },
};
