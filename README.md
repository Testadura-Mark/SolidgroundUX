SoluxGround is a small, powerful Bash framework designed for system engineers,
developers, automation builders, and anyone who wants clean, structured, reliable
shell scripts — without the usual mess or over-engineered tooling.

It provides:

- A predictable bootstrap lifecycle  
- Robust argument parsing  
- Clear, styled UI output  
- Practical helpers for deployment and file management  
- A consistent template system for building new scripts  

SoluxGround is built on decades of practical scripting experience, with the simple
mission of making Bash *civilized*.

---

## 🏷 Badges

![License: TD-NC](https://img.shields.io/badge/License-TD--NC-blue.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-green)
![Status](https://img.shields.io/badge/Stability-Production%20Ready-brightgreen)
![Version](https://img.shields.io/badge/Version-1.0--R1-purple)
![Last Commit](https://img.shields.io/github/last-commit/YOUR_GITHUB_USERNAME/YOUR_REPOSITORY_NAME)
![Made in NL](https://img.shields.io/badge/Made%20in-The%20Netherlands-ff4f00?labelColor=003399)
---

## 🧭 Philosophy

SoluxGround was created to bring clarity, discipline, and reliability to Bash scripting.
Instead of relying on heavy toolchains or complex automation frameworks, it focuses on:

- **Simplicity** — Everything is explicit, readable, and easy to follow  
- **Consistency** — All scripts follow the same lifecycle and structure  
- **Predictability** — No hidden magic; behavior is always traceable  
- **Maintainability** — Designed for long-term use, not quick hacks  
- **Practicality** — Built from real-world operational experience, not trends  

The goal is simple:  
**Make Bash civilized again** — without losing the power and flexibility that make Unix scripting useful.


## ✨ Features

### 🔧 Framework Architecture
- Self-locating bootstrap system  
- Optional config-file loading  
- `constructor + run` lifecycle pattern  
- Built-in load guards (no double sourcing)  
- Automatic environment detection (development vs. installed)  
- Structured directory layout via `setdirectories`

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

---

## 📁 Repository Structure
SoluxGround is organized around a `target-root` directory, which mirrors the filesystem
layout of the environment it will be installed into. Deployment is straightforward:
the entire structure is copied to the target system, placing framework files under
`/usr/local/lib/testadura` and creating executable symlinks in `/usr/local/bin`.

The repository layout:

soluxground/ (or your projectname)
├── LICENSE
├── README.md
├── target-root/
│ ├── etc/
│ └── usr/local/lib/testadura/
│ ├── common/
│ ├── templates/
│ └── tools/

## 🧰 Included Tools

SoluxGround ships with two key tools that streamline scripting workflows:

### **1. create-workspace.sh**
Creates a new script workspace based on SoluxGround conventions.

It:
- Generates a folder structure
- Copies a template (full or minimal)
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
- Safely installs Testadura/SoluxGround framework files

This is the mechanism used to install SoluxGround or update existing deployments.

