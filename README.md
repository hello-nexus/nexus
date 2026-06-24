<div align="center">

<img src="brand/NexusLogoMarkColorAlpha.png" alt="Nexus logo" width="120" />

# Nexus

[![CI](https://img.shields.io/github/actions/workflow/status/hello-nexus/nexus/ci.yml?branch=main&label=CI&logo=github)](https://github.com/hello-nexus/nexus/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/hello-nexus/nexus?include_prereleases&sort=semver&label=release)](https://github.com/hello-nexus/nexus/releases)
[![License](https://img.shields.io/github/license/hello-nexus/nexus?color=blue)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](#prerequisites)

</div>

> **Going open source:** the component repositories linked below are private for now and will be published shortly. Until then, cloning the submodules and building locally requires `hello-nexus` org access.

Nexus is a local-first hardware monitoring, control, RGB lighting and fan
control suite for Windows, macOS, and Linux. A small native service runs on the
machine, talks to the hardware, and serves a web dashboard you open in the
browser or in an app.

There is no heavy Electron runtime and it uses your OS-native WebView. It uses a
minimal amount of CPU and RAM, and it unloads systems that you're not actively
using. By default, it will use your integrated GPU to run any rendering, freeing
up your dedicated GPU for your gaming or workstation tasks.

This repository is the umbrella: it pulls each component in as a git submodule
and carries the cross-component CI. Each component is developed in its own
repository and documented by its own `README`.

## Components

| Submodule | What it is |
|---|---|
| [`nexus-service`](https://github.com/hello-nexus/nexus-service) | The local service: hardware monitoring + control, RGB engine, dashboard host. .NET 10, native AOT. |
| [`nexus-web`](https://github.com/hello-nexus/nexus-web) | The React + TypeScript dashboard, served by the service. |
| [`nexus-overlay`](https://github.com/hello-nexus/nexus-overlay) | The desktop / in-game overlay. |
| [`nexus-rgb`](https://github.com/hello-nexus/nexus-rgb) | OpenRGB-headless workspace; provides the RGB device backends. |
| [`nexus-gamesync`](https://github.com/hello-nexus/nexus-gamesync) | Game lighting capture shims. |
| [`nexus-apps`](https://github.com/hello-nexus/nexus-apps) | First-party + community apps the service bundles (build dependency of `nexus-service`). |

## Prerequisites

- git
- .NET 10 SDK (for `nexus-service`)
- Node.js 22.12+ (for `nexus-web`)

## Quick start

```bash
# Clone with all components
git clone --recurse-submodules https://github.com/hello-nexus/nexus.git
cd nexus
# (if cloned without submodules)
git submodule update --init --recursive

# Install dashboard dependencies once
cd nexus-web && npm install && cd ..

# Build + run the service (it embeds and serves the dashboard)
cd nexus-service && dotnet run
```

Open <http://localhost:9400> for the dashboard.

For dashboard development with hot reload, keep the service running and start the
Vite dev server in a second terminal:

```bash
cd nexus-web && npm run dev    # http://localhost:5173
```

RGB lighting needs the OpenRGB-headless binaries under
`nexus-service/Bundled/<rid>/openrgb/`, built from `nexus-rgb`; everything else
runs without them. Per-component build, publish, and test commands live in each
submodule's `README`.

## Layout

```
nexus/
  nexus-service/   Local service (.NET 10 AOT; Windows / macOS / Linux)
  nexus-web/       React dashboard, served by the service
  nexus-overlay/   Desktop / in-game overlay
  nexus-rgb/       OpenRGB-headless workspace (RGB device backends)
  nexus-gamesync/  Game lighting capture shims
  nexus-apps/      Bundled + community apps (built into the service)
  .github/         Cross-component CI
  brand/           Brand assets
```

## Releases

Installer downloads are published as GitHub Releases on this repository. The
in-app updater compares against the latest semver `vX.Y.Z` tag; prerelease tags
(`vX.Y.Z-beta.N`) are the beta channel.

## License

[AGPL-3.0](LICENSE). Each submodule carries its own license; the bundled
OpenRGB engine is GPLv2 and runs as a separate child process.
