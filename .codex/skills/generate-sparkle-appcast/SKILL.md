---
name: generate-sparkle-appcast
description: Generate Mos Sparkle appcast.xml from the latest build zip and recent git changes (since a given commit), then sync to docs/ for publishing.
---

Use this skill when the user wants to publish a new Mos release (stable or beta) and needs a Sparkle `appcast.xml` generated from the notarized `.zip` in `build/`, with human-friendly bilingual release notes derived from git changes.

**Inputs**

- `--since <commit>`: the previous release commit (exclusive). Used to generate release notes from changes since that commit.
- A notarized+zipped app in `build/` named:
  - `Mos.Versions.<version>-<YYYYMMDD>.<num>.zip` (stable)
  - `Mos.Versions.<version>-beta-<YYYYMMDD>.<num>.zip` (beta)
- Sparkle Ed25519 private key at `sparkle_private_key.txt` (gitignored).

**What to do**

1. Run the skill script:
   - `bash .codex/skills/generate-sparkle-appcast/scripts/generate_appcast.sh --since <commit>`
2. Confirm outputs:
   - `build/appcast.xml` (generated)
   - `docs/appcast.xml` (copied for `mos.caldis.me/appcast.xml`)
3. Ensure the GitHub Release tag and asset name match the URL inside the generated appcast.

**Notes**

- The script produces Sparkle-compatible HTML inside `<description><![CDATA[...]]></description>` following the provided bilingual template (Chinese + English, with beta warnings when applicable).
- By default, the script does **not** emit `<sparkle:releaseNotesLink>`, so Sparkle will show the inline `<description>` instead of opening a WebView. If you want a WebView, set `RELEASE_NOTES_LINK` when running the script.
- If the zip changes in any way (repacked/re-signed), you must re-run the script to regenerate `sparkle:edSignature`.
