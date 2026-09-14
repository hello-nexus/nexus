#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
ORIGINAL_ARGS=("$@")
PROJECT="nexus-linux-setup"
OFFICIAL_REPO="hello-nexus/nexus"
NEXUS_URL="http://localhost:9400"
STATE_DIR="/etc/${PROJECT}"
STATE_FILE="${STATE_DIR}/state.env"
BACKUP_DIR="${STATE_DIR}/backups"
SHARE_DIR="/usr/local/share/${PROJECT}"
LIBEXEC="/usr/local/libexec/${PROJECT}"
DROPIN_DIR="/etc/systemd/system/nexus.service.d"

NO_Y70=0
WAIT_FOR_PLASMA=0
FORCE_UPDATE=0
PURGE_NEXUS=0
NEXUS_VERSION=""
LOCAL_ARCHIVE=""
QUIET=0

log(){ [[ "$QUIET" -eq 1 ]] || printf '[%s] %s\n' "$PROJECT" "$*" >&2; }
warn(){ printf '[%s] WARNING: %s\n' "$PROJECT" "$*" >&2; }
die(){ printf '[%s] ERROR: %s\n' "$PROJECT" "$*" >&2; exit 1; }

usage(){
cat <<'EOF'
Nexus Linux Setup Helper (unofficial)

Usage:
  ./nexus-linux-setup.sh install [options]
  ./nexus-linux-setup.sh repair [options]
  ./nexus-linux-setup.sh doctor
  ./nexus-linux-setup.sh status
  ./nexus-linux-setup.sh uninstall [--purge-nexus]

Options:
  --version TAG       Install a specific official Nexus release tag.
  --archive FILE      Install from an already-downloaded official Linux tarball.
  --update            Re-run the official installer/update path.
  --no-y70            Skip Y70-specific integration.
  --wait-for-plasma   Opt in to a bounded (30s) tray startup workaround.
  --purge-nexus       With uninstall, also invoke Nexus's own uninstaller if found.
  --quiet             Reduce normal output.

Environment overrides:
  NEXUS_SETUP_USER    Desktop user to configure.
  NEXUS_PANEL_ID      Existing Y70 panel record ID.
  NEXUS_CHROME        Chrome/Chromium executable.

The helper never changes KScreen resolution, scale, rotation, or monitor layout.
It never writes PWM values itself and never stores a Nexus bearer token in a
systemd unit or state file.
EOF
}

need_root(){
  if [[ "$EUID" -ne 0 ]]; then
    local u="${NEXUS_SETUP_USER:-${USER:-}}"
    exec sudo -E env NEXUS_SETUP_USER="$u" "$0" "${ORIGINAL_ARGS[@]}"
  fi
}

detect_desktop_user(){
  if [[ -n "${NEXUS_SETUP_USER:-}" ]] && id "$NEXUS_SETUP_USER" >/dev/null 2>&1; then
    printf '%s\n' "$NEXUS_SETUP_USER"; return
  fi
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] && id "$SUDO_USER" >/dev/null 2>&1; then
    printf '%s\n' "$SUDO_USER"; return
  fi
  local p uid u
  p="$(pgrep -o -x plasmashell 2>/dev/null || true)"
  if [[ -n "$p" ]]; then
    uid="$(stat -c '%u' "/proc/$p" 2>/dev/null || true)"
    u="$(getent passwd "$uid" | cut -d: -f1)"
    [[ -n "$u" ]] && { printf '%s\n' "$u"; return; }
  fi
  die "Could not determine the desktop user. Set NEXUS_SETUP_USER=<username>."
}

init_user(){
  DESKTOP_USER="$(detect_desktop_user)"
  DESKTOP_UID="$(id -u "$DESKTOP_USER")"
  DESKTOP_GID="$(id -g "$DESKTOP_USER")"
  DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"
  USER_RUNTIME="/run/user/${DESKTOP_UID}"
  USER_BUS="unix:path=${USER_RUNTIME}/bus"
  USER_ENV=("HOME=$DESKTOP_HOME" "USER=$DESKTOP_USER" "LOGNAME=$DESKTOP_USER" "XDG_RUNTIME_DIR=$USER_RUNTIME" "DBUS_SESSION_BUS_ADDRESS=$USER_BUS")

  local p kv
  p="$(pgrep -u "$DESKTOP_UID" -o -x plasmashell 2>/dev/null || true)"
  if [[ -n "$p" && -r "/proc/$p/environ" ]]; then
    while IFS= read -r kv; do
      case "$kv" in
        DISPLAY=*|WAYLAND_DISPLAY=*|XDG_CURRENT_DESKTOP=*|XDG_SESSION_DESKTOP=*|XDG_SESSION_TYPE=*) USER_ENV+=("$kv") ;;
      esac
    done < <(tr '\0' '\n' < "/proc/$p/environ")
  fi
}

as_user(){ sudo -u "$DESKTOP_USER" env "${USER_ENV[@]}" "$@"; }

