# Docs and Pages Decoupling Design

**Goal:** Make `docs/` a human-authored documentation tree while GitHub Pages is deployed from a generated website artifact.

**Problem:** `docs/` currently mixes hand-written plans, README media, GitHub Pages export files, Sparkle `appcast.xml`, and release notes. The website publish script clears `docs/*` before copying a fresh Next.js export, so documentation assets stored there can be accidentally removed during website publishing.

**Decision:** Use GitHub Actions to build `website/`, prepare a Pages artifact, and deploy that artifact directly. Keep Sparkle's public URL unchanged by copying release feed files into the artifact root during the workflow.

**Source Layout:**

- `docs/` keeps hand-written documentation and plans.
- `assets/readme/` stores README images and archived README screenshots.
- `release/appcast.xml` stores the tracked Sparkle feed source.
- `release/release-notes/` stores tracked Sparkle release note sources.
- `website/out/` remains generated and ignored.

**Deployment Layout:**

- GitHub Actions builds `website/`.
- `website/scripts/prepare-pages-artifact.sh` copies `release/appcast.xml` to `website/out/appcast.xml`.
- `website/scripts/prepare-pages-artifact.sh` copies `release/release-notes/` to `website/out/release-notes/`.
- `actions/upload-pages-artifact` uploads `website/out`.
- `actions/deploy-pages` publishes the artifact.

**Compatibility:** The app still points Sparkle at `https://mos.caldis.me/appcast.xml`, so the deployed artifact must keep `appcast.xml` at the Pages site root.
