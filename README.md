# Gitot

A lightweight Git workflow plugin for the Godot 4 editor in pure GDScript intended for solo developers who want fast, reliable local Git operations (stage/unstage, commit, stash/pop, push/pull), inline diff visibility and issue tracker without leaving the editor.

**Gitot** wraps the system `git` binary directly via `OS.execute()`, in pure GDScript, with no GDExtension and no bundled `libgit2`. It inherits your existing SSH/credential setup and the full Git feature set without re-implementing any of it. This trades a small amount of raw performance for stability, transparency, and zero maintenance burden across engine/OS updates.

**If Git works from your terminal, it works from Gitot because it use your terminal's git setup.**

---

## Features (v0.7.1)

- **Commit & Sync:** Single and bulk Staging/Unstaging, commit message (multiline supported), and Commit / Push / Pull buttons.
- **Stash Quick-Actions:** One-click stash and pop from the dock toolbar, for shelving experimental changes before a branch switch.
- **Local Branch Management:** Switch branches, create new local branches. Scenes open in the editor refresh automatically on switch, without a full project rescan. (read: [Limitation](#known-limitations))
- **Remote Branch Management:** Fetch button, remote-only branches listed and checked out with automatic tracking.
- **Gitot Settings Panel:** A one-line Status panel summarizing current repo, current branch (detached HEAD flagged in red), branch scope and ahead/behind sync status.
- **Tags Versioning:** Push with/without annotated tag. *(auto tagging settings - see details)*. (read: [Limitation](#known-limitations)).
- **Commit History:** List of recent commits (message, author, date) with a count filter (10/20/30).
- **Color-only diff gutter:** Modified and added lines are marked directly in the script editor's gutter.
- **GitHub Issues Tracker Board:** Display remote GitHub issues of the project repo (read: [PAT](#github-personal-access-token)). **(opt-out in settings)**.
- **Large-file guard:** Blocks staging any file over a configurable size to prevent accidental repository bloat. Add a warning icon on those file in the staged/unstaged list.
- **Gitot Logger:** To not bloat the Godot output log, Git and Gitot output are routed through Gitot own dock logger. (Styled with Godot's own console font).

<details>
<summary>Details</summary>

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Commit & Sync:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with single and bulk stage/unstage. Status color & icon. Warning icon for conflicted file and large-file guard. Push targets `-u origin HEAD`.
- **Stash Quick-Actions:** One-click stash with `-u` flag (staged + unstaged + untracked) and pop from the dock toolbar. Fixed stash message. Pop conflicts output.
- **Local Branch Management:** Branch dropdown, and a "new branch" button/dialogue. On switch/create, only files git actually changed are refreshed - `EditorFileSystem.update_file()` for cache bookkeeping, plus `EditorInterface.reload_scene_from_path()` for any of those files currently open in a tab - avoiding the full-project `scan()` noise that a refresh would trigger.
- **Remote Branch Management:** `git fetch origin` via button, refreshing the branch list on success. Remote-tracking branches with no local counterpart appear in the dropdown, selecting one runs `switch -c <name> --track origin/<name>` in one atomic op. Full name and branch scope on tooltip.
- **Repo Status Panel:** Show `owner/repo · branch (local/remote) · ↑ahead ↓behind`. Updates live on every status-triggering command. Detached HEAD shown in red in place of a branch name. Ahead/behind only logs to console on actual change, not on redundant refreshes (e.g. focus-in polling).
- **Tags Versioning:** Tag is push with commit. Settings to auto use Version *(from project settings)* for the tag's name (with auto `v` prefix) and the commit message for the tag's message. (read: [Limitation](#known-limitations)).
- **Commit History:** `git log` parsed via `\x1f`-delimited format string. Count-filtered dropdown (10/20/30, default reflects last selection). Relative date shown in-list, exact short date (`YYYY-MM-DD HH-MM`) on date hover tooltip. Auto-refreshes alongside status on the same trigger set (commit/push/pull/switch) and on manual *Refresh Status* fallback button.
- **Gitot Settings Panel:** Add Settings (user://gitot_settings.cfg), large_file_mb, confirm_push, auto_refresh_on_focus, github_issues_enabled.
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably), on Godot editor focus, and a manual **Refresh Diff Gutter** fallback button.
- **GitHub Issues Tracker Board:** (opt-out in settings possible). Issue report include: number, title, author, date, tags, content of the issue and a link to open it in the browser. *PAT auth, issue fetch, PR filter, main-screen panel.*
- **Large-file guard:**  Size configurable in settings, *0 to disable*.
- **Gitot Logger:** Output routed through `GitotLogger`, so they can be filter out of Godot output log with the "standard output message" filter.
</details>

### Planned Features

- [x] Commit & Sync (commit/push/pull)
- [x] Color-only diff gutter
- [x] GitHub Issues Tracker Board
- [x] Commit with tags versioning
- [x] Local Branch Management
- [x] Commit History
- [x] Stash Quick-Actions
- [x] Remote Branch Management
- [ ] Diff hover popup & bottom-dock full diff view
- [ ] Stash Manager
- [ ] Git LFS support and asset locking
- [ ] Ignore Preset Manager, `.gitignore` generator
- [ ] Asset Dependency Analyzer
- [ ] Pre-Commit Scene Linter
- [ ] Hunk-level (partial file) staging
- [ ] .....

### Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`.
- A GitHub Personal Access Token ([PAT](#github-personal-access-token)), **only for the GitHub Issues Tracker Board feature**.

### Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

---

## Known Limitations

- After a `Pull` or a branch `Switch`, changed scripts already open in the editor won't visually refresh. This is a known Godot engine limitation ([godotengine/godot#104540](https://github.com/godotengine/godot/issues/104540)), Godot may fail to show the update even after closing/reopening the file ([godotengine/godot#59115](https://github.com/godotengine/godot/issues/59115)). **Use Project → Reload Current Project** or **restarting the editor** to force a refresh and guarantees correct content. **close/reopen the affected script tab *before* switching branches next time.**

- Godot's `resource_saved` signal does not fire for all save paths (e.g. Run Project/Scene auto-saves). Use the **Refresh Diff Gutter** button to catch up manually in those cases. Or switch away from the Godot windows and switch back to trigger auto-refresh (see in settings).

- **Branch Management** scene/resource refresh relies on the git reflog (`HEAD@{1}`) to detect changed files, so it only compares against the immediately-previous checkout. On the very first switch after a fresh clone (no prior reflog entry) or after multiple rapid switches, the changed-file list may be empty and open tabs won't auto-refresh - close/reopen the tab manually in that case.

- Switching to a branch whose `project.godot` differs from the current one *(e.g. different enabled plugins/autoloads)* triggers Godot's own **"File has been modified outside Godot"** dialog for `project.godot`. This is a Godot editor behavior outside Gitot's control (separate watcher from `EditorFileSystem`) - click **Reload from Disk** reflects the real branch content.

- **Tags Versioning** self-heals from a failed tag push: if `Push` previously created a tag locally but failed to push it (network/timeout), retrying will detect the existing local tag and **push it as-is** instead of erroring. **Caveat:** if you reuse a tag name that already exists locally from an *unrelated*, fully-completed push (pointing at an older commit), **Gitot will push that existing tag silently instead of creating a new one (no error is shown)**. Verify on GitHub that the tag lands on the commit you expect, or use a unique tag name to avoid collisions.

- **Stash** includes untracked files (`-u` flag). Popping after switching branches can reintroduce files that conflict with the new branch's content. Same underlying risk as any `switch` with pending changes.

- The diff gutter only applies to **tracked** files. Untracked (never-committed) files have no `HEAD` version to diff against.

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

**This is not encrypted.** Godot/GDScript cannot access your OS-level credential store (Windows Credential Manager, macOS Keychain, etc.) without a native extension, which is outside this plugin's scope.
**Anyone with access to your local user account can read this file.**
And the Godot hot-reload and `_exit_tree()` make it not possible to auto clear the PAT when uninstalling/disabling Gitot.
**User must click "Clear Token" before uninstalling/disabling**

**PAT Recommendations:**

- Use a token scoped to `repo` access only. Never an admin or org-wide token!
- Use the **Clear Token** button in the Gitot Issues Panel toolbar **before uninstalling or disabling the plugin**, or when working on a shared machine!
- If a token expires or is revoked, Gitot detects this automatically (HTTP 401) and re-prompts for a new one.

---

## Architecture

Gitot is split into decoupled domain modules under `core/` (git and GitHub logic) and `ui/` (presentation only).
Each module is decoupled via signals; the Git engine has no knowledge of UI, and the UI never calls `OS.execute()` directly.

<details>
<summary>Core</summary>

- `gitot.gd` - `EditorPlugin` entry point; lifecycle, wiring, and main-screen tab registration.
- `core/git_engine.gd` - all `git` CLI execution (sync-fast and async-network paths), including commit, push, pull, branch, switch, stash, pop, fetch.
- `core/git_sync_orchestrator.gd` - push -> create-tag -> push-tag state machine; reacts to `GitEngine.command_completed`, decoupled from UI via signals.
- `core/git_branch_parser.gd` - parses `git branch --format=...` into local branch entries.
- `core/git_status_parser.gd` - parses `git status --porcelain=v2`.
- `core/git_diff_parser.gd` - parses `git diff -U0` hunk headers.
- `core/git_log_parser.gd` - parses `git log` (custom `\x1f`-delimited format) into commit entries.
- `core/github_auth.gd` - PAT storage (`user://gitot_auth.cfg`, plaintext)(read: [PAT](#github-personal-access-token) section).
- `core/github_api.gd` - authenticated `HTTPRequest` wrapper for the GitHub REST API.
- `core/gitot_settings.gd` - `GitotSettings`, settings storage (`user://gitot_settings.cfg`, plaintext, non-sensitive values only).
- `core/gitot_logger.gd` - `GitotLogger`, centralized print wrapper (info/success/warning/error/extreme/git) with capped history and an optional UI listener; `EXTREME` also routes through `printerr` to bypass the Output panel's message filter.
</details>

<details>
<summary>Ui</summary>

- `ui/gitot_dock.tscn` / `gitot_dock.gd` - local Git dock UI shell (wiring, commit/push/pull handlers);
- `ui/gitot_status_tree.gd` - staged/Unstaged file trees: population, staging/unstaging, bulk actions, size guard.
- `ui/git_log_panel.gd` - commit history fold: Tree population, count-filter dropdown, relative/short date tooltip.
- `ui/gitot_branch_panel.gd` - branch dropdown (switch) and new-branch dialog.
- `ui/gitot_status_panel.gd` - compact repo-state summary (owner/repo, branch, branch scope); constructor-injected `RichTextLabel`.
- `ui/gitot_tag_panel.gd` - tag-versioning UI: toggles, version-tag formatting, tag input resolution.
- `ui/gitot_settings_panel.gd` - settings panel UI; self-contained, reads/writes `GitotSettings` directly.
- `ui/gitot_diff_gutter.gd` - script editor gutter coloring.
- `ui/github_panel.tscn` / `github_panel.gd` - GitHub Issues Tracker Board, main-screen tab, owns `GithubApi`, fetches on first tab-open.
- `ui/github_auth_dialog.tscn` / `github_auth_dialog.gd` - [PAT](#github-personal-access-token) entry modal, opened on first use or 401.
- `ui/issue_card.tscn` / `issue_card.gd` - single issue card (title, author, date, labels, body, browser link).
- `ui/gitot_log_console.gd` - live console view backfilling `GitotLogger.log_history` and appending new entries via listener callback; styled with the editor's own Output panel font.
</details>

## Changelog

<details>
<summary>v0.7.1</summary>

fix: harden v0.7.0 - correctness, lifecycle, security, architecture.

- Add branch scope (local/remote) to the branch dropdown and status panel.

Correctness:
- Dedupe EXITCODE-marker stripping into `GitEngine._poll_process()` instead of duplicating it per-branch in the dock.
- Guard `output[0]` access with `is_empty()` in the dock's stash branch and the orchestrator's tag-exists branch (real crash risk on empty stdout).
- `fetch` now triggers `get_ahead_behind()` on success - sync status no longer goes stale until the next unrelated refresh.
- `GitEngine.pull()` wrapper (was calling `run_network()` directly from the dock, same layer violation already fixed for `fetch()`).
- Diff gutter now gates on `exit_code == 0` - a failed `git diff` no longer paints stale/garbage markers.
- Size-guard icon no longer overwrites the conflict icon/tooltip on a file that's both conflicted and oversized.
- Empty GitHub PAT can no longer silently overwrite an existing valid token on accidental dialog confirm.
- `GithubApi` now guards against overlapping in-flight requests instead of silently dropping the second call.
- Fixed dock `_ready()` firing before `GitEngine` injection completes (known Godot `@tool`-dock timing quirk) - was crashing on every editor launch; now retries via deferred call, guarded against double-init.

Security:
- `create_tag()` rejects shell-unsafe characters (`$`, `` ` ``, `;`, `&`) that are valid git ref characters but unsafe once interpolated into `push_tag()`'s shell string.
- Confirmed PAT storage is single-sourced (`user://gitot_auth.cfg`) - no drift found.

Lifecycle:
- `GitSyncOrchestrator.teardown()` - disconnects from `GitEngine.command_completed` on plugin exit (was relying on free-order luck).
- `GitotLogConsole` caps rendered lines to `GitotLogger.MAX_HISTORY` - was growing one `RichTextLabel` per line, unbounded, over a long editor session.
- Network log files disambiguated with a monotonic timestamp instead of just the command name - concurrent same-named ops (e.g. two fetches) no longer share/corrupt one log file.
- `GIT_TERMINAL_PROMPT` restored via `OS.unset_environment()` on `_exit_tree()`.

Architecture (SoC/DRY):
- Split `_on_status_result` (~120-line function) into a thin dispatcher plus six domain handlers.
- Replaced the `command_name: String` signal bus with a typed `GitEngine.Command` enum across `GitEngine`, `gitot.gd`, the dock, the orchestrator, the diff gutter, and the status tree - a mistyped/renamed command now fails to compile instead of silently mismatching at runtime.
- Consolidated duplicate origin/repo-URL parsing (status panel vs. GitHub panel) into one shared `GitEngine.parse_owner_repo()`.
- Removed dead code: `GithubApi.fetch_labels()` (zero callers).
- `GDScript` member ordering brought in line with the style guide across all touched files; repeated `EditorIcons` theme lookups extracted to a shared `_icon()` helper.
<hr>
</details>

<details>
<summary>v0.7.0</summary>

feat: Remote Branch Management & Status Panel

- `GitEngine`: `fetch()` wrapper (`git fetch origin`, network op), `get_ahead_behind()` (`rev-list --left-right --count @{u}...HEAD`, fast/local), `track_remote_branch()` (`switch -c <name> --track origin/<name>`, reuses `"create_branch"` result path).
- Push fixed: `-u origin HEAD` instead of bare `push` - resolves first-push failure on branches with no upstream.
- `GitBranchParser`: switched from `%(refname:short)` to `%(refname)` to reliably detect and exclude the `origin/HEAD` symbolic-ref alias; added `is_remote` flag.
- `GitotBranchPanel`: filters remote entries that already have a matching local branch (avoids `main` + `origin/main` duplicate clutter); cloud vs. branch icon per entry.
- New `GitotStatusPanel` (`RefCounted`, constructor-injected `RichTextLabel`): owner/repo, branch name (truncated), branche scope, ahead/behind. Detached HEAD flagged in red.
- `fetch` on success triggers `list_branches()` refresh (new remote branches only become visible after a fetch).
<hr>
</details>

<details>
<summary>v0.6.0</summary>

feat: Commit History.

- `GitEngine.get_log()`: `git log` wrapper, `\x1f`-delimited format (hash, author, relative date, short date, subject) — avoids delimiter collisions with commit message content.
- `GitLogParser`: static parse into `Array[Dictionary]`, mirrors `GitBranchParser` shape.
- `GitLogPanel`: `RefCounted`, constructor-injected `FoldableContainer` + `Tree` (matches `GitotBranchPanel`/`GitotTagPanel` pattern). Count-filter `OptionButton` created in code, injected into fold title bar via `add_title_bar_control()`.
- Relative date shown in list; exact short date (`YYYY-MM-DD HH:MM`) on hover tooltip.
- Wired into existing refresh triggers: `STATUS_TRIGGERING_COMMANDS` (commit/push/pull/switch) and manual `Refresh Status` fallback.

feat: Stash Quick-Actions

- `GitEngine.stash_push()` / `stash_pop()`: thin wrappers, same pattern as `create_tag`/`switch_branch`.
- `stash push` uses `-u` to include untracked files - matches solo-dev intent of "shelve all WIP", not just tracked changes.
- Fixed stash message: `"Gitot quick-stash"`.
- Wired into `STATUS_TRIGGERING_COMMANDS` - stash/pop trigger the same status refresh as stage/commit/switch.
- Pop conflicts are not treated as silent failure: exit code != 0 logs git's raw output and still refreshes status so conflicted files are visible immediately.
<hr>
</details>

<details>
<summary>v0.5.0</summary>

feat: Branch Management (switch, create, live scene refresh).

- `GitEngine`: `list_branches()`, `switch_branch()`, `create_branch()`, `get_changed_files_since_switch()`, `get_current_branch()`.
- `GitBranchParser`: parses local branch list with current-branch flag.
- `GitotBranchPanel`: dropdown (switch) + create-branch dialog, wired into the existing dock UI (no new `.tscn`).
- Scene/resource refresh on switch: precise per-file `update_file()` + `reload_scene_from_path()` for open tabs, instead of a full `scan()` - avoids full-project `.import` error noise (read: [Limitation](#known-limitations)).
- Success/error console feedback for switch/create, including resulting branch name.
- Guard against `git_engine` being unset on mid-session script hot-reload.

feat: Gitot Logger

- **`gitot_logger.gd`**: capped history (`MAX_HISTORY = 200`), decoupled push-listener (`set_listener`/`_on_log`).
- **`gitot_log_console.gd`** (new, `RefCounted`, constructor-injected - matches `GitotStatusTree`/`GitotTagPanel` pattern): backfills history on open, appends new lines at the bottom, auto-scrolls via `resized` signal, styled with Godot's own `output_source` console font at a smaller size.
- **`gitot_dock.gd`**: wires `GitotLogConsole.new(%LogList, %LogScroll)` in `_ready()`, tears it down properly.
<hr>
</details>

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
- **Commit & Sync:** stage/unstage, commit message input (multiline supported), and Commit / Push / Pull buttons (read: [Limitation](#known-limitations)).
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh Diff** fallback button.
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.
</details>

## License

Copyright (c) 2026-present SigK - under the MIT License.

