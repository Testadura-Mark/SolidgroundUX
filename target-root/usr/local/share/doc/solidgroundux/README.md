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
```bash

# === main() must be the last function in the script ==============================
    main() {
    # --- Bootstrap ---------------------------------------------------------------
        #   --ui            Initialize UI layer (ui_init after libs)
        #   --state         Load persistent state (td_state_load)
        #   --cfg           Load configuration (td_cfg_load)
        #   --needroot      Enforce execution as root
        #   --cannotroot    Enforce execution as non-root
        #   --args          Enable argument parsing (default: on; included for symmetry)
        #   --initcfg       Allow creation of missing config templates during bootstrap
        #
        #   --              End bootstrap options; remaining args are passed to td_parse_args
        td_bootstrap -- "$@"
        if [[ "${FLAG_STATERESET:-0}" -eq 1 ]]; then
            td_state_reset
            sayinfo "State file reset as requested."
        fi

    # --- Main script logic here --------------------------------------------------

    }

    # --- Run main with positional args only (not the options)
    main "$@"
```

## 🏗 Templates
Templates define *how you start*, not how you think.
- exe-template.sh   Executable scripttemplate with bootstrapper locater and loader
- lib-template.sh   Actively refuses execute, prevents double sourcing
- wrapper-template  Nothing but a call to an executable script somehwere depper in the tree

## 🚀 Getting Started

### 📦 Installation
SolidgroundUX is distributed as versioned release archives and can be installed either manually or via the provided installer script.
- Download the latest release from  
  https://github.com/Testadura-Mark/SolidgroundUX/releases
- The installer expects to run in a directory containing the release tarballs
- `sudo install.sh --auto` installs the latest available version
- `sudo install.sh` lets you choose from available versions

## 🔹 Fresh install vs Upgrade

### Fresh install
A *fresh install* is the initial placement of SolidgroundUX onto a system or into a development sandbox.

- Installation is performed by **extracting the release archive**
- No installer script is required
- Recommended for:
  - first-time installation
  - development or test environments
  - sandboxed or non-system installs

### Upgrade (managed install)
An *upgrade* installs a newer version over an existing installation using the installer script.

- Intended for systems where SolidgroundUX is already installed
- Performs checksum verification
- Extracts files consistently
- Records the version manifest for later uninstallation

---

## 🔹 Manual installation (bootstrap / first install)

- Download the latest release from  
  https://github.com/Testadura-Mark/SolidgroundUX/releases

- Extract the archive to the desired target root:

```bash
  sudo tar -C / -xzf SolidgroundUX-x.y.z.tar.gz
```
  For development or sandbox installs, extract to a custom directory:
```bash
  tar -C ~/dev/solidgroundux-root -xzf SolidgroundUX-x.y.z.tar.gz
```
  Extracting the archive is sufficient to install SolidgroundUX.

  No installer is required for the initial setup.

### Managed installation and updates (install.sh)
Place install.sh in a directory containing:
- one or more SolidgroundUX-*.tar.gz release archives
- a SHA256SUMS file
- optional *.manifest files

The installer verifies checksums and extracts the selected release.

Common usage
- Install the latest available version automatically:
```bash
  sudo ./install.sh --auto
```
- Select a version interactively:
```bash
  sudo ./install.sh
```
- Development install to a custom target root (no sudo required):
```bash
  ./install.sh --auto --target-root ~/dev/solidgroundux-root
```
- Dry-run (verify and simulate extraction):
```bash
  ./install.sh --auto --dryrun
```
By default, files are extracted to /.

Use --target-root for development or non-system installs.

### Uninstallation (uninstall.sh)

Each release includes a version-specific uninstall manifest
Installed manifests are stored under:

  /var/lib/solidgroundux/manifests/

To uninstall a specific version:
```bash
  sudo ./uninstall.sh /var/lib/solidgroundux/manifests/SolidgroundUX-x.y.z.manifest
```
The uninstaller removes only files listed in the manifest and cleans up empty directories.

### 🛠️ Script development
Once SolidgroundUX has been installed:

- Create a new script repository using `td-create-workspace`
- Copy or generate an executable template
- Open the generated script and implement your logic inside `main()`
- Proceed…

### Notes

- Multiple release archives may coexist, but only one version should be installed on a system at a time
- Uninstallation is always manifest-driven; no files outside the manifest are touched
- Development installs using --target-root are fully isolated from the system

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

### 🧱 Repository layout
```text
/target-root
├── etc/
|   ├── systemmd
|   |  └── system
|   ├── testadura                        _*.cfg-files_
|   └── update-motd.d                   _Message of the day_       
├── share
|   └── doc
|       └── solidgroundux               _README.md, LICENSE_
└── usr
    └── local
    |   ├── bin                         _Executables not requiring root_                  
    |   ├── lib
    |   |    └── testadura
    |   |        ├── styles             _Style constant overrides_     
    |   |        └── common             _Core libraries_
    |   |            ├── templates      _Developemnt templates_
    |   |            └── tools          _Machine and repo management tools_
    |   └── sbin                        _Executables requiring root_
    ├── var
    |   └── lib
    |       ├── testadura               _*.state-files_
    └── log
        └── testadura                   _solidgroundux.log_       
Alternates:
    ~/.config/testadura                 _*.cfg-files_
    ~/.log
        └── testadura                   _solidgroundux.log_    
```
## 🧰 Included Tools

SolidgroundUX ships with four tools to make your life a bit easier:

### **1. td-create-workspace**
Creates a new script workspace based on SolidgroundUX conventions.

It:
- Generates a folder structure
- Copies the template scripts to the repository
- Creates a default script based on the exe-template
- Optionally adds argument parsing and config support
- Ensures consistent bootstrap + constructor setup  

This is the recommended way to start new scripts.

### **2. td-deploy-workspace**
Deploys the entire `target-root` directory onto a real system.

It:
- Mirrors directory structure under `/usr/local`
- Preserves permissions
- Supports dry-run mode
- Detects updates cleanly
- Safely installs Testadura/SolidgroundUX framework files
- Optionally creates symlinks to executable scripts in `bin` or `bins`, as an alternative to wrapper scripts

This is the mechanism used to install SolidgroundUX or update existing deployments.

### **3. td-prepare-release**
Prepares a workspace for distribution.

It:
- Assembles a clean, versioned release tree
- Excludes state, logs, and development artifacts
- Validates permissions and layout
- Produces a tar-based release suitable for deployment

This tool is used to create reproducible, install-ready releases.

### **4. td-clone-config**
Basic setup and configuration of a newly cloned/installed machine

It:
- Offers a menu to selectively configure 
    - MachineID
    - Network 
    - Samba domain membership
    - Prepare a machine for cloning
    
### **5. td-script-hub**

`td-script-hub` is the execution environment that turns individual SolidgroundUX scripts into a structured, discoverable system.

Rather than invoking scripts directly, the Script Hub provides:

- Automatic discovery of executable modules
- A consistent, menu-driven interface
- Centralized run modes (Commit, Dry-Run, Verbose)
- Predictable execution order and grouping
- Unified UI output and logging behavior

At its core, the hub establishes **convention-based structure** without obscuring the fact that everything remains plain Bash.

#### Concepts at a glance

- **Hub**  
  A logical root that owns a namespace, module directory, runtime flags, and shared UI state.

- **Module**  
  A self-contained directory discovered by the hub. Modules typically contain an `app.sh` entry point and related helpers.

- **Applet**  
  The executable identity of a module, defining menu entries, titles, and handlers. Applets are activated through the hub, not executed directly.

- **Menu model**  
  Menu entries are registered as specifications, compiled into normalized items, grouped, ordered, and rendered deterministically.

- **Run modes**  
  Execution modifiers that apply globally:
  - **Commit** – perform real actions
  - **Dry-Run** – simulate without side effects
  - **Verbose** – expose internal decisions

Run modes are always visible and treated as first-class controls, not optional flags.

The Script Hub is optional, but once adopted it becomes the canonical way to compose, run, and reason about SolidgroundUX-based tooling.

For a deeper explanation of the execution model and design principles, see the Script Hub documentation in  
`/usr/local/share/doc/solidgroundux`.



## 🏷 License

Licensed under the **Testadura Non-Commercial License (TD-NC)**.  
See `LICENSE` for details.

---

### Design Note

If you are looking for implicit behavior, clever hacks, or magical globals —  
**this framework is not for you**.

SolidgroundUX is for people who want to know exactly what their scripts are doing.