# Gitot

A lightweight Git workflow plugin for the Godot 4 editor in pure GDScript intended for solo developers who want fast, reliable local Git operations (status, stage/unstage, commit, push/pull) and inline diff visibility without leaving the editor.

## Why

Gitot wraps the system `git` binary directly via `OS.execute()`, in pure GDScript, with no GDExtension and no bundled `libgit2`. It inherits your existing SSH/credential setup and the full Git feature set without re-implementing any of it. This trades a small amount of raw performance for stability, transparency, and zero maintenance burden across engine/OS updates.

If `git` works from your terminal, it works from Gitot because it *is* your terminal's git.

## Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`

## Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

## Features (v0.1.0 MVP)

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Git dock:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click stage/unstage.
- **Commit & sync:** commit message input, and Commit / Push / Pull buttons.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh Diff** fallback button.
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.

## Known Limitations

These are documented, verified engine behaviors:

- After a `Pull`, changed scripts already open in the editor won't visually refresh. This is a known Godot engine limitation ([godotengine/godot#104540](https://github.com/godotengine/godot/issues/104540)), Godot may fail to show the update even after closing/reopening the tab (known engine bug: ([godotengine/godot#59115](https://github.com/godotengine/godot/issues/59115)). **Restarting the editor guarantees correct content.**
- Godot's `resource_saved` signal does not fire for all save paths (e.g. Run Project/Scene auto-saves). Use the **Refresh Diff** button to catch up manually in those cases.
- The diff gutter only applies to **tracked** files — untracked (never-committed) files have no `HEAD` version to diff against.

## Credential Handling

Pushing/pulling relies on your system Git's own credential handling (SSH agent, Git Credential Manager, etc.).
**Gitot does not manage credentials!**
Gitot does not suppress OS-level credential prompts (e.g. Windows Git Credential Manager popups). If push/pull hangs waiting on such a prompt, it will be automatically killed after 30 seconds.
Configure a working credential helper or SSH agent so `git push`/`git pull` succeed from a terminal before relying on Gitot for sync.

## Planned Features

- GitHub Issues tracker panel
- Git LFS support and asset locking
- Branch management UI
- Hunk-level (partial file) staging
- Diff hover popup / bottom-dock full diff view
- `.gitignore` generator (as an opt-in setting, not automatic)

## Architecture

- `gitot.gd` — `EditorPlugin` entry point; lifecycle and wiring only.
- `core/git_engine.gd` — all `git` CLI execution (sync-fast and async-network paths).
- `core/git_status_parser.gd` — parses `git status --porcelain=v2`.
- `core/git_diff_parser.gd` — parses `git diff -U0` hunk headers.
- `ui/gitot_dock.tscn` — dock UI scene.
- `ui/gitot_dock.gd` — dock UI logic.
- `ui/gitot_diff_gutter.gd` — script editor gutter coloring.

Each module is decoupled via signals; the Git engine has no knowledge of UI, and the UI never calls `OS.execute()` directly.

## Updates

<details>
<summary>v0.1.1</summary>

fix: harden MVP v0.1.0 - correctness, lifecycle, security, performance

Phase A — Correctness:
- Fix inverted git-missing failsafe (real push_error, no false success)
- Wire missing Pull button connection
- Gate all success/failure messaging on real exit_code, not string-matching
- Pin all git calls to project root (-C) instead of editor CWD
- Fix porcelain v2 path parsing to preserve spaces in filenames
- Remove dead code (_on_diff_test, unused locals, TEMP prints)
- Run initial status on dock ready

Phase B — Memory & Lifecycle:
- Disconnect all signals and null refs on plugin exit
- Delete temp git log files after read
- Null-check FileAccess.open() before use
- Kill in-flight push/pull processes on plugin disable

Phase C — Security:
- Document shell-string safety boundary in run_network()
- Extend 50MB guard to directory staging (recursive scan)
- Document credential-handling boundary in README

Phase D — Performance:
- Compile diff parser regex once instead of per-hunk
- Remove duplicate _old_count() call

Phase E — Architecture (SoC):
- Move status-refresh orchestration from dock to plugin composition root
- Correct run_fast() doc comment (read/write, not read-only)
<hr>
</details>

v0.1.0 (Initial MVP commit)

## License

Copyright (c) 2026-present SigK - under the MIT License.