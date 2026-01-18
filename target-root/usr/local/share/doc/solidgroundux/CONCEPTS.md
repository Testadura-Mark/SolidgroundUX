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

