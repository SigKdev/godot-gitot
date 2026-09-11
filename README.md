# Gitot - WIP

A lightweight Git workflow plugin for the Godot 4 editor in pure GDScript intended for solo developers who want fast, reliable local Git operations (stage/unstage, commit, push/pull), inline diff visibility and issue tracker without leaving the editor.

Gitot wraps the system `git` binary directly via `OS.execute()`, in pure GDScript, with no GDExtension and no bundled `libgit2`. It inherits your existing SSH/credential setup and the full Git feature set without re-implementing any of it. This trades a small amount of raw performance for stability, transparency, and zero maintenance burden across engine/OS updates.

**If Git works from your terminal, it works from Gitot because it use your terminal's git setup.**

---

## Features (v0.4.0)

- **Commit & Sync:** Single and bulk Staging/Unstaging, commit message (multiline supported), and Commit / Push / Pull buttons.
- **Tags Versioning:** Push commit with or without annotated tag. *(auto tagging settings - see details)*. (read: [Limitation](#known-limitations)).
- **Color-only diff gutter:** Modified and added lines are marked directly in the script editor's gutter.
- **GitHub Issues Tracker Board:** Display remote GitHub issues of the project repo (read: [PAT](#github-personal-access-token)). **(opt-out in settings)**.
- **Large-file guard:** Blocks staging any file over a configurable size to prevent accidental repository bloat. Add a warning icon on those file in the staged/unstaged list.

<details>
<summary>Details</summary>

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Commit & Sync (Gitot dock):** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with single and bulk stage/unstage. Status color (no color=modified, green=untracked, red=deleted). Warning icon for conflicted file and large-file guard.
- **Tags Versioning:** Tag is push with commit. Settings to auto use Version *(from project settings)* for the tag's name (with auto `v` prefix) and the commit message for the tag's message. (read: [Limitation](#known-limitations)).
- **Gitot settings panel:** Add Settings (user://gitot_settings.cfg), large_file_mb, confirm_push, auto_refresh_on_focus, github_issues_enabled.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably), on Godot editor focus, and a manual **Refresh Diff Gutter** fallback button.
- **GitHub Issues Tracker Board:** (opt-out in settings possible). Issue report include: number, title, author, date, tags, content of the issue and a link to open it in the browser. *PAT auth, issue fetch, PR filter, main-screen panel.*
- **Large-file guard:**  Size configurable in settings, *0 to disable*.
</details>

### Planned Features

- [x] Commit & Sync (commit/push/pull)
- [x] Color-only diff gutter
- [x] GitHub Issues Tracker Board
- [x] Commit with tags versioning
- [ ] Branch Management
- [ ] Diff hover popup & bottom-dock full diff view
- [ ] Stash Quick-Actions
- [ ] Local Stash Manager
- [ ] Git LFS support and asset locking
- [ ] Ignore Preset Manager, `.gitignore` generator
- [ ] Asset Dependency Analyzer
- [ ] Pre-Commit Scene Linter
- [ ] Hunk-level (partial file) staging
- [ ] .....

---

## Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`.
- A GitHub Personal Access Token ([PAT](#github-personal-access-token)), **only for the GitHub Issues Tracker Board feature**.

## Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

## Known Limitations

These are documented, verified engine behaviors:

- After a `Pull`, changed scripts already open in the editor won't visually refresh. This is a known Godot engine limitation ([godotengine/godot#104540](https://github.com/godotengine/godot/issues/104540)), Godot may fail to show the update even after closing/reopening the tab (known engine bug: ([godotengine/godot#59115](https://github.com/godotengine/godot/issues/59115)). **Restarting the editor guarantees correct content.**
- Godot's `resource_saved` signal does not fire for all save paths (e.g. Run Project/Scene auto-saves). Use the **Refresh Diff Gutter** button to catch up manually in those cases. Or switch away from the Godot windows and switch back to trigger auto-refresh (see in settings).
- The diff gutter only applies to **tracked** files — untracked (never-committed) files have no `HEAD` version to diff against.
- **Tags Versioning** self-heals from a failed tag push: if `Push` previously created a tag locally but failed to push it (network/timeout), retrying will detect the existing local tag and **push it as-is** instead of erroring. **Caveat:** if you reuse a tag name that already exists locally from an *unrelated*, fully-completed push (pointing at an older commit), **Gitot will push that existing tag silently instead of creating a new one (no error is shown)**. Verify on GitHub that the tag lands on the commit you expect, or use a unique tag name to avoid collisions.

## Credential Handling

#### SSH

Pushing/pulling relies on your system Git's own credential handling (SSH agent, Git Credential Manager, etc.).
**Gitot does not manage credentials!**
Gitot does not suppress OS-level credential prompts (e.g. Windows Git Credential Manager popups). If push/pull hangs waiting on such a prompt, it will be automatically killed after 30 seconds.
Configure a working credential helper or SSH agent so `git push`/`git pull` succeed from a terminal before relying on Gitot for sync.

#### GitHub Personal Access Token

Only needed to use the **GitHub Issues Tracker Board** feature.

**Gitot** stores your GitHub PAT locally in plaintext at `user://gitot_auth.cfg`
(outside `res://`, so it is never committed to your repository).

**This is not encrypted.** Godot/GDScript cannot access your OS-level
credential store (Windows Credential Manager, macOS Keychain, etc.) without
a native extension, which is outside this plugin's scope.
**Anyone with access to your local user account can read this file.**

**PAT Recommendations:**

- Generate a token scoped to `repo` access only — never an admin or org-wide token.
- Use the **Clear Token** button in the Gitot Issues panel toolbar before uninstalling
  or disabling the plugin, or when working on a shared machine.
- If a token expires or is revoked, Gitot detects this automatically (HTTP 401)
  and re-prompts for a new one.

## Architecture

Gitot is split into decoupled domain modules under `core/` (git and GitHub logic) and `ui/` (presentation only).
Each module is decoupled via signals; the Git engine has no knowledge of UI, and the UI never calls `OS.execute()` directly.

<details>
<summary>Core</summary>

- `gitot.gd` - `EditorPlugin` entry point; lifecycle, wiring, and main-screen tab registration.
- `core/git_engine.gd` - all `git` CLI execution (sync-fast and async-network paths).
- `core/git_sync_orchestrator.gd` - push -> create-tag -> push-tag state machine; reacts to `GitEngine.command_completed`, decoupled from UI via signals.
- `core/git_status_parser.gd` - parses `git status --porcelain=v2`.
- `core/git_diff_parser.gd` - parses `git diff -U0` hunk headers.
- `core/github_auth.gd` - PAT storage (`user://gitot_auth.cfg`, plaintext)(read: [PAT](#github-personal-access-token) section).
- `core/github_api.gd` - authenticated `HTTPRequest` wrapper for the GitHub REST API.
- `core/gitot_settings.gd` - `GitotSettings`, settings storage (`user://gitot_settings.cfg`, plaintext, non-sensitive values only).
</details>

<details>
<summary>Ui</summary>

- `ui/gitot_dock.tscn` / `gitot_dock.gd` - local Git dock UI shell (wiring, commit/push/pull handlers);
- `ui/gitot_status_tree.gd` - Staged/Unstaged file trees: population, staging/unstaging, bulk actions, size guard.
- `ui/gitot_tag_panel.gd` - tag-versioning UI: toggles, version-tag formatting, tag input resolution.
- `ui/gitot_settings_panel.gd` - settings panel UI; self-contained, reads/writes `GitotSettings` directly.
- `ui/gitot_diff_gutter.gd` - script editor gutter coloring.
- `ui/github_panel.tscn` / `github_panel.gd` - GitHub Issues Tracker Board, main-screen tab, owns `GithubApi`, fetches on first tab-open.
- `ui/github_auth_dialog.tscn` / `github_auth_dialog.gd` - [PAT](#github-personal-access-token) entry modal, opened on first use or 401.
- `ui/issue_card.tscn` / `issue_card.gd` - single issue card (title, author, date, labels, body, browser link).
</details>

---

## Changelog

<details>
<summary>v0.4.0</summary>

feat & fix: Tags Versioning, safeguard, cleanup gitot_dock.gd (SoC)...

- Cleaned `gitot_dock.gd`, split into `gitot_status_tree.gd` and `gitot_tag_panel.gd`.
- `GitEngine.create_tag()` / `push_tag()` primitives.
- Dock UI: tag versioning toggle, project-version/manual tag name, commit-message/manual tag message, dynamic version label with auto `v` prefix.
- Orchestration chain: chain in `git_sync_orchestrator.gd`: push → tag → push_tag, with per-step console feedback.
- Guards: empty tag name, empty tag message, empty commit message - all pre-push, no silent partial states.
- Retry button for failed `push_tag` command. (query directly `git log -1`).
- Self-heal on "tag already exists" (read: [Limitation](#known-limitations)).
- `read_stderr=true` fix in `_execute_and_report` - makes stderr visible on *every* `fast command` (status, diff, add, restore, commit too), not just tag, which is good for future error handling.
<hr>
</details>

<details>
<summary>v0.3.0</summary>

feat & fix: bulk stage/unstage, settings panel, status coloring, list fixes...

- Fix untracked folder collapse (--untracked-files=all).
- Fix status args drift via GitEngine.STATUS_ARGS.
- Fix bulk-stage rename mis-parse via --no-renames.
- Fix _refresh_status() null git_engine crash on editor startup.
- Add Stage All / Unstage All with per-file size-guard skip.
- Color-code + icon unstaged entries (new/modified/deleted/conflict/oversized).
- Guard root-item click on both trees".
- Add Settings (user://gitot_settings.cfg): large_file_mb, confirm_push, auto_refresh_on_focus.
- Add collapsible settings panel UI (gear icon in dock TopBar).
- Wire large-file guard, push confirmation, and focus-refresh to settings.
- Add Push/Pull loading state feedback.
<hr>
</details>

<details>
<summary>v0.2.0</summary>

feature: GitHub Issues Tracker Board.

- PAT storage (user://, plaintext, scoped-token documented as security boundary).
- Auth modal with retry-on-401 flow.
- HTTPRequest wrapper (github_api.gd), PR-excluded issue fetch.
- Auto-detected owner/repo via git remote parsing.
- Main-screen tab with issue cards, first-tab-open fetch.
- Clear Token button (panel toolbar) for explicit PAT lifecycle control.
<hr>
</details>

<details>
<summary>v0.1.1</summary>

fix: harden MVP v0.1.0 - correctness, lifecycle, security, performance.

Correctness:
- Fix inverted git-missing failsafe (real push_error, no false success).
- Wire missing Pull button connection.
- Gate all success/failure messaging on real exit_code, not string-matching.
- Pin all git calls to project root (-C) instead of editor CWD.
- Fix porcelain v2 path parsing to preserve spaces in filenames.
- Remove dead code (_on_diff_test, unused locals, TEMP prints).
- Run initial status on dock ready.

Memory & Lifecycle:
- Disconnect all signals and null refs on plugin exit.
- Delete temp git log files after read.
- Null-check FileAccess.open() before use.
- Kill in-flight push/pull processes on plugin disable.

Security:
- Document shell-string safety boundary in run_network().
- Extend 50MB guard to directory staging (recursive scan).
- Document credential-handling boundary in README.

Performance:
- Compile diff parser regex once instead of per-hunk.
- Remove duplicate _old_count() call.

Architecture (SoC):
- Move status-refresh orchestration from dock to plugin composition root.
- Correct run_fast() doc comment (read/write, not read-only).
<hr>
</details>

<details>
<summary>v0.1.0</summary>

Initial MVP commit

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Git dock:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click stage/unstage.
- **Commit & Sync:** stage/unstage, commit message input (multiline supported), and Commit / Push / Pull buttons.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh Diff** fallback button.
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.
</details>

## License

Copyright (c) 2026-present SigK - under the MIT License.

