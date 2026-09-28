#!/bin/bash
# NeOS release torrent generator — creates a BitTorrent metainfo (.torrent)
# for a built ISO so every release automatically ships a torrent next to the
# image (the .torrent itself is a few tens of KiB, so it is small enough for
# the GitHub Release while the payload stays on SourceForge).
#
# Called automatically from two places:
#   - build.sh, after the ISO has validated: local builds get a torrent for
#     the image in out/ (DHT + the default public tracker list, no web seeds).
#   - .github/workflows/build-iso.yml, after the release-tag step: CI re-runs
#     the generator with SOURCEFORGE_PROJECT/NEOS_RELEASE_TAG set, which adds
#     the SourceForge download URLs as web seeds. The torrent therefore keeps
#     working even with zero swarm peers — clients fall back to plain HTTP
#     download from SourceForge until other peers appear.
#
# Usage: gen-torrent.sh [options] [ISO_FILE]
#
#   ISO_FILE           torrent this image (default: the newest out/*.iso,
#                      selected by mtime — same rule as build.sh/CI)
#
# Options:
#   --output DIR       write "<iso basename>.torrent" into DIR
#                      (default: next to the ISO)
#   --tracker URL      announce URL; repeatable, each URL becomes its own
#                      tier (backup tracker). Overrides the default list.
#   --no-trackers      write no announce list at all (DHT-only torrent)
#   --private          set the private flag (clients disable DHT/PEX; only
#                      useful for restricted swarms, not for releases)
#   --comment TEXT     comment field (default: "NeOS <iso basename>")
#   --piece-size N     piece length exponent, piece size = 2^N bytes
#                      (default: auto-selected from the ISO size)
#   -h|--help          this help
#
# Environment:
#   NEOS_TORRENT_TRACKERS     default tracker list override (comma and/or
#                             space separated)
#   NEOS_TORRENT_SOURCE_DIR   directory scanned for the newest ISO
#                             (default: "out", relative to the repository root)
#   SOURCEFORGE_PROJECT       SourceForge project name; when set together with
#                             NEOS_RELEASE_TAG, the SourceForge download URLs
#                             are added as web seeds
#   NEOS_RELEASE_TAG          release tag segment of the SourceForge path
#   NEOS_RELEASE_BRANCH       branch segment of the SourceForge path
#                             (default: "testing" — the branch releases are
#                             currently cut from)
#
# Requires: mktorrent (pacman -S mktorrent / apt install mktorrent)

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_NAME="${0##*/}"
SCRIPT_NAME="${SCRIPT_NAME//[^a-zA-Z0-9_.-]/}"

_error_handler() {
    local err=$1
    local line=$2
    local cmd="${BASH_COMMAND//[^[:print:]]/}"
    printf -- "\n\e[1m\e[31m================================================================================\e[0m\n\e[1m\e[31m[CRITICAL] SCRIPT FAILURE: %s\e[0m\n\e[1m\e[31m================================================================================\e[0m\n\e[1m\e[36mDIAGNOSTICS:\e[0m\n  • Failed Command: \"%s\"\n  • File / Line:    %s:%s\n  • Exit Status:    %s\n\e[1m\e[31m================================================================================\e[0m\n" "$SCRIPT_NAME" "$cmd" "$SCRIPT_NAME" "$line" "$err" >&2 || true
    logger -t "neos-$SCRIPT_NAME" "CRITICAL: Script failed at line $line (Exit Code $err). Command: \"$cmd\"." || true
    exit "$err"
}

trap '_error_handler $? $LINENO' ERR

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
    sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'
}

# ---- Default public trackers ------------------------------------------------
# Open, UDP-based trackers that require no registration. Every URL becomes its
# own tier, so a dead tracker falls through to the next one; DHT and PEX stay
# enabled regardless, so a trackerless swarm still bootstraps.
DEFAULT_TRACKERS=(
    "udp://tracker.opentrackr.org:1337/announce"
    "udp://open.demonii.com:1337/announce"
    "udp://tracker.openbittorrent.com:6969/announce"
    "udp://exodus.desync.com:6969/announce"
    "udp://tracker.torrent.eu.org:451/announce"
)

SOURCE_DIR="out"
OUTPUT_DIR=""
PRIVATE_FLAG="false"
NO_TRACKERS="false"
COMMENT=""
PIECE_SIZE=""
declare -a CLI_TRACKERS=()

