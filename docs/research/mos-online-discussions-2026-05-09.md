# Mos online discussion research archive - 2026-05-09

Date: 2026-05-09
Scope: online discussion and article sources about Mos, excluding `github.com/caldis/Mos` issues.
Goal: collect at least 50 effective websites, group recurring topics, and preserve all analyzed sources.

## Executive Summary

I analyzed 58 websites. By the requested threshold, 50 websites are effective sources: each yielded at least three constructive issues, suggestions, expectations, or product-positioning signals. I kept the confidence labels explicit:

- High / medium confidence effective sources: forums, Q&A sites, comment threads, and first-hand blogs with direct Mos or macOS mouse-scroll discussion.
- Low confidence effective sources: competitor pages, editorial explainers, download-site reviews, or SEO-style articles that still contain at least three actionable points.
- Not counted: sources with only a link/repost, no discussion, inaccessible content, or too few useful signals.

The dominant signal is consistent across regions: Mos is valued because macOS treats wheel mice as second-class input devices compared with trackpads and Magic Mouse. Users want trackpad-like smoothness, separate mouse/trackpad direction, per-app exceptions, and predictable setup. The biggest adoption blockers are trust/permission friction, Logitech/Options+ conflicts, app-specific failures in Adobe/Figma/Catalyst/Electron apps, and unclear advanced settings.

## Source Count

- Effective websites counted: 50
- Additional useful but low-confidence / duplicate / invalid websites archived: 8
- Raw per-site archives created by subagents or local research:
  - `.codex-archives/`
  - `docs/research/apple-discussions-mos-scroll-2026-05-09.md`
  - `docs/research/techpp-mos-2026-05-09/analyzed-pages.md`

## Main Topic Groups

### 1. Third-party mouse scrolling feels broken on macOS

Users repeatedly describe wheel scrolling as jumpy, choppy, slow at low wheel velocity, too accelerated at high wheel velocity, or visually inferior to a trackpad. This appears in Reddit, MacRumors, Overclockers, ComputerBase, Super User, Apple Support, MacMagazine, ifun, Figma Forum, Adobe Community, and many individual blogs.

Product implication: Mos should continue to own the simple message "make wheel mice feel sane on macOS", but the onboarding should also explain the technical boundary: different apps interpret wheel events differently, so Mos can improve the feel but cannot guarantee pixel-perfect behavior everywhere.

### 2. Separate mouse and trackpad direction is a core use case

Many users want natural scrolling on trackpad but traditional wheel direction on a mouse. This is one of the clearest jobs-to-be-done, especially for Windows switchers and MacBook users who dock with an external display.

Product implication: treat direction separation as a first-run decision, not an advanced setting. Provide a preset such as "Trackpad natural, mouse traditional".

### 3. Logitech / MX Master / Logi Options+ conflict is the highest-value support niche

Logitech MX Master 3 / 3S / MX Ergo users are overrepresented. Common advice is to disable Logi Options+ smooth scrolling, sometimes set scrolling speed to 0%, and let Mos handle interpolation while Logi Options+ handles buttons. Users also mention Bluetooth vs dongle, SmartShift, free-spin mode, sleep/wake issues, and Options+ bloat or certificate failures.

Product implication: add a Logitech setup guide and conflict detector/checklist. This could become one of the most valuable docs pages.

### 4. Per-app exceptions are essential, not niche

Adobe Photoshop, Acrobat, Figma, Excel, Preview, Maps, Messages, Weather, Signal, WhatsApp, browsers, DAWs, and design tools all appear in app-specific complaints. Smooth scrolling can fix web reading but harm zoom or canvas precision.

Product implication: ship known-good app profiles or a guided "this app feels wrong" flow. Explain when to disable smoothing or tune X/Y axes.

### 5. Trust and permissions are a recurring adoption blocker

Users ask whether Mos is safe because it needs Accessibility permission, is downloaded outside the App Store, or triggers Gatekeeper warnings. Some reviews wrongly attribute unrelated mouse control or security events to Mos. Several guides explain right-click Open, `xattr`, Accessibility authorization, or launch-on-login.

Product implication: prioritize notarization/signing clarity, a plain-language permissions page, and localized security copy. This matters because Mos handles input events.

### 6. Advanced controls need presets and better language

Step / Speed / Gain / Duration, Dash Key, Toggle Key, Block Key, horizontal vs vertical smoothing, and "simulate trackpad" appear as useful but confusing. Users often ask for exact settings.

