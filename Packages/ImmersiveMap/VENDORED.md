# Vendored: ImmersiveMap

- Upstream: https://github.com/artembobkin/ImmersiveMap
- Revision: `edfe99e20dcde793606d306f9985ccb0c9bcccb0` (branch `main` at vendoring time)
- License: MIT (see `LICENSE`)
- What was copied: `Package.swift`, `Sources/`, `Plugins/` (the Metal build plugin), `LICENSE`, `README.md`.
- What was not copied: `Assets/` (README screenshots), `Develop/`, `Documentation/`, `Tests/` and `Tools/`. Re-add the upstream test targets from the URL above if you want them in the workspace.

Revert depends on this local package. To update, copy the upstream `Sources/` and `Plugins/` over this folder, update the revision above, and build. Never edit `Sources/` casually: changes here are ours to maintain.
