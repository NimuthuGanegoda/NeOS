#!/bin/bash
# ISO size release gate.
#
# Why this test exists: the 2 GiB budget is documented as hard and enforced in
# four places — README.md ("sub-2GB ISO size"), profile/profiledef.sh ("stay
# under the 2048 MiB release gate"), docs/architecture/PERFORMANCE.md (ISO Size
# budget) and docs/decisions/0006-ubuntu-parity-capabilities.md ("2 GiB ISO
# limit enforced"). Nothing actually enforced it: the workflow only printed the
# size, so a regression would ship rather than fail.
#
# The documented two-tier package strategy (ADR 0006) depends on the live image
# staying under this budget, and the offline install repo at /neos/pkg is the
# other side of that trade-off — if either grows, this gate is what notices.
#
# Usage:
#   bash tests/verify_iso_size.sh              # skip gracefully with no ISO
#   REQUIRE_ISO=1 bash tests/verify_iso_size.sh # fail if no ISO is present
#   MAX_ISO_MIB=4096 bash tests/verify_iso_size.sh
#
# Part of the *iso* test family: build-iso.yml's pre-build loop skips it (no
# ISO exists yet) and the post-build "Validate ISO" step runs it for real.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

OUT_DIR="${OUT_DIR:-out}"
MAX_ISO_MIB="${MAX_ISO_MIB:-2048}"

skip_or_fail() {
    local msg="$1"
    if [[ "${REQUIRE_ISO:-0}" == "1" ]]; then
        echo "[FAIL] $msg"
        exit 1
    fi
    echo "SKIPPED: $msg (set REQUIRE_ISO=1 to make this fatal)"
    exit 0
}

echo "Verifying ISO size against the ${MAX_ISO_MIB} MiB release gate..."

if [[ ! -d "$OUT_DIR" ]]; then
    skip_or_fail "output directory '$OUT_DIR' not found"
fi

shopt -s nullglob
ISOS=("$OUT_DIR"/*.iso)

if [[ ${#ISOS[@]} -eq 0 ]]; then
    skip_or_fail "no .iso found in '$OUT_DIR'"
fi

# Pick the NEWEST ISO by mtime rather than the first glob match. build.sh leaves
# a '<name>-with-repo.iso' temporary behind if the final mv is interrupted, and
# lexically '-' (0x2d) sorts before '.' (0x2e), so a plain glob would select the
# stale temporary instead of the real image.
NEWEST=""
NEWEST_MTIME=0
for iso in "${ISOS[@]}"; do
    mtime=$(stat -c %Y "$iso" 2>/dev/null || echo 0)
    if (( mtime > NEWEST_MTIME )); then
        NEWEST_MTIME=$mtime
        NEWEST="$iso"
    fi
done

if [[ -z "$NEWEST" ]]; then
    skip_or_fail "could not stat any ISO in '$OUT_DIR'"
fi

SIZE_BYTES=$(stat -c %s "$NEWEST")
SIZE_MIB=$((SIZE_BYTES / 1048576))
NAME="${NEWEST##*/}"

echo "  ISO: $NAME"
echo "  Size: $SIZE_BYTES bytes (${SIZE_MIB} MiB)"
if [[ ${#ISOS[@]} -gt 1 ]]; then
    echo "  Note: ${#ISOS[@]} ISO files present; checked the newest ($NAME)"
fi

if (( SIZE_MIB > MAX_ISO_MIB )); then
    echo ""
    echo "[FAIL] ISO exceeds the ${MAX_ISO_MIB} MiB release gate: ${SIZE_MIB} MiB."
    echo ""
    echo "This budget is documented as enforced in:"
    echo "  - README.md (sub-2GB ISO size objective)"
    echo "  - profile/profiledef.sh (airootfs_image_tool_options comment)"
    echo "  - docs/architecture/PERFORMANCE.md (Performance Budgets)"
    echo "  - docs/decisions/0006-ubuntu-parity-capabilities.md"
    echo ""
    echo "How to fix:"
    echo "  - Move the offending packages from profile/packages.x86_64 into the"
    echo "    installed-system block of tools/gen-manifests.sh (the two-tier"
    echo "    strategy from ADR 0006), or"
    echo "  - Raise the gate deliberately with MAX_ISO_MIB and update all four"
    echo "    places above in the same commit."
    exit 1
fi

echo "[PASS] ISO is within the ${MAX_ISO_MIB} MiB release gate (headroom: $((MAX_ISO_MIB - SIZE_MIB)) MiB)."