Product implication: provide named presets: "Precise", "Trackpad-like", "Fast long documents", "Design apps", "MX Master", "High refresh display". Keep the sliders, but reduce first-run cognitive load.

### 7. Automation and power-user hooks are a credible expansion

Keyboard Maestro and AppleScript users want enable/disable hooks, modifier+wheel behavior, app-scoped automation, and less menu-bar clicking. BTT and SteerMouse are frequent comparison tools.

Product implication: a scriptable enable/disable interface, URL scheme, CLI, or Shortcuts actions could be a paid/pro feature without weakening the free core.

## Effective Sources By Website

Confidence labels:

- High: direct user discussion, comments, forum/Q&A, or first-hand long-term report.
- Medium: first-hand article or editorial with enough concrete product signals.
- Low: competitor page, download/review aggregator, SEO-style guide, or weak direct discussion; still counted only if it provides at least three actionable signals.

| # | Website | Confidence | Effective? | Key URLs | Main signals |
|---:|---|---|---|---|---|
| 1 | reddit.com | High | Yes | https://www.reddit.com/r/macapps/comments/1iacm88/mos_brings_macos_smooth_scrolling_to_any_mouse/ ; https://www.reddit.com/r/MacOS/comments/ptl91u/why_not_try_mos_as_an_alternative_for/ ; https://www.reddit.com/r/logitech/comments/1nwjrda/mx_master_3_on_mac_the_only_configuration_guide/ | Strongest volume. Logitech/MX recipes, Mos vs Mac Mouse Fix/SmoothScroll/BetterMouse, glitches, privacy trust, Apple Silicon, app focus loss, browser stutter. |
| 2 | producthunt.com | Low | Yes | https://www.producthunt.com/products/mos ; https://www.producthunt.com/p/mos | Free/open-source positioning, praise vs Logitech scrolling, Scroll Reverser alternative, weak but direct product sentiment. |
| 3 | news.ycombinator.com | High | Yes | https://news.ycombinator.com/item?id=39701162 ; https://news.ycombinator.com/item?id=32179842 ; https://news.ycombinator.com/item?id=33331266 | macOS missing wheel smoothness, separate direction demand, stability/restart complaints, README/site clarity, performance on older machines. |
| 4 | forums.macrumors.com | High | Yes | https://forums.macrumors.com/threads/magic-mouse-and-mbp-16-m3-pro-2023.2415976/ ; https://forums.macrumors.com/threads/how-to-set-natural-scrolling-for-mouse-and-trackpad-independently.2396187/ ; https://forums.macrumors.com/threads/i-cant-believe-ive-had-to-install-a-third-party-app-to-fix-mouse-scrolling.2445811/ | Many direct threads. MX Master smoothness, independent direction, Settings questions, Magic Mouse/trackpad comparisons, Reason DAW and horizontal/vertical needs. |
| 5 | macupdate.com | High | Yes | https://mos.macupdate.com/ | Reviews mention Monterey compatibility, Accessibility and first-open friction, security fears, "no annual subscription" pricing signal, Magic Mouse-like value. |
| 6 | discussions.apple.com | High | Yes | https://discussions.apple.com/thread/255899023 ; https://discussions.apple.com/thread/252108130 ; https://discussions.apple.com/thread/252336951 ; https://discussions.apple.com/thread/255161881 | Apple-owned support context. Choppy scrolling, Safari/YouTube issues, M1/M2 stutter, Mos/MMF/Smooze comparisons, OS-update regressions. |
| 7 | community.adobe.com | High | Yes | https://community.adobe.com/t5/photoshop-ecosystem-discussions/slow-down-zoom-with-mouse-wheel-on-mac/td-p/13052403 ; https://community.adobe.com/questions-12/scrolling-too-fast-on-adobe-acrobat-pro-dc-1510418 ; https://community.adobe.com/questions-712/scroll-to-zoom-function-of-mouse-is-causing-too-much-zoom-in-photoshop-macos-1141891 | App-specific exceptions are essential. Mos can fix general scrolling but cause Photoshop/Acrobat zoom or line-jump problems; users need per-app disable guidance. |
| 8 | superuser.com | High | Yes | https://superuser.com/questions/201645/mac-os-x-scrolling-is-jumpy ; https://superuser.com/questions/1605926/logitech-mx-master-3-3s-bluetooth-mouses-magspeed-scroll-is-unreliable-with-all | Long-lived Q&A. Jumpy wheel, MX Master MagSpeed unreliability, KVM/USB Overdrive conflicts, pinch zoom, natural direction setup. |
| 9 | v2ex.com | High | Yes | https://v2ex.com/t/337190 ; https://www.v2ex.com/t/1183913 ; https://us.v2ex.com/t/1160448 ; https://www.v2ex.com/t/836748 | Chinese power-user discussion. USB mouse support, CPU/login item, per-app disable, game wheel multiplication, trackpad misclassification, macOS 26 breakage, Bartender conflict. |
| 10 | applech2.com | Medium | Yes | https://applech2.com/archives/20181211-macos-mouse-scroll-utility-mos.html | Japanese article/comments. iPad support ask, conflicts with SmoothScroll/Logicool Options/SteerMouse, old device support, Accessibility permission friction. |
| 11 | techpp.com | Medium | Yes | https://techpp.com/2024/06/29/change-scrolling-directions-for-mac-mouse-and-trackpad-separately/ | Separate direction explainer. Mos as advanced alternative to Scroll Reverser; Accessibility/setup complexity; macOS 10.11+ audience. |
| 12 | tildes.net | High | Yes | https://tildes.net/~tech/1lkd/mos_brings_macos_smooth_scrolling_to_any_mouse | Discussion around kinetic vs smooth terminology, non-Apple mouse pain, MX Master/Safari low-FPS feel, settings discoverability, Linux extension interest. |
| 13 | xda-developers.com | Medium | Yes | https://www.xda-developers.com/this-app-fixes-most-annoying-parts-using-mac/ ; https://www.xda-developers.com/moved-away-from-windows-11-but-didnt-go-to-linux/ | Windows switcher framing, Magic Mouse question, Photoshop compatibility, LinearMouse/Smooze alternatives, broader Mac mouse pain. |
| 14 | softpedia.com | Low | Yes | https://mac.softpedia.com/get/System-Utilities/Mos.shtml ; https://mac.softpedia.com/progChangelog/Mos-Changelog-142796.html | Download/review plus changelog. Crashes, DisplayLink/Catalyst, Accessibility revoked, Logi/HID/Bolt/Unifying/Bluetooth, exceptions, remote desktop, Java/Steam. |
| 15 | addictivetips.com | Medium | Yes | https://www.addictivetips.com/mac-os/set-different-scroll-direction-for-mouse-and-trackpad-on-macos/ | Separate direction, per-app exceptions, Step/Speed/Duration, launch at login, Accessibility setup. |
| 16 | apple.stackexchange.com | High | Yes | https://apple.stackexchange.com/questions/392936/shift-scroll-doesnt-horizontally-scroll-with-any-external-mouse ; https://apple.stackexchange.com/questions/253111/how-to-disable-scroll-acceleration-in-macos-sierra ; https://apple.stackexchange.com/questions/70868/trackpad-and-mouse-different-scrolling-directions | External mouse jumpiness, shift+wheel horizontal, discrete wheel vs touchpad, one-stop mouse-suite expectation. |
| 17 | airscroll.net | Low | Yes | https://airscroll.net/best-smooth-scrolling-for-mac ; https://airscroll.net/product ; https://airscroll.net/changelog | Competitor page, useful as market signal. Claims gaps around feel/reliability/update cadence/high-refresh/per-screen profiles; $6.99/year benchmark. |
| 18 | osxinfo.net | High | Yes | https://osxinfo.net/konu/mos-mouseunuza-akicilik-katin.9712/ ; https://osxinfo.net/konu/scroll-islevi-magic-mouse-gibi.4234/ ; https://osxinfo.net/konu/mouse-sarma-hizi-sorunu.10294/ | Turkish/Hackintosh forum. Adobe exception, trackpad/touchpad confusion, speed lower bound too high, SmoothScroll/Smooze alternatives. |
| 19 | mac.webmist.info | Medium | Yes | https://mac.webmist.info/macos-mos/ ; https://mac.webmist.info/macos-direction-scroll/ | Japanese guide. Non-Apple mouse smoothness, Gatekeeper/Accessibility, Scroll Reverse not syncing, advanced controls, trackpad disable with mouse. |
| 20 | baty.net | High | Yes | https://baty.net/posts/2025/03/fixing-the-terrible-scrolling-behavior-with-logitech-mx-master-on-mac-os/ | Strong first-hand MX Master setup. Logi Options + Mos, Step/Speed/Duration recipes, `xattr` quarantine issue, free-spin precision. |
| 21 | old.taikun-room.com | Medium | Yes | https://old.taikun-room.com/2020/09/mac-software-mos.html | Japanese guide. Non-Magic Mouse wants trackpad-like scroll, Windows-like direction, horizontal Toggle Key, per-app Reverse confusion, Gatekeeper/Accessibility. |
| 22 | hackintosh-forum.de | High | Yes | https://www.hackintosh-forum.de/forum/thread/37252-mos-app-smooth-scrolling-f%C3%BCr-nicht-apple-m%C3%A4use/ | German Hackintosh forum. Natural/smooth scrolling, third-party mouse compatibility, side buttons/back-forward, 4K scrolling and performance. |
| 23 | stackoverflow.com | High | Yes | https://stackoverflow.com/questions/70787984/change-mac-scroll-direction-in-mouse-and-not-touchpad ; https://stackoverflow.com/questions/75862981/shift-mouse-scroll-wheel-not-working-on-a-mac ; https://stackoverflow.com/questions/65572075/how-to-get-nsscrollview-to-scroll-horizontally-with-the-scroll-wheel-without-the | Developer angle. Direct Mos references plus horizontal scroll, NSScrollView behavior, wheel event semantics, app/context config. |
| 24 | blog.kueiapp.com | Medium | Yes | https://blog.kueiapp.com/os-zh/mos-%e8%ae%93macbook%e8%a7%b8%e6%8e%a7%e6%9d%bf%e8%88%87%e6%bb%91%e9%bc%a0%e5%8f%af%e7%8d%a8%e7%ab%8b%e8%a8%ad%e5%ae%9a%e6%8d%b2%e5%8b%95%e6%96%b9%e5%90%91%e7%9a%84%e8%b6%85%e6%a3%92-macos-app/ | Traditional Chinese/English guide. Direction split, smoothness, Accessibility/menu background/restart persistence, Hammerspoon replacement risk. |
| 25 | saggiamente.com | Medium | Yes | https://saggiamente.com/2024/10/come-rendere-fluido-lo-scorrimento-della-rotellina-del-mouse-su-macos/ ; https://saggiamente.com/2016/12/come-si-fa-scorrere-in-orizzontale-su-macos-usando-la-rotella-verticale-dei-mouse/ | Italian source. Logitech smooth loses precision, Magic Mouse/Trackpad vs ergonomic mouse, horizontal panning, middle-click autoscroll demand. |
| 26 | technest-official.hatenablog.com | Low | Yes | https://technest-official.hatenablog.com/entry/mac-win-mouse-scroll-lag-fix | Japanese SEO/guide. Mac/Windows shared mouse, generic non-Logitech users, Bluetooth latency misattribution, LinearMouse vs Mos positioning. |
| 27 | tek-next.jp | Medium | Yes | https://tek-next.jp/pc/mac-mx-master-3/ | Japanese MX Master guide. Windows-to-Mac transition, non-Apple mouse jank, Chrome/Firefox scroll flags, Logi Options overlap, simple setup. |
| 28 | talushan.com | Medium | Yes | https://talushan.com/mac-mouse-windows-movement/ | Japanese guide. Windows-like Mac mouse, direction separation, smooth/eye-strain, launch on login, pointer acceleration adjacent need. |
| 29 | mlabo.org | Medium | Yes | https://mlabo.org/7847/ ; https://mlabo.org/11757/ ; https://mlabo.org/12523/ | Japanese trackball ecosystem. M575/MX ERGO/Kensington, Magic Trackpad-like scroll, Accessibility/old version permission residue, app exceptions, SteerMouse. |
| 30 | 60d.jp | Medium | Yes | https://60d.jp/blog/entry/app-mos | Subagent archive. Fine-grained Step/Speed/Duration, slow wheel not moving, fast wheel jumping, Launch on Login, Dash/Block/Toggle explanation gap. |
| 31 | rosedale.co.jp | Medium | Yes | https://www.rosedale.co.jp/topics/261/ ; https://www.rosedale.co.jp/topics/340/ | Subagent archive. Inertial scroll expectations, onboarding permissions, Step/Speed/Duration, Dash/Toggle/Block, overrun risk. |
| 32 | forums.overclockers.co.uk | High | Yes | https://forums.overclockers.co.uk/threads/new-to-macos-how-to-get-mouse-moving-smooth.18940884/ | Windows/Linux switcher says mouse stutter may block Mac desktop migration; Razer driver gap; acceleration and slow scrolling pain; trackpad workaround. |
| 33 | mac-help.com | High | Yes | https://www.mac-help.com/threads/horizontal-scroll-not-working.228407/ | Big Sur horizontal scroll regression; Logic Pro/ProTools workflow; Mos horizontal command works for one user but fails for another; OS-native preference desired. |
| 34 | forum.keyboardmaestro.com | High | Yes | https://forum.keyboardmaestro.com/t/invert-mouse-scroll/28123 ; https://forum.keyboardmaestro.com/t/can-the-mouse-scroll-wheel-be-used-as-a-trigger/395 ; https://forum.keyboardmaestro.com/t/activating-and-quitting-application-when-switching-applications/50487 | Automation users. Per-app reverse, modifier+wheel triggers, simulated scroll unreliability, enable/disable hook better than launch/quit. |
| 35 | computerbase.de | High | Yes | https://www.computerbase.de/forum/threads/scroll-traegheit-nur-bei-langsamen-initialen-scrollen-erste-2-bis-3-mausrad-rasten.2147825/ ; https://www.computerbase.de/forum/threads/magic-mouse-2-m1-air-big-sur-beschleunigung-deaktiveren.2026448/ | German forum. Slow initial notches, multiple mice affected, Mos suggestion, ScrollReverser conflict, per-device natural direction demand. |
| 36 | mac-forums.com | Medium | Yes | https://www.mac-forums.com/threads/non-apple-magic-mouse-users-what-app-are-you-using-smooth-scrolling.379754/ | Keychron mouse terrible scrolling, Mos fixes Windows-like feel, Logitech user reports Mos not working, iScroll/Mac Mouse Fix alternatives. |
| 37 | prashant.me | High | Yes | https://prashant.me/mac/2024/07/10/logitech-mx-master-configuration-in-macos.html | Concise first-hand MX Master 3S setup: Logi Options+ speed 0%, smooth off, SmartShift off, Mos smooth on, launch login, no restart. |
| 38 | notes.ghed.in / rmarotta.business.blog | High | Yes | https://rmarotta.business.blog/2025/01/26/mos-brings-macos-smooth-scrolling-to-any-mouse/ ; https://notes.ghed.in/posts/2025/mos-smooth-scrolling-mouse-macos/ | First-hand long-term user. Catalyst/Electron freeze, exceptions, hide menu icon, update silence, alternatives, subscription competitor signal. |
| 39 | bgr.com | Medium | Yes | https://www.bgr.com/2161438/free-open-source-apps-mac-users-need-try/ | Mainstream awareness. Natural scrolling mismatch, mouse speed too slow, advanced step/speed/duration, Excel exceptions, Dash Key, open-source/free value. |
| 40 | linguax.app | Low | Yes | https://linguax.app/zh-Hant/blog/macos-mouse-smooth-scroll-enhancement | Competitor article. Choppy Logitech/Razer, Logi Options+ certificate failures, reverse direction, driver bloat, Mos too basic claim, local/lightweight marketing. |
| 41 | ifun.de | High | Yes | https://www.ifun.de/maus-mit-scrollrad-mos-optimiert-die-mac-performance-131113/ ; https://www.ifun.de/maus-mit-scrollrad-mac-app-mos-scrollt-butterweich-156899/ | German Apple site with comments. Natural Scrolling debate, Logitech MX Master and pro audio, Mos vs SmoothScroll, Logi Options coexistence, multi-user/input issues. |
| 42 | macmagazine.com.br | High | Yes | https://macmagazine.com.br/post/2025/01/24/utilitario-leva-rolagem-suave-a-mouses-de-terceiros-no-macos/ ; https://forum.macmagazine.com.br/topic/280469-rolagem-inercial-app-mos/ | Brazilian article/forum. Logitech Pebble, trust/security question, direct GitHub/notarization concern, third-party mouse vs Lenovo comparison, inertia demand. |
| 43 | megatenpa.com | Medium | Yes | https://megatenpa.com/gadget/mouse/macos-non-genuine-mouse/ ; https://megatenpa.com/macos/macos-application/m1-application/ | Subagent archive. Non-genuine mouse speed too slow, LogiOptions max insufficient, Dash Key for long pages/Excel, Toggle Key for MX ERGO horizontal. |
| 44 | sspai.com | High | Yes | https://sspai.com/post/44107 ; https://go-post.sspai.com/post/106974 ; https://sspai.com/post/71540 | Chinese editorial/community. Known issues warning, donation support, Keychron M6 lacks vendor software, button mapping, per-browser profiles, mouse+trackpad hybrid workflow. |
| 45 | tekbyte.net | Medium | Yes | https://www.tekbyte.net/get-smooth-scrolling-in-safari-and-other-apps-with-mos/ | First-hand Safari/Xcode setup. Safari wheel not smooth, Edge-like preset desire, LinearMouse coexistence, Homebrew install. |
| 46 | canion.blog | Medium | Yes | https://canion.blog/2025/02/01/mos-for-smooth-mouse-scrolling.html | First-hand note. SteerMouse covers Logitech MX Master buttons but not smooth scrolling; Mos fills that gap; kinetic scrolling as missing feature. |
| 47 | community.folivora.ai | High | Yes | https://community.folivora.ai/t/smooth-scrolling-adjustments/46932 | BetterTouchTool community. User cannot replicate Mos smoothness in BTT; duration/animation settings matter; BTT author says Mos failed for horizontal Calendar/Safari/Mail; user wants fewer background processes. |
| 48 | forum.figma.com | High | Yes | https://forum.figma.com/suggest-a-feature-11/zoom-with-scroll-wheel-jumps-too-much-21455 | Figma users. Ctrl+wheel zoom jumps too much; M1 + Logitech G Pro choppy/fast; Mos per-app settings as solution; alternate zoom handling as native fix. |
| 49 | note.com | Medium | Yes | https://note.com/kohada721/n/na1d637994539 ; https://note.com/digitalcube/n/n45399d93ee30 | Japanese individual/company posts. Desktop Mac needs mouse tools, Windows/Mac same mouse direction, "install and feels right", remote-work survey mentions Mos for productivity. |
| 50 | helium7.me | Medium | Yes | https://helium7.me/posts/mac-setup/ | Chinese macOS setup guide. Gatekeeper/quarantine, macOS optimized for trackpad, no separate direction, mechanical slow wheel scroll, Mos as open-source fix. |

