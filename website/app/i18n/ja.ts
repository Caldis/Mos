import type { Translations } from "./context";

export const ja: Translations = {
  donate: {
    trigger: "Mos を応援",
    footerLink: "寄付",
    title: "Mos を応援",
    intro: "Mos は無料・オープンソースで、これからもずっと変わりません。寄付は任意ですが、いただけるととても励みになります。",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "中国本土",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "{app}を開いてスキャン",
    meowWall: "猫の写真、見ていく？",
  },
  languageSelector: {
    title: "言語を選択",
  },
  a11y: {
    skipToContent: "本文へスキップ",
    closeDialog: "ダイアログを閉じる",
    githubAria: "Mos の GitHub",
    appIconAlt: "Mos アプリアイコン",
    appProfileIconAlt: "Mos のアプリ別スクロールプロファイル用 {app} アプリアイコン",
    scrollCurveGraph: "スクロールカーブのグラフ",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "macOS のマウスホイールをスムーズに",
    badgeLine2: "アプリ別プロファイル · 軸の分離 · ボタン/ショートカット",
    titleLine1: "マウスを",
    titleLine2Before: "",
    titleLine2Highlight: "flow",
    titleLine2After: " に変える。",
    lead:
      "Mos は無料・オープンソースの macOS ユーティリティです。ホイールスクロールをトラックパッドに近い感触にしつつ、操作感はそのまま。カーブ調整、X/Y の分離、アプリ別の上書きができます。",
    ctaDownload: "Mos をダウンロード",
    ctaViewGitHub: "GitHub で見る",
    ctaInstallHomebrew: "Homebrew でインストール",
    requirementsLine1: "macOS 10.13 以降",
    requirementsLine2: "無料 · オープンソース",
    scrollHint: "スクロールして見る",
  },
  sectionFeel: {
    title: "狙いどおりにスクロール。手触りは調整できる。",
    lead:
      "Mos は生のホイール入力を予測しやすい動きに変換します。アプリ間で同じ感触を保ち、必要なときだけアプリ別に上書きできます。",
    cards: {
      curves: {
        kicker: "カーブと加速",
        title: "手触りを作る。",
        body:
          "滑らかさはカーブです。Step / Gain / Duration を調整して、生の入力がどう制御された動きになるかを確認できます。",
      },
      axes: {
        kicker: "独立した軸",
        title: "X と Y を分ける。",
        body:
          "縦と横を別々の軸として扱えます。スムーズと反転は、軸ごとにオン/オフできます。",
        smooth: "スムーズ",
        reverse: "反転",
        on: "ON",
        off: "OFF",
      },
      perApp: {
        kicker: "アプリ別プロファイル",
        title: "アプリごとに手触りを。",
        body:
          "基本設定のまま使うことも、アプリごとにスクロールやボタンのルールを上書きすることもできます。必要なところは正確に、他は滑らかに。",
      },
      buttons: {
        kicker: "ボタンとショートカット",
        title: "割り当てて、記録して、繰り返す。",
        body:
          "マウスやキーボードのイベントを記録して、システムのショートカットに割り当てます。ライブモニターで送信内容も確認できます。",
        quickBind: "クイックバインド",
        rows: {
          button4: "ボタン 4",
          button5: "ボタン 5",
          wheelClick: "ホイールクリック",
          missionControl: "Mission Control",
          nextSpace: "次のスペース",
          appSwitcher: "アプリ切り替え",
        },
      },
    },
  },
  download: {
    title: "Mos をダウンロード。スクロールを自分好みに。",
    body:
      "数秒で入れて、必要なときに調整。よく使うアプリでも同じ感触に揃えられます。",
    ctaDownload: "ダウンロード",
    releaseNotes: "リリースノート",
    docs: "ドキュメント",
  },
  homebrew: {
    title: "Homebrew",
    copy: "コピー",
    copied: "コピーしました",
    tip: "ヒント: beta を使っている場合、cask は {cask} かもしれません。",
  },
  footer: {
    latestRelease: "最新リリース",
    latestVersion: "最新 {version}",
    requiresMacos: "macOS 10.13 以降",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "スクロールカーブのグラフ",
    step: {
      label: "Step",
      aria: "Step",
      help: "ホイール入力の量子化の下限。",
    },
    gain: {
      label: "Gain",
      aria: "Gain",
      help: "1 ティックあたりの距離と、立ち上がりの速さを決めます。",
    },
    duration: {
      label: "Duration",
      aria: "Duration",
      help: "平滑化の時間定数（大きいほど尾を引きます）。",
    },
    footer: "ScrollCore curve",
  },
  wall: {
    back: "Mos",
    title: "ウォール",
    tagline: "付箋を貼っていこう",
    empty: "最初の一枚を貼ってみよう",
    trayHint: "付箋をウォールにドラッグ",
    trayDragAria: "{color}の付箋をウォールにドラッグ",
    bodyPlaceholder: "何か書いてみて…",
    namePlaceholder: "名前（任意）",
    colorAria: "{color}色",
    cancel: "キャンセル",
    submit: "貼り付ける ↗",
    submitting: "貼り付け中…",
    anonymous: "匿名",
    delete: "メモを削除",
    verifyHint: "人間確認をさせてください…",
    errorGeneric: "投稿できませんでした。もう一度試してください。",
    errorRate: "投稿が早すぎます — 少し待ってから再試行してください。",
    errorTurnstile: "認証を完了してから再試行してください。",
    errorLinks: "リンクが多すぎます。",
  },
};
