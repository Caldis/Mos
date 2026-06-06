import type { Translations } from "./context";

export const ko: Translations = {
  donate: {
    trigger: "Mos 후원하기",
    footerLink: "후원",
    title: "Mos 후원하기",
    intro: "Mos는 무료이며 오픈 소스이고, 앞으로도 그렇습니다. 후원은 전적으로 선택이지만, 해주신다면 정말 큰 힘이 됩니다.",
    paypal: "PayPal",
    buyMeACoffee: "Buy Me a Coffee",
    qrLabel: "중국 본토",
    alipay: "Alipay",
    wechat: "WeChat Pay",
    scanHint: "{app} 열고 스캔하기",
    meowWall: "고양이 사진 보고 갈래요?",
  },
  languageSelector: {
    title: "언어 선택",
  },
  a11y: {
    skipToContent: "본문으로 건너뛰기",
    closeDialog: "대화상자 닫기",
    githubAria: "Mos GitHub",
    appIconAlt: "Mos 앱 아이콘",
    appProfileIconAlt: "Mos 앱별 스크롤 프로필용 {app} 앱 아이콘",
    scrollCurveGraph: "스크롤 커브 그래프",
  },
  nav: {
    githubTitle: "GitHub",
  },
  hero: {
    badgeLine1: "macOS에서 마우스 휠 스크롤을 부드럽게",
    badgeLine2: "앱별 프로필 · 축 분리 · 버튼/단축키",
    titleLine1: "마우스를",
    titleLine2Before: "",
    titleLine2Highlight: "flow",
    titleLine2After: "로 바꿉니다.",
    lead:
      "Mos는 무료 오픈소스 macOS 유틸리티입니다. 휠 스크롤을 트랙패드에 가까운 느낌으로 만들면서도, 필요한 제어는 그대로 남겨둡니다. 곡선을 조정하고, X/Y 축을 분리하고, 앱별로 동작을 덮어쓸 수 있어요.",
    ctaDownload: "Mos 다운로드",
    ctaViewGitHub: "GitHub에서 보기",
    ctaInstallHomebrew: "Homebrew로 설치",
    requirementsLine1: "macOS 10.13+ 필요",
    requirementsLine2: "무료 · 오픈 소스",
    scrollHint: "스크롤해서 더 보기",
  },
  sectionFeel: {
    title: "예측 가능한 스크롤. 조절 가능한 감각.",
    lead:
      "Mos는 원시 휠 델타를 예측 가능한 움직임으로 바꿉니다. 앱 전반에 같은 느낌을 유지하고, 필요할 때만 앱별로 덮어쓰세요.",
    cards: {
      curves: {
        kicker: "곡선과 가속",
        title: "느낌을 다듬기.",
        body:
          "부드러움은 곡선입니다. Step, Gain, Duration을 조절하고, 원시 휠 델타가 어떻게 제어된 움직임으로 바뀌는지 확인하세요.",
      },
      axes: {
        kicker: "독립 축",
        title: "X와 Y를 분리.",
        body:
          "세로/가로를 서로 다른 축으로 취급합니다. 스무딩과 반전은 축별로 ON/OFF 할 수 있어요.",
        smooth: "스무딩",
        reverse: "반전",
        on: "ON",
        off: "OFF",
      },
      perApp: {
        kicker: "앱별 프로필",
        title: "앱마다 다른 감각.",
        body:
          "각 앱은 기본값을 그대로 쓰거나, 스크롤/버튼 규칙을 앱별로 덮어쓸 수 있습니다. 필요한 곳은 정확하게, 나머지는 부드럽게.",
      },
      buttons: {
        kicker: "버튼과 단축키",
        title: "바인딩, 기록, 반복.",
        body:
          "마우스나 키보드 이벤트를 기록해 시스템 단축키에 바인딩합니다. 라이브 모니터로 기기가 보내는 값을 확인할 수도 있어요.",
        quickBind: "빠른 바인드",
        rows: {
          button4: "버튼 4",
          button5: "버튼 5",
          wheelClick: "휠 클릭",
          missionControl: "Mission Control",
          nextSpace: "다음 공간",
          appSwitcher: "앱 전환기",
        },
      },
    },
  },
  download: {
    title: "Mos 다운로드. 스크롤을 내 취향으로.",
    body:
      "몇 초 만에 설치하고, 필요할 때만 조절하세요. 자주 쓰는 앱에서도 같은 스크롤 감각을 유지할 수 있습니다.",
    ctaDownload: "다운로드",
    releaseNotes: "릴리스 노트",
    docs: "문서",
  },
  homebrew: {
    title: "Homebrew",
    copy: "복사",
    copied: "복사됨",
    tip: "팁: beta를 사용 중이라면 cask가 {cask}일 수 있어요.",
  },
  footer: {
    latestRelease: "최신 릴리스",
    latestVersion: "최신 {version}",
    requiresMacos: "macOS 10.13+ 필요",
    github: "GitHub",
    wiki: "Wiki",
    releases: "Releases",
  },
  easing: {
    graphAria: "스크롤 커브 그래프",
    step: {
      label: "Step",
      aria: "Step",
      help: "휠 델타의 양자화 하한.",
    },
    gain: {
      label: "Gain",
      aria: "Gain",
      help: "틱당 이동 거리와 곡선이 올라가는 속도를 결정합니다.",
    },
    duration: {
      label: "Duration",
      aria: "Duration",
      help: "스무딩 시간 상수(클수록 꼬리가 길어짐).",
    },
    footer: "ScrollCore curve",
  },
  wall: {
    back: "Mos",
    title: "더 월",
    tagline: "메모지를 남겨요",
    empty: "첫 번째 메모를 남겨보세요",
    trayHint: "메모지를 벽으로 드래그하세요",
    trayDragAria: "{color} 메모지를 벽으로 드래그",
    bodyPlaceholder: "뭔가 써보세요…",
    namePlaceholder: "이름 (선택)",
    colorAria: "{color} 색상",
    cancel: "취소",
    submit: "붙이기 ↗",
    submitting: "붙이는 중…",
    anonymous: "익명",
    delete: "메모 삭제",
    deleteConfirm: "삭제?",
    verifyHint: "잠깐, 사람인지 확인할게요…",
    errorGeneric: "메모를 올리지 못했어요. 다시 시도해 주세요.",
    errorRate: "너무 빠르게 올리고 있어요 — 잠시 후 다시 시도해 주세요.",
    errorTurnstile: "인증을 완료한 후 다시 시도해 주세요.",
    errorLinks: "메모에 링크가 너무 많아요.",
  },
};
