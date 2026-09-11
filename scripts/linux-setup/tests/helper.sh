#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ./nexus-linux-setup.sh
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The archive path must be the only stdout, even with progress logging enabled.
curl() {
  local dest=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then dest="$2"; shift; fi
    shift
  done
  if [[ "$dest" == */releases.json ]]; then
    cat > "$dest" <<'JSON'
[{"tag_name":"v1","assets":[{"name":"nexus-linux-x64.tar.gz","browser_download_url":"https://example.invalid/archive"}]}]
JSON
  else touch "$dest"; fi
}
archive="$(download_official_archive "$scratch")"
[[ "$archive" == "$scratch/nexus.tar.gz" && -f "$archive" ]]
NEXUS_VERSION=v-missing
if select_release_asset "$scratch/releases.json"; then exit 1; fi
NEXUS_VERSION=""

# Test only generated configuration inside the fixture, never host services.
DROPIN_DIR="$scratch/dropins"
DESKTOP_UID=12345
DESKTOP_USER=fixture
pgrep() { return 0; }
configure_plasma_gate
[[ ! -e "$DROPIN_DIR" ]]
WAIT_FOR_PLASMA=1
configure_plasma_gate
python3 - "$DROPIN_DIR/10-wait-for-plasma.conf" <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
assert 'while [ $$i -lt 30 ]' in text
assert 'i=$$((i + 1))' in text
assert 'pgrep -u 12345' in text
assert 'done; exit 0' in text
PY

# Marked web patch is idempotent and removable without altering surrounding HTML.
BACKUP_DIR="$scratch/backups"
SHARE_DIR="$PWD/assets"
mkdir -p "$BACKUP_DIR"
printf '<html><head></head><body>fixture</body></html>\n' > "$scratch/index.html"
cp "$scratch/index.html" "$scratch/original.html"
find_nexus_index() { printf '%s\n' "$scratch/index.html"; }
apply_web_patch
cp "$scratch/index.html" "$scratch/once.html"
apply_web_patch
cmp "$scratch/index.html" "$scratch/once.html"
remove_web_patch
cmp "$scratch/index.html" "$scratch/original.html"
# Reject ordinary landscape ultrawides and ambiguous panel associations.
as_user() { printf '%s\n' "$screen_fixture"; }
kscreen-doctor() { :; }
screen_fixture='Output: 1 DP-fixture enabled connected
Geometry: 0,0 3440x1440'
if detect_y70_output; then exit 1; fi
screen_fixture='Output: 1 DP-fixture enabled connected
Geometry: 0,0 1100x3840'
[[ "$(detect_y70_output)" == $'DP-fixture\n0,0,1100,3840' ]]
curl() {
  local dest=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then dest="$2"; shift; fi
    shift
  done
  printf '%s\n' "$record_fixture" > "$dest"
}
record_fixture='[{"id":"fixture-a","capabilities":{"surface":"y70"}}]'
[[ "$(select_y70_record fixture-token)" == fixture-a ]]
record_fixture='[{"id":"fixture-a","capabilities":{"surface":"y70"}},{"id":"fixture-b","capabilities":{"surface":"y70"}}]'
if select_y70_record fixture-token; then exit 1; fi
echo 'helper fixture tests passed'