ensure_dirs(){
  install -d -m 0700 "$STATE_DIR" "$BACKUP_DIR"
  install -d -m 0755 "$SHARE_DIR" "$(dirname "$LIBEXEC")"
}

backup_file(){
  local f="$1" sha out
  [[ -f "$f" ]] || return 0
  sha="$(sha256sum "$f" | awk '{print $1}')"
  out="${BACKUP_DIR}/$(basename "$f").${sha}"
  [[ -e "$out" ]] || cp -a "$f" "$out"
}

save_state(){
  local t; t="$(mktemp)"
  {
    printf 'DESKTOP_USER=%q\n' "$DESKTOP_USER"
    printf 'DESKTOP_UID=%q\n' "$DESKTOP_UID"
    printf 'DESKTOP_HOME=%q\n' "$DESKTOP_HOME"
    printf 'PANEL_ID=%q\n' "${PANEL_ID:-}"
    printf 'Y70_OUTPUT=%q\n' "${Y70_OUTPUT:-}"
    printf 'Y70_GEOMETRY=%q\n' "${Y70_GEOMETRY:-}"
    printf 'CHROME_BIN=%q\n' "${CHROME_BIN:-}"
    printf 'KIOSK_PROFILE=%q\n' "${KIOSK_PROFILE:-}"
    printf 'FAN_MODULE=%q\n' "${FAN_MODULE:-}"
  } > "$t"
  install -m 0600 "$t" "$STATE_FILE"
  rm -f "$t"
}

load_state(){ [[ -r "$STATE_FILE" ]] && source "$STATE_FILE" || true; }

install_self(){
  install -m 0755 "${BASH_SOURCE[0]}" "$LIBEXEC"
  local asset="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/assets/simulator-fix.js"
  if [[ -f "$asset" ]]; then
    install -m 0644 "$asset" "$SHARE_DIR/simulator-fix.js"
  elif [[ ! -f "$SHARE_DIR/simulator-fix.js" ]]; then
    die "Missing assets/simulator-fix.js"
  fi
}

nexus_installed(){ [[ -x /opt/nexus/Nexus ]] && systemctl cat nexus.service >/dev/null 2>&1; }

select_release_asset(){
  local jsonfile="$1"
  python3 - "$jsonfile" "$NEXUS_VERSION" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2].strip()
with open(path, encoding='utf-8') as f:
    releases=json.load(f)
for rel in releases:
    if rel.get('draft'): continue
    tag=rel.get('tag_name','')
    if wanted and tag != wanted: continue
    for a in rel.get('assets',[]):
        name=a.get('name',''); low=name.lower()
        if not low.endswith(('.tar.gz','.tgz')): continue
        if 'linux' not in low: continue
        if not any(x in low for x in ('x64','x86_64','amd64')): continue
        if any(x in low for x in ('sha256','checksum','symbols','debug')): continue
        print(tag); print(name); print(a['browser_download_url']); raise SystemExit(0)
raise SystemExit(2)
PY
}

download_official_archive(){
  local tmp="$1"
  if [[ -n "$LOCAL_ARCHIVE" ]]; then
    [[ -f "$LOCAL_ARCHIVE" ]] || die "Archive not found: $LOCAL_ARCHIVE"
    cp -a "$LOCAL_ARCHIVE" "$tmp/nexus.tar.gz"
    printf '%s\n' "$tmp/nexus.tar.gz"; return
  fi
  command -v curl >/dev/null || die "curl is required"
  command -v python3 >/dev/null || die "python3 is required"
  log "Querying official ${OFFICIAL_REPO} releases..."
  curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' -H 'User-Agent: nexus-linux-setup' \
    "https://api.github.com/repos/${OFFICIAL_REPO}/releases?per_page=20" -o "$tmp/releases.json" \
    || die "Could not query official GitHub releases"
  local selection tag name url
  selection="$(select_release_asset "$tmp/releases.json")" || die "No matching Linux x86-64 release archive found"
  tag="$(sed -n '1p' <<<"$selection")"; name="$(sed -n '2p' <<<"$selection")"; url="$(sed -n '3p' <<<"$selection")"
  log "Downloading official Nexus ${tag}: ${name}"
  curl -fL --retry 3 --progress-bar "$url" -o "$tmp/nexus.tar.gz"
  printf '%s\n' "$tmp/nexus.tar.gz"
}

install_official_nexus(){
  if nexus_installed && [[ "$FORCE_UPDATE" -eq 0 && -z "$LOCAL_ARCHIVE" && -z "$NEXUS_VERSION" ]]; then
    log "Nexus is already installed; keeping the official installation."
    return
  fi
  local tmp archive installer
  tmp="$(mktemp -d)"
  archive="$(download_official_archive "$tmp")"
  mkdir -p "$tmp/extract"
  tar -xzf "$archive" -C "$tmp/extract"
  installer="$(find "$tmp/extract" -type f -name install.sh -print | head -1)"
  [[ -n "$installer" ]] || { rm -rf "$tmp"; die "Official archive contained no install.sh; refusing to invent an install layout."; }
  log "Running the official Nexus installer..."
  (cd "$(dirname "$installer")" && bash "./$(basename "$installer")")
  rm -rf "$tmp"
  systemctl daemon-reload
  nexus_installed || die "Official installer finished, but Nexus was not found under /opt/nexus or nexus.service is missing."
}