## Additional Useful Sources Not Counted Toward The 50

These were analyzed or archived but kept out of the count because they are duplicate, too weak, too promotional, or do not clearly provide three independent discussion signals.

| Website | Verdict | URLs / archive | Reason |
|---|---|---|---|
| alternativeto.net | Not counted | https://alternativeto.net/software/caldis-mos/ | Only a small number of direct constructive points for Mos itself. Useful competitor directory, weak discussion. |
| macdownload.informer.com | Not counted | https://macdownload.informer.com/mos/ | No meaningful comments/questions; mostly outdated listing. |
| talk.waerfa.com | Not counted | https://talk.waerfa.com/t/mos/170 | One recommendation post, no real discussion. |
| chrishannah.me | Not counted | `.codex-archives/chrishannah.me/research-2026-05-09.md` | Adjacent Mac/power-user context, no direct Mos value. |
| chaitanyapingle.com | Not counted | `.codex-archives/chaitanyapingle.com/mos-research-2026-05-09.md` | No reachable relevant content. |
| forum.mactalk.ch | Not counted | https://forum.mactalk.ch/viewtopic.php?t=944 | Repost of ifun-style article with little original discussion. |
| benchmark.rs | Not counted | https://forum.benchmark.rs/threads/aplikacije-ios.194450/page-115 | Only weak recommendation signal found. |
| macnav.net / softonic.cn / xbeios.com / cnblogs.com / blog.sukisq.me / minatokobe.com | Kept as supplemental | https://www.macnav.net/en/app/utilities/mos ; https://mos.softonic.cn/mac ; https://www.xbeios.com/3862.html ; https://www.cnblogs.com/bugshare/p/19630998 ; https://blog.sukisq.me/docs/tinkering-journey/mac-tools-sharing/ ; https://minatokobe.com/wp/os-x/mac/post-67719.html | Useful for feature framing, SEO/download-channel messaging, and Chinese/Japanese discovery paths. I did not need them to satisfy the 50 effective-source count. |