while (( $# > 0 )); do
    case "$1" in
        --output)      OUTPUT_DIR="${2:?--output needs a directory}"; shift 2 ;;
        --tracker)     CLI_TRACKERS+=("${2:?--tracker needs a URL}"); shift 2 ;;
        --no-trackers) NO_TRACKERS="true"; shift ;;
        --private)     PRIVATE_FLAG="true"; shift ;;
        --comment)     COMMENT="${2:?--comment needs text}"; shift 2 ;;
        --piece-size)  PIECE_SIZE="${2:?--piece-size needs an exponent}"; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        -*)            echo -e "${RED}Unknown option: $1${NC}" >&2; usage >&2; exit 2 ;;
        *)             ISO_FILE="$1"; shift ;;
    esac
done

# ---- Dependency -------------------------------------------------------------
if ! command -v mktorrent &> /dev/null; then
    echo -e "${RED}Error: mktorrent could not be found. Please install 'mktorrent' (pacman -S mktorrent / apt install mktorrent).${NC}" >&2
    exit 1
fi

# ---- Locate the target ISO ---------------------------------------------------
if [[ -z "${ISO_FILE:-}" ]]; then
    SOURCE_DIR="${NEOS_TORRENT_SOURCE_DIR:-$SOURCE_DIR}"
    # Newest image by mtime, not first glob match — mirrors the selection rule
    # in build.sh and the CI workflow (reports/v2026.09.18 M5).
    ISO_FILE=$(find "$SOURCE_DIR" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    if [[ -z "$ISO_FILE" ]]; then
        echo -e "${RED}Error: no ISO found in '$SOURCE_DIR'. Build one first (sudo ./build.sh) or pass an ISO_FILE.${NC}" >&2
        exit 1
    fi
fi

if [[ ! -f "$ISO_FILE" ]]; then
    echo -e "${RED}Error: ISO file not found: $ISO_FILE${NC}" >&2
    exit 1
fi

ISO_SIZE=$(stat -c%s "$ISO_FILE")
if (( ISO_SIZE == 0 )); then
    echo -e "${RED}Error: $ISO_FILE is empty — refusing to torrent a zero-byte image.${NC}" >&2
    exit 1
fi

ISO_BASENAME="${ISO_FILE##*/}"

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    TORRENT_FILE="$OUTPUT_DIR/$ISO_BASENAME.torrent"
else
    # "${var%/*}" degenerates when the path has no directory component
    # (ISO_FILE="neos.iso" would yield "neos.iso/neos.iso.torrent").
    ISO_DIR="${ISO_FILE%/*}"
    if [[ "$ISO_DIR" == "$ISO_FILE" ]]; then
        ISO_DIR="."
    fi
    TORRENT_FILE="$ISO_DIR/$ISO_BASENAME.torrent"
fi

# ---- Trackers ----------------------------------------------------------------
declare -a TRACKERS=()
if [[ "$NO_TRACKERS" == "true" ]]; then
    if (( ${#CLI_TRACKERS[@]} > 0 )); then
        echo -e "${RED}Error: --tracker and --no-trackers are mutually exclusive.${NC}" >&2
        exit 2
    fi
    echo "Trackers: none (--no-trackers, DHT-only)"
else
    if (( ${#CLI_TRACKERS[@]} > 0 )); then
        TRACKERS=("${CLI_TRACKERS[@]}")
    elif [[ -n "${NEOS_TORRENT_TRACKERS:-}" ]]; then
        # Comma and/or space separated override list.
        read -r -a TRACKERS <<< "$(echo "$NEOS_TORRENT_TRACKERS" | tr ',' ' ')"
        if (( ${#TRACKERS[@]} == 0 )); then
            echo -e "${RED}Error: NEOS_TORRENT_TRACKERS is set but contains no tracker URLs.${NC}" >&2
            exit 2
        fi
    else
        TRACKERS=("${DEFAULT_TRACKERS[@]}")
    fi
    echo "Trackers (${#TRACKERS[@]}):"
    printf '  - %s\n' "${TRACKERS[@]}"
fi

# ---- Web seeds (SourceForge) ---------------------------------------------------
declare -a WEB_SEEDS=()
if [[ -n "${SOURCEFORGE_PROJECT:-}" && -n "${NEOS_RELEASE_TAG:-}" ]]; then
    SF_BRANCH="${NEOS_RELEASE_BRANCH:-testing}"
    SF_BASE="https://downloads.sourceforge.net/project/${SOURCEFORGE_PROJECT}/${SF_BRANCH}/${NEOS_RELEASE_TAG}"
    # Both URL forms are kept as separate web seeds: downloads.sourceforge.net
    # round-robins across mirrors directly, sourceforge.net/files/.../download
    # redirects — different failure modes, so a client that cannot follow one
    # may still use the other.
    WEB_SEEDS+=(
        "${SF_BASE}/${ISO_BASENAME}"
        "https://sourceforge.net/projects/${SOURCEFORGE_PROJECT}/files/${SF_BRANCH}/${NEOS_RELEASE_TAG}/${ISO_BASENAME}/download"
    )
    echo "Web seeds (${#WEB_SEEDS[@]}):"
    printf '  - %s\n' "${WEB_SEEDS[@]}"
else
    echo "Web seeds: none (set SOURCEFORGE_PROJECT and NEOS_RELEASE_TAG to add SourceForge seeds)"
fi

# ---- Piece size ----------------------------------------------------------------
# mktorrent's fixed default is 2^18 (256 KiB), which produces a ~250 KiB
# metainfo for a 3 GiB ISO. Size-matched pieces keep the .torrent at a few
# tens of KiB while staying swappable on slow links.
if [[ -z "$PIECE_SIZE" ]]; then
    if   (( ISO_SIZE >= 4294967296 )); then PIECE_SIZE=23   # >= 4 GiB -> 8 MiB
    elif (( ISO_SIZE >= 1073741824 )); then PIECE_SIZE=22   # >= 1 GiB -> 4 MiB
    elif (( ISO_SIZE >= 268435456   )); then PIECE_SIZE=21   # >= 256 MiB -> 2 MiB
    elif (( ISO_SIZE >= 67108864    )); then PIECE_SIZE=20   # >= 64 MiB -> 1 MiB
    else PIECE_SIZE=18                                       # mktorrent default
    fi
fi
if ! [[ "$PIECE_SIZE" =~ ^1[4-9]$|^2[0-7]$ ]]; then
    echo -e "${RED}Error: --piece-size must be an integer 14..27 (got: $PIECE_SIZE).${NC}" >&2
    exit 2
fi

# ---- Comment --------------------------------------------------------------------
if [[ -z "$COMMENT" ]]; then
    COMMENT="NeOS ${ISO_BASENAME}"
fi

# ---- Build the metainfo ----------------------------------------------------------
# mktorrent 1.1 refuses to overwrite an existing output file and errors out
# when stdin is closed, so remove any previous torrent for this image first
# (regenerating is always the intent — CI re-runs this generator after
# build.sh to add the SourceForge web seeds).
rm -f "$TORRENT_FILE"

MKARGS=(-v -l "$PIECE_SIZE" -c "$COMMENT" -o "$TORRENT_FILE")
if [[ "$PRIVATE_FLAG" == "true" ]]; then
    MKARGS+=(-p)
fi
# One -a per tracker: mktorrent puts each in its own announce tier (backups).
if [[ "$NO_TRACKERS" != "true" ]]; then
    for tracker in "${TRACKERS[@]}"; do
        MKARGS+=(-a "$tracker")
    done
fi
for seed in "${WEB_SEEDS[@]}"; do
    MKARGS+=(-w "$seed")
done

echo -e "${GREEN}Generating torrent for $ISO_BASENAME ($(numfmt --to=iec --suffix=B "$ISO_SIZE" 2>/dev/null || echo "${ISO_SIZE} bytes"), piece size 2^${PIECE_SIZE})...${NC}"
mktorrent "${MKARGS[@]}" "$ISO_FILE"

if [[ ! -s "$TORRENT_FILE" ]]; then
    echo -e "${RED}Error: mktorrent did not produce $TORRENT_FILE${NC}" >&2
    exit 1
fi

TORRENT_SIZE=$(stat -c%s "$TORRENT_FILE")
echo -e "${GREEN}Torrent written: $TORRENT_FILE ($TORRENT_SIZE bytes)${NC}"
echo -e "${GREEN}Done. Seed the ISO from the same path to grow the swarm.${NC}"
