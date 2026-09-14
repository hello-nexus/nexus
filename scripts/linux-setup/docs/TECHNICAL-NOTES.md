# Technical notes

## Stable physical-panel identity

The physical display's identity must not depend on the initial browser viewport.
A direct `/panel/<record-id>` route bypasses allocation and therefore prevents a
short-lived startup geometry from rewriting a known Y70 into another surface.

The helper always uses `localhost`. Chromium/Chrome derives the app class from
the URL, so switching to `127.0.0.1` creates a different class and can break a
window-placement rule.

## Token handling

For a new direct kiosk profile the helper may need Nexus's local bearer token
once. It obtains it only from Nexus's own already-running local kiosk command
line during setup, uses it to open the direct route once, then relies on the
browser profile's persisted local authentication.

The helper does not write the token to its state file, launcher, user unit or
log output.

## KScreen versus KWin responsibility

KScreen owns the user's monitor mode, scale, rotation and desktop arrangement.
The verified failure did not require changing any of those values. KWin only
needs to place the Nexus kiosk window on the already-configured output.

The generated KWin 6 script therefore reads `workspace.screens`, matches the
single direct Nexus app class, uses the output geometry for `frameGeometry`,
and applies fullscreen/no-border/task-switcher properties only to that window.

## Fan discovery

The verified board uses an NCT6799-compatible Super-I/O chip. Loading the
in-tree `nct6775` module created seven `pwmN` channels. Nexus discovered them on
the next service start.

The helper treats module insertion as discovery only. It makes no raw PWM
writes, leaves `pwmN_enable` untouched and lets Nexus own cooling policy.

## Simulator protocol

The observed child protocol recognizes:

```text
simulator/ready
simulator/init
simulator/set-layout
simulator/set-grid
simulator/set-touch
simulator/set-display-bound
simulator/set-theme
simulator/set-selection
simulator/flash-widget
simulator/set-display
```

The child starts with `ready=false` and an empty layout. Only
`simulator/init` sets `ready=true`. That makes complete initialization a
protocol requirement, not merely an optimization.

The workaround waits for real theme + layout state, allows a short window for a
real init, then synthesizes one only if the peer still has not been initialized.

## Service/session architecture

The local Plasma gate is intentionally conservative. The upstream design should
be different: hardware service startup should not depend on a desktop login.
Session-dependent capabilities such as tray/MPRIS should attach, detach and
reattach as graphical sessions appear or change.
