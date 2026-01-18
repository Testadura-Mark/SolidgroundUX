# SolidgroundUX Function Glossary (by library file)

This document is a **discoverability index** of SolidgroundUX *public* helpers.

**Rules**
- Only functions **not** starting with `__` are listed.
- Functions are listed **under the library file they live in**.
- Subsections mirror the library’s own `# ---` headers where present.

**Format**
- **Function** — purpose (short)
- **Params** — brief hint (when obvious)

> This is intentionally *not* full API documentation. It’s a “does it exist?” map.

---

## `args.sh`

### Public API

- **`td_show_help`** — Generate help text derived from `TD_ARGS_SPEC`.
- **`td_parse_args`** — Parse CLI arguments according to `TD_ARGS_SPEC`.
  **Params:** `td_parse_args "$@"`
- **`td_showarguments`** — Print a diagnostic overview (script/framework + args).

---

## `cfg.sh`

### public: config

- **`td_cfg_load`** — Load `TD_CFG_FILE` (`KEY=VALUE`) into the current shell.
- **`td_cfg_set`** — Persist `KEY=VALUE` to `TD_CFG_FILE` and update current shell.
  **Params:** `td_cfg_set KEY VALUE`
- **`td_cfg_unset`** — Remove `KEY` from `TD_CFG_FILE` and unset it in current shell.
  **Params:** `td_cfg_unset KEY`
- **`td_cfg_reset`** — Reset `TD_CFG_FILE` to an empty/default file.

### public: state

- **`td_state_load`** — Load `TD_STATE_FILE` (`KEY=VALUE`) into the current shell.
- **`td_state_set`** — Persist `KEY=VALUE` to `TD_STATE_FILE` and update current shell.
  **Params:** `td_state_set KEY VALUE`
- **`td_state_unset`** — Remove `KEY` from `TD_STATE_FILE` and unset it in current shell.
  **Params:** `td_state_unset KEY`
- **`td_state_reset`** — Reset `TD_STATE_FILE` to an empty/default file.

---

## `core.sh`

### Privilege & Command Checks

- **`have`** — Test whether a command exists in `PATH`.
  **Params:** `have cmd`
- **`need_cmd`** — Require a command to exist or fail.
  **Params:** `need_cmd cmd`
- **`need_root`** — Require root; re-exec via `sudo` if needed.
- **`cannot_root`** — Require non-root.
- **`need_bash`** — Require Bash (optionally a minimum major version).
  **Params:** `need_bash [MAJOR]`
- **`need_tty`** — Require an attached TTY on stdout.
- **`is_active`** — Check whether a systemd unit is active.
  **Params:** `is_active unit`
- **`need_systemd`** — Require systemd (`systemctl`) or fail.

### Filesystem Helpers

- **`ensure_dir`** — Create a directory (including parents) if missing.
  **Params:** `ensure_dir path`
- **`exists`** — Test whether a regular file exists.
  **Params:** `exists file`
- **`is_dir`** — Test whether a directory exists.
  **Params:** `is_dir dir`
- **`is_nonempty`** — Test whether a file exists and is non-empty.
  **Params:** `is_nonempty file`
- **`need_writable`** — Require a path to be writable or fail.
  **Params:** `need_writable path`
- **`abs_path`** — Resolve an absolute canonical path.
  **Params:** `abs_path path`
- **`mktemp_dir`** — Create a temporary directory and print its path.
- **`mktemp_file`** — Create a temporary file and print its path.

### Systeminfo

- **`get_primary_nic`** — Return the primary NIC (best-effort).

### Network Helpers

- **`ping_ok`** — Return success if a host responds to a single ping.
  **Params:** `ping_ok host`
- **`port_open`** — Test if a TCP port is reachable (`nc` preferred, `/dev/tcp` fallback).
  **Params:** `port_open host port`
- **`get_ip`** — Return the first non-loopback IP.

### Argument & Environment Helpers

- **`is_set`** — Test whether a variable name is defined (`[[ -v VAR ]]`).
  **Params:** `is_set VARNAME`
- **`need_env`** — Require a named environment variable to be non-empty.
  **Params:** `need_env VARNAME`
- **`default`** — Set `VAR` to VALUE if `VAR` is unset/empty.
  **Params:** `default VAR VALUE`
- **`is_number`** — Digits-only check.
  **Params:** `is_number value`
- **`is_bool`** — Boolean-token check (`true/false/yes/no/on/off/1/0`).
  **Params:** `is_bool value`
- **`confirm`** — Ask a yes/no question; success on `[Yy]`.
  **Params:** `confirm "Question?"`

### Process & State Helpers

- **`proc_exists`** — Check if a process with a given name is running.
  **Params:** `proc_exists name`
- **`wait_for_exit`** — Block until a named process is no longer running.
  **Params:** `wait_for_exit name [timeout]`
- **`kill_if_running`** — Terminate processes by name if they’re running.
  **Params:** `kill_if_running name`

### Version & OS Helpers

- **`get_os`** — Return OS ID from `/etc/os-release`.
- **`get_os_version`** — Return `VERSION_ID` from `/etc/os-release`.
- **`version_ge`** — Compare versions: A >= B (uses `sort -V`).
  **Params:** `version_ge A B`
- **`show_script_version`** — Print script version/build metadata.

### Misc Utilities

