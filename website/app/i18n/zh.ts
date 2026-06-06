import type { Translations } from "./context";

export const zh: Translations = {
  donate: {
    trigger: "支持 Mos",
    footerLink: "打赏",
    title: "支持 Mos",
    intro: "Mos 一直是免费且开源的,以后也会如此。打赏完全出于自愿,但如果有,我会非常开心。",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "中国大陆",
    alipay: "支付宝",
    wechat: "微信",
    scanHint: "打开{app}扫一扫",
    meowWall: "想看点猫片吗?",
  },
  languageSelector: {
    title: "选择语言",
  },
  a11y: {
    skipToContent: "跳到正文",
    closeDialog: "关闭对话框",
    githubAria: "Mos 的 GitHub",
    appIconAlt: "Mos 应用图标",
    appProfileIconAlt: "{app} 应用图标，用于展示 Mos 按应用滚动配置",
    scrollCurveGraph: "滚动曲线图",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "让 macOS 上的鼠标滚轮滚动更顺滑",
    badgeLine2: "按应用配置 · 横纵轴独立 · 按键与快捷键",
    titleLine1: "让鼠标",
    titleLine2Before: "变得",
    titleLine2Highlight: "顺滑",
    titleLine2After: "。",
    lead:
      "Mos 是一个免费的开源 macOS 小工具，让滚轮滚动更接近触控板的手感，同时不影响你的控制。你可以调曲线、分离横纵轴，也可以按 App 覆盖行为。",
    ctaDownload: "下载 Mos",
    ctaViewGitHub: "在 GitHub 查看",
    ctaInstallHomebrew: "通过 Homebrew 安装",
    requirementsLine1: "需要 macOS 10.13+",
    requirementsLine2: "免费 · 开源",
    scrollHint: "向下滚动了解更多",
  },
  sectionFeel: {
    title: "滚动更可控。手感可调。",
    lead:
      "Mos 会把原始滚轮增量变成更可预测的运动。不同 App 也能保持同样的手感，需要时再按应用覆盖。",
    cards: {
      curves: {
        kicker: "曲线与加速",
        title: "调出你喜欢的手感。",
        body:
          "顺滑其实是一条曲线。调整步进、增益和时长，看看原始滚轮增量如何变成更可控的滚动。",
      },
      axes: {
        kicker: "轴向独立",
        title: "横纵轴分开调。",
        body:
          "把垂直/水平当成两条独立的轴：平滑与反向都可以按轴单独开关。",
        smooth: "平滑",
        reverse: "反向",
        on: "开",
        off: "关",
      },
      perApp: {
        kicker: "按应用配置",
        title: "不同 App，不同规则。",
        body:
          "每个 App 可以继承默认值，也可以单独覆盖滚动和按键规则。需要精准就精准，其他地方保持顺滑。",
      },
      buttons: {
        kicker: "按键与快捷键",
        title: "绑定、记录、重复。",
        body:
          "把鼠标或键盘事件录下来，绑定到系统快捷键。也可以用实时监视器看看设备到底发了什么。",
        quickBind: "快速绑定",
        rows: {
          button4: "按键 4",
          button5: "按键 5",
          wheelClick: "滚轮按下",
          missionControl: "调度中心",
          nextSpace: "下一个空间",
          appSwitcher: "应用切换器",
        },
      },
    },
  },
  download: {
    title: "下载 Mos。按你的习惯调。",
    body: "几秒就能装好，需要时再慢慢调参数，让常用 App 里滚动手感保持一致。",
    ctaDownload: "下载",
    releaseNotes: "更新日志",
    docs: "文档",
  },
  homebrew: {
    title: "Homebrew",
    copy: "复制",
    copied: "已复制",
    tip: "提示：如果你在用 beta 版，cask 可能是 {cask}。",
  },
  footer: {
    latestRelease: "最新发布",
    latestVersion: "最新 {version}",
    requiresMacos: "需要 macOS 10.13+",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "滚动曲线图",
    step: {
      label: "步进",
      aria: "步进",
      help: "滚轮增量的量化下限。",
    },
    gain: {
      label: "增益",
      aria: "增益",
      help: "决定每次滚动的距离，以及曲线爬升的速度。",
    },
    duration: {
      label: "时长",
      aria: "时长",
      help: "平滑时间常数（越大尾巴越长）。",
    },
    footer: "ScrollCore 曲线",
  },
  wall: {
    back: "Mos",
    title: "留言墙",
    tagline: "贴张便利贴",
    empty: "来当第一个留言的人吧",
    trayHint: "把便利贴拖到墙上",
    trayDragAria: "将{color}便利贴拖到墙上",
    bodyPlaceholder: "写点什么…",
    namePlaceholder: "你的名字（可选）",
    colorAria: "{color}色",
    cancel: "取消",
    submit: "贴上去 ↗",
    submitting: "贴中…",
    anonymous: "匿名",
    verifyHint: "先确认一下你是人类…",
    errorGeneric: "便利贴没发出去，再试一次吧。",
    errorRate: "发得有点快——过一分钟再试。",
    errorTurnstile: "请完成验证后再试。",
    errorLinks: "便利贴里链接太多啦。",
  },
};
