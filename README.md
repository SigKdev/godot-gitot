<div align="center">
<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/af78184e-57f6-4306-bd31-e50b3315ac7b" />
</div>

<p align="center">
<a href="https://ko-fi.com/sigkgames"><img src="https://img.shields.io/badge/Sponsor-30363D?logo=GitHub-Sponsors" alt="Ko-fi
SigKgames"></a> <a href="https://godotengine.org/"><img
src="https://img.shields.io/badge/Godot-4.7+-478CBF?logo=godotengine&logoColor=478CBF" alt="Godot 4.7"></a> <a
href="https://git-scm.com/"><img src="https://img.shields.io/badge/GIT-2.3+-E44C30?logo=git&logoColor=E44C30" alt="Git"></a> <a
href="https://store.godotengine.org/asset/sigk/gitot/"><img src="https://img.shields.io/badge/Gitot-0.14.1-B8195F"
alt="Gitot"></a> <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License"></a>
</p>

<p align="center">
  <a href="https://store.godotengine.org/asset/sigk/gitot/"><kbd>📸 Screenshots</kbd></a> &nbsp;&nbsp; <a
  href="#-features"><kbd>🧬 Features</kbd></a> &nbsp;&nbsp; <a href="#-installation"><kbd>🛠️ Installation</kbd></a> &nbsp;&nbsp;
  <a href="#-changelog"><kbd>🗃 Changelog</kbd></a>
</p>

**Gitot** is a lightweight Git workflow plugin for the Godot 4 editor **intended for solo developers** who want fast, reliable Git
operations (stage/unstage, commit, stash/pop, fetch/push/pull), inline diff gutter, full diff viewer, and issue tracker without
leaving the editor.

**Gitot** wraps the system `git` binary directly via `OS.execute()`, in pure GDScript, with no GDExtension and no bundled
`libgit2`. It inherits your existing SSH/credential setup and the full Git feature set without re-implementing any of it. This
trades a tiny amount of raw performance for stability, transparency, and zero maintenance burden across engine/OS updates.

**If Git works from your terminal, it works from Gitot as it uses your terminal's git setup.**

Gitot is fully independent of Godot's built-in Version Control integration (Editor Settings → Version Control), no VCS plugin
needed, nothing to configure there. Gitot talks to your system `git` directly.