stop_nexus(){
  systemctl stop nexus.service >/dev/null 2>&1 &
  local p=$!
  for _ in {1..10}; do
    systemctl is-active --quiet nexus.service || { wait "$p" 2>/dev/null || true; return 0; }
    sleep 1
  done
  systemctl kill --kill-whom=all --signal=SIGKILL nexus.service >/dev/null 2>&1 || true
  wait "$p" 2>/dev/null || true
}

restart_nexus(){ stop_nexus; systemctl reset-failed nexus.service >/dev/null 2>&1 || true; systemctl start nexus.service; }

wait_http(){
  local max="${1:-45}"
  for ((i=0;i<max;i++)); do curl -fsS --max-time 1 "$NEXUS_URL/" >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}

configure_plasma_gate(){
  [[ "$WAIT_FOR_PLASMA" -eq 1 ]] || return 0
  if ! pgrep -u "$DESKTOP_UID" -x plasmashell >/dev/null 2>&1; then
    warn "Plasma is not running for $DESKTOP_USER; tray startup workaround skipped."
    return 0
  fi
  install -d -m 0755 "$DROPIN_DIR"
  cat > "$DROPIN_DIR/10-wait-for-plasma.conf" <<EOF
# Managed by nexus-linux-setup. Nexus currently adopts the graphical user
# session at startup; on Plasma, starting before plasmashell can leave no tray.
[Service]
ExecStartPre=/bin/sh -c 'i=0; while [ \$\$i -lt 30 ]; do i=\$\$((i + 1)); pgrep -u ${DESKTOP_UID} -x plasmashell >/dev/null 2>&1 && exit 0; sleep 1; done; exit 0'
EOF
  log "Configured Nexus to wait up to 30 seconds for Plasma user ${DESKTOP_USER} (UID ${DESKTOP_UID})."
}

find_nct_pwm(){
  local h n
  for h in /sys/class/hwmon/hwmon*; do
    [[ -r "$h/name" ]] || continue
    n="$(cat "$h/name" 2>/dev/null || true)"
    case "$n" in
      nct6775|nct6776|nct6779|nct6791|nct6792|nct6793|nct6795|nct6796|nct6797|nct6798|nct6799)
        compgen -G "$h/pwm[0-9]" >/dev/null && { printf '%s\n' "$h"; return 0; }
        ;;
    esac
  done
  return 1
}

configure_fans(){
  FAN_MODULE=""
  modinfo nct6775 >/dev/null 2>&1 || { log "nct6775 is unavailable; leaving fan discovery to Nexus/kernel defaults."; return 0; }
  modprobe nct6775 >/dev/null 2>&1 || { warn "nct6775 exists but could not be loaded."; return 0; }
  sleep 1
  local h; h="$(find_nct_pwm || true)"
  [[ -n "$h" ]] || { log "nct6775 exposed no supported PWM hwmon controller; not persisting it."; return 0; }
  FAN_MODULE="nct6775"
  printf 'nct6775\n' > /etc/modules-load.d/nexus-fans.conf
  install -d -m 0755 "$DROPIN_DIR"
  cat > "$DROPIN_DIR/20-nct6775.conf" <<'EOF'
# Managed by nexus-linux-setup. Makes motherboard PWM channels available before
# Nexus performs cooling enumeration. Discovery only; Nexus owns fan policy.
[Service]
ExecStartPre=/sbin/modprobe nct6775
EOF
  log "Detected $(cat "$h/name") PWM controller; nct6775 will be available before Nexus starts."
}

