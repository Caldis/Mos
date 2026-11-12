# Docs and Pages Decoupling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split human docs from GitHub Pages output without changing the public Sparkle feed URL.

**Architecture:** The repository keeps source files only. `docs/` becomes the documentation tree, `release/` owns Sparkle public source files, and `website/out/` is produced during local builds or GitHub Actions runs. A GitHub Pages workflow uploads the generated artifact instead of committing static export output.

**Tech Stack:** Bash, Next.js static export, GitHub Actions Pages deployment, Sparkle appcast XML.

---

### Task 1: Move Source Assets

**Files:**
- Move: `docs/readme/` to `assets/readme/`
- Move: `docs/appcast.xml` to `release/appcast.xml`
- Move: `docs/release-notes/` to `release/release-notes/`

**Steps:**
- Create `assets/` and `release/` if needed.
- Move the files with `git mv` when tracked.
- Keep `docs/plans/` and `docs/superpowers/` in place.

### Task 2: Remove Generated Pages Output From docs

**Files:**
- Remove tracked generated files under `docs/`, including `_next/`, `index.html`, `404.html`, `app-icons/`, generated metadata files, `.nojekyll`, and `CNAME`.

**Steps:**
- Use `git rm` only for generated output files.
- Do not remove hand-written docs.

### Task 3: Add Pages Artifact Preparation

**Files:**
- Replace: `website/scripts/publish-docs.sh`
- Modify: `website/package.json`

**Steps:**
- Rename the workflow from publishing to preparing an artifact.
- Validate `website/out` exists.
- Copy `website/CNAME` into `website/out/`.
- Touch `website/out/.nojekyll`.
- Copy `release/appcast.xml` and `release/release-notes/` into `website/out/`.

### Task 4: Add GitHub Pages Workflow

**Files:**
- Create: `.github/workflows/pages.yml`

**Steps:**
- Trigger on pushes to `master` for website, release, and workflow changes.
- Trigger on manual dispatch.
- Run `npm ci` and `npm run build` in `website/`.
- Upload `website/out` with `actions/upload-pages-artifact`.
- Deploy with `actions/deploy-pages`.

### Task 5: Update References

**Files:**
- Modify: README files that reference `docs/readme/`
- Modify: `.agents/skills/release-preparation/SKILL.md`
- Modify: `scripts/release/update_appcast.sh`
- Modify: `.agents/INDEX.md`

**Steps:**
- Replace README image paths with `assets/readme/`.
- Make appcast release instructions point to `release/appcast.xml`.
- Keep build output in `build/appcast.xml` for local release work.

### Task 6: Verify

**Commands:**
- `rg -n "docs/readme|docs/appcast|docs/release-notes|publish-docs" README*.md .agents website .github`
- `cd website && npm run build`
- `git status --short`

**Expected:** README references point to `assets/readme/`; release references point to `release/`; website build creates `website/out` and prepares `appcast.xml` plus `release-notes/` there.