- **`join_by`** — Join args with a separator.
  **Params:** `join_by "," a b c`
- **`trim`** — Remove leading/trailing whitespace.
  **Params:** `trim " text "`
- **`timestamp`** — Return current time as `YYYY-MM-DD HH:MM:SS`.
- **`retry`** — Retry a command N times with a delay.
  **Params:** `retry N DELAY cmd ...`
- **`strip_ansi`** — Strip ANSI SGR sequences.
  **Params:** `strip_ansi "..."`
- **`visible_len`** — Visible string length (after stripping ANSI).
  **Params:** `visible_len "..."`
- **`is_true`** — Truthy-token check.
  **Params:** `is_true value`
- **`string_repeat`** — Repeat a string N times.
  **Params:** `string_repeat text N`

### Die and exit handlers

- **`die`** — Fail fast with an error message.
  **Params:** `die "message" [exitcode]`
- **`on_exit`** — Append a command to an existing `EXIT` trap.
  **Params:** `on_exit 'cmd ...'`

---

## `td-bootstrap.sh`

### Minimal fallback UI (overridden by ui.sh when sourced)

- **`saystart`**, **`saywarning`**, **`sayfail`**, **`saydebug`**, **`saycancel`**, **`sayend`**, **`sayok`**, **`sayinfo`**, **`sayerror`** — Minimal logging fallbacks before UI is loaded.

### Loading libraries from TD_COMMON_LIB

- **`td_source_libs`** — Load required framework libraries (with guards).

### Public API

- **`td_bootstrap`** — Framework bootstrap entry point (libs, args, runmodes, cfg/state, root policy, etc.).
  **Params:** `td_bootstrap [bootstrap-flags] -- "$@"`

---

## `td-globals.sh`

### Framework settings (overridden by scripts when sourced)

- **`init_derived_paths`** — Compute derived paths from roots.
- **`init_global_defaults`** — Initialize default global values.
- **`init_script_paths`** — Derive script path metadata.

---

## `ui-ask.sh`

### ask

- **`ask`** — Prompt for interactive input (reads from TTY; independent of stdin).
  **Params:** `ask --label TEXT --var VAR [--default VALUE] [--validate FN] ...`
  **Example:**
  ```bash
  ask --label "Hostname" --var HOST --default "$HOST"
  ```

### ask shorthand

- **`ask_yesno`** — Yes/no prompt wrapper.
  **Params:** `ask_yesno "Question?"`
- **`ask_noyes`** — Yes/no prompt wrapper (reversed default semantics).
  **Params:** `ask_noyes "Question?"`
- **`ask_okcancel`** — OK/Cancel prompt wrapper.
  **Params:** `ask_okcancel "Question?"`
- **`ask_ok_redo_quit`** — OK/Redo/Quit prompt wrapper.
  **Params:** `ask_ok_redo_quit "Question?"; decision=$?`
- **`ask_continue`** — Continue prompt wrapper.
- **`ask_autocontinue`** — Auto-continue wrapper (countdown).

### File system validations

- **`validate_file_exists`** — Validate that a file exists.
- **`validate_path_exists`** — Validate that a path exists.
- **`validate_dir_exists`** — Validate that a dir exists.
- **`validate_executable`** — Validate that a path is executable.
- **`validate_file_not_exists`** — Validate that a file does *not* exist.

### Type validations

- **`validate_int`** — Validate integer.
- **`validate_numeric`** — Validate numeric.
- **`validate_text`** — Validate non-empty text.
- **`validate_bool`** — Validate bool tokens.
- **`validate_date`** — Validate date.
- **`validate_ip`** — Validate IPv4.
- **`validate_cidr`** — Validate CIDR.
- **`validate_slug`** — Validate slug-like tokens.
- **`validate_fs_name`** — Validate filename-safe tokens.

---

## `ui-dlg.sh`

### Public API

- **`td_dlg_autocontinue`** — Interactive auto-continue dialog with countdown and key controls.
  **Params:** `td_dlg_autocontinue [SECONDS] [MESSAGE] [CHOICES]`

---

## `ui-say.sh`

### say

- **`say`** — Typed message output with optional prefix parts, colors, and logging.
  **Params:** `say [TYPE] [--options] -- "message"`
  **Example:**
  ```bash
  sayinfo "Configuration loaded"
  sayfail "Missing configuration file"
  ```

- **`sayinfo`**, **`saystart`**, **`saywarning`**, **`sayfail`**, **`saycancel`**, **`sayok`**, **`sayend`**, **`saydebug`** — Convenience wrappers.
- **`justsay`** — Minimal “print message” helper.
- **`say_test`** — Self-test helper.

---

## `ui.sh`

### Public API

- **`td_print_globals`** — Print framework globals (system/user/both).
  **Params:** `td_print_globals [sys|usr|both]`
- **`td_print_labeledvalue`** — Print `Label : Value` lines with width/sep options.
  **Params:** `td_print_labeledvalue "Label" "Value" [--opts]`
- **`td_print_fill`** — Print one line with left/right content separated by fill.
  **Params:** `td_print_fill "Left" "Right" [--opts]`
- **`td_print_titlebar`** — Print a framed title bar (supports right-aligned text).
  **Params:** `td_print_titlebar [--opts]`
- **`td_print_sectionheader`** — Print a full-width section header line.
  **Params:** `td_print_sectionheader "Title" [--opts]`