find_nexus_index(){
  local a=() f
  while IFS= read -r -d '' f; do
    grep -qE 'assets/index-[A-Za-z0-9_-]+\.js' "$f" 2>/dev/null && a+=("$f")
  done < <(find /opt/nexus -type f -name index.html -print0 2>/dev/null)
  if [[ ${#a[@]} -ne 1 ]]; then warn "Expected one Nexus web index.html; found ${#a[@]}."; return 1; fi
  printf '%s\n' "${a[0]}"
}

apply_web_patch(){
  local idx js marker='<!-- BEGIN nexus-linux-setup simulator fix -->'
  idx="$(find_nexus_index || true)"; [[ -n "$idx" ]] || return 0
  js="$SHARE_DIR/simulator-fix.js"; [[ -r "$js" ]] || return 0
  backup_file "$idx"
  # Migrate the one-off local patch used during diagnosis so we never run two
  # simulator shims at once.
  INDEX="$idx" python3 <<'PYLEGACY'
from pathlib import Path
import os,re
p=Path(os.environ['INDEX']); t=p.read_text(encoding='utf-8')
pat=re.compile(r'<!-- BEGIN nexus-y70-local-simulator-fix -->.*?<!-- END nexus-y70-local-simulator-fix -->\s*',re.S)
n,c=pat.subn('',t,count=1)
if c: p.write_text(n,encoding='utf-8')
PYLEGACY
  grep -Fq "$marker" "$idx" && return 0
  INDEX="$idx" JSFILE="$js" python3 <<'PY'
from pathlib import Path
import os
p=Path(os.environ['INDEX']); js=Path(os.environ['JSFILE']).read_text(encoding='utf-8')
text=p.read_text(encoding='utf-8')
b='<!-- BEGIN nexus-linux-setup simulator fix -->'; e='<!-- END nexus-linux-setup simulator fix -->'
block=f'{b}\n<script id="nexus-linux-setup-simulator-fix">\n{js}\n</script>\n{e}\n'
if b in text: raise SystemExit(0)
needle='</head>' if '</head>' in text else '</body>'
if needle not in text: raise SystemExit('Nexus index has neither </head> nor </body>')
p.write_text(text.replace(needle, block+needle, 1), encoding='utf-8')
PY
  log "Applied reversible local Y70 simulator handshake workaround."
}

remove_web_patch(){
  local idx; idx="$(find_nexus_index || true)"; [[ -n "$idx" ]] || return 0
  INDEX="$idx" python3 <<'PY'
from pathlib import Path
import os,re
p=Path(os.environ['INDEX']); t=p.read_text(encoding='utf-8')
pat=re.compile(r'<!-- BEGIN nexus-linux-setup simulator fix -->.*?<!-- END nexus-linux-setup simulator fix -->\s*',re.S)
n,c=pat.subn('',t,count=1)
if c: p.write_text(n,encoding='utf-8')
PY
}

configure_web_patch(){
  install -d -m 0755 "$DROPIN_DIR"
  cat > "$DROPIN_DIR/15-y70-simulator.conf" <<EOF
# Managed by nexus-linux-setup. Official updates can replace wwwroot/index.html,
# so reapply the marked/reversible local workaround before service start.
[Service]
ExecStartPre=${LIBEXEC} internal-apply-web-patch
EOF
  apply_web_patch
}

settings_file(){ local f="$DESKTOP_HOME/.config/Nexus/settings.json"; [[ -f "$f" ]] && printf '%s\n' "$f"; }

set_auto_launch(){
  local val="$1" f; f="$(settings_file || true)"; [[ -n "$f" ]] || return 1
  backup_file "$f"
  FILE="$f" VALUE="$val" python3 <<'PY'
from pathlib import Path
import json,os
p=Path(os.environ['FILE']); data=json.loads(p.read_text(encoding='utf-8'))
data.setdefault('panel',{})['autoLaunch']=os.environ['VALUE'].lower()=='true'
p.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
PY
  chown "$DESKTOP_UID:$DESKTOP_GID" "$f" 2>/dev/null || true
}

detect_existing_panel_id(){
  [[ -n "${NEXUS_PANEL_ID:-}" ]] && { printf '%s\n' "$NEXUS_PANEL_ID"; return; }
  [[ -n "${PANEL_ID:-}" ]] && { printf '%s\n' "$PANEL_ID"; return; }
  local u="$DESKTOP_HOME/.config/systemd/user/nexus-y70-direct.service" launcher="$DESKTOP_HOME/.local/bin/nexus-y70-direct" id pid cmd
  if [[ -r "$u" ]]; then
    id="$(grep -oE '/panel/[A-Za-z0-9_-]+' "$u" | head -1 | cut -d/ -f3 || true)"
    case "$id" in ''|phone|q60|devices) ;; *) printf '%s\n' "$id"; return ;; esac
  fi
  if [[ -r "$launcher" ]]; then
    id="$(grep -oE '/panel/[A-Za-z0-9_-]+' "$launcher" | head -1 | cut -d/ -f3 || true)"
    case "$id" in ''|phone|q60|devices) ;; *) printf '%s\n' "$id"; return ;; esac
  fi
  for pid in /proc/[0-9]*; do
    [[ "$(stat -c %u "$pid" 2>/dev/null || echo x)" == "$DESKTOP_UID" ]] || continue
    [[ -r "$pid/cmdline" ]] || continue
    cmd="$(tr '\0' ' ' < "$pid/cmdline" 2>/dev/null || true)"
    if [[ "$cmd" =~ localhost:9400/panel/([A-Za-z0-9_-]+) ]]; then
      id="${BASH_REMATCH[1]}"; case "$id" in phone|q60|devices) ;; *) printf '%s\n' "$id"; return ;; esac
    fi
  done
  return 1
}

capture_kiosk_token(){
  local end=$((SECONDS+40)) pid cmd url token
  while (( SECONDS < end )); do
    for pid in /proc/[0-9]*; do
      [[ "$(stat -c %u "$pid" 2>/dev/null || echo x)" == "$DESKTOP_UID" ]] || continue
      [[ -r "$pid/cmdline" ]] || continue
      cmd="$(tr '\0' ' ' < "$pid/cmdline" 2>/dev/null || true)"
      [[ "$cmd" == *"localhost:9400/panel"*"?token="* ]] || continue
      url="$(grep -oE 'http://localhost:9400/panel[^ ]*\?token=[^ ]+' <<<"$cmd" | head -1 || true)"
      [[ -n "$url" ]] || continue
      token="$(URL="$url" python3 - <<'PY'
import os,urllib.parse
u=urllib.parse.urlsplit(os.environ['URL']); print(urllib.parse.parse_qs(u.query).get('token',[''])[0])
PY
)"
      [[ -n "$token" ]] && { printf '%s\n' "$token"; return 0; }
    done
    sleep 1
  done
  return 1
}

select_y70_record(){
  local token="$1" data tmp
  tmp="$(mktemp)"
  curl -fsS -H "Authorization: Bearer ${token}" "$NEXUS_URL/panel/devices" -o "$tmp" || { rm -f "$tmp"; return 1; }
  python3 - "$tmp" <<'PY'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: x=json.load(f)
d=x.get('devices',[]) if isinstance(x,dict) else x
c=[]
for r in d if isinstance(d,list) else []:
    if not isinstance(r,dict): continue
    cap=r.get('capabilities') or {}
    if cap.get('surface')!='y70': continue
    w,h=cap.get('cssWidth') or 0,cap.get('cssHeight') or 0
    ar=max(w,h)/max(1,min(w,h)) if w and h else 0
    score=(3 if ar>=2.5 else 0)+(2 if 'y70' in (r.get('displayName') or '').lower() else 0)+(1 if not r.get('displayId') else 0)
    c.append((score,r.get('lastSeenAt') or '',r.get('id') or ''))
if not c: raise SystemExit(2)
if len(c) != 1: raise SystemExit('Multiple Y70 records; set NEXUS_PANEL_ID explicitly')
print(c[0][2])
PY
  local rc=$?; rm -f "$tmp"; return "$rc"
}

find_chrome(){
  if [[ -n "${NEXUS_CHROME:-}" && -x "$NEXUS_CHROME" ]]; then printf '%s\n' "$NEXUS_CHROME"; return; fi
  local c; for c in /opt/google/chrome/chrome /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium /usr/bin/chromium-browser; do [[ -x "$c" ]] && { printf '%s\n' "$c"; return; }; done
  return 1
}

detect_y70_output(){
  command -v kscreen-doctor >/dev/null 2>&1 || return 1
  local tmp; tmp="$(mktemp)"; as_user kscreen-doctor -o > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  python3 - "$tmp" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); starts=[m.start() for m in re.finditer(r'(?m)^Output:',s)]
c=[]
for i,p in enumerate(starts):
    b=s[p: starts[i+1] if i+1<len(starts) else len(s)]
    m=re.search(r'^Output:\s*(?:\d+\s+)?(\S+)',b,re.M); g=re.search(r'Geometry:\s*(-?\d+),(-?\d+)\s+(\d+)x(\d+)',b)
    if not m or not g: continue
    name=m.group(1); x,y,w,h=map(int,g.groups()); native='3840x1100' in b; tall=h/max(1,w)>=2.5
    if native or tall: c.append((2 if native else 1,name,x,y,w,h))
if not c: raise SystemExit(2)
c.sort(reverse=True)
if len(c)>1 and c[0][0]==c[1][0]: raise SystemExit(3)
_,n,x,y,w,h=c[0]; print(n); print(f'{x},{y},{w},{h}')
PY
  local rc=$?; rm -f "$tmp"; return "$rc"
}

existing_profile(){
  local u="$DESKTOP_HOME/.config/systemd/user/nexus-y70-direct.service" launcher="$DESKTOP_HOME/.local/bin/nexus-y70-direct" p=""
  if [[ -r "$u" ]]; then p="$(grep -oE -- '--user-data-dir=[^[:space:]]+' "$u" | head -1 | cut -d= -f2- || true)"; fi
  if [[ -z "$p" && -r "$launcher" ]]; then p="$(grep -oE -- '--user-data-dir=[^[:space:]]+' "$launcher" | head -1 | cut -d= -f2- || true)"; fi
  [[ -n "$p" ]] && { printf '%s\n' "$p"; return 0; }
  [[ -n "${KIOSK_PROFILE:-}" ]] && { printf '%s\n' "$KIOSK_PROFILE"; return 0; }
  return 1
}

kill_generic_kiosks(){
  local pid cmd
  for pid in /proc/[0-9]*; do
    [[ "$(stat -c %u "$pid" 2>/dev/null || echo x)" == "$DESKTOP_UID" ]] || continue
    [[ -r "$pid/cmdline" ]] || continue
    cmd="$(tr '\0' ' ' < "$pid/cmdline" 2>/dev/null || true)"
    if [[ "$cmd" == *"--app=http://localhost:9400/panel"* ]] && [[ "$cmd" == *"--kiosk"* ]]; then kill "${pid#/proc/}" 2>/dev/null || true; fi
  done
}

