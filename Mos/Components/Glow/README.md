# Glow

Atlas-style animated aurora glow behind a window, rendered with Metal.

A self-contained component that attaches a transparent, click-through child window behind any `NSWindow` and renders a slowly rotating, procedural multicolor halo around it. Currently used by the Introduction (onboarding) window. The visual recipe was reverse-engineered from ChatGPT Atlas's onboarding glow (`BackgroundShimmerWindowManager` / `BackgroundShimmerRenderer` / `BackgroundShimmer.metal` inside `Aura.framework`).

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
```

The shader source is embedded as a Swift string and compiled at runtime via `device.makeLibrary(source:)`. This is deliberate: a `.metal` file in the target would require every contributor and CI runner to install the multi-GB Metal Toolchain component (separate download since Xcode 26). Runtime compilation uses the OS's built-in compiler service and costs a few milliseconds, once, when the window opens.

## Usage

```swift
// Attach (returns nil on machines without Metal — no glow, no failure)
glowWindowController = GlowWindowController.attach(to: window)

// Custom margin
glowWindowController = GlowWindowController.attach(to: window, margin: 200)

// Detach before the host window closes
glowWindowController?.detach()
glowWindowController = nil
```

Integration example: `Mos/Windows/IntroductionWindow/IntroductionWindowController.swift` (attach in `windowDidLoad`, detach in `windowWillClose`).

## Tuning

| Knob | Where | Default | Effect |
| --- | --- | --- | --- |
| `margin` | `GlowWindowController.attach(to:margin:)` | 150 | How far the glow extends beyond the host window (pt) |
| `cornerRadius` | `GlowMetalView.init` | 14 | SDF corner radius; should roughly match the host window corners |
| `intensity` | `GlowMetalView.init` | 1.15 | Overall brightness multiplier |
| palette phases | shader: `float3(0.0, 0.33, 0.67)` | — | Hue distribution around the window (cosine palette `d` coefficients) |
| hue rotation speed | shader: `t * 0.03` | ~33 s/rev | Speed of color rotation around the window |
| band undulation | shader: `sin(ang * 3.0 + t * 0.7)` | 3 lobes | Count and speed of brightness waves along the edge |
| falloff length | shader: `u.margin * 0.28` | — | How quickly the glow fades with distance |

## Behavior

- **Click-through** — the glow window ignores all mouse events
- **Drag-follow** — child window keeps its offset when the host is dragged
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