## Product Direction Opportunities

### Priority 1: Setup and trust

- Ship a first-run flow that explains Accessibility permission in plain language.
- Make Gatekeeper / right-click Open / quarantine troubleshooting easy to find.
- Add a "Why Mos needs this permission" page in Chinese, English, Japanese, Portuguese, German, and Turkish.
- If feasible, improve notarization/signing communication because trust fears appear repeatedly.

### Priority 2: Logitech guide and conflict detection

- Create dedicated guides for MX Master 3, MX Master 3S, MX Ergo, M575, Keychron M6, Razer mice, and generic wheel mice.
- Explain common Logi Options+ settings: disable Logi smooth scrolling, avoid double interpolation, SmartShift tradeoffs, Bluetooth vs dongle, sleep/wake behavior.
- Add a diagnostic checklist: "If scrolling feels jittery/inconsistent".

### Priority 3: Presets instead of raw sliders first

- Keep Step/Gain/Duration, but front-load presets:
  - Trackpad-like
  - Precise design/CAD/Figma
  - Fast long documents
  - MX Master
  - Low inertia
  - Browser reading
- Explain Dash Key, Toggle Key, and Block Key with concrete workflows: long webpages, Excel, horizontal timeline/canvas, temporary native app behavior.

### Priority 4: App profiles and exceptions

- Offer default exception/profile recommendations for Photoshop, Acrobat, Figma, Excel, Preview, Signal, WhatsApp, Maps, Messages, Weather, Safari, Chrome, Firefox, DAWs, and CAD/design tools.
- Add a one-click "This app feels wrong" helper that opens per-app settings and suggests disabling smooth scrolling or tuning X/Y separately.

### Priority 5: Automation and pro workflows

- Add a CLI, URL scheme, AppleScript, or Shortcuts actions for enable/disable, profile switching, and app-specific toggles.
- Consider modifier+wheel and button binding as a power-user tier, but document technical limitations honestly.
- Provide import/export/sync for profiles, useful for users who configure many machines.

## Monetization Signals

### What users are likely to accept

- Donation/sponsorship remains aligned with current goodwill. Several sources explicitly value free/open-source availability.
- One-time paid "Pro" upgrade may work better than a subscription. Reddit and other sources show subscription fatigue toward SmoothScroll-style annual pricing.
- Paid add-ons could be acceptable if the core smooth-scroll and direction split remain free:
  - device presets
  - profile sync/import/export
  - diagnostics dashboard
  - automation hooks
  - curated app profiles
  - priority support for new macOS releases
- Team/commercial license for managed Macs could sell support, documentation, and configuration templates rather than locking core features.

