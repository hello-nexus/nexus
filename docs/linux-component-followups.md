# Upstream implementation notes

These are source-level contracts rather than fabricated file paths. The public
umbrella repository currently states that its component repositories are still
private, so the exact private source tree cannot be truthfully patched from the
public checkout.

## nexus-service: Y70 launcher

When physical Y70 hardware has a stable panel association:

```text
panelRecordId != null
```

construct the local kiosk route from that identity:

```text
http://localhost:9400/panel/<url-encoded-panelRecordId>
```

Use generic `/panel` only when allocation is actually required.

Acceptance condition: no viewport observed during browser startup can change an
already-bound hardware Y70's record surface to `phone`.

## nexus-service: Linux cooling

Cooling discovery should tolerate providers appearing after process startup.
A robust sequence is:

```text
service starts
  -> enumerate current hwmon PWM providers
  -> optionally perform supported, read-only module/provider probes
  -> subscribe/retry for provider changes
  -> add/remove Linux fan channels when providers change
```

Do not modify `pwmN`, `pwmN_enable`, curves or duty values merely to discover a
provider.

## nexus-service: graphical session

Separate hardware lifetime from session lifetime:

```text
service starts
  -> hardware monitoring/control starts immediately
  -> no eligible graphical user: session integration = pending
  -> graphical session appears
  -> adopt user environment + register tray/MPRIS/etc.
  -> session disappears/changes
  -> detach and retry/adopt the current eligible session
```

A failed first adoption should not require a daemon restart.

## nexus-web: simulator protocol

Treat each iframe document as a new protocol peer.

Conceptual parent state:

```text
peerReady = false
peerInitialized = false
```

On iframe load, clear both flags.

On `simulator/ready`:

```text
peerReady = true
if complete current state is available:
    send simulator/init {
      surface,
      deviceTouch,
      dpi,
      displayBound,
      layout,
      theme,
      themeMode,
      selectedWidgetId,
      brightness,
      screenOn,
      showPanel,
      deviceId
    }
    peerInitialized = true
else:
    remember peerReady and initialize when state becomes available
```

Send incremental simulator messages only after the peer has been initialized,
or queue them behind init.

## `showPanel`

Do not equate:

```text
panel.autoLaunch == false
```

with:

```text
physical panel is hidden
```

`autoLaunch` is desired launch policy. `showPanel` is runtime visibility/state.
Use active panel session/binding/display state when available.
