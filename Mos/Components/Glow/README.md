# Glow

A procedural window-glow effect library, rendered with Metal.

A self-contained component that attaches a transparent, click-through child window behind any `NSWindow` and renders animated, fully-procedural light effects around it — **22 effects** ranging from auroras to particles, pulses, lightning and fireworks, each with curated presets. Currently used by the Introduction (onboarding) window. The original visual recipe was reverse-engineered from ChatGPT Atlas's onboarding glow (`BackgroundShimmerWindowManager` / `BackgroundShimmerRenderer` / `BackgroundShimmer.metal` inside `Aura.framework`), then extended into an effect catalog inspired by game spell/particle VFX.

## Effect catalog

| # | 效果 | # | 效果 | # | 效果 |
| --- | --- | --- | --- | --- | --- |
| 0 | 极光流转 | 8 | 翡翠毒雾 | 16 | 极地磁暴 |
| 1 | 烛焰摇曳 | 9 | 落日熔金 | 17 | 樱瓣飘落 |
| 2 | 魔法余烬 | 10 | 虹彩涟漪 | 18 | 雷云蓄能 |
| 3 | 符文脉冲 | 11 | 暗影吞噬 | 19 | 彩虹扫掠 |
| 4 | 奥术电弧 | 12 | 圣光守护 | 20 | 心跳脉冲 |
| 5 | 星尘环绕 | 13 | 血月光环 | 21 | 烟花绽放 |
| 6 | 深海呼吸 | 14 | 量子噪点 | | |
| 7 | 冰晶辉光 | 15 | 凤凰尾焰 | | |

All effects are implemented in a single uber-shader (`GlowMetalView.shaderSource`) dispatched by `effectId`, sharing helpers (rounded-rect SDF, value noise/fbm, cosine palettes). `GlowEffectCatalog` defines each effect's display name, per-effect parameter metadata (name/range/integer-ness of up to 8 generic slots) and an aesthetic preset (palette, speed, intensity, falloff, slot values). Nine cosine palettes (虹彩/暖焰/寒霜/翡翠/血月/鎏金/紫夜/碧海/樱粉) are shared across effects.

## Architecture

```
Host window (e.g. IntroductionWindow)
  ▲ addChildWindow(_, ordered: .below)     — drag-follows automatically
Glow window (GlowWindowController)
  · borderless, transparent, ignoresMouseEvents, no shadow
  · host.frame inset by -margin on all sides
GlowMetalView (MTKView, 60 fps)
  · single-pass fragment shader, one fullscreen triangle
  · recipe: rounded-rect SDF distance falloff
            × atan2 polar angle driving a cosine palette (iquilezles.org/articles/palettes)
            × sin band undulation + thin rim light
  · premultiplied-alpha output, tonemapped with 1-exp(-x)
  · uber-shader: 22 effects dispatched by effectId, all knobs are uniforms
GlowParams (single source of truth)
  · plain struct, mutated live by GlowDebugPanel, read by the renderer per frame
GlowEffectCatalog
  · effect names + per-effect slot metadata + aesthetic presets + palettes
GlowDebugPanel "Glow Studio" (status item ⌥-menu → "Debug: Glow")
  · effect-list │ live preview (same shader, preview mode — no need to open
    the Introduction window) │ sectioned controls (全局/布局/调色/光形/效果参数)
  · control types match parameter types: sliders for floats, tick-snapped
    sliders for integers, popup for palettes, buttons for actions
  · pause/resume preview, reset-to-preset, copy-params-as-Swift-literal
```

### Drag compensation

Child windows normally follow their parent, but macOS can drop the final
position update on fast drags or click-drag-release flicks, leaving the glow
desynced. Two compensation layers fix this:

1. **Per-frame self-heal** — `frameSync` runs before every draw and re-pins
   the glow window to `host.frame.insetBy(-margin)`; any desync survives at
   most one frame (~16 ms). Also picks up live `margin` changes from the panel.
2. **Notification fallback** — `didMove` / `didResize` observers re-pin even
   while rendering is paused (occlusion, Reduce Motion).

The shader source is embedded as a Swift string and compiled at runtime via `device.makeLibrary(source:)`. This is deliberate: a `.metal` file in the target would require every contributor and CI runner to install the multi-GB Metal Toolchain component (separate download since Xcode 26). Runtime compilation uses the OS's built-in compiler service and costs a few milliseconds, once, when the window opens.

## Usage

```swift
// Attach (returns nil on machines without Metal — no glow, no failure)
glowWindowController = GlowWindowController.attach(to: window)

// Switch effect: apply a curated preset from the catalog
GlowParams.shared = GlowEffectCatalog.all[15].preset   // 凤凰尾焰

// Or adjust any knob at runtime (read every frame)
GlowParams.shared.margin = 200
GlowParams.shared.intensity = 1.8
GlowParams.shared.slots[0] = 0.2

// Detach before the host window closes
glowWindowController?.detach()
glowWindowController = nil
```

Integration example: `Mos/Windows/IntroductionWindow/IntroductionWindowController.swift` (attach in `windowDidLoad`, detach in `windowWillClose`).

## Tuning workflow

Open **Glow Studio** (hold ⌥, click the status bar icon → **Debug: Glow**):

1. Pick an effect from the left-hand list — its curated preset applies
   immediately and renders in the embedded preview (margin/corner radius are
   preserved across switches, since they are scene-dependent).
2. Adjust shared sections (全局: 亮度/速度 · 布局: 外扩/圆角 · 调色: 调色板/
   色相/饱和/明度 · 光形: 衰减/亮线) and the effect's own 效果参数 sliders.
3. **应用到引导窗口** shows the same params on the real Introduction window.
4. **复制参数** copies the current values as a Swift literal — paste it as the
   new preset in `GlowEffectCatalog` to make the tuning permanent.

Palette coefficient sets themselves live in `GlowEffectCatalog.palettes`
(cosine palette a/b/c/d vectors) — extend there for new color families.

## Behavior

- **Click-through** — the glow window ignores all mouse events
- **Drag-follow** — child window mechanism plus two-layer compensation (see above); glow stays pinned through fast drags and flick-releases
- **Resize-sync** — observes `NSWindow.didResizeNotification` on the host
- **Occlusion pause** — rendering stops while the glow window is not visible
- **Reduce Motion** — renders a single static frame when the system accessibility setting is on
- **Graceful degradation** — `attach` returns `nil` when `MTLCreateSystemDefaultDevice()` fails (pre-Metal hardware on macOS 10.13); the host window is unaffected

## Verifying / demoing

The Introduction window shows automatically on launch when accessibility permission is missing, or manually via Preferences → About → welcome button (`setManuallyOpened(true)` prevents the auto-close-on-permission timer from dismissing it). Note for CLI builds: the Debug scheme product is `Mos Debug.app` (bundle id `com.caldis.Mos.debug`); if that bundle already holds accessibility permission, a debug instance will run the scroll engines alongside production Mos — quit it after checking the glow.

## Future work (researched, not yet built)

- **fbm domain warp** — replace regular sin undulation with fractal-noise-warped bands for an aurora-like irregular flow
- **EDR** — `CAMetalLayer.wantsExtendedDynamicRangeContent` + `rgba16Float` on XDR/HDR displays so glow peaks exceed SDR white (Atlas does not do this)
- **Scroll-reactive** — modulate flow speed/brightness from live scroll events (Mos-specific storytelling)
- **Low-res offscreen + blit upscale** — Atlas renders the shimmer at reduced resolution and upscales (`blit_fragment`); free softening plus GPU savings if the effect is ever used on larger surfaces