### What would be risky

- Mandatory subscription for core smoothing would likely create backlash.
- Ads, bundled downloaders, or opaque telemetry would damage trust because users already worry about Accessibility/input permissions.
- Hiding basic separate-direction support behind a paywall would conflict with the strongest goodwill signal.

### Practical monetization path

1. Keep Mos core free/open-source: smooth scrolling, reverse scroll, basic per-app profiles.
2. Add visible sponsorship/donation surfaces in app and docs, with non-annoying copy.
3. Offer an optional one-time paid "Mos Pro" or "Supporter" license for advanced presets, import/export/sync, diagnostics, automation, and priority builds.
4. Offer a commercial support tier for teams that need reliable mouse behavior across Logitech-heavy offices.

## Research Gaps

- I did not use logged-in browser sessions; public pages were enough for the 50-source target.
- Some sources are machine-translated/SEO-like or competitor-authored and should be weighted lower.
- GitHub issues/discussions inside `github.com/caldis/Mos` were deliberately excluded from the source count per request, though search results surfaced them.
- Real device testing is outside this research task and should be confirmed separately before making Logi/HID claims.
- The `indigolog.com` subagent repeatedly timed out and returned no verifiable data; it is not counted as an analyzed or effective source.

## Follow-up

On 2026-05-10 I added a follow-up report for five questions: whether to expand to 100 sources, whether Mos 4.2.0 Logitech button adaptation has external discussion, how the visualization changed, what Mos can do for AI friendliness, and how the dashboard was restyled.

- Follow-up report: `docs/research/mos-followup-questions-2026-05-10.md`
- Visual dashboard: `docs/research/mos-online-discussions-visual-summary-2026-05-09.html`
- Logitech buttons archive: `.codex-archives/logitech-buttons-2026-05-10/research.md`
- Source expansion archive: `.codex-archives/source-expansion-100-2026-05-10/research.md`
- AI-friendly archive: `.codex-archives/ai-friendly-2026-05-10/research.md`
