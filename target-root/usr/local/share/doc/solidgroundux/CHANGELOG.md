# Changelog

All notable changes to **SolidgroundUX** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to **Semantic Versioning** where practical.

---

## [Unreleased]

### Added
- **SolidGround Console (`sgnd-console`)**
  A configurable interactive module host replacing `script-hub`.  
  Supports dynamic module discovery, grouped menus, runtime toggles, and configurable console environments via `appcfg`.

- **Module system**
  Console modules can now register groups and menu items dynamically, allowing framework tools and external environments to integrate into a unified console.

- **Lightweight Bash DataTable library (`td-datatable`)**
  Provides structured row/column handling for Bash arrays, enabling reliable internal registries (modules, groups, menu items).

- **UI glyph library**
  Short symbolic constants for line drawing, keyboard hints, math symbols, and common characters used in console rendering.

- **Module template**
  Canonical template for developing console modules.

### Changed
- **Framework root resolution**
  All framework paths now derive from a single configuration file `solidgroundux.cfg`, defining:

  - `TD_FRAMEWORK_ROOT`
  - `TD_APPLICATION_ROOT`

- **Bootstrap discovery**
  Executables now locate and load the framework bootstrap deterministically through the root configuration.

- **Console architecture**
  Menu compilation, rendering, and dispatch have been rewritten to support dynamic module integration.

- **Ask helpers**
  All shorthand `ask_*` helpers now support optional timed auto-continue.

- **Library guard**
  Simplified and generalized guard pattern for library loading.

- **Deployment layout**
  Standardized and reordered framework deployment paths.

### Deprecated
- `script-hub.sh`
  Fully replaced by `sgnd-console`.

---

## [1.1-beta] – Structural Expansion

### Added
- Script Hub execution environment with module discovery
- Menu-driven execution model with grouped, ordered actions
- Global run modes: Commit, Dry-Run, Verbose
- Workspace creation, deployment, release, and clone tooling
- Unified UI output, logging, and status handling

### Changed
- Formalized script lifecycle and execution flow
- Introduced deterministic menu compilation and rendering
- Standardized directory layout and deployment targets
- Hardened safety mechanisms for dry-run and commit paths

### Notes
This release represents a conceptual shift from a loose scripting toolkit to a structured execution environment, while preserving the transparency and flexibility of Bash.

### Fixed
- Load-guard edge cases
- Inconsistent stdout vs logfile handling

---

## [1.0-initial]

### Added
- Initial SolidgroundUX framework
- Core bootstrap, UI, state, and config libraries
- Script and library templates
- Script-hub module integrator

---

<!--
Guidelines:
- Add new entries under [Unreleased]
- Move items to a versioned section when releasing
- Keep entries concise and user-facing
- Do not list internal refactors unless they affect behavior
-->

