# Nexus Linux Setup Helper

An **unofficial** setup and repair helper for the open-source
[`hello-nexus/nexus`](https://github.com/hello-nexus/nexus) hardware monitoring,
fan control and RGB suite.

This repository automates the complete Linux setup that was proven on a real
Kubuntu/Plasma + HYTE Y70 system after several independent startup failures were
isolated and fixed.

## One-command setup

```bash
chmod +x nexus-linux-setup.sh
./nexus-linux-setup.sh install
```

For an existing Nexus installation:

```bash
./nexus-linux-setup.sh repair
```

Then verify everything:

```bash
./nexus-linux-setup.sh doctor
```

## What it automates

The helper:

- installs the current official Nexus Linux x86-64 release from
  `hello-nexus/nexus` unless Nexus is already present;
- deliberately runs Nexus's own `install.sh` rather than inventing a private
  installation layout;
- detects whether `nct6775` exposes a real NCT67xx/NCT679x PWM controller and,
  only when it does, guarantees that driver is loaded before Nexus enumerates
  cooling hardware;
- with `--wait-for-plasma` on KDE Plasma, waits up to 30 seconds for the active Plasma
  session so its tray integration is established reliably;
- detects the existing Y70-shaped KScreen output without changing resolution,
  scale, rotation or desktop placement;
- converts the physical Y70 kiosk from the fragile generic `/panel` route to a
  stable `/panel/<record-id>` route;
- installs a KWin 6 placement helper that targets only the managed Nexus kiosk;
- uses `localhost` consistently so Chrome's app/window class stays stable;
- seeds a dedicated Chrome profile once, while never writing the Nexus bearer
  token into a service unit or state file;
- applies the proven local simulator/editor handshake workaround and reapplies
  it after Nexus updates replace `wwwroot/index.html`;
- provides `doctor`, `repair`, `status`, and `uninstall` commands.

## Safety boundaries

This helper **does not**:

- write motherboard PWM duty values itself;
- change KScreen monitor mode, scale, rotation or desktop geometry;
- store Nexus authentication tokens in systemd units, helper state or logs;
- delete Nexus user data during a normal uninstall;
- replace Nexus's official installer with a custom binary layout;
- change unrelated KWin settings.

Actual fan policy and RGB behavior remain Nexus's responsibility.

## Verified environment

The complete flow was developed and verified with:

```text
Linux:       Kubuntu / KDE Plasma 6 / Wayland
Panel:       HYTE Y70 Touch, native 3840x1100, portrait
Nexus:       3.0.12 beta line
Kernel:      Ubuntu 7.0.0-31-generic
Motherboard: ASUS ROG STRIX X870E-E GAMING WIFI
Fan chip:    NCT6799-compatible via nct6775
```

The script is deliberately capability-driven rather than hard-coded to those
identifiers. It skips a feature when it cannot safely prove that feature
applies.

## Commands

### Install or fully configure

```bash
./nexus-linux-setup.sh install
```

### Repair an existing installation

```bash
./nexus-linux-setup.sh repair
```

### Read-only health check

```bash
./nexus-linux-setup.sh doctor
```

### Show managed state

```bash
./nexus-linux-setup.sh status
```

### Remove only this helper's integration

```bash
./nexus-linux-setup.sh uninstall
```

This keeps the official Nexus installation, Nexus user data and the dedicated
Chrome kiosk profile.

To additionally invoke Nexus's own uninstaller when available:

```bash
./nexus-linux-setup.sh uninstall --purge-nexus
```

### Install a specific official release

```bash
./nexus-linux-setup.sh install --version v3.0.12-beta.2
```

### Use an official archive already downloaded

```bash
./nexus-linux-setup.sh install --archive ~/Downloads/<nexus-linux-x64.tar.gz>
```

## Why the Y70 workaround exists

Nexus's generic `/panel` bootstrap derives the panel surface from the browser's
runtime viewport. During Wayland/KWin startup or resume, Chrome can briefly have
the geometry of another monitor before final placement. That can cause the
physical Y70 kiosk to be allocated or updated as a `phone` panel.

The stable workaround is to use the already-associated Y70 record directly:

```text
http://localhost:9400/panel/<y70-record-id>
```

The helper discovers that record and builds the user service dynamically. It
never hard-codes a machine-specific panel ID, connector name, UID or geometry.

## Why the simulator/editor workaround exists

The embedded `/panel?simulator=1` frame starts with an empty layout and an
independent `ready` state. In the reproduced failure the child emitted
`simulator/ready`, then received incremental `simulator/set-theme` and
`simulator/set-layout` messages, but did not receive the complete
`simulator/init` required to initialize it.

The local patch waits briefly for a real init. If none arrives after the real
theme and layout are known, it synthesizes one from those real values. Because
this helper intentionally uses an external direct Y70 launcher while Nexus's
built-in `panel.autoLaunch` is disabled, the patch also keeps the editor's
`showPanel` state aligned with the actually visible direct kiosk.

The injection is bounded to the simulator iframe and surrounded by explicit
HTML markers so it can be removed cleanly.

## Why motherboard fans were missing

On the verified ASUS X870E system, Nexus initially started before `nct6775` was
loaded. Linux exposed no writable motherboard PWM channels, so Nexus could only
control the NVIDIA GPU fan.

After a safe module load:

```bash
sudo modprobe nct6775
```

Linux exposed an `nct6799` hwmon device with seven PWM channels. Restarting
Nexus immediately produced:

```text
[Motherboard] Fans channels=7 id=linux-fans
```

The helper automates only that discovery/preload step. It never writes a PWM
value.

## Why the Plasma startup gate exists

The current Linux Nexus service runs as a root hardware daemon and adopts the
active user session for tray/MPRIS integration. On the reproduced system the
service could start before `plasmashell`; hardware worked but the tray icon was
absent until Nexus was restarted after login.

The opt-in local workaround waits up to 30 seconds for the target user's Plasma process before starting
Nexus. The upstream proposal is better: keep the hardware daemon independent
and make session/tray adoption retryable.

## Files installed by this helper

Depending on detected capabilities, the helper may manage:

```text
/etc/nexus-linux-setup/
/etc/modules-load.d/nexus-fans.conf
/etc/systemd/system/nexus.service.d/10-wait-for-plasma.conf
/etc/systemd/system/nexus.service.d/15-y70-simulator.conf
/etc/systemd/system/nexus.service.d/20-nct6775.conf
/usr/local/libexec/nexus-linux-setup
/usr/local/share/nexus-linux-setup/simulator-fix.js
~/.config/systemd/user/nexus-y70-direct.service
~/.local/bin/nexus-y70-direct
~/.local/share/kwin/scripts/nexus-y70-placement/
```

Original files touched by the web/settings work are copied by content hash into
`/etc/nexus-linux-setup/backups/` before modification.

## Updates

To run the official release installer/update path and then reapply this helper:

```bash
./nexus-linux-setup.sh install --update
```

The system service also calls the helper's idempotent web-patch action before
Nexus starts, so a replaced `index.html` is patched again automatically.

## Diagnostics

`doctor` checks the service, localhost dashboard, Plasma startup gate,
NCT PWM exposure, Nexus's own motherboard-fan enumeration log, simulator patch,
direct Y70 user service/route and basic lighting/OpenRGB log activity.

A shell script cannot visually inspect whether a tray glyph is painted; it
verifies the startup condition that fixed the tray race on the reproduced
system.

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for manual checks.

## Origin and scope

Adapted from [nexus-linux-setup](https://github.com/Ottomatic-Mike/nexus-linux-setup)
commit `510cd4f`, developed on the environment above. This is an optional recovery
helper, not a replacement for component-level fixes. See
[the maintainer notes](../../docs/linux-recovery.md) for the failure-to-fix map.

### Changes made for this contribution

- Download progress goes to stderr so command substitution receives only the archive path.
- The Plasma startup gate requires `--wait-for-plasma` and stops waiting after
  30 seconds. Hardware startup must not depend indefinitely on a desktop login.
- The simulator workaround is installed only when configuring a direct Y70 kiosk,
  and only changes simulator state after receiving an explicit Y70 layout.
- Multiple Y70 records require an explicit `NEXUS_PANEL_ID`; the output fallback
  requires portrait geometry so ordinary ultrawide monitors are not selected.
- Panel IDs are validated before generating launchers; browser output during
  token seeding is discarded to avoid recording authentication URLs.
- Setup no longer deletes the earlier diagnostic KWin script automatically.

Requirements: Linux x86-64 with systemd, Bash, Python 3, curl, sudo, kmod and
standard GNU utilities. Y70 integration additionally needs a logged-in Plasma 6
Wayland session, KScreen, KWin tools and Chrome/Chromium. Finish Nexus onboarding
first. Run the commands above from `scripts/linux-setup` in this repository.
The default download searches the most recent 20 releases and may select a beta;
use an explicit version or local archive for reproducible installation.

The direct-profile seeding step uses a six-second browser launch and does not
prove authentication succeeded. Check the actual panel after setup. Uninstall
reenables Nexus panel auto-launch rather than restoring its previous value;
content-hash backups remain under `/etc/nexus-linux-setup/backups`. The optional
Plasma gate is a startup workaround, not support for session reconnection.

## License

MIT for this helper. Nexus itself is licensed separately by its maintainers.
This project is not an official Nexus distribution.
