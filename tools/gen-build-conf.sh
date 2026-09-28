#!/bin/bash
# NeOS build pacman.conf generator — single source of truth for build.sh and
# the CI workflow (previously duplicated in both, which risked drift).
# Copies profile/pacman.conf to pacman-build.conf and rewrites the mirrorlist
# includes to absolute host paths so mkarchiso resolves them outside the chroot.
#
# Also injects a retrying XferCommand into the generated conf: pacman does NOT
# fail over to the next Server line when a download dies with an HTTP 5xx
# (observed as chaotic-aur.db 503s from cdn-mirror.chaotic.cx aborting the
# whole mkarchiso sync in seconds). Letting curl --retry absorb transient 5xx
# per URL keeps the build on the primary CDN instead of dying on a blip; if
# all retries still fail, pacman moves on to the next mirror in the list.
#
# Usage: gen-build-conf.sh [REPO_ROOT] [OUTPUT_CONF]
#   REPO_ROOT   repository root (default: $PWD)
#   OUTPUT_CONF output path (default: REPO_ROOT/pacman-build.conf)

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

REPO_ROOT="${1:-$PWD}"
BUILD_CONF="${2:-$REPO_ROOT/pacman-build.conf}"
PROFILE_DIR="$REPO_ROOT/profile"

MIRRORLIST_PATH="$PROFILE_DIR/airootfs/etc/pacman.d/neos-mirrorlist"
CHAOTIC_MIRRORLIST_PATH="$PROFILE_DIR/airootfs/etc/pacman.d/chaotic-mirrorlist"

if ! grep -q "^[[:space:]]*Server" "$MIRRORLIST_PATH"; then
    echo "Error: No active servers found in $MIRRORLIST_PATH." >&2
    echo "The build cannot proceed without valid repositories." >&2
    exit 1
fi

cp "$PROFILE_DIR/pacman.conf" "$BUILD_CONF"

# Use | as sed delimiter to avoid conflict with / in paths
sed -i "s|/etc/pacman.d/neos-mirrorlist|$MIRRORLIST_PATH|g" "$BUILD_CONF"
sed -i "s|/etc/pacman.d/chaotic-mirrorlist|$CHAOTIC_MIRRORLIST_PATH|g" "$BUILD_CONF"

# Retry transfers instead of aborting the sync on a transient 5xx (see header
# comment). Full re-download per retry (no -C -): resuming against the CDN
# after a 503 would just re-enter the same error path on the .db files.
awk '
    /^\[options\]$/ && !done {
        print
        print "# Injected by tools/gen-build-conf.sh: curl retries absorb transient CDN 5xx"
        print "# (e.g. cdn-mirror.chaotic.cx 503s) that would otherwise abort the whole sync."
        print "XferCommand = /usr/bin/curl -L --fail --silent --show-error --retry 8 --retry-delay 3 --retry-all-errors -o %o %u"
        done = 1
        next
    }
    { print }
' "$BUILD_CONF" > "${BUILD_CONF}.tmp" && mv "${BUILD_CONF}.tmp" "$BUILD_CONF"

echo "Generated $BUILD_CONF"
