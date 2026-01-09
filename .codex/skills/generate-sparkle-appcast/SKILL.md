---
name: generate-sparkle-appcast
description: Generate Mos Sparkle appcast.xml from the latest build zip and recent git changes (since a given commit), then sync to docs/ for publishing.
---

Use this skill when the user wants to publish a new Mos release (stable or beta) and needs:

- Sparkle `appcast.xml` generated from the notarized `.zip` in `build/`
- Two hosted release notes pages (Chinese + English)
- Sparkle to show Chinese for all `zh*` locales (Simplified/Traditional/HK/TW), and English for everything else

**Inputs**

- `--since <commit>`: the previous release commit (exclusive). Used to generate release notes from changes since that commit.
- A notarized+zipped app in `build/` named:
  - `Mos.Versions.<version>-<YYYYMMDD>.<num>.zip` (stable)
  - `Mos.Versions.<version>-beta-<YYYYMMDD>.<num>.zip` (beta)
- Sparkle Ed25519 private key at `sparkle_private_key.txt` (gitignored).
- Optional env:
  - `RELEASE_NOTES_BASE_URL` (default `https://mos.caldis.me/release-notes`)
  - `RELEASE_NOTES_ZH_FILE` / `RELEASE_NOTES_EN_FILE` to point to pre-written HTML files (otherwise the script writes to `build/release-notes/<tag>.*.html`)

**What to do**

1. Run the skill script:
   - `bash .codex/skills/generate-sparkle-appcast/scripts/generate_appcast.sh --since <commit>`
2. Confirm outputs:
   - `build/appcast.xml` (generated)
   - `docs/appcast.xml` (copied for `mos.caldis.me/appcast.xml`)
   - `build/release-notes/<tag>.zh.html` + `build/release-notes/<tag>.en.html` (generated)
   - `docs/release-notes/<tag>.zh.html` + `docs/release-notes/<tag>.en.html` (copied for hosting)
3. Ensure the GitHub Release tag and asset name match the URL inside the generated appcast.

**Notes**

- The script emits two `<sparkle:releaseNotesLink>` entries: `xml:lang="zh"` points to the Chinese page, and the default link points to the English page.
- You can pre-create/edit `build/release-notes/<tag>.zh.html` and `build/release-notes/<tag>.en.html` before running the script; the script will reuse them if present, otherwise it generates a default template from git history.
- If the zip changes in any way (repacked/re-signed), you must re-run the script to regenerate `sparkle:edSignature`.
