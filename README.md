# Gitot

A lightweight Git workflow plugin for the Godot 4 editor in pure GDScript intended for solo developers who want fast, reliable local Git operations (status, stage/unstage, commit, push/pull) and inline diff visibility without leaving the editor.

## Why

Gitot wraps the system `git` binary directly via `OS.execute()`, in pure GDScript, with no GDExtension and no bundled `libgit2`. It inherits your existing SSH/credential setup and the full Git feature set without re-implementing any of it. This trades a small amount of raw performance for stability, transparency, and zero maintenance burden across engine/OS updates.

**If Git works from your terminal, it works from Gitot because it use your terminal's git.**

## Features MVP (v0.2.0)

- **Commit & Sync:** Staging/Unstaging, commit message input, and Commit / Push / Pull buttons.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter.
- **GitHub Issues Tracker Board:** display remote GitHub issues of the project (read: [PAT](###github-personal-access-token) section).
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.

<details>
<summary>Details</summary>

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Git dock:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click stage/unstage.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh Diff** fallback button.
- **GitHub Issues Tracker Board:** display remote GitHub issues of the project. PAT auth, issue fetch, PR filter, main-screen panel.
</details>

## Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`

## Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

## Known Limitations

These are documented, verified engine behaviors:

- After a `Pull`, changed scripts already open in the editor won't visually refresh. This is a known Godot engine limitation ([godotengine/godot#104540](https://github.com/godotengine/godot/issues/104540)), Godot may fail to show the update even after closing/reopening the tab (known engine bug: ([godotengine/godot#59115](https://github.com/godotengine/godot/issues/59115)). **Restarting the editor guarantees correct content.**
- Godot's `resource_saved` signal does not fire for all save paths (e.g. Run Project/Scene auto-saves). Use the **Refresh Diff** button to catch up manually in those cases.
- The diff gutter only applies to **tracked** files — untracked (never-committed) files have no `HEAD` version to diff against.

## Credential Handling

### SSH

Pushing/pulling relies on your system Git's own credential handling (SSH agent, Git Credential Manager, etc.).
**Gitot does not manage credentials!**
Gitot does not suppress OS-level credential prompts (e.g. Windows Git Credential Manager popups). If push/pull hangs waiting on such a prompt, it will be automatically killed after 30 seconds.
Configure a working credential helper or SSH agent so `git push`/`git pull` succeed from a terminal before relying on Gitot for sync.

### GitHub Personal Access Token

**Gitot** stores your GitHub PAT locally in plaintext at `user://gitot_auth.cfg`
(outside `res://`, so it is never committed to your repository).

**This is not encrypted.** Godot/GDScript cannot access your OS-level
credential store (Windows Credential Manager, macOS Keychain, etc.) without
a native extension, which is outside this plugin's scope. **Anyone with access
to your local user account can read this file.**

**Recommendations:**
- Generate a token scoped to `repo` access only — never an admin or org-wide token.
- Use the **Clear Token** button in the GitHub panel toolbar before uninstalling
  or disabling the plugin, or when working on a shared machine.
- If a token expires or is revoked, Gitot detects this automatically (HTTP 401)
  and re-prompts for a new one.

## Planned Features

[x] Commit & Sync (commit/push/pull)
[x] Color-only diff gutter
[x] GitHub Issues Tracker Board
[ ] Git LFS support and asset locking
[ ] Branch management UI
[ ] Hunk-level (partial file) staging
[ ] Diff hover popup / bottom-dock full diff view
[ ] `.gitignore` generator (as an opt-in setting, not automatic)

## Architecture

- `gitot.gd` — `EditorPlugin` entry point; lifecycle, wiring, and main-screen tab registration.
- `core/git_engine.gd` — all `git` CLI execution (sync-fast and async-network paths).
- `core/git_status_parser.gd` — parses `git status --porcelain=v2`.
- `core/git_diff_parser.gd` — parses `git diff -U0` hunk headers.
- `core/github_auth.gd` — PAT storage (`user://gitot_auth.cfg`, plaintext — see Security).
- `core/github_api.gd` — authenticated `HTTPRequest` wrapper for the GitHub REST API.
- `ui/gitot_dock.tscn` / `gitot_dock.gd` — local Git dock UI (stage, commit, push/pull).
- `ui/gitot_diff_gutter.gd` — script editor gutter coloring.
- `ui/github_panel.tscn` / `github_panel.gd` — GitHub Issues main-screen tab; owns `GithubApi`, fetches on first tab-open.
- `ui/github_auth_dialog.tscn` / `github_auth_dialog.gd` — PAT entry modal, opened on first use or 401.
- `ui/issue_card.tscn` / `issue_card.gd` — single issue card (title, labels, body, browser link).

Each module is decoupled via signals; the Git engine has no knowledge of UI, and the UI never calls `OS.execute()` directly.

## Detailed Updates

<details>
<summary>v0.2.0</summary>

feature: GitHub Issues Tracker Board

- PAT storage (user://, plaintext, scoped-token documented as security boundary)
- Auth modal with retry-on-401 flow
- HTTPRequest wrapper (github_api.gd), PR-excluded issue fetch
- Auto-detected owner/repo via git remote parsing
- Main-screen tab with issue cards, first-tab-open fetch
- Clear Token button (panel toolbar) for explicit PAT lifecycle control
<hr>
</details>

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

<details>
<summary>v0.1.0</summary>

Initial MVP commit

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Git dock:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click stage/unstage.
- **Commit & Sync:** stage/unstage, commit message input, and Commit / Push / Pull buttons.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh Diff** fallback button.
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.
</details>

## License

Copyright (c) 2026-present SigK - under the MIT License.

