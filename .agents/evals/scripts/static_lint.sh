#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$ROOT_DIR"

failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $*"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] && pass "file exists: $path" || fail "missing file: $path"
}

require_contains() {
  local path="$1"
  local pattern="$2"
  if grep -REq "$pattern" "$path"; then
    pass "$path contains /$pattern/"
  else
    fail "$path missing /$pattern/"
  fi
}

require_not_contains() {
  local path="$1"
  local pattern="$2"
  if grep -REq "$pattern" "$path"; then
    fail "$path unexpectedly contains /$pattern/"
  else
    pass "$path avoids /$pattern/"
  fi
}

require_file AGENTS.md
require_file .agents/INDEX.md
require_file .agents/docs/code-map.md
require_file .agents/docs/testing.md
require_file .agents/docs/quality-gates.md
require_file .agents/skills/README.md
require_file .agents/skills/release-preparation/SKILL.md
require_file .github/copilot-instructions.md

if [[ "$(cat CLAUDE.md 2>/dev/null || true)" == "@AGENTS.md" ]]; then
  pass "CLAUDE.md points to AGENTS.md"
else
  fail "CLAUDE.md must contain only @AGENTS.md"
fi

if [[ -L .claude/skills && "$(readlink .claude/skills)" == "../.agents/skills" ]]; then
  pass ".claude/skills points to ../.agents/skills"
else
  fail ".claude/skills must point to ../.agents/skills"
fi

if [[ -L .codex/skills && "$(readlink .codex/skills)" == "../.agents/skills" ]]; then
  pass ".codex/skills points to ../.agents/skills"
else
  fail ".codex/skills must point to ../.agents/skills"
fi

require_contains AGENTS.md '\.agents/INDEX\.md'
require_contains AGENTS.md 'git status --short'
require_contains AGENTS.md 'xcodebuild -scheme Debug'
require_contains AGENTS.md 'LOGI_REAL_DEVICE=1'
require_contains AGENTS.md 'scripts/qa/lint-logi-boundary\.sh'
require_contains AGENTS.md 'NSLocalizedString'
require_contains AGENTS.md 'macOS 10\.13'
require_contains AGENTS.md '人类确认'
require_contains AGENTS.md '用户确认后执行'

require_contains .agents/INDEX.md '\.agents/docs/code-map\.md'
require_contains .agents/INDEX.md '\.agents/docs/testing\.md'
require_contains .agents/INDEX.md '\.agents/docs/quality-gates\.md'
require_contains .agents/INDEX.md '\.agents/skills/release-preparation/SKILL\.md'
require_contains .agents/INDEX.md '历史 plans'

require_contains .agents/docs/code-map.md 'scripts/qa/lint-logi-boundary\.sh'
require_contains .agents/docs/testing.md 'xcodebuild -scheme Debug'
require_contains .agents/docs/testing.md 'LOGI_REAL_DEVICE=1'
require_contains .agents/docs/quality-gates.md 'CURRENT_PROJECT_VERSION'
require_contains .agents/docs/quality-gates.md 'NSLocalizedString'
require_contains .agents/docs/quality-gates.md 'String\(localized:\)'

require_contains .agents/skills/README.md 'release-preparation'
require_contains .agents/skills/release-preparation/SKILL.md 'scripts/release/prepare_zip\.sh'
require_contains .agents/skills/release-preparation/SKILL.md 'scripts/release/update_appcast\.sh'
require_contains .agents/skills/release-preparation/SKILL.md 'scripts/release/create_gh_draft\.sh'
require_contains .agents/skills/release-preparation/SKILL.md 'Do not publish the release'
require_contains .agents/skills/release-preparation/SKILL.md 'run `git push` as part of the autonomous release command sequence'

require_contains .github/copilot-instructions.md '@\.\./AGENTS\.md'

require_not_contains .agents/skills/release-preparation/SKILL.md 'bash \.skills/release-preparation/scripts'
require_not_contains .agents/docs 'xcodebuild.*-target Mos'
require_not_contains .agents/skills 'xcodebuild.*-target Mos'

case_count=$(find .agents/evals/cases -name '*.md' -type f | wc -l | tr -d ' ')
if [[ "$case_count" -ge 6 ]]; then
  pass "eval cases present: $case_count"
else
  fail "expected at least 6 eval cases, found $case_count"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "AGENTS static lint failed with $failures issue(s)."
  exit 1
fi

echo "AGENTS static lint passed."
