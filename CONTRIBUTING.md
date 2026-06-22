# Contributing to Nexus

Thanks for your interest in Nexus. This repository is the umbrella: it pulls
each component in as a git submodule and carries the cross-component CI. Each
component is developed and documented in its own repository.

> **Status:** the component repositories are being published and will be public
> shortly. Until then, cloning the submodules and building locally requires
> `hello-nexus` org access. You can still open issues here.

## Reporting issues

- Bugs and feature requests: open an issue here using the templates.
- Security vulnerabilities: do **not** open a public issue. Follow
  [SECURITY.md](SECURITY.md) (GitHub private vulnerability reporting).

## Project layout

| Component | What it is |
|---|---|
| `nexus-service` | Local service: hardware monitoring + control, RGB engine, dashboard host (.NET 10, native AOT). |
| `nexus-web` | React + TypeScript dashboard, served by the service. |
| `nexus-overlay` | Desktop / in-game overlay. |
| `nexus-rgb` | OpenRGB-headless workspace (RGB device backends). |
| `nexus-gamesync` | Game lighting capture shims. |
| `nexus-apps` | First-party + community apps the service bundles. |

Each component's `README` carries its own build, run, and test commands.

## Development setup

```bash
git clone --recurse-submodules https://github.com/hello-nexus/nexus.git
cd nexus
cd nexus-web && npm install && cd ..
cd nexus-service && dotnet run    # builds + serves the dashboard on :9400
```

Prerequisites: git, the .NET 10 SDK, and Node.js 22.12+.

## Pull requests

- Keep each PR focused on a single change.
- Match the style of the surrounding code; run the affected component's lint and
  tests before pushing.
- Use conventional-commit subjects (`feat:`, `fix:`, `docs:`, `chore:`, ...).
- Update the relevant `README` in the same PR when you change behavior, layout,
  commands, or prerequisites.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By
participating, you agree to uphold it.
