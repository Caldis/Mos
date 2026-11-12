# Release

Public release feed sources live here.

- `appcast.xml`: tracked Sparkle appcast source. Release automation writes the
  signed update item here and also mirrors a generated copy to `build/appcast.xml`.
- `release-notes/`: public HTML and Markdown release notes kept for historical
  and compatibility links. The current appcast flow uses inline changelog HTML,
  but this directory is still copied into the GitHub Pages artifact during the
  website build.

These files are source inputs for the public update feed, not generated website
output. GitHub Pages deployment copies them into `website/out/` via the website
build pipeline.

Use the release preparation workflow before changing `appcast.xml` for an actual
release. The repo-owned helper scripts live in `scripts/release/`, while the
release procedure is documented in `.agents/skills/release-preparation/SKILL.md`.