write_kwin_script(){
  local dir="$DESKTOP_HOME/.local/share/kwin/scripts/nexus-y70-placement"
  install -d -o "$DESKTOP_UID" -g "$DESKTOP_GID" -m 0755 "$dir/contents/code"
  cat > "$dir/metadata.json" <<'EOF'
{
  "KPlugin": {
    "Id": "nexus-y70-placement",
    "Name": "Nexus Y70 placement",
    "Description": "Keeps the managed Nexus Y70 kiosk on its existing output",
    "Version": "1.0.0",
    "License": "MIT"
  },
  "X-Plasma-API": "javascript",
  "X-Plasma-MainScript": "code/main.js"
}
EOF
  cat > "$dir/contents/code/main.js" <<EOF
// Managed by nexus-linux-setup. KWin 6.
const TARGET_OUTPUT = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$Y70_OUTPUT");
const PANEL_ID = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PANEL_ID");
const EXPECTED_CLASS = "chrome-localhost__panel_" + PANEL_ID + "-Default";
function targetOutput() { return workspace.screens.find(o => o.name === TARGET_OUTPUT) || null; }
function matches(w) { return String(w.resourceClass || "") === EXPECTED_CLASS || String(w.resourceName || "") === EXPECTED_CLASS; }
function place(w) {
  if (!matches(w)) return;
  const out = targetOutput(); if (!out) return;
  try { w.fullScreen = false; } catch (_) {}
  try { workspace.sendClientToScreen(w, out); } catch (_) {}
  const g = out.geometry;
  try { w.frameGeometry = Qt.rect(g.x, g.y, g.width, g.height); } catch (_) {}
  try { w.noBorder = true; } catch (_) {}
  try { w.skipTaskbar = true; } catch (_) {}
  try { w.skipPager = true; } catch (_) {}
  try { w.skipSwitcher = true; } catch (_) {}
  try { w.fullScreen = true; } catch (_) {}
}
function attach(w) {
  if (!matches(w)) return; place(w);
  try { w.outputChanged.connect(() => place(w)); } catch (_) {}
  try { w.windowClassChanged.connect(() => place(w)); } catch (_) {}
}
workspace.stackingOrder.forEach(attach);
workspace.windowAdded.connect(attach);
workspace.screensChanged.connect(() => workspace.stackingOrder.forEach(place));
EOF
  chown -R "$DESKTOP_UID:$DESKTOP_GID" "$dir"
  command -v kwriteconfig6 >/dev/null 2>&1 && as_user kwriteconfig6 --file kwinrc --group Plugins --key nexus-y70-placementEnabled true || true
  command -v qdbus6 >/dev/null 2>&1 && as_user qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  log "Installed KWin placement helper for Y70 output $Y70_OUTPUT."
}

seed_profile(){
  local token="$1"
  install -d -o "$DESKTOP_UID" -g "$DESKTOP_GID" "$KIOSK_PROFILE"
  log "Seeding dedicated Y70 Chrome profile once (token is not written to a unit or state file)..."
  as_user "$CHROME_BIN" --ozone-platform=wayland --app="$NEXUS_URL/panel/$PANEL_ID?token=$token" --kiosk --password-store=basic --no-first-run --noerrdialogs --disable-session-crashed-bubble --user-data-dir="$KIOSK_PROFILE" >/dev/null 2>&1 &
  local p=$!; sleep 6; kill "$p" 2>/dev/null || true; sleep 1
  touch "$KIOSK_PROFILE/.nexus-linux-setup-seeded"; chown "$DESKTOP_UID:$DESKTOP_GID" "$KIOSK_PROFILE/.nexus-linux-setup-seeded"
}

write_y70_service(){
  local bindir="$DESKTOP_HOME/.local/bin" unitdir="$DESKTOP_HOME/.config/systemd/user" bin="$DESKTOP_HOME/.local/bin/nexus-y70-direct"
  install -d -o "$DESKTOP_UID" -g "$DESKTOP_GID" -m 0755 "$bindir" "$unitdir"
  cat > "$bin" <<EOF
#!/usr/bin/env bash
set -euo pipefail
for _ in {1..60}; do
  curl -fsS --max-time 1 http://localhost:9400/ >/dev/null 2>&1 && break
  sleep 1
done
exec $(printf '%q' "$CHROME_BIN") \\
  --ozone-platform=wayland \\
  --app="http://localhost:9400/panel/$PANEL_ID" \\
  --kiosk \\
  --password-store=basic \\
  --no-first-run \\
  --noerrdialogs \\
  --disable-session-crashed-bubble \\
  --user-data-dir=$(printf '%q' "$KIOSK_PROFILE")
EOF
  chmod 0755 "$bin"; chown "$DESKTOP_UID:$DESKTOP_GID" "$bin"
  cat > "$unitdir/nexus-y70-direct.service" <<EOF
[Unit]
Description=Nexus direct Y70 panel
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart="${bin//%/%%}"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
  chown "$DESKTOP_UID:$DESKTOP_GID" "$unitdir/nexus-y70-direct.service"
  as_user systemctl --user daemon-reload
  as_user systemctl --user enable nexus-y70-direct.service >/dev/null
}

