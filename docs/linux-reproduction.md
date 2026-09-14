# Reproduction checklist

Sanitized environment used for the verified reproduction:

```text
Desktop:     KDE Plasma 6 / Wayland
Panel:       HYTE Y70 Touch, native 3840x1100, portrait
Nexus:       v3.0.12 beta line
Kernel:      Ubuntu 7.0.0-31-generic
Motherboard: ASUS ROG STRIX X870E-E GAMING WIFI
Fan chip:    NCT6799-compatible
```

## A. Y70 identity

1. Configure the Y70 as a normal extended KScreen output.
2. Let Nexus auto-launch generic `/panel`.
3. Exercise login/startup, service restart, suspend/resume, or hibernate/resume.
4. Observe the kiosk before final KWin placement.
5. Inspect the panel records/capabilities.

Failure: a `phone`-surface record is allocated/updated for the physical kiosk,
or the kiosk binds to the wrong record.

Control: direct `/panel/<known-y70-record-id>` stays on the correct stored Y70
layout.

## B. Simulator

1. Open the Y70 device editor.
2. Inspect the same-origin `/panel?simulator=1` iframe.
3. Listen for `message` events in the iframe.
4. Reload the iframe or reproduce the editor state loss.

Observed failure sequence:

```text
simulator/ready
simulator/set-theme
simulator/set-layout
(no simulator/init)
```

Control: one complete `simulator/init` immediately renders the saved Y70
layout.

## C. Motherboard fans

Before module load:

```bash
for h in /sys/class/hwmon/hwmon*; do
  cat "$h/name" 2>/dev/null
  ls "$h"/pwm[0-9] 2>/dev/null || true
done
```

On the reproduced board there were no motherboard PWM attributes.

Load the in-tree provider:

```bash
sudo modprobe nct6775
```

Expected kernel identification on this board:

```text
NCT6796D-S/NCT6799D-R or compatible chip
```

Expected hwmon provider: `nct6799` with seven PWM channels.

Restart Nexus only. Expected log:

```text
[Motherboard] Fans channels=7 id=linux-fans
```

## D. Plasma tray race

1. Allow the system service to start before the user's Plasma session exists.
2. Log into Plasma.
3. Confirm Nexus hardware service is running but tray is absent.
4. Restart `nexus.service` after `plasmashell` exists.

Control: tray appears after the restart.
