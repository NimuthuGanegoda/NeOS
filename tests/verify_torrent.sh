#!/bin/bash
# Verifies tools/gen-torrent.sh — the automatic .torrent release artifact.
#
# build.sh and the CI workflow both invoke the generator, but only a torrent
# that is actually valid keeps its swarm alive: a wrong info name or a missing
# web seed silently produces a torrent no client will fetch. This gate runs
# the generator against scratch images in a temp dir and decodes the resulting
# bencode with python3, asserting:
#   - newest-by-mtime ISO selection inside the source dir (the same rule
#     build.sh/CI use, not first-glob)
#   - announce list defaults, --tracker override, --no-trackers (DHT-only)
#   - SourceForge web seeds when SOURCEFORGE_PROJECT/NEOS_RELEASE_TAG are set
#   - info name/length/piece-size, private flag, comment field
#
# Requires mktorrent + python3. Skips with a warning when missing, unless
# REQUIRE_TOOLS=1 (CI installs both, so a missing tool must fail there).
set -euo pipefail

SCRIPT="tools/gen-torrent.sh"

echo "Verifying release torrent generator ($SCRIPT)..."

if [[ ! -f "$SCRIPT" ]]; then
    echo "[FAIL] Missing $SCRIPT"
    exit 1
fi

MISSING=()
command -v mktorrent >/dev/null 2>&1 || MISSING+=(mktorrent)
command -v python3   >/dev/null 2>&1 || MISSING+=(python3)

if (( ${#MISSING[@]} > 0 )); then
    if [[ "${REQUIRE_TOOLS:-0}" == "1" ]]; then
        echo "[FAIL] ${MISSING[*]} required (REQUIRE_TOOLS=1) but not installed — the torrent gate cannot be skipped here."
        exit 1
    fi
    echo "[WARN] ${MISSING[*]} not installed — skipping (CI runs this gate in the archlinux container)."
    exit 0
fi

WORK=$(mktemp -d /tmp/neos-torrent.XXXXXX)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ---- bencode helpers ---------------------------------------------------------
read_py() {  # read_torrent.py <torrent> <python-expr over t (dict)>
    python3 - "$1" "$2" <<'PYEOF'
import sys

def bdecode(data, i=0):
    c = data[i:i+1]
    if c == b'd':
        d, i = {}, i + 1
        while data[i:i+1] != b'e':
            k, i = bdecode(data, i)
            v, i = bdecode(data, i)
            d[k] = v
        return d, i + 1
    if c == b'l':
        l, i = [], i + 1
        while data[i:i+1] != b'e':
            v, i = bdecode(data, i)
            l.append(v)
        return l, i + 1
    if c == b'i':
        j = data.index(b'e', i)
        return int(data[i+1:j]), j + 1
    j = data.index(b':', i)
    n = int(data[i:j])
    return data[j+1:j+1+n], j + 1 + n

path, expr = sys.argv[1], sys.argv[2]
with open(path, 'rb') as fh:
    t, _ = bdecode(fh.read())
result = eval(expr, {"t": t})
print(result)
PYEOF
}

assert_eq() {  # assert_eq <desc> <actual> <expected>
    if [[ "$2" != "$3" ]]; then
        echo "[FAIL] $1"
        echo "       expected: $3"
        echo "       actual:   $2"
        exit 1
    fi
    echo "  ok: $1"
}

assert_contains() {  # assert_contains <desc> <haystack> <needle>
    if [[ "$2" != *"$3"* ]]; then
        echo "[FAIL] $1"
        echo "       '$3' not found in: $2"
        exit 1
    fi
    echo "  ok: $1"
}

# ---- scratch images: two ISOs, the NEWEST by mtime must win -------------------
mkdir -p "$WORK/src"
head -c 268435456 /dev/zero > "$WORK/src/neos-old-alpha-x86_64.iso"      # 256 MiB -> 2 MiB pieces
sleep 0.1
head -c 134217728 /dev/zero > "$WORK/src/neos-new-beta-x86_64.iso"       # 128 MiB -> 1 MiB pieces
NEWER_SIZE=$(stat -c%s "$WORK/src/neos-new-beta-x86_64.iso")

echo "Testing newest-by-mtime selection..."
OUT=$(NEOS_TORRENT_SOURCE_DIR="$WORK/src" bash "$SCRIPT" 2>&1) || {
    echo "[FAIL] generator exited non-zero in auto-select mode"
    printf '    %s\n' "$OUT"
    exit 1
}
[[ -s "$WORK/src/neos-new-beta-x86_64.iso.torrent" ]] || { echo "[FAIL] torrent not written for the newest ISO (mtime selection failed)"; exit 1; }
assert_eq "newest ISO wins (mtime, not name)" \
    "$([[ -e "$WORK/src/neos-old-alpha-x86_64.iso.torrent" ]] && echo old-torrent-exists || echo only-newest-torrent)" \
    "only-newest-torrent"

# newest = 128 MiB -> 1 MiB pieces (2^20); the older 256 MiB one would be 2 MiB
assert_eq "piece size matches auto-selection for the newest ISO" \
    "$(read_py "$WORK/src/neos-new-beta-x86_64.iso.torrent" "t[b'info'][b'piece length']")" "1048576"
assert_eq "info length matches ISO size" \
    "$(read_py "$WORK/src/neos-new-beta-x86_64.iso.torrent" "t[b'info'][b'length']")" "$NEWER_SIZE"
assert_eq "info name is the ISO basename" \
    "$(read_py "$WORK/src/neos-new-beta-x86_64.iso.torrent" "t[b'info'][b'name'].decode()")" "neos-new-beta-x86_64.iso"

echo "Testing default tracker list..."
ANNOUNCE=$(read_py "$WORK/src/neos-new-beta-x86_64.iso.torrent" \
    "b'|'.join(sum([[u] if isinstance(u, bytes) else list(u) for u in t.get(b'announce-list', [])], [])).decode()")
assert_contains "opentrackr in announce data" "$ANNOUNCE" "udp://tracker.opentrackr.org:1337/announce"
assert_contains "comment defaults to NeOS <basename>" \
    "$(read_py "$WORK/src/neos-new-beta-x86_64.iso.torrent" "t[b'comment'].decode()")" "NeOS neos-new-beta"

echo "Testing --tracker override, --output, --comment..."
bash "$SCRIPT" --output "$WORK/out" --tracker "udp://custom.example:6969/announce" \
    --comment "gate test" "$WORK/src/neos-new-beta-x86_64.iso" >/dev/null
assert_eq "override replaces the default list" \
    "$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" "t[b'announce'].decode()")" "udp://custom.example:6969/announce"
assert_eq "--comment is embedded" \
    "$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" "t[b'comment'].decode()")" "gate test"
OVERRIDE_ANNOUNCE=$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" \
    "b'|'.join(sum([[u] if isinstance(u, bytes) else list(u) for u in [t[b'announce']] + list(t.get(b'announce-list', []))], [])).decode()")
assert_contains "override tracker present in announce data" "$OVERRIDE_ANNOUNCE" "custom.example"
if [[ "$OVERRIDE_ANNOUNCE" == *opentrackr* ]]; then
    echo "[FAIL] default tracker list must NOT survive a --tracker override"
    exit 1
fi
echo "  ok: default list must NOT survive an override"

echo "Testing --no-trackers (DHT-only)..."
bash "$SCRIPT" --no-trackers --output "$WORK/out" "$WORK/src/neos-new-beta-x86_64.iso" >/dev/null
assert_eq "no announce key in DHT-only torrent" \
    "$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" "b'announce' in t")" "False"

echo "Testing --private..."
bash "$SCRIPT" --private --output "$WORK/out" "$WORK/src/neos-new-beta-x86_64.iso" >/dev/null
assert_eq "private flag set in info dict" \
    "$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" "t[b'info'].get(b'private')")" "1"

echo "Testing SourceForge web seeds via environment..."
OUT=$(SOURCEFORGE_PROJECT="neos" NEOS_RELEASE_TAG="Marlin-b42-testing" NEOS_RELEASE_BRANCH="testing" \
    bash "$SCRIPT" --output "$WORK/out" "$WORK/src/neos-new-beta-x86_64.iso" 2>&1) || {
    echo "[FAIL] generator exited non-zero with web-seed env"
    printf '    %s\n' "$OUT"
    exit 1
}
SEEDS=$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" \
    "b'|'.join(t.get(b'url-list', [])).decode()")
assert_contains "downloads.sourceforge.net web seed" "$SEEDS" \
    "https://downloads.sourceforge.net/project/neos/testing/Marlin-b42-testing/neos-new-beta-x86_64.iso"
assert_contains "sourceforge.net/files web seed" "$SEEDS" \
    "https://sourceforge.net/projects/neos/files/testing/Marlin-b42-testing/neos-new-beta-x86_64.iso/download"

echo "Testing regeneration overwrites cleanly..."
OUT=$(SOURCEFORGE_PROJECT="neos" NEOS_RELEASE_TAG="Marlin-b43-testing" \
    bash "$SCRIPT" --output "$WORK/out" "$WORK/src/neos-new-beta-x86_64.iso" 2>&1) || {
    echo "[FAIL] re-running the generator must overwrite the previous torrent (mktorrent refuses to overwrite, the wrapper must handle it)"
    printf '    %s\n' "$OUT"
    exit 1
}
assert_contains "web seed points at the NEW tag after regen" \
    "$(read_py "$WORK/out/neos-new-beta-x86_64.iso.torrent" "b'|'.join(t.get(b'url-list', [])).decode()")" \
    "Marlin-b43-testing"

echo "[PASS] tools/gen-torrent.sh: selection, trackers, web seeds, flags and regeneration all verified."