configure_y70(){
  [[ "$NO_Y70" -eq 0 ]] || { log "Y70 integration skipped."; return 0; }
  pgrep -u "$DESKTOP_UID" -x plasmashell >/dev/null 2>&1 || { warn "No active Plasma session; Y70 setup skipped for now. Run repair after login."; return 0; }
  local det profile token=""
  det="$(detect_y70_output || true)"; [[ -n "$det" ]] || { warn "No unambiguous Y70-shaped KScreen output found; not guessing."; return 0; }
  Y70_OUTPUT="$(sed -n '1p' <<<"$det")"; Y70_GEOMETRY="$(sed -n '2p' <<<"$det")"
  log "Detected Y70 output $Y70_OUTPUT at $Y70_GEOMETRY; KScreen settings will not be changed."

  PANEL_ID="$(detect_existing_panel_id || true)"
  profile="$(existing_profile || true)"

  if [[ -z "$PANEL_ID" ]]; then
    log "No existing direct panel record found; bootstrapping from Nexus's own authenticated kiosk."
    set_auto_launch true || { warn "Nexus settings.json not ready; open Nexus once, finish onboarding, then rerun repair."; return 0; }
    restart_nexus; wait_http 45 || die "Nexus did not become reachable"
    token="$(capture_kiosk_token || true)"; [[ -n "$token" ]] || die "Could not obtain the one-time local kiosk token. Open Nexus once and rerun repair."
    PANEL_ID="$(select_y70_record "$token" || true)"; [[ -n "$PANEL_ID" ]] || die "Could not select a Y70 panel record from Nexus."
  else
    log "Using existing Y70 panel record $PANEL_ID."
  fi

  [[ "$PANEL_ID" =~ ^[A-Za-z0-9_-]+$ ]] || die "Invalid panel record ID"

  CHROME_BIN="$(find_chrome || true)"; [[ -n "$CHROME_BIN" ]] || die "Chrome/Chromium executable not found"
  if [[ -n "$profile" && -d "$profile" ]]; then KIOSK_PROFILE="$profile"; else KIOSK_PROFILE="$DESKTOP_HOME/nexus-kiosk/y70-direct"; fi

  write_kwin_script
  set_auto_launch false || die "Could not disable Nexus generic panel auto-launch"
  kill_generic_kiosks

  if [[ ! -e "$KIOSK_PROFILE/.nexus-linux-setup-seeded" && -z "$profile" ]]; then
    if [[ -z "$token" ]]; then
      set_auto_launch true || true; restart_nexus; wait_http 30 || true
      token="$(capture_kiosk_token || true)"
      set_auto_launch false || true; kill_generic_kiosks
    fi
    [[ -n "$token" ]] || die "Could not seed the dedicated Y70 profile without a one-time local token"
    seed_profile "$token"
  fi

  configure_web_patch
  write_y70_service
  as_user systemctl --user restart nexus-y70-direct.service
  token=""
  log "Persistent direct Y70 kiosk configured at /panel/$PANEL_ID using localhost."
}

doctor_line(){ printf '%-6s %-27s %s\n' "$1" "$2" "$3"; }

doctor(){
  init_user; load_state; local fail=0 h idx id l
  systemctl is-active --quiet nexus.service && doctor_line PASS "Nexus service" active || { doctor_line FAIL "Nexus service" inactive; fail=1; }
  curl -fsS --max-time 2 "$NEXUS_URL/" >/dev/null 2>&1 && doctor_line PASS "Nexus dashboard" localhost:9400 || { doctor_line FAIL "Nexus dashboard" unreachable; fail=1; }

  if pgrep -u "$DESKTOP_UID" -x plasmashell >/dev/null 2>&1; then
    [[ -f "$DROPIN_DIR/10-wait-for-plasma.conf" ]] && doctor_line PASS "Plasma/tray startup" "gate installed" || doctor_line WARN "Plasma/tray startup" "gate absent"
  else doctor_line WARN "Plasma/tray startup" "plasmashell not running"; fi

  h="$(find_nct_pwm || true)"
  if [[ -n "$h" ]]; then doctor_line PASS "Motherboard PWM" "$(cat "$h/name") exposed"; else doctor_line WARN "Motherboard PWM" "no supported NCT PWM hwmon found"; fi
  l="$(journalctl -u nexus -b --no-pager 2>/dev/null | grep -E '\[Motherboard\].*Fans channels=[1-9]' | tail -1 || true)"
  [[ -n "$l" ]] && doctor_line PASS "Nexus fan enumeration" "${l##*: }" || doctor_line WARN "Nexus fan enumeration" "no motherboard fan line this boot"

  idx="$(find_nexus_index || true)"
  [[ -n "$idx" ]] && grep -Fq '<!-- BEGIN nexus-linux-setup simulator fix -->' "$idx" && doctor_line PASS "Y70 simulator patch" installed || doctor_line WARN "Y70 simulator patch" absent

  id="${PANEL_ID:-}"; [[ -n "$id" ]] || id="$(detect_existing_panel_id || true)"
  if [[ -n "$id" ]]; then
    as_user systemctl --user is-active --quiet nexus-y70-direct.service && doctor_line PASS "Y70 direct service" "active ($id)" || { doctor_line FAIL "Y70 direct service" "inactive ($id)"; fail=1; }
    pgrep -u "$DESKTOP_UID" -af chrome 2>/dev/null | grep -Fq "localhost:9400/panel/$id" && doctor_line PASS "Y70 direct kiosk" "correct direct route" || doctor_line WARN "Y70 direct kiosk" "route not found in Chrome process list"
  else doctor_line WARN "Y70 direct service" "not configured"; fi

  journalctl -u nexus -b --no-pager 2>/dev/null | grep -qiE 'lighting|openrgb' && doctor_line PASS "Lighting subsystem" "journal activity present" || doctor_line WARN "Lighting subsystem" "no lighting/OpenRGB journal match"
  return "$fail"
}