**Screenshots available on the [Godot Asset Store](https://store.godotengine.org/asset/sigk/gitot/).**

> [!IMPORTANT]
> 
> Gitot is under active, daily-use development by a solo developer. It is built and tested on Godot 4.7.2. Core workflows
> (stage/commit/push/pull, branching, diff gutter & viewer) are used daily in real projects and have been through several
> correctness/lifecycle hardening passes (see [Changelog](#-changelog)).
> 
> - This is **not yet a widely-tested release**. It has been validated on Windows with one developer's workflow, on small repo,
> not across operating systems or project sizes. Gitot requires significantly more testing under everyday usage conditions!
> - **Commit your work / make backup before trying a new Gitot version**, same as you would for any Git tool in active
> development.
> - Bug reports and real-world usage feedback are the most valuable contribution right now, the roadmap below is
> deliberately reliability-first before new features.


## 🧬 Features

- **Commit & Sync:** Stage or unstage files individually or in bulk, write multiline commit messages, and Commit, Amend, Push, or
  Pull. Amend is guarded and automatically forces the next push when required.

- **Stash Manager (Shelf):** Stash all changes (staged + unstaged + untracked) under an optional name, then pop or drop any
  entry from a capped, foldable list (limit is a setting, default 10). Pop refreshes only the files it touched in the editor.

- **Local Branch Management:** Foldable branch list (name, ahead/behind, last update). Double-click to switch, `+` to create a
  branch inline, trash button to delete a merged local branch. Open scenes refresh
  automatically on switch without a full project rescan. A toast warns if an open script changed on disk, or if changed files
  couldn't be reliably detected (see [Limitations](#-known-limitations)).

- **Remote Branch Management:** Fetch remote updates from the branch fold's title bar, list remote-only branches, and
  double-click one to check it out with automatic tracking.

- **Tag Versioning:** Push with or without an annotated tag. Auto-tagging settings - see _Details_ below.

- **Commit History:** Browse recent commits (message, author, date) with a count filter (10/20/30). Click a commit to inspect its
  changes file-by-file in the bottom-dock diff viewer.

- **Color Diff Gutter:** Modified and added lines are marked directly in the script editor's gutter. Click to open the matching
  hunk in the diff viewer.

- **Diff Viewer Panel:** Bottom-dock full-context unified diff for the current script. Basic syntax highlighting,
  foldable hunk with headers, per-line +/- gutter with real source line numbers and color-coded additions/deletions.
  Also browses any past commit file-by-file: pick a file from the changed-files list to view its diff.
  (Click the commit header to copy its hash).

- **Restore File:** In the diff viewer's commit-history mode, restore a file to its content at that commit.
  Confirmation dialog before overwriting uncommitted changes.

- **GitHub Issues Tracker Board:** Split list/detail view (like the commit history) of the repo's open issues (requires a [PAT](#github-personal-access-token));
  opt-out in settings. Sortable 6-column list (number, title, date, type, priority, labels), Type/Priority/Label filters,
  full issue detail (metadata, colored labels, Markdown body, Open in Browser). Create a branch directly from an issue,
  auto-named from its number/title/type (editable), with a base-branch picker and a dirty-working-tree confirmation.

- **Repo Status Panel:** One-line summary of the current repo, branch (detached HEAD flagged in red), branch scope, and
  ahead/behind sync status.

- **Large-File Guard:** Blocks staging any file over a configurable size limit to prevent repository bloat, flagging oversized
  files with a warning icon in the staged/unstaged list.

- **Gitot Logger:** Git and Gitot output are routed through Gitot's own dock logger to keep the Godot output panel clean.
  A **Reflog** button dumps the last 20 reflog entries to the console.

<details>
<summary>Details</summary>

- **Failsafe Startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async Execution:** all process execution lives in `GitRunner`. Local commands (status, diff) run via a monitored
  background process with a 120-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Commit & Sync:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with single and bulk stage/unstage.
  Status color & icon. Warning icon for conflicted file and large-file guard. Push targets `-u origin HEAD`. **Amend** checkbox
  runs `commit --amend` (keeps message with `--no-edit` if left blank); blocked behind a confirm dialog if the tracked ahead-count
  shows the commit is already pushed. Before every push, `GitEngine.needs_force_push()` runs
  `git merge-base --is-ancestor @{u} HEAD` live - if HEAD has diverged from upstream for any reason (amend, rebase, reset,
  terminal use), the push confirm dialog warns and the push uses `--force-with-lease` instead of a plain push. Cancelling either
  confirm dialog logs a message and changes nothing.
- **Stash Manager (Shelf):** Foldable list (name, branch, relative date, exact date on tooltip) built from `git stash list`
  (`\x1f`-delimited format, parsed by `GitStashParser`). Header title shows `Shelf (count/cap)`. Stash / Pop / Drop buttons.
  An optional name field feeds `stash push -u -m`; left blank, git's own `WIP on <branch>: ...` subject is used.
  The cap is the `max_stashes` setting (1-50, default 10): Stash is disabled when the shelf is full,
  existing entries are never deleted, and the list shows every entry, including ones made from a terminal.
  The selection is kept across refreshes by stash SHA (the top entry is selected by default, so Pop acts on the latest). Drop
  asks for confirmation and re-resolves the SHA to its current `stash@{n}`, since the stack can shift while the dialog is open;
  git's output (which contains the dropped SHA) is logged, so a mistake can be undone with `git stash store <sha>`. Before a pop,
  the touched files are listed with `git stash show --name-only --include-untracked --no-renames` and only those are refreshed
  (`update_file()`, open scene reload, stale-script toast). A failed pop (conflict) refreshes nothing and logs the raw output.
- **Local Branch Management:** Foldable `Tree` (name, sync, updated) built from `git branch -a` (`GitEngine.BRANCH_LIST_FORMAT`,
  `\x1f`-delimited, parsed by `GitBranchParser`). Sync uses `%(upstream:trackshort)` (`↑` ahead, `↓` behind, `↑↓` diverged, `✓` in
  sync), which is locale-independent. Title-bar buttons: Fetch, `+`, Delete. Double-click switches. `+` toggles an inline name
  row (Enter or Create button), guarded by a confirmation unless `confirm_create_branch` is off. Delete runs `git branch -d` on the
  selected local, non-current branch, always after a confirmation. There is no Force, so git refuses unmerged branches.
  On switch/create, only files git actually changed are refreshed. `EditorFileSystem.update_file()` for cache bookkeeping, plus
  `EditorInterface.reload_scene_from_path()` for any of those files currently open in a tab, avoiding the full-project `scan()`
  noise. Godot has no API to reload or close an open script tab, so an editor toast flags any open script that changed on disk
  (close/reopen manually), and a separate toast warns when changed-file detection itself is unreliable (first switch after clone, or
  rapid successive switches). (read: [Limitation](#-known-limitations)).
- **Remote Branch Management:** `git fetch origin` via the fold's title-bar button, refreshing the branch list on success.
  Remote-tracking branches with no local counterpart appear in the list, and double-clicking one runs
  `switch -c <name> --track origin/<name>` in one atomic op.
- **Tags Versioning:** Tag is push with commit. Settings to auto use Version _(from project settings)_ for the tag's name (with
  auto `v` prefix) and the commit message for the tag's message.
- **Repo Status Panel:** Show `owner/repo · branch (local/remote) · ↑ahead ↓behind`. Updates live on every status-triggering
  command. Detached HEAD shown in red in place of a branch name. Ahead/behind only logs to console on actual change, not on
  redundant refreshes (e.g. focus-in polling).
- **Commit History:** `git log` parsed via `\x1f`- delimited format string. Count-filtered dropdown (10/20/30, default reflects
  last selection). Relative date shown in-list, exact short date (`YYYY-MM-DD HH-MM`) on date hover tooltip. Auto-refreshes
  alongside status on the same trigger set (commit/push/pull/switch) and on manual _Refresh Status_ fallback button. Selecting a
  row (click or arrow keys) opens that commit history in the Diff Viewer Panel.
- **Color Diff Gutter:** Modified and added lines are marked directly in the script editor's gutter, computed from `git diff -U0`
  against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably), on Godot editor focus, and a manual
  fallback refresh diff gutter button. Clicking a marked line gutter opens the bottom-dock diff viewer, jumped to that line.
- **Diff Viewer Panel:** Separate `git diff -U3` against `HEAD`, decoupled from the gutter's own `-U0` diff (no shared parser
  state, no regression risk to the gutter). Renders, as a read-only `CodeEdit`: `@@ -old,count +new,count @@` header
  per foldable hunk, basic syntax highlighting, dedicated +/- sign gutter, real source line numbers in their own gutter,
  color-coded background per line. File-path label at the top confirms which file is shown. Stale-result guard discards
  a diff response if the active script tab changed before it arrived. (Manual fallback refresh button).
  **Commit history mode:** selecting a commit history row lists the commit's changed files
  (`git show --name-status --format= --no-renames`, status-colored A/M/D); the selected file's diff
  (`git show -U3 ... -- <path>`) is fetched on demand, so large commits stay fast. A latest-wins gate keeps one request in flight
  and drops outdated results (fast arrow-key navigation always ends on the highlighted commit), and a single file diff is
  truncated at 200,000 characters for display. Clicking the commit header copy its hash (brief color flash confirms the copy).
  Clicking a gutter marker in a script returns the panel to working-tree mode. (read: [Limitation](#-known-limitations)).
- **Restore File:** In commit-history mode, restores the selected file to its content at that commit
  (`git restore --source=<hash> -- <path>`). A confirmation dialog warns that uncommitted changes to the file will be lost.
  Guarded against the no-file-changes merge-commit case (button no-ops if there's nothing to restore). If the file is open in
  the script editor, its compiled class reloads automatically, but the tab's visible text only refreshes on the next editor
  focus change. Tooltip and console log both call this out (read: [Limitations](#-known-limitations)).
- **GitHub Issues Tracker Board:** (opt-out in settings possible). Split container (columns:
  number/title/date/type/priority/labels, header-click sort) on the left, `IssueDetail` on the right
  (metadata header, colored label pills, Markdown body in a read-only `CodeEdit`, Open in Browser button). Parser
  normalizes raw REST JSON (native issue Type, org "Priority" issue field, null-safe body/labels). Filter:
  Type/Priority/Label built from the fetched data, client-side AND filter (no extra requests). Paginated
  fetch (50 issues/page, capped at 8 pages = 400 issues), chained automatically and stopping at the first short page.
  Branch creation from an issue: auto-generated name (`<type-prefix><number>-<title-slug>`, e.g.
  `feature/12-fix-login`, editable), base-branch picker (defaults to current branch), confirmation dialog if the working
  tree is dirty. If a token expires or is revoked, Gitot detects this automatically (HTTP 401) and re-prompts for a new one.
- **Gitot Settings Panel:** Add Settings (user://gitot_settings.cfg), large_file_mb, network_timeout_sec, max_stashes,
  confirm_push, auto_refresh_on_focus, github_issues_enabled.
- **Large-file Guard:** Size configurable in settings, _0 to disable_.
- **Gitot Logger:** Output routed through `GitotLogger` (Styled with Godot's own console font), so they can be filter out of Godot
  output log with the "standard output message" filter. The console's **Reflog** button runs `git reflog -n 20`
  (`GitEngine.REFLOG_COUNT`) and prints the raw output.
</details>

#### 📅 Planned Features

- [ ] Git LFS Support and Asset Locking
- [ ] Asset Dependency Analyzer (Pre-Commit Scene Linter)
- [ ] Hunk-level (partial file) staging
- [ ] ...

---

## 🛠 Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

#### Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`.
- A GitHub Personal Access Token ([PAT](#github-personal-access-token)), **(optional, only needed for the Issues integration)**.

---

## ⚠ Known Limitations

- After a `Pull`, a branch `Switch`, a `Restore`, or a `Stash Pop`, Godot has no API to reload an open script tab. Gitot
  recompiles the script's class and shows a toast, but the tab's visible text only updates on the next **editor focus change**
  (click away from the editor window and back, which triggers Godot's own external-change check). In some cases Godot may
  still fail to show the update, even after closing/reopening the file: a known engine limitation ([godot#104540](https://github.com/godotengine/godot/issues/104540)), ([godot#73808](https://github.com/godotengine/godot/issues/73808)).
  Then use **Project → Reload Current Project** or **restart the editor**.
  To avoid it altogether, close the affected script tab _before_ switching branches, pulling or popping.

- Godot's `resource_saved` signal does not fire for all save paths (e.g. Run Project/Scene auto-saves).
  Use the **Refresh Diff Gutter** button to catch up manually in those cases. Or switch away from the Godot windows
  and switch back to trigger auto-refresh (see in settings).

- **Branch Management** scene/resource refresh relies on the git reflog (`HEAD@{1}`) to detect changed files, so it only compares
  against the immediately-previous checkout. On the very first switch after a fresh clone (no prior reflog entry) or after
  multiple rapid switches, Gitot cannot reliably tell what changed and shows an editor toast warning instead of silently doing
  nothing - close/reopen any open scripts/scenes manually in that case.

- Switching to a branch whose `project.godot` differs from the current one _(e.g. different enabled plugins/autoloads)_ triggers
  Godot's own **"File has been modified outside Godot"** dialog for `project.godot`. This is a Godot editor behavior outside
  Gitot's control (separate watcher from `EditorFileSystem`) - click **Reload from Disk** reflects the real branch content.

- **Stash** includes untracked files (`-u` flag). Popping after switching branches can reintroduce files that conflict with the
  new branch's content. Same underlying risk as any `switch` with pending changes.

- **Stash Pop** refreshes only the files git reports for that stash, using `git stash show --include-untracked`. On a Git
  version without that flag, or if the call fails, Gitot shows the "couldn't verify changed files" toast instead. After a pop
  that fails on conflicts, nothing is refreshed: open files may be stale, so check for conflict markers.

- **Commit history diff viewer:** merge commits are not handled specially (`git show` prints a combined diff, so the file list can
  be short or empty). Binary files are listed but their diff body is empty. File names Git quotes (non-ASCII characters) may fail
  to load their diff.

- The diff gutter only applies to **tracked** files. Untracked (never-committed) files have no `HEAD` version to diff against.

## 🔑 Credential Handling

#### SSH

Pushing/pulling relies on your system Git's own credential handling (SSH agent, Git Credential Manager, etc.). **Gitot does not
manage credentials!** Gitot does not suppress OS-level credential prompts (e.g. Windows Git Credential Manager popups). If
push/pull hangs waiting on such a prompt, it will be automatically killed after 120 seconds. Configure a working credential helper
or SSH agent so `git push`/`git pull` succeed from a terminal before relying on Gitot for sync.

#### GitHub Personal Access Token

Only needed to use the **GitHub Issues Tracker Board** feature.

> [!CAUTION]
> 
> **Gitot** stores your GitHub PAT locally in plaintext at `user://gitot_auth.cfg` (outside `res://`, so it is never committed to
> your repository).
> 
> **This is not encrypted.** Godot/GDScript cannot access your OS-level credential store (Windows Credential Manager, macOS
> Keychain, etc.) without a native extension, which is outside this plugin's scope. **Anyone with access to your local user
> account can read this file.** And the Godot hot-reload and `_exit_tree()` make it not possible to auto clear the PAT when
> uninstalling/disabling Gitot. **You must clear your token before uninstalling/disabling**

> [!TIP]
> 
> **PAT Recommendations:**
> 
> - Use a **fine-grained token** scoped to Repo Access and with Issues Access read/write only. **Never an admin or org-wide
> token!**
> - Use the **Clear Token** button in the Gitot Issues Panel toolbar **before uninstalling or disabling the plugin**, or
> when working on a shared machine!
> - If you do not intend to use this feature, opt-out in settings to unload it completely!
> - Check the GitHub Personal Access Token [documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

---

## 💬 Feedback & Support

- **Bug reports:** use [Issues](../../issues) - include your OS, Godot version, and steps to reproduce.
- **Feature ideas, questions, general feedback:** use [Discussions](../../discussions) instead. Issues are kept strictly for
  actionable bugs.


## 💝 Sponsor This Project

**Gitot** is developed and maintained solo, in my own time, alongside an ongoing personal Godot game project _(stopped cause of
hardware issue)_. If Gitot has saved you time or you'd like to see development continue, sponsoring is the most direct way to
help, it goes straight toward the hours and the hardware this project and my game project runs on.

<a href='https://ko-fi.com/sigkgames' target='_blank'><img height='48' style='border:0px;height:48px;'
src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

No pressure! Using Gitot, reporting bugs, and sharing feedback in Discussions is just as valuable to the project.

---

## 📂 Project Structure

Gitot is split into decoupled domain modules under `core/` (git and GitHub logic) and `ui/` (presentation only). Each module is
decoupled via signals; the Git engine has no knowledge of UI, and the UI never calls `OS.execute()` directly.

<details>
<summary><strong>Full directory tree</strong></summary>

```
addons/gitot/
├── plugin.cfg                                    	# Plugin manifest (name, version, entry script)
├── gitot.gd                                      	# EditorPlugin entry point; lifecycle, wiring, main-screen tab registration
├── core/
│   ├── git_engine.gd                             	# Command API + command_completed signal (per-call context); delegates execution to GitRunner
│   ├── git_runner.gd                             	# Process execution: worker threads, timeouts, shell redirect, write lock (no git-domain knowledge)
│   ├── git_sync_orchestrator.gd                  	# push → create-tag → push-tag state machine; picks --force-with-lease vs plain push
│   ├── git_branch_parser.gd   						# Parses `git branch -a --format=...` (BRANCH_LIST_FORMAT) into local/remote branch entries
│   ├── git_status_parser.gd                      	# Parses `git status --porcelain=v2`
│   ├── git_diff_parser.gd                        	# Parses `git diff -U0/-U3` hunks + `--name-status` output
│   ├── git_log_parser.gd                         	# Parses `git log` (custom \x1f-delimited) into commit entries
│   ├── git_stash_parser.gd                       	# Parses `git stash list` (custom \x1f-delimited) into stash entries
│   ├── github_auth.gd                            	# PAT storage (user://gitot_auth.cfg, plaintext)
│   ├── github_api.gd                             	# Authenticated HTTPRequest wrapper for GitHub REST API
│   ├── github_issue_parser.gd                    	# Normalizes raw GitHub issue JSON (type/priority/labels/branch-name slug)
│   ├── gitot_settings.gd                         	# GitotSettings; settings storage (user://gitot_settings.cfg)
│   └── gitot_logger.gd                           	# GitotLogger; centralized print wrapper, capped history + UI listener
└── ui/
    ├── gitot_dock.tscn / gitot_dock.gd           	# Local Git dock UI shell (wiring, commit/push/pull handlers)
    ├── gitot_result_router.gd						# Routes command_completed results to domain handlers; emits head_moved / stash_popped / file_restored
    ├── gitot_status_tree.gd                      	# Staged/unstaged file trees: population, staging, bulk actions, size guard
    ├── git_log_panel.gd                          	# Commit history fold: Tree population, filters, commit_selected signal
	├── gitot_stash_panel.gd                      	# Shelf fold: stash list Tree, Stash/Pop/Drop, cap, drop confirm
    ├── gitot_ui.gd              					# Shared UI helpers: editor-theme icons, title-bar buttons, busy state
    ├── gitot_commit_files_list.gd                	# Changed-files ItemList for one commit; pure UI
    ├── gitot_commit_log_diff.gd                  	# Commit-mode flow (history → file list → diff); latest-wins gate + size cap
    ├── gitot_branch_panel.gd    					# Branch list fold: Tree, switch/track on double-click, Fetch button
	├── gitot_branch_creator.gd  					# Inline create-branch row (+ toggle), confirmation gate
	├── gitot_branch_deleter.gd  					# Delete-branch button and confirmation (git branch -d)
    ├── gitot_status_panel.gd                     	# Compact repo-state summary (owner/repo, branch, scope)
	├── gitot_diff_gutter.gd                      	# Script editor gutter coloring + click-to-diff (hunk_clicked signal)
    ├── gitot_tag_panel.gd                        	# Tag-versioning UI: toggles, version-tag formatting, tag resolution
    ├── gitot_settings_panel.gd                   	# Settings panel UI; reads/writes GitotSettings directly
	├── gitot_log_console.gd                      	# Live console view backfilling GitotLogger.log_history; owns Reflog button
    ├── github_issue_list.gd                        # Issue Tree: population, header-click sort, filter integration
    ├── github_issue_filter.gd                      # Type/Priority/Label dropdowns + AND-match rule
	├── github_panel.tscn / github_panel.gd         # GitHub Issues Tracker Board, main-screen tab, owns GithubApi
    ├── issue_detail.tscn / issue_detail.gd         # Selected-issue detail: header, actions, branch creation, body
    ├── gitot_diff_panel.tscn / gitot_diff_panel.gd    	# Bottom-dock full diff viewer
    └── github_auth_dialog.tscn / github_auth_dialog.gd # PAT entry modal, opened on first use or 401
```

</details>

---

## 🗃 Changelog

<details>
<summary>v0.14.1</summary>

fix: per-call, Stage/Unstage empty list  + ref: git_engine>git_runner

fix: per-call `context` replaces the `_last_*` side-channel state

- `command_completed(command, exit_code, output, context)`: the new `context: Dictionary` carries data captured at call time:
  `branch` (switch / create / track), `path` (restore), `{reliable, files}` (stash pop). `run_fast()` gains an optional
  `context` parameter, so existing callers are unaffected.
- `_last_switch_target`, `_last_restored_path`, `_last_popped_files` and their getters are removed. This fixes a log mix-up: a
  switch ignored by the write guard still overwrote the target of the switch in flight, so the log could name the wrong branch.
- `stash_popped` now carries the file list, and the dock connects it straight to `_notify_file_list()`
  (`_notify_popped_files()` removed).
- Every `command_completed` handler takes the extra `context` parameter.

fix: Stage All / Unstage All on an empty list

- `TreeItem.get_child(0)` on a childless root raised `Index p_index = 0 is out of bounds`. Replaced by `get_first_child()` in
  `GitotStatusTree._get_tree_paths()`, plus a new `_is_empty()` helper used by the Unstage All guard.

fix: Issues tab base-branch dropdown never followed HEAD

- `IssueDetail.set_base_branches()` kept the previous selection whenever that branch still existed, so after a switch or create
  the dropdown stayed on the old branch until a restart. It now selects the current branch when HEAD moved (and on first fill) and
  keeps the user's manual pick across plain refreshes.

refactor: GitRunner extraction - per-call context on `command_completed`

- `GitRunner` (new, `core/`, `RefCounted`): all process execution moved out of `GitEngine` with no behavior change -
  `run_fast()` (`WorkerThreadPool` + write lock), `run_network()` (kill-on-timeout), `execute_bounded()` (sync, capped at
  `LOCAL_TIMEOUT_SEC`), `teardown()`. It is git-domain agnostic: it takes a label, an `is_write` flag and a `Callable`
  instead of a `Command`, so it has no dependency on the engine.
- `GitEngine` keeps the public API (`Command`, `WRITE_COMMANDS`, wrappers, `command_completed`). `run_fast()` / `run_network()`
  keep their signatures and reach the runner through one `_relay()` callback. Early failures (spawn failure, unsafe tag name)
  go through the same path.
- The write-guard warning now reads `<Command> skipped: another git write was still running.`

refactor: UI polish

- The Staged fold closes itself when there is nothing staged and reopens when files arrive. A manual fold is not overridden by
  plain refreshes.
- Status panel shortens `(Local + Remote)` to `(L+R)`. Display-only mapping in `GitotStatusPanel`; the router's scope strings are
  unchanged.
- Startup message now includes the git and git LFS versions: `'git' binary verified. Plugin ready! (git x.y.z | LFS x.y.z)`.
  Without git-lfs it shows `LFS not installed` and never blocks startup. New `GitEngine.get_git_version()` /
  `get_lfs_version()`; `is_git_available()` now wraps `get_git_version()`, so startup spawns no extra `git --version`.
- Amended commits are reported as such: `Commit amended.` / `Amend failed.` (`_handle_commit_result()` now receives the
  `Command`).
<hr>
</details>

<details>
<summary>v0.14.0</summary>

ref: Branch list, cleanup - feat: delete branch

refactor: Branch panel rebuilt as a foldable list

- `GitEngine.BRANCH_LIST_FORMAT` (new) and `GitBranchParser` rewritten: name, current/remote flags, upstream, sync
  (`%(upstream:trackshort)`, locale-independent), commit date (unix/relative/exact), short hash, subject. Delimiter is
  `UNIT_SEP`; the old `|` split could break on ref names containing it.
- `GitotBranchPanel`: dropdown replaced by a 3-column `Tree` (name/sync/updated) in the `BranchFold` `FoldableContainer`. Double-click
  switches, or tracks a remote-only branch. Selection survives refreshes (by name). Fetch moved from its own button
  into the fold title bar (fetch / + / delete).
- Push / Pull / Retry Tag stay in their own row.

feat: Inline create branch

- `GitotBranchCreator` (new, `RefCounted`): `+` title-bar toggle shows a name `LineEdit` + Create button under the header. Enter or
  Create confirms through `%CreateBranchConfirmDialog` unless disabled. The `NewBranchDialog` window is removed.
- New `confirm_create_branch` setting (default on) with a settings-panel checkbox.

feat: Delete branch

- `Command.DELETE_BRANCH` (in `WRITE_COMMANDS`), `GitEngine.delete_branch(name)` runs `git branch -d`.
- `GitotBranchDeleter` (new, `RefCounted`): trash button enabled only for a selected local, non-current branch. Always asks
  for confirmation, no Force: git refuses unmerged branches and its output is logged. The router refreshes the list on success.

refactor: cleanup

- `GitotUi` (new) replaces `GitotIcons`: `get_icon()`, `add_title_button()`, `set_busy()`. The dock's `_set_busy()` and the
  stash panel's title-button code now use it.
- `GitotDock.refresh_status()` now also requests `list_branches()`, so the list refreshes on every status-triggering command,
  on focus-in and on manual refresh. The duplicate `list_branches()` / `get_current_branch()` calls in the router's switch/create
  path are removed.
<hr>
</details>

<details>
<summary>v0.13.0</summary>

fix: network timeout. feat: Stash Manager (Shelf) - list, named stash, drop, refresh after pop

Fix: network timeout: `_poll_process` killed the push at 30s. A large asset push on slow connection
will be killed mid-transfer. Now configurable timeout in settings (default 120s - range: 30/900).

feat: Shelf panel (replaces the toolbar Stash/Pop quick-actions)

- `GitStashParser` (new, `core/`): static parser for `git stash list` (`GitEngine.STASH_LIST_FORMAT`: selector, SHA, relative
  date, absolute date, subject). The subject splits into branch + name (`WIP on` = git default, `On` = custom `-m`); an
  unmatched subject falls back to an empty branch and the raw subject.
- `GitotStashPanel` (new, `RefCounted`): 3-column `Tree` (name/branch/date) in a `FoldableContainer`; Stash / Pop / Drop buttons in
  the title bar, name `LineEdit`, drop `ConfirmationDialog`. Selection survives refreshes (by SHA); Drop re-resolves its SHA
  to the current index before running.
- `GitEngine`: `Command.STASH_LIST` (read-only), `Command.STASH_DROP` (in `WRITE_COMMANDS`); `list_stashes()`,
  `stash_push(message)` (blank = no `-m`, git's default subject), `stash_pop(index)`, `stash_drop(index)`. The fixed
  "Gitot quick-stash" message is gone.
- New `max_stashes` setting (1-50, default 10) with a settings-panel SpinBox; Stash is blocked when the shelf is full. Changing
  the value updates the shelf immediately (`stash_cap_changed`).
- `STASH_DROP` added to `gitot.gd`'s `STATUS_TRIGGERING_COMMANDS`. The shelf refreshes with status on every trigger, on focus-in
  and on manual refresh (`GitotDock.refresh_status()` is now the single refresh path; `refresh_log()` removed).

feat: Precise editor refresh after Stash Pop

- `stash_pop(index)` lists the stash's files first (`git stash show --name-only --include-untracked --no-renames`, one bounded
  call), because the entry no longer exists afterwards. On success the router emits `stash_popped` and the dock refreshes only
  those files. The blanket "close and reopen any open scripts/scenes" log line is gone.
- `GitEngine._to_file_list()` (new) shared by `get_changed_files_since_switch()` and the pop path;
  `GitotDock._notify_file_list()` shared by branch switch and pop.

refactor: cleanup

- `GitotIcons.get_icon()` (new): single source for editor-theme icon lookup, replacing the private `_icon()` copies in the
  dock, router, and plugin entry point.
- `GitotResultRouter` no longer holds the Fetch/Pull buttons (constructor 8 → 6 parameters); the dock owns busy state for
  Fetch, Pull and Push through one `_set_busy()` helper.
- `GitLogParser.FIELD_SEP` removed; `GitEngine.UNIT_SEP` is the single separator constant.
<hr>
</details>

<details>
<summary>v0.12.0</summary>

feat: GitHub Issues Tracker Board - split list/detail refactor, base-branch picker, pagination

feat: Split list/detail Issues panel (commit-history-style layout)

- `GithubIssueParser` (new, `core/`): static, null-safe normalizer for raw REST issue JSON. casts float `number` to `int`,
  reads native issue `type`, resolves the org `Priority` issue field (`issue_field_values`), computes a relative date, and
  builds the auto branch name (see below). `PRIORITY_ORDER` (Low/Medium/High/Urgent, project-specific) is the single source
  of truth for priority ranking.
- `GithubIssueList` (new, `RefCounted`): 6-column `Tree` (number/title/date/type/priority/labels), header-click sort
  (ascending/descending, empty values always last), selection survives sort/refresh/filter. Replaces the old scrolling
  `IssueCard` list.
- `IssueDetail` (new sub-scene): full metadata header (author, date, type, priority, colored label pills via inline
  `[bgcolor]` BBCode), Markdown body in a read-only `CodeEdit`, Open in Browser. Replaces `issue_card.tscn`/`.gd` (removed).
- `GithubIssueFilter` (new, `RefCounted`): Type/Priority/Label `OptionButton`s, options built from the fetched data
  (no hardcoded vocabulary), client-side AND filter — instant, no extra requests.

feat: Create branch from an issue

- Auto-generated branch name: `<type-prefix><number>-<title-slug>` (`feature/`, `bugfix/`, `task/` per issue type, no prefix
  if unset/unknown), editable before creating.
- Base-branch picker (`OptionButton`, local branches only, defaults to the current branch); `GitEngine.create_branch()` gains
  an optional `base` parameter (`switch -c <name> [<base>]`), existing single-argument callers unaffected.
- Confirmation dialog before creating a branch with a dirty working tree (uncommitted changes move with the branch).

feat: Paginated issue fetch

- `GithubApi.fetch_issues()` now pages (`ISSUES_PER_PAGE = 50`); `github_panel.gd` chains requests automatically up to
  `MAX_ISSUE_PAGES = 8` (400 issues), stopping at the first short page. Bounded scope by design (solo/small-team repos) rather
  than a full paged UI.
<hr>
</details>

<details>
<summary>v0.11.0</summary>

feat: Restore file to an older commit's version - fix: editor-refresh reliability - hardening v0.11.0

feat: Restore file (commit-mode diff panel)

- `Command.RESTORE_FILE` / `WRITE_COMMANDS` entry - `git restore --source=<hash> -- <path>`, same mutual-exclusion guard as
  other write commands.
- `GitotDiffPanel`: `%RestoreFileButton` (commit mode only) + `%RestoreConfirmDialog`, guarded against the no-file-changes
  merge-commit case; emits `restore_file_requested(commit_hash, path)`.
- `GitotCommitLogDiff` wires the request to `GitEngine.restore_file()`; `GitotResultRouter._handle_restore_result()` logs
  success/failure and emits `file_restored(path)`.
- `RESTORE_FILE` added to `gitot.gd`'s `STATUS_TRIGGERING_COMMANDS`.

fix: Editor-refresh reliability

- `GitotDock._notify_file_changed()` (new, shared): reloads an open scene tab (`reload_scene_from_path()`) or open script
  (`Script.reload()`) for one file changed on disk outside the editor. Replaces duplicated logic previously split between
  branch-switch and restore-file handling - branch switch now actually reloads open scripts' compiled class, which it never
  did before.
- `GitotResultRouter.branch_switched` renamed `head_moved` and now also fires on a successful pull (pull moves HEAD the same
  way switch does, so the existing `HEAD@{1}..HEAD` diff applies unchanged).
- Stash-pop success logs a blanket "close and reopen any open scripts/scenes" warning - no `HEAD@{1}..HEAD`-style diff exists
  for a pop, so the affected files aren't knowable.
- Toasts/log lines clarify the real fix for a stale open tab: an editor focus change (not closing/reopening the tab), which
  is Godot's own external-change check and the only thing that refreshes a tab's visible text.

fix: Hardening v0.11.0 - correctness, performance, type safety

- Diff viewer hunks are now collapsible via a fold gutter, with a button to fold/unfold all.
- Add a basic syntax highlighting for gdscript file to the Diff viewer.

Correctness:

- `needs_force_push()` no longer misreads `_execute_bounded()`'s collapsed exit code on the no-upstream case - first push on a
  brand-new branch no longer risks a false force-push read.
- Commit/Amend failures now log git's raw output (`GitotLogger.g(output[0])`) instead of failing silently.
- `_on_diff_full_result()` (working-tree diff, `gitot.gd`) now applies the same `MAX_DIFF_CHARS` cap as the commit-diff path -
  a huge working-tree diff can no longer stall the panel.
- Empty/missing remote no longer renders the status panel's repo label as `"/"` - shows blank instead.
- `_execute_bounded()`'s timeout branch now deletes its temp log file on kill, matching `_poll_process()` - was leaking a
  `user://gitot_sync_*.log` on every local query that hit `LOCAL_TIMEOUT_SEC` (stuck lock/gc).

Performance:

- Removed a redundant blocking `get_current_branch()` call from `GitotDock._ready()` - the async `list_branches()` result
  (already fetched on the line above) sets the same label with better data (adds Local/Remote scope); was stalling the main
  thread on every dock init and every hot-reload of Gitot's own scripts.
- `needs_force_push()` was called twice per push (dock, for dialog wording; orchestrator, for push args) - dock now computes it
  once and passes it to `GitSyncOrchestrator.start_push(tag_input, force)`.

Type safety:

- `GitSyncOrchestrator._on_command_completed()` / `_handle_tag_collision_result()`: `output: Array` -> `Array[String]`,
  matching `command_completed`'s signature and every other handler.
<hr>
</details>

<details>
<summary>v0.10.0</summary>

feat & fix: amend & copy hash - hardening: result-routing architecture, correctness, type safety

feat: Amend last commit

- `Command.AMEND` / `WRITE_COMMANDS` entry - `commit --amend` (`--no-edit` if the message field is left blank), same
  mutual-exclusion guard as other write commands.
- `gitot_dock.gd`: `%AmendCheckbox` on the commit box, guarded by locally-tracked ahead-count/upstream state - amending a commit
  already on origin requires confirming `%AmendConfirmDialog` first.
- `GitEngine.needs_force_push()` - live check (`git merge-base --is-ancestor @{u} HEAD`, bounded sync call) run right before every
  push, instead of a cached flag - self-corrects for any cause of divergence (amend, rebase, reset, branch switch, terminal use),
  not just amend.
- `GitSyncOrchestrator.start_push()` - uses `needs_force_push()` to choose `push --force-with-lease -u origin HEAD` over a plain
  push.
- `gitot_dock.gd`: push confirmation is forced (regardless of the `confirm_push` setting) whenever the next push would be a
  force-push; both `%PushConfirmDialog` and `%AmendConfirmDialog` log on Cancel (`canceled` signal).
- `gitot.gd`: `AMEND` added to `STATUS_TRIGGERING_COMMANDS` so ahead/behind and history refresh the same as after a normal commit.

feat: Copy Commit Hash

- `GitotDiffPanel`: commit header now copies commit hash to clipboard on click, with a brief color-flash confirmation.

Refactor: Split GitotResultRouter out of gitot_dock.gd

- `gitot_dock.gd`'s `#region Status Result` (dispatcher + six domain handlers, ~150 lines) extracted to new
  `ui/gitot_result_router.gd`; dock now forwards results via `_result_router.route()`, except `LAST_COMMIT_MSG` which stays
  dock-side (push-flow specific).
- `_has_upstream` / `_ahead_count` (amend/push guard state) now owned by `GitotResultRouter`, exposed via `has_upstream()` /
  `ahead_count()`.
- New `branch_switched` signal replaces a direct dock-internal call, keeping the router UI-agnostic beyond its injected
  button/panel refs.

Correctness:

- `_handle_branch_result`'s `BRANCHES` case now gates on `exit_code == 0` before parsing output (was output-emptiness only).
- `_ready()` now logs an error if `MAX_READY_RETRIES` is exceeded instead of failing silently.

Type safety:

- `_handle_last_commit_message_result`'s `output: Array` -> `Array[String]` (matches every sibling handler).
- Two untyped `for` loops in `_notify_changed_files()` now typed (`relative_path: String`, `script: Script`).
<hr>
</details>

<details>
<summary>v0.9.0</summary>

feat: Commit history inspection

- `Command.COMMIT_FILES` / `GitEngine.get_commit_files()` - `git show --name-status --format= --no-renames` (same `--no-renames`
  convention as `STATUS_ARGS`, so only A/M/D/T appear).
- `Command.DIFF_COMMIT` / `GitEngine.get_commit_file_diff()` - `git show -U3` for ONE file of a commit, reusing
  `GitDiffParser.parse_full()`. Files are diffed on demand, not per commit, so large commits stay cheap.
- `GitDiffParser.parse_name_status()` - `<letter>\t<path>` lines into `{status, path}` entries. The file list comes from
  `--name-status` because `parse_full()` cannot name deleted or binary files.
- `GitLogPanel.commit_selected(commit_hash)` - new signal; each history row now carries its hash as metadata. Forwarded upward by
  `GitotDock.commit_selected`.
- `GitotCommitFilesList` (new): status-colored `ItemList`, auto-selects the first file.
- `GitotDiffPanel`: body wrapped in an `HSplitContainer`; new `set_commit_mode()`, `show_commit_files()` and
  `commit_file_selected`. The refresh button is hidden in commit mode (a commit's diff never changes).
- `GitotCommitLogDiff` (new, `RefCounted`): serializes requests behind a latest-wins gate, since `command_completed` carries no
  request ID and worker threads can finish out of order. Truncates a single file diff at 200,000 characters.
- `gitot.gd`: wires history click → presenter → bottom panel; a gutter click cancels commit mode, and the working-tree diff result
  restores the normal layout.

feat: Reflog button

- `Command.REFLOG` / `GitEngine.get_reflog()` - `git reflog -n 20` via `run_fast` (read-only, not in `WRITE_COMMANDS`); limit held
  in `GitEngine.REFLOG_COUNT`.
- `GitotLogConsole`: title-bar Reflog button added via `add_title_bar_control()`, same pattern as the bulk stage/unstage buttons
  and the log count dropdown. `GitEngine` is now constructor-injected, and the constructor is
  `_init(git_engine, log_list, scroll, fold)`.
- `gitot_dock.gd`: `_handle_reflog_result()` prints the raw output through `GitotLogger.g()`, so it lands in both the Gitot
  console and the Godot Output panel; failure logs an error, with git's stderr included.

Also changed unstaged/staged color and icon to fit common git user habit! (Modified in orange and Untracked in green)

<hr>
</details>

<details>
<summary>v0.8.1</summary>

fix: Hardening v0.8.0. Performance, correctness, reliability, lifecycle, type safety

Performance:

- Settings reads (`GitotSettings.get_value`) now cached in memory instead of hitting disk on every hot-path call.
- Six previously-unbounded synchronous `OS.execute()` local queries (`get_current_branch()`, `get_remote_url()`,
  `get_changed_files_since_switch()`, etc.) now route through a shared `_execute_bounded()` helper capped at `LOCAL_TIMEOUT_SEC`
  instead of blocking the main thread indefinitely.
- Push's commit-message read and tag-collision resolution converted from sync to async (`request_last_commit_message()`,
  `check_tag_collision()` via `run_fast`).
- Branch dropdown now derives the current branch from the already-parsed branch list (`_get_current_branch_from_list()`) instead
  of an extra sync git call.

Correctness:

- `GitotDiffPanel` guards against a stale result: a diff response is only rendered if the script tab it was requested for is still
  the active one.
- `_handle_sync_result`'s FETCH and push/pull output reads now guard `output.is_empty()` before indexing `output[0]`, matching
  every other handler.

Reliability:

- `GitEngine.run_fast()` rejects a new write command while one is in flight (`_write_busy`), preventing overlapping git processes
  from tripping `index.lock`.

Lifecycle:

- Temp log files (`user://gitot_*.log`) are now tracked per-PID and cleaned up on both the timeout-kill path and `teardown()` —
  previously leaked on every forced-close during a network op.

Architecture:

- `command_completed`'s `output` parameter, and every handler receiving it, typed `Array[String]` instead of bare `Array`.
<hr>
</details>

<details>
<summary>v0.8.0</summary>

feat: Bottom-dock full diff viewer

- `Command.DIFF_FULL` / `GitEngine.diff_full()` - `git diff -U3` against `HEAD`, separate from the gutter's `Command.DIFF`
  (`-U0`). Zero shared state with the shipped, hardened gutter (no regression risk).
- `GitDiffParser.parse_full()` - multi-file-ready hunk parser (`{file, hunks: [{old_start, new_start, lines}]}`), additive to the
  existing `-U0` parser.
- `GitotDiffGutter.hunk_clicked(file_path, line)` - new signal, emitted on gutter click (`set_gutter_clickable` was missing
  entirely before this - gutter had no click behavior).
- `GitotDiffPanel` (new bottom-dock panel): read-only `CodeEdit`, `@@` header per hunk (git's own line span, not the rendered line
  count), dedicated +/- sign gutter, zero-padded real source line numbers in their own gutter, per-line background color,
  file-path label, manual refresh button.
- `gitot.gd`: wires gutter click -> `diff_full()` -> parse -> panel render + jump-to-line. Guards against a stale diff result if
  the active script tab changes before the git process returns.
<hr>
</details>

<details>
<summary>v0.7.2</summary>

fix: harden v0.7.1 - tag collision hardening & feedback for stale resources

Previous retry-on-null-engine fix has a real flaw, it retries unconditionally forever, with no cap. Under normal conditions
\_git_engine gets set within a frame or two and it's harmless. But there's a Godot editor behavior I didn't account for: the
editor can instantiate @tool scenes on its own, most commonly for filesystem thumbnail/preview generation, completely outside the
plugin's own add_control_to_dock() flow. An instance created that way never gets set_git_engine() called on it at all, ever. With
my fix, that orphaned instance's \_ready() just calls \_ready.call_deferred() on itself, forever, one more queued call every
frame, with nothing ever stopping it. Fixed with a `MAX_READY_RETRIES: int = 30`

Correctness:

- Tag push no longer silently overwrites a same-named tag pointing at a different commit - `git_sync_orchestrator.gd` now compares
  the existing tag's commit against HEAD before reusing it; mismatches abort with a clear error instead of pushing.
- Fixed misleading "Push aborted" tag-collision error - the commit push already succeeded by that point; message now says so and
  tells the user to rename and push again to tag it.
- `Push` button is now disabled while a failed tag push is awaiting retry, forcing the dedicated Retry button as the single
  recovery path instead of two buttons silently resolving the same pending state differently.

Reliability:

- `GitEngine.get_changed_files_since_switch()` now distinguishes "nothing changed" from "couldn't determine what changed" (no
  reflog entry yet, or git failure) instead of returning the same empty result for both.
- Editor toast now warns when an open script changed on disk after a branch switch/pull (Godot has no API to reload or close a
  script tab, so this replaces silent staleness with a visible warning).
- Editor toast also warns when changed-file detection itself is unreliable, instead of doing nothing.
<hr>
</details>

<details>
<summary>v0.7.1</summary>

fix: harden v0.7.0 - correctness, lifecycle, security, architecture.

- Add branch scope (local/remote) to the branch dropdown and status panel.

Correctness:

- Dedupe EXITCODE-marker stripping into `GitEngine._poll_process()` instead of duplicating it per-branch in the dock.
- Guard `output[0]` access with `is_empty()` in the dock's stash branch and the orchestrator's tag-exists branch (real crash risk
  on empty stdout).
- `fetch` now triggers `get_ahead_behind()` on success - sync status no longer goes stale until the next unrelated refresh.
- `GitEngine.pull()` wrapper (was calling `run_network()` directly from the dock, same layer violation already fixed for
  `fetch()`).
- Diff gutter now gates on `exit_code == 0` - a failed `git diff` no longer paints stale/garbage markers.
- Size-guard icon no longer overwrites the conflict icon/tooltip on a file that's both conflicted and oversized.
- Empty GitHub PAT can no longer silently overwrite an existing valid token on accidental dialog confirm.
- `GithubApi` now guards against overlapping in-flight requests instead of silently dropping the second call.
- Fixed dock `_ready()` firing before `GitEngine` injection completes (known Godot `@tool`-dock timing quirk), now retries via
  deferred call, guarded against double-init.

Security:

- `create_tag()` rejects shell-unsafe characters (`$`, `` ` ``, `;`, `&`) that are valid git ref characters but unsafe once
  interpolated into `push_tag()`'s shell string.

Lifecycle:

- `GitSyncOrchestrator.teardown()` - disconnects from `GitEngine.command_completed` on plugin exit (was relying on free-order
  luck).
- `GitotLogConsole` caps rendered lines to `GitotLogger.MAX_HISTORY` - was growing one `RichTextLabel` per line, unbounded, over a
  long editor session.
- Network log files disambiguated with a monotonic timestamp instead of just the command name - concurrent same-named ops (e.g.
  two fetches) no longer share/corrupt one log file.
- `GIT_TERMINAL_PROMPT` restored via `OS.unset_environment()` on `_exit_tree()`.

Architecture:

- Split `_on_status_result` (~120-line function) into a thin dispatcher plus six domain handlers.
- Replaced the `command_name: String` signal bus with a typed `GitEngine.Command` enum across `GitEngine`, `gitot.gd`, the dock,
  the orchestrator, the diff gutter, and the status tree - a mistyped/renamed command now fails to compile instead of silently
  mismatching at runtime.
- Consolidated duplicate origin/repo-URL parsing (status panel vs. GitHub panel) into one shared `GitEngine.parse_owner_repo()`.
- Removed dead code: `GithubApi.fetch_labels()` (zero callers).
- `GDScript` member ordering brought in line with the style guide across all touched files; repeated `EditorIcons` theme lookups
  extracted to a shared `_icon()` helper.
<hr>
</details>

<details>
<summary>v0.7.0</summary>

feat: Remote Branch Management & Status Panel

- `GitEngine`: `fetch()` wrapper (`git fetch origin`, network op), `get_ahead_behind()`
  (`rev-list --left-right --count @{u}...HEAD`, fast/local), `track_remote_branch()` (`switch -c <name> --track origin/<name>`,
  reuses `"create_branch"` result path).
- Push fixed: `-u origin HEAD` instead of bare `push` - resolves first-push failure on branches with no upstream.
- `GitBranchParser`: switched from `%(refname:short)` to `%(refname)` to reliably detect and exclude the `origin/HEAD`
  symbolic-ref alias; added `is_remote` flag.
- `GitotBranchPanel`: filters remote entries that already have a matching local branch (avoids `main` + `origin/main` duplicate
  clutter); cloud vs. branch icon per entry.
- New `GitotStatusPanel` (`RefCounted`, constructor-injected `RichTextLabel`): owner/repo, branch name (truncated), branch scope,
  ahead/behind. Detached HEAD flagged in red.
- `fetch` on success triggers `list_branches()` refresh (new remote branches only become visible after a fetch).
<hr>
</details>

<details>
<summary>v0.6.0</summary>

feat: Commit History.

- `GitEngine.get_log()`: `git log` wrapper, `\x1f`-delimited format (hash, author, relative date, short date, subject) — avoids
  delimiter collisions with commit message content.
- `GitLogParser`: static parse into `Array[Dictionary]`, mirrors `GitBranchParser` shape.
- `GitLogPanel`: `RefCounted`, constructor-injected `FoldableContainer` + `Tree` (matches `GitotBranchPanel`/`GitotTagPanel`
  pattern). Count-filter `OptionButton` created in code, injected into fold title bar via `add_title_bar_control()`.
- Relative date shown in list; exact short date (`YYYY-MM-DD HH:MM`) on hover tooltip.
- Wired into existing refresh triggers: `STATUS_TRIGGERING_COMMANDS` (commit/push/pull/switch) and manual `Refresh Status`
  fallback.

feat: Stash Quick-Actions

- `GitEngine.stash_push()` / `stash_pop()`: thin wrappers, same pattern as `create_tag`/`switch_branch`.
- `stash push` uses `-u` to include untracked files - matches solo-dev intent of "shelve all WIP", not just tracked changes.
- Fixed stash message: `"Gitot quick-stash"`.
- Wired into `STATUS_TRIGGERING_COMMANDS` - stash/pop trigger the same status refresh as stage/commit/switch.
- Pop conflicts are not treated as silent failure: exit code != 0 logs git's raw output and still refreshes status so conflicted
  files are visible immediately.
<hr>
</details>

<details>
<summary>v0.5.0</summary>

feat: Branch Management (switch, create, live scene refresh).

- `GitEngine`: `list_branches()`, `switch_branch()`, `create_branch()`, `get_changed_files_since_switch()`,
  `get_current_branch()`.
- `GitBranchParser`: parses local branch list with current-branch flag.
- `GitotBranchPanel`: dropdown (switch) + create-branch dialog, wired into the existing dock UI (no new `.tscn`).
- Scene/resource refresh on switch: precise per-file `update_file()` + `reload_scene_from_path()` for open tabs, instead of a full
  `scan()` - avoids full-project `.import` error noise (read: [Limitation](#-known-limitations)).
- Success/error console feedback for switch/create, including resulting branch name.
- Guard against `git_engine` being unset on mid-session script hot-reload.

feat: Gitot Logger

- **`gitot_logger.gd`**: capped history (`MAX_HISTORY = 200`), decoupled push-listener (`set_listener`/`_on_log`).
- **`gitot_log_console.gd`** (new, `RefCounted`, constructor-injected - matches `GitotStatusTree`/`GitotTagPanel` pattern):
  backfills history on open, appends new lines at the bottom, auto-scrolls via `resized` signal, styled with Godot's own
  `output_source` console font at a smaller size.
- **`gitot_dock.gd`**: wires `GitotLogConsole.new(%LogList, %LogScroll)` in `_ready()`, tears it down properly.
<hr>
</details>

<details>
<summary>v0.4.0</summary>

feat & fix: Tags Versioning, safeguard, cleanup gitot_dock.gd (SoC)...

- Cleaned `gitot_dock.gd`, split into `gitot_status_tree.gd` and `gitot_tag_panel.gd`.
- `GitEngine.create_tag()` / `push_tag()` primitives.
- Dock UI: tag versioning toggle, project-version/manual tag name, commit-message/manual tag message, dynamic version label with
  auto `v` prefix.
- Orchestration chain: chain in `git_sync_orchestrator.gd`: push → tag → push_tag, with per-step console feedback.
- Guards: empty tag name, empty tag message, empty commit message - all pre-push, no silent partial states.
- Retry button for failed `push_tag` command. (query directly `git log -1`).
- Self-heal on "tag already exists" (read: [Limitation](#-known-limitations)).
- `read_stderr=true` fix in `_execute_and_report` - makes stderr visible on _every_ `fast command` (status, diff, add, restore,
  commit too), not just tag, which is good for future error handling.
<hr>
</details>

<details>
<summary>v0.3.0</summary>

feat & fix: bulk stage/unstage, settings panel, status coloring, list fixes...

- Fix untracked folder collapse `--untracked-files=all`
- Fix status args drift via GitEngine.STATUS_ARGS.
- Fix bulk-stage rename mis-parse via --no-renames.
- Fix \_refresh_status() null git_engine crash on editor startup.
- Add Stage All / Unstage All with per-file size-guard skip.
- Color-code + icon unstaged entries (new/modified/deleted/conflict/oversized).
- Guard root-item click on both trees.
- Add Settings `user://gitot_settings.cfg`: large_file_mb, confirm_push, auto_refresh_on_focus.
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
- Remove dead code (\_on_diff_test, unused locals, TEMP prints).
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
- Remove duplicate \_old_count() call.

Architecture:

- Move status-refresh orchestration from dock to plugin composition root.
- Correct run_fast() doc comment (read/write, not read-only).
<hr>
</details>

<details>
<summary>v0.1.0</summary>

Initial MVP commit

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull) run via a monitored
  background process with a 30-second timeout guard, so a slow or stalled connection never freezes the editor.
- **Git dock:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click stage/unstage.
- **Commit & Sync:** stage/unstage, commit message input (multiline supported), and Commit / Push / Pull buttons (read:
  [Limitation](#-known-limitations)).
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter, computed from
  `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires reliably) with a manual **Refresh
  Diff** fallback button.
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.
</details>

---

## © License

Copyright (c) 2026-present SigK - under the [MIT License](LICENSE).
