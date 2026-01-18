# SolidgroundUX Architecture

This document describes the **architectural principles and execution model** of SolidgroundUX.
It is intended for contributors and advanced users who want to understand *how the framework works* and *why it is designed this way*.

This is **not** an API reference.

---

## Design Goals

SolidgroundUX is built around a small number of strict goals:

- **Explicit execution** — Nothing runs unless explicitly invoked
- **Predictable lifecycle** — Every script follows the same execution phases
- **No implicit behavior** — No hidden side effects, no auto-executing code
- **Operational reliability** — Scripts must be debuggable under pressure
- **Bash as a systems language** — Treated with discipline, not as a toy

These goals override convenience when the two are in conflict.

---

## High-Level Overview

SolidgroundUX distinguishes clearly between:

- **Executables** — Scripts that define and call `main()`
- **Libraries** — Reusable code that never executes on load
- **Wrappers** — Thin entry points that invoke executables elsewhere
- **Tools** — Framework-maintenance and workspace utilities
- **Deployment layout** — A filesystem mirror of the target system

Each category has strict rules and responsibilities.

---

## Execution Lifecycle

A SolidgroundUX executable follows a fixed lifecycle:

1. Script is invoked (directly or via wrapper)
2. Libraries are sourced
3. `main()` is defined
4. `main()` is explicitly called
5. Bootstrap phase executes
6. User logic runs
7. Script exits with explicit status

Nothing outside `main()` may perform actions.

---

## The Bootstrap Contract

The bootstrap phase is entered via `td_bootstrap`.

Bootstrap responsibilities:

- Initialize optional subsystems (UI, state, config)
- Enforce privilege requirements (root / non-root)
- Parse arguments (if enabled)
- Establish a consistent runtime environment

Bootstrap guarantees:

- No user logic has executed yet
- No side effects outside declared subsystems
- All enabled systems are ready for use

Bootstrap explicitly does **not**:

- Execute user code
- Modify system state implicitly
- Guess intent or infer behavior

---

## Libraries vs Executables

### Libraries

Libraries:

- May define functions, variables, constants
- Must be idempotent when sourced
- Must include load guards
- Must never execute logic on load

Libraries are passive by design.

### Executables

Executables:

- Define `main()`
- Call `main()` explicitly
- Control execution order
- Own side effects

This separation is strictly enforced.

---

## State, Configuration, and Environment

SolidgroundUX distinguishes between:

- **Configuration** — Declarative, user-editable intent
- **State** — Runtime or historical data managed by scripts

Scopes:

- System configuration
- User configuration
- Persistent state

Scripts must never conflate configuration and state.

---

## UI & Interaction Model

User interaction is treated as a first-class concern.

Principles:

- Predictable output structure
- Clear distinction between UI, logging, and data output
- Centralized formatting and styling

Libraries must not emit UI output.

---

## Deployment Architecture

SolidgroundUX uses a **filesystem mirror model**:

- Repository contains `target-root`
- `target-root` mirrors the final system layout
- Deployment copies the structure verbatim

This ensures:

- Predictable paths
- No install-time logic
- Easy auditing and rollback

Install layout
/(root)
├── etc/
|   ├── systemmd
|   |  └── system
|   ├── testadura
|   |   └── _*.cfg-files_
|   └── update-motd.d
        └── 90-solidgroundUX            
└── share
|   └── doc
|       └── solidgroundux             
└── usr
    └── local
    |   ├── bin  
    |   |   ├── td-create-workspace  
    |   |   └── td-prepare-release                      
    |   ├── lib
    |   |    └── testadura
    |   |        ├── styles   
    |   |        |   ├── style-carnaval.sh
    |   |        |   ├── style-greenyellow.sh
    |   |        |   ├── style-monoamber.sh
    |   |        |   ├── style-monoblack.sh
    |   |        |   └── style-monogreen.sh         
    |   |        └── common            
    |   |            ├── templates     
    |   |            |   ├── exe-template.sh
    |   |            |   ├── lib-template.sh
    |   |            |   └── wrapper-template.sh
    |   |            └── tools         
    |   |            |   ├── clone-config.sh
    |   |            |   ├── create-workspace.sh
    |   |            |   ├── deploy-workspace.sh
    |   |            |   └── prepare-release.sh
    |   |            ├── args.sh
    |   |            ├── cfg.sh
    |   |            ├── core.sh
    |   |            ├── default-colors.sh
    |   |            ├── default-styles.sh
    |   |            ├── td-bootstrap.sh
    |   |            ├── td-globals.sh
    |   |            ├── ui-ask.sh
    |   |            ├── ui-dlg.sh
    |   |            ├── ui-say.sh
    |   |            └── ui.sh
    |   └── sbin
    |       ├── td-clone-config  
    |       └── td-deploy-workspace
    ├── var/
    |   └── lib/
    |       ├── testadura               
    |       └── _*.state-files_
    └── log/
        └── testadura
            └── _solidgroundux.log_       
    ~/.config/testadura
              └── _*.cfg-files_
    ~/.log
        └── testadura
            └── _solidgroundux.log_      
---

## Non-Goals

SolidgroundUX intentionally does **not** attempt to provide:

- Implicit execution models
- Auto-discovery or auto-registration
- DSLs or meta-programming layers
- Hidden global state

If a behavior is not obvious from reading the script, it is considered a design failure.

