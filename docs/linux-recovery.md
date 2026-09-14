# Linux recovery: what failed and what this change does

This contribution brings the working recovery helper from
[Ottomatic-Mike/nexus-linux-setup](https://github.com/Ottomatic-Mike/nexus-linux-setup/tree/510cd4f)
into `scripts/linux-setup`, with its MIT attribution preserved. The original
Nexus README, license, installer, and submodule revisions remain intact.

The original work reports successful recovery on Kubuntu, Plasma 6/Wayland,
a HYTE Y70 Touch and an ASUS X870E board with an NCT6799-compatible fan chip,
using the Nexus 3.0.12 beta line. That hardware result belongs to the original
work; this contribution was checked with isolated tests, without running setup,
changing the host, restarting Nexus or touching hardware.

| Observed problem | Executable recovery included here | Long-term component change |
| --- | --- | --- |
| Y70 starts with another monitor's dimensions and becomes a phone panel | Reuse the existing Y70 record at `/panel/<id>`; place its Chrome window with KWin, leaving KScreen configuration alone | Launch associated physical panels using their stored identity |
| Editor receives theme/layout updates but no initial state and stays blank | After 250 ms, synthesize one init from received Y70 theme/layout unless a real init arrives; keep the direct kiosk preview visible | Parent sends full init after each iframe ready/load before incremental updates |
| Only GPU fans appear because motherboard hwmon loads late | Probe `nct6775`; persist a preload only if supported NCT PWM channels appear; restart Nexus for enumeration | Rediscover cooling providers after startup |
| Hardware runs but the Plasma tray is absent after login | Optional, bounded wait for the selected user's Plasma process | Retry graphical session adoption independently of hardware lifetime |

The helper also preserves the original local-token profile bootstrap, consistent
`localhost` URL, update-time marked HTML patch, diagnostics, backups, and removal
commands. It makes no direct PWM writes. It does not repair RGB internals; its
lighting check only reports matching journal activity.

## Why this is an optional helper

The public repository is an umbrella. The `nexus-service` and `nexus-web`
repositories were inaccessible with the contributor's account when preparing
this change. This PR therefore adds code that can actually run from this public
repository, rather than claiming to fix inaccessible component code.

Nothing runs automatically when cloning, building, or installing Nexus.
Users explicitly invoke the [helper](../scripts/linux-setup/README.md).
The Plasma gate is opt-in because delaying the hardware daemon is not a durable
solution. The simulator fallback is also a workaround, including its Y70
visibility override; it should be retired when the protocol is fixed upstream.

The [reproduction](linux-reproduction.md) records the original observations.
The [component follow-ups](linux-component-followups.md) describe the internal
changes and acceptance conditions for maintainers with source access.

## Validation

Run from the repository root:

```bash
bash scripts/linux-setup/tests/static.sh
bash scripts/linux-setup/tests/helper.sh
node --test scripts/linux-setup/tests/simulator.test.cjs
```

These tests use temporary fixtures and simulated browser messages. They do not
run install/repair, systemctl, sudo, modprobe, Chrome, or KWin on the host.
Real hardware validation is still needed for fresh install, logout/login,
suspend/resume, profile authentication, update/reapply, and uninstall on the
maintainer's supported configurations. Component lint/build/tests cannot be run
without the private component repositories.
