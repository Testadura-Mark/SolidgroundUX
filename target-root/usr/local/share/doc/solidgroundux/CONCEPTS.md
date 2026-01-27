# User Interaction & UI Concepts

This document describes how **user interaction** is intended to work in SolidgroundUX.

It focuses on *patterns and expectations*, not function signatures.

---

## Design Philosophy

Terminal output is the user interface.

SolidgroundUX UI is designed to be:

- Calm and readable
- Consistent across scripts
- Informative without being noisy
- Predictable under automation

Visual consistency is treated as a usability feature.

---

## Output Channels

SolidgroundUX distinguishes between:

- **stdout** — Normal script output
- **stderr** — Errors and diagnostics
- **logfile** — Persistent audit trail

Scripts should not mix concerns between these channels.

---

## The `say` Family

### Purpose

`say` exists to provide **structured, styled messaging**.

Use it when:

- Communicating script progress
- Reporting success or failure
- Emitting user-facing status messages

Do not use it when:

- Producing machine-readable output
- Writing library code

### Patterns

Common patterns include:

- Start / end markers
- Informational updates
- Warnings and failures

Consistency matters more than verbosity.

---

## The `ask` Family

### Purpose

`ask` exists to manage **controlled user input**.

It provides:

- Defaults
- Validation
- Consistent prompting behavior

Use it when:

- Requesting user decisions
- Collecting configuration values

Avoid raw `read` unless implementing low-level behavior.

---

## Dialogs & Menus

Dialogs are higher-level interaction patterns built on `ask`.

They are intended for:

- Setup flows
- Configuration menus
- Guided operations

Design rules:

- Clear entry and exit paths
- Explicit cancel behavior
- No hidden state transitions

---
# Script Hub – Concepts

## What is the Script Hub
The Script Hub is the execution environment that ties SolidgroundUX scripts together into a coherent, discoverable system. It provides structure, lifecycle, and interaction patterns on top of plain Bash scripts, without turning them into a framework-heavy abstraction.

A Script Hub:
- Discovers executable modules automatically
- Presents them through a consistent, menu-driven interface
- Enforces predictable execution rules
- Centralizes run modes, logging, and UI behavior

The hub is optional, but once used it becomes the canonical way to run and compose SolidgroundUX-based tooling.

## Core Concepts

### Hub
A *hub* is a logical root that owns:
- A namespace
- A module directory
- Shared runtime state (flags, run modes, UI state)

Each hub represents one coherent toolset or domain (e.g. system setup, machine preparation, administration).

### Module
A *module* is a directory discovered by the hub. It typically contains:
- An `app.sh` entry script
- One or more library or helper scripts
- Optional configuration or assets

Modules are self-contained and are treated as deployable units.

### Applet
An *applet* is the executable identity of a module. It defines:
- Menu entries
- User-visible title
- Execution handlers

Applets are not invoked directly; they are activated through the hub.

## Discovery & Layout

Module discovery is convention-based:
- Modules live under the hub’s module directory
- Each module is identified by its folder name
- Presence of `app.sh` marks a valid module

The hub resolves module paths in a fixed precedence order:
1. CLI override (`--moddir`)
2. App-defined module directory
3. Default hub directory

This guarantees reproducible behavior across environments.

## Menu Model

Menu construction is a multi-step process:
1. Menu specs are registered
2. Specs are compiled into normalized menu items
3. Items are grouped and ordered
4. The final menu is rendered

### Groups
- Items belong to logical groups
- Groups are rendered in deterministic order
- Certain groups (e.g. Run Modes) are fixed to the bottom

### Keys & Ordering
- Numeric keys are ordered numerically
- Non-numeric keys follow
- Ordering is stable and predictable

This avoids subtle UI drift and accidental reordering.

## Run Modes

Run modes are global execution modifiers:
- **Commit**: perform actual actions
- **Dry-Run**: simulate actions without side effects
- **Verbose**: expose internal decisions and arguments

Run modes are always visible and always accessible. They are treated as first-class controls, not optional flags.

## Design Principles

- Convention over configuration
- Predictability beats cleverness
- Bash remains Bash
- No hidden control flow
- Explicit is better than implicit

The Script Hub exists to reduce cognitive load, not increase it.

---

## Non-Interactive Mode

Scripts may run without a TTY.

Expectations:

- Prompts must fail safely or use defaults
- Output must remain parseable
- UI must degrade gracefully

Automation is a first-class use case.

---

## What Not to Do

Avoid:

- Mixing raw `printf` UI with `say`
- Emitting UI from libraries
- Writing directly to `/dev/tty` without intent
- Relying on cursor tricks for correctness

If interaction behavior is surprising, it is considered a bug.

