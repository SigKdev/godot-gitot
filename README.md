# Gitot

A lightweight Git workflow plugin for the Godot 4 editor — pure GDScript, no GDExtension, no `libgit2`. Gitot wraps your system's `git` binary directly, so it inherits your existing SSH/credential setup and the full Git feature set without reimplementing any of it.

## Why

The official Godot Git plugin relies on a compiled `libgit2` GDExtension, which can be fragile, slow to update, and limited in feature coverage. Gitot takes a different approach: a standalone `EditorPlugin` written entirely in GDScript that shells out to your local `git` CLI. This trades a small amount of raw performance for stability, transparency, and zero maintenance burden across engine/OS updates.

## Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`

## Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

## Features (v0.1 MVP)

- **Failsafe startup** — verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution** — local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Git dock** — Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click stage/unstage.
- **Commit & sync** — commit message input, and Commit / Push / Pull buttons.
- **Color-only diff gutter** — modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh Diff** fallback button.
- **Large-file guard** — blocks staging any file ≥50MB to prevent accidental repository bloat.

## Known Limitations

These are documented, verified engine behaviors — not assumptions:

- Godot's `resource_saved` signal does not fire for all save paths (e.g. Run Project/Scene auto-saves). Use the **Refresh Diff** button to catch up manually in those cases.
- The diff gutter only applies to **tracked** files — untracked (never-committed) files have no `HEAD` version to diff against.
- After a `Pull`, changed scripts already open in the editor won't visually refresh. This is a known Godot engine limitation ([godotengine/godot#104540](https://github.com/godotengine/godot/issues/104540)), Godot may fail to show the update even after closing/reopening the tab (known engine bug: ([godotengine/godot#59115](https://github.com/godotengine/godot/issues/59115)). **Restarting the editor guarantees correct content.**
- Pushing/pulling relies on your system Git's own credential handling (SSH agent, Git Credential Manager, etc.). Gitot does not manage credentials. 

## Planned / Deferred (post-MVP)

- `.gitignore` generator (as an opt-in setting, not automatic)
- GitHub Issues tracker panel
- Git LFS support and asset locking
- Branch management UI
- Hunk-level (partial file) staging
- Diff hover popup / bottom-dock full diff view

## Architecture

- `gitot.gd` — `EditorPlugin` entry point; lifecycle and wiring only.
- `core/git_engine.gd` — all `git` CLI execution (sync-fast and async-network paths).
- `core/git_status_parser.gd` — parses `git status --porcelain=v2`.
- `core/git_diff_parser.gd` — parses `git diff -U0` hunk headers.
- `ui/gitot_dock.tscn` — dock UI scene.
- `ui/gitot_dock.gd` — dock UI logic.
- `ui/gitot_diff_gutter.gd` — script editor gutter coloring.

Each module is decoupled via signals; the Git engine has no knowledge of UI, and the UI never calls `OS.execute()` directly.

## License

Copyright (c) 2026-present SigK - under the MIT License.