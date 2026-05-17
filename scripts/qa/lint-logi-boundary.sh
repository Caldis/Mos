#!/usr/bin/env bash
# scripts/qa/lint-logi-boundary.sh
#
# Enforces the Mos/Logi/ module boundary because same-target `internal` is
# not enough. Two zones, two allowlists:
#
#   Zone A: outside Mos/Logi/ AND Mos/Integration/ (the rest of the app).
#     Only public-surface + bootstrap-wiring symbols may appear.
#   Zone B: inside Mos/Integration/ (the bridge implementation).
#     Public symbols + the internal bridge protocol/enums.
#   Inside Mos/Logi/: no restriction.
#
# Spec §4.7 listed the public allowlist; LogiIntegrationBridge and
# LogiUsageBootstrap added because AppDelegate legitimately wires both
# at launch (Tasks 3.10 + 4.2).
#
# Tests under MosTests/ are exempt — Tier 1/2 unit tests legitimately
# reference internal Logi symbols (canary, divert planner, etc.).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
cd "$ROOT_DIR"

ZONE_A_ALLOW=(
    LogiCenter
    LogiButtonCaptureDiagnosis
    LogiStandardMouseButtonAlias
    UsageSource
    ScrollRole
    ConflictStatus
    Direction
    LogiDeviceSessionSnapshot
    SessionActivityStatus
    LogiIntegrationBridge
    LogiUsageBootstrap
)

ZONE_B_ADDITIONAL=(
    LogiExternalBridge
    LogiDispatchResult
    LogiToastSeverity
    LogiNoOpBridge
)

VIOLATIONS=0

# Writes one VIOLATION line per offending symbol to stdout.
# Returns the number of violations as the function's count via stdout lines.
scan_zone() {
    local zone_label="$1"; shift
    local allowlist=("$@")
    local input
    input=$(cat)

    if [[ -z "$input" ]]; then
        return 0
    fi

    while IFS= read -r line_num_match; do
        [[ -z "$line_num_match" ]] && continue
        local file_path="${line_num_match%%:*}"
        local rest="${line_num_match#*:}"
        local line_num="${rest%%:*}"
        local line="${rest#*:}"

        for symbol in $(echo "$line" | grep -oE '\b(Logi[A-Z][a-zA-Z]*|Logitech[A-Z][a-zA-Z]*)\b' | sort -u); do
            local allowed=false
            for allow in "${allowlist[@]}"; do
                if [[ "$symbol" == "$allow" ]]; then allowed=true; break; fi
            done
            if [[ "$allowed" == "false" ]]; then
                echo "VIOLATION (zone $zone_label): $file_path:$line_num references '$symbol'"
            fi
        done
    done <<< "$input"
}

# Collect violations into a temp file so the parent shell can count them
# (piping into scan_zone would lose the counter due to subshell scoping).
VIOLATIONS_FILE=$(mktemp)
trap 'rm -f "$VIOLATIONS_FILE"' EXIT

# Zone A scan: Mos/ outside Logi/ + Integration/
ZONE_A_FILES=$(find Mos -type f -name '*.swift' -not -path 'Mos/Logi/*' -not -path 'Mos/Integration/*')
{
    for f in $ZONE_A_FILES; do
        grep -nE '\b(Logi[A-Z]|Logitech[A-Z])' "$f" 2>/dev/null | sed "s|^|$f:|" || true
    done
} | scan_zone "A" "${ZONE_A_ALLOW[@]}" >> "$VIOLATIONS_FILE"

# Zone B scan: Mos/Integration/
ZONE_B_ALLOW=("${ZONE_A_ALLOW[@]}" "${ZONE_B_ADDITIONAL[@]}")
ZONE_B_FILES=$(find Mos/Integration -type f -name '*.swift' 2>/dev/null || true)
{
    for f in $ZONE_B_FILES; do
        grep -nE '\b(Logi[A-Z]|Logitech[A-Z])' "$f" 2>/dev/null | sed "s|^|$f:|" || true
    done
} | scan_zone "B" "${ZONE_B_ALLOW[@]}" >> "$VIOLATIONS_FILE"

if [[ -s "$VIOLATIONS_FILE" ]]; then
    cat "$VIOLATIONS_FILE"
    VIOLATIONS=$(wc -l < "$VIOLATIONS_FILE" | tr -d ' ')
fi

if [ "$VIOLATIONS" -gt 0 ]; then
    echo "Lint failed: $VIOLATIONS Logi boundary violations."
    exit 1
fi
echo "Lint passed: zone A + zone B allowlists enforced."
