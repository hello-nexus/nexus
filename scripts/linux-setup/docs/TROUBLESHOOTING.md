# Troubleshooting

## Start with the health check

```bash
sudo ./nexus-linux-setup.sh doctor
```

## Nexus service will not stop cleanly

The helper already uses a bounded stop followed by a service-scoped SIGKILL
fallback. To reproduce that manually:

```bash
sudo systemctl stop nexus &
sleep 5
sudo systemctl kill --kill-whom=all --signal=SIGKILL nexus 2>/dev/null || true
wait
```

## Y70 direct service is configured but inactive

```bash
systemctl --user status nexus-y70-direct.service
journalctl --user -u nexus-y70-direct.service -b --no-pager
```

The launcher waits for `http://localhost:9400` before Chrome starts.

## Y70 output is not detected

```bash
kscreen-doctor -o
```

A classic Y70 Touch normally exposes a `3840x1100` mode. The helper strongly
prefers that signature and otherwise uses a portrait display ratio of at least 2.5. It
refuses to guess if equally strong candidates exist.

The helper never modifies the KScreen mode, scale, rotation or position.

## Motherboard fans are absent

```bash
lsmod | grep nct6775
for h in /sys/class/hwmon/hwmon*; do
  printf '%s: ' "$h"
  cat "$h/name" 2>/dev/null || true
  ls "$h"/pwm[0-9] 2>/dev/null || true
done
```

Then inspect what Nexus enumerated:

```bash
journalctl -u nexus -b --no-pager | grep -Ei 'cool|fan|pwm|nct'
```

The helper persists `nct6775` only when the module really exposes a supported
NCT PWM controller.

## Tray icon is absent

```bash
pgrep -a plasmashell
systemctl status nexus
systemctl cat nexus
```

On Plasma, opt in with `repair --wait-for-plasma`. It waits at most 30 seconds
and appears as:

```text
/etc/systemd/system/nexus.service.d/10-wait-for-plasma.conf
```

To install the tray startup workaround, run:

```bash
sudo ./nexus-linux-setup.sh repair --wait-for-plasma
```

## Editor says Panel hidden / Desktop visible

Check whether the marked local patch exists:

```bash
sudo grep -n 'BEGIN nexus-linux-setup simulator fix' /opt/nexus/wwwroot/index.html
```

Then repair:

```bash
sudo ./nexus-linux-setup.sh repair
```

## Nexus update replaced the app files

```bash
sudo ./nexus-linux-setup.sh repair
```

The service drop-in also reapplies the simulator patch automatically on the
next Nexus start.

## Undo the helper

```bash
sudo ./nexus-linux-setup.sh uninstall
```

This restores Nexus's own `panel.autoLaunch` behavior and removes the managed
service/KWin/module integration while preserving Nexus user data.