status_cmd(){
  init_user; load_state
  printf '%s %s\n' "$PROJECT" "$VERSION"
  printf 'desktop user: %s (%s)\n' "$DESKTOP_USER" "$DESKTOP_UID"
  printf 'panel id: %s\n' "${PANEL_ID:-not set}"
  printf 'Y70 output: %s\n' "${Y70_OUTPUT:-not set}"
  printf 'fan module: %s\n' "${FAN_MODULE:-not set}"
  doctor || true
}

install_all(){
  need_root install
  init_user; ensure_dirs; install_self; install_official_nexus
  configure_plasma_gate; configure_fans
  systemctl daemon-reload; restart_nexus; wait_http 45 || die "Nexus did not become reachable after setup"
  configure_y70; save_state
  log "Installation/setup complete."; doctor
}

repair_all(){
  need_root repair
  init_user; ensure_dirs; load_state; install_self
  nexus_installed || die "Nexus is not installed; use install"
  configure_plasma_gate; configure_fans
  systemctl daemon-reload; restart_nexus; wait_http 45 || die "Nexus did not become reachable after repair"
  configure_y70; save_state
  log "Repair complete."; doctor
}

uninstall_integration(){
  need_root uninstall
  init_user; load_state
  as_user systemctl --user disable --now nexus-y70-direct.service >/dev/null 2>&1 || true
  rm -f "$DESKTOP_HOME/.config/systemd/user/nexus-y70-direct.service" "$DESKTOP_HOME/.local/bin/nexus-y70-direct"
  as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
  rm -rf "$DESKTOP_HOME/.local/share/kwin/scripts/nexus-y70-placement"
  command -v kwriteconfig6 >/dev/null 2>&1 && as_user kwriteconfig6 --file kwinrc --group Plugins --delete nexus-y70-placementEnabled >/dev/null 2>&1 || true
  command -v qdbus6 >/dev/null 2>&1 && as_user qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  remove_web_patch
  rm -f "$DROPIN_DIR/10-wait-for-plasma.conf" "$DROPIN_DIR/15-y70-simulator.conf" "$DROPIN_DIR/20-nct6775.conf" /etc/modules-load.d/nexus-fans.conf
  set_auto_launch true >/dev/null 2>&1 || true
  systemctl daemon-reload
  nexus_installed && restart_nexus || true
  if [[ "$PURGE_NEXUS" -eq 1 ]]; then
    local u; u="$(find /opt/nexus -maxdepth 2 -type f -name 'uninstall*.sh' -print | head -1 || true)"
    [[ -n "$u" ]] && bash "$u" || warn "No official Nexus uninstaller found; Nexus left installed."
  fi
  rm -f "$LIBEXEC"; rm -rf "$SHARE_DIR"
  log "Helper integration removed. Nexus user data and the dedicated kiosk profile were preserved."
}

internal_apply(){ ensure_dirs; apply_web_patch; }

# Sourcing exposes functions for isolated tests; it never dispatches a command.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

cmd="${1:-}"; [[ $# -gt 0 ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || die "--version needs a value"; NEXUS_VERSION="$2"; shift 2 ;;
    --archive) [[ $# -ge 2 ]] || die "--archive needs a file"; LOCAL_ARCHIVE="$2"; shift 2 ;;
    --update) FORCE_UPDATE=1; shift ;;
    --no-y70) NO_Y70=1; shift ;;
    --wait-for-plasma) WAIT_FOR_PLASMA=1; shift ;;
    --purge-nexus) PURGE_NEXUS=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "$cmd" in
  install) install_all ;;
  repair) repair_all ;;
  doctor) need_root doctor; doctor ;;
  status) need_root status; status_cmd ;;
  uninstall) uninstall_integration ;;
  internal-apply-web-patch) internal_apply ;;
  -h|--help|'') usage ;;
  *) usage >&2; exit 2 ;;
esac
