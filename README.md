SolidgroundUX is a small, powerful Bash framework designed for system engineers,
developers, automation builders, and anyone who wants clean, structured, reliable
shell scripts — without the usual mess or over-engineered tooling.

## What SolidgroundUX Provides

- A predictable bootstrap and execution lifecycle  
- Robust, declarative argument parsing  
- Clear, styled, user-friendly terminal output  
- Practical helpers for deployment, validation, and system interaction  
- A consistent template system for building new scripts and toolsets  

No hidden magic.  
No auto-executing libraries.  
No framework surprises.

## 🏷 Badges

![License: TD-NC](https://img.shields.io/badge/License-TD--NC-blue.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-green)
![Last Commit](https://img.shields.io/github/last-commit/Testadura-Mark/SolidgroundUX)
![Made in NL](https://img.shields.io/badge/Made%20in-The%20Netherlands-ff4f00?labelColor=003399)
---

## 🧭 Philosophy

SolidgroundUX was created to bring **clarity, discipline, and reliability** to Bash scripting.

Instead of relying on large automation frameworks or fragile conventions, it focuses on:

- **Simplicity** — Everything is explicit and readable  
- **Consistency** — All scripts follow the same structure and lifecycle  
- **Predictability** — Behavior is traceable and debuggable  
- **Maintainability** — Designed for long-term use, not quick hacks  
- **Practicality** — Built from operational experience, not trends  

Bash is powerful — but only if it is treated with respect.  
SolidgroundUX exists to enforce that respect.

## 🔁 Execution Model
- Wrappers do nothing except invoke a script located elsewhere
- Wrappers and symlinks are both supported; neither affects execution semantics
- Libraries never execute code; they only define behavior and detect prior loading
- Executable scripts do nothing unless `main()` is explicitly called

A typical executable script looks like this (see executable template):
'''bash
main() {
    # --- Source libraries ------------------------------------------------------
    td_source_libs
    
    # --- Ensure sudo or non-sudo as desired ---------------------------
        #need_root "$@"
        #cannot_root "$@"

    # --- Load previous state and config
        # enable if desired:
        #td_state_load
        #td_cfg_load

    # --- Parse arguments
        td_parse_args "$@"
        FLAG_DRYRUN="${FLAG_DRYRUN:-0}"   

        if [[ "${FLAG_VERBOSE:-0}" -eq 1 ]]; then
            __td_showarguments
        fi

    # --- Main script logic here ---------------------------------------------
}

# Run main with positional args only (not the options)
main "$@"

## 🏗 Templates
Templates define *how you start*, not how you think.

### Executable Template
Full-featured scripts with lifecycle and UI.

### Library Template
Reusable helpers, no execution.

### Wrapper-template.sh
Wrapper script to be published to bin or bins

## 🚀 Getting Started
Once SolidgroundUX has been installed
- Create a repository using td-create-workspace
- Copy the executable template
- proceed...

## ✨ Features

### 🔧 Framework Architecture
- Self-locating bootstrap system  
- Optional config-file loading 
- Built-in load guards (no double sourcing)  
- Automatic environment detection (development vs. installed)  

### 🖥️ UI Output & Messaging
- `say` and `ask` command with icons, labels, symbols, and colors  
- Optional date/time prefix  
- Logfile support  
- Toggleable color modes  
- Override points for custom UI and error handling

### 🎛 Argument Handling
- ArgSpec-based specification format  
- Flags, values, enums, and actions  
- Automatic help generation  
- Short and long options

### 🧰 Utility Tools
- Validators (integer, decimal, IP address, yes/no)  
- Privilege checks  
- File presence tests  
- Internal error handlers

### 📦 Deployment Tools
- `deploy-workspace.sh`: safe file deployment to system paths  
- Dry-run capability  
- Auto-detection of changed files  
- Ignore rules for meta/hidden files

### 🏗 Workspace & Template System
- Script generator for new workspaces  
- Full-framework or minimal templates  
- Familiar, readable structure  
- Easy onboarding for collaborators

## 📁 Repository Structure
SolidgroundUX is organized around a `target-root` directory, which mirrors the filesystem
layout of the environment it will be installed into. Deployment is straightforward:
the entire structure is copied to the target system, placing framework files under
`/usr/local/lib/testadura` and creating executable symlinks in `/usr/local/bin`.

The repository layout:

SolidgroundUX/
├── LICENSE
├── README.md
└── target-root/
    ├── etc/
    └── usr/
        └── local/
            └── lib/
                └── testadura/
                    ├── common/
                    │   ├── templates/
                    │   └── tools/


## 🧰 Included Tools

SolidgroundUX ships with two key tools that streamline scripting workflows:

### **1. create-workspace.sh**
Creates a new script workspace based on SolidgroundUX conventions.

It:
- Generates a folder structure
- Copies the template scripts to the repository
- Creates a default script based on the exe-template
- Optionally adds argument parsing and config support
- Ensures consistent bootstrap + constructor setup  

This is the recommended way to start new scripts.

### **2. deploy-workspace.sh**
Deploys the entire `target-root` directory onto a real system.

It:
- Mirrors directory structure under `/usr/local`
- Preserves permissions
- Supports dry-run mode
- Detects updates cleanly
- Safely installs Testadura/SolidgroundUX framework files
- Optionally creates symlinks to executable scripts in `bin` or `bins`, as an alternative to wrapper scripts

This is the mechanism used to install SolidgroundUX or update existing deployments.

## 🏷 License

Licensed under the **Testadura Non-Commercial License (TD-NC)**.  
See `LICENSE` for details.

---

### Design Note

If you are looking for implicit behavior, clever hacks, or magical globals —  
**this framework is not for you**.

SolidgroundUX is for people who want to know exactly what their scripts are doing.