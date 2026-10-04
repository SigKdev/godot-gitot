<div align="center">
<img width="640" height="360" alt="Image" src="https://github.com/user-attachments/assets/af78184e-57f6-4306-bd31-e50b3315ac7b" />
</div>

<p align="center">
<a href="https://ko-fi.com/sigkgames"><img
src="https://img.shields.io/badge/Sponsor-30363D?logo=GitHub-Sponsors" alt="Sponsor SigKgames"></a> <a
href="https://godotengine.org/"><img
src="https://img.shields.io/badge/Godot-4.7+-478CBF?logo=godotengine&logoColor=478CBF" alt="Godot 4.7"></a> <a
href="https://git-scm.com/"><img src="https://img.shields.io/badge/GIT-2.3+-F03C2E?logo=git&logoColor=F03C2E"
alt="Git"></a> <a href="https://git-lfs.com"><img
src="https://img.shields.io/badge/GIT_LFS-3.4+-F64935?logo=gitlfs&logoColor=F64935" alt="Git LFS"></a> <a
href="https://store.godotengine.org/asset/sigk/gitot/"><img
src="https://img.shields.io/badge/Gitot-0.15.1-B8195F" alt="Gitot"></a> <a href="LICENSE"><img
src="https://img.shields.io/badge/License-MIT-green" alt="License"></a>
</p>

<p align="center">
  <a href="https://store.godotengine.org/asset/sigk/gitot/"><kbd>📸 Screenshots</kbd></a> &nbsp;&nbsp; <a
  href="#-features"><kbd>🧬 Features</kbd></a> &nbsp;&nbsp; <a href="#-installation"><kbd>🛠️
  Installation</kbd></a> &nbsp;&nbsp; <a href="CHANGELOG.md"><kbd>🗃 Changelog</kbd></a> &nbsp;&nbsp; <a href="wiki"><kbd>📖 Wiki</kbd></a>
</p>

**Gitot** is a lightweight Git workflow plugin for the Godot 4 editor **intended for solo developers** who
want fast, reliable Git operations (stage/unstage, commit, stash/pop, fetch/push/pull), inline diff gutter,
full diff viewer, full LFS support and issue tracker without leaving the editor.

**Gitot** wraps the system `git` binary directly via `OS.execute()`, in pure GDScript, with no GDExtension and
no bundled `libgit2`. It inherits your existing SSH/credential setup and the full Git feature set without
re-implementing any of it. This trades a tiny amount of raw performance for stability, transparency, and zero
maintenance burden across engine/OS updates.

**If Git works from your terminal, it works from Gitot as it uses your terminal's git setup.**

Gitot is fully independent of Godot's built-in Version Control integration (Editor Settings → Version
Control), no VCS plugin needed, nothing to configure there. Gitot talks to your system `git` directly.

**Screenshots available on the [Godot Asset Store](https://store.godotengine.org/asset/sigk/gitot/).**

> [!IMPORTANT]
> 
> Gitot is under active, daily-use development by a solo developer. It is built and tested on Godot 4.7.2.
> Core workflows (stage/commit/push/pull, branching, diff gutter & viewer) are used daily in real projects and
> have been through several correctness/lifecycle hardening passes (see [Changelog](#-changelog)).
> - This is **not yet a widely-tested release**. It has been validated on Windows with one developer's
> workflow, on small repo, not across operating systems or project sizes.
> - **Pure logic [GdUnit4](https://github.com/MikeSchulze/gdUnit4) tested.** (see [Testing](#-testing))
> Gitot requires significantly more testing under everyday usage conditions!
> - **Commit your work / make backup before trying a new Gitot version**, same as any Git tool in active development.
> - Bug reports and real-world usage feedback are the most valuable contribution right now.



## 🧬 Features

- **Commit & Sync:** Stage or unstage files individually, by multi-selection (Enter) or in bulk, write
  multiline commit messages, and Commit, Amend, Push, or Pull. Amend is guarded. A diverged branch asks
  before a force push (`--force-with-lease`); a branch that is only behind is never pushed. The Push
  tooltip says what it will do right now. Buttons show a busy state while a write runs.

- **Stash Manager (Shelf):** Stash all changes (staged + unstaged + untracked) under an optional name, then
  pop or drop any entry from a capped, foldable list (limit is a setting, default 10). Pop refreshes only the
  files it touched in the editor.

- **Local Branch Management:** Foldable branch list (name, ahead/behind, last update). The title shows the
  current branch; its sync status with commit counts (`↑ 2`) sits on the right of the title bar. A button row
  under the title has Fetch, `+` (create a branch inline) and delete buttons. Double-click to switch. Open scenes refresh
  automatically on switch without a full project rescan. A toast warns if an open script changed on disk, or
  if changed files couldn't be reliably detected (see [Limitations](#-known-limitations)).

- **Remote Branch Management:** Fetch remote updates, list remote-only branches, and double-click one to
  check it out with automatic tracking. A **Delete on origin** button removes a branch from origin only
  (never forced, always confirmed; the old tip hash is logged so it can be restored).

- **Tag Versioning:** Push with or without an annotated tag. Auto-tagging settings - see _Details_ below.
  The tag name is validated before the push.

- **Commit History:** Browse recent commits (message, author, date) with a count filter (10/20/30). Click a
  commit to inspect its changes file-by-file in the bottom-dock diff viewer.

- **Color Diff Gutter:** Modified and added lines are marked directly in the script editor's gutter. Click to
  open the matching hunk in the diff viewer.

- **Diff Viewer Panel:** Bottom-dock full-context unified diff for the current script. Basic syntax
  highlighting, foldable hunk with headers, per-line +/- gutter with real source line numbers and color-coded
  additions/deletions. Also browses any past commit file-by-file: pick a file from the changed-files list to
  view its diff. (Click the commit header to copy its hash).

- **Restore File:** In the diff viewer's commit-history mode, restore a file to its content at that commit.
  Confirmation dialog before overwriting uncommitted changes.

- **Git LFS:** Dedicated **Gitot LFS** bottom panel: a left dashboard (state, Download / Prune, storage stats
  computed from the files list, tracked patterns with one-click Godot-aware presets) beside the files list
  (size, `Local + Remote` / `Local` / `Remote` / `Missing` status). Without git-lfs, or before `git lfs install`,
  it shows a simple setup guide instead. The bottom notes can be hidden (**Info**). Normal Push/Pull already
  handle LFS through git's own hooks and filters.

- **Large-File Guard:** Blocks staging any file over a configurable size limit to prevent repository bloat,
  flagging oversized files with a warning icon. Files covered by an LFS rule are exempt (when LFS is ready),
  and a **Track with LFS** button on a flagged file adds the rule in one click.

- **GitHub Issues Tracker Board:** Split list/detail view (like the commit history) of the repo's open issues
  (requires a [PAT](#github-personal-access-token)); opt-out in settings. Header: `owner/repo · N open`,
  Refresh, Clear PAT. Sortable column list (number, title, date, type, priority, labels),
  Type/Priority/Label filters, full issue detail (metadata, colored labels, Markdown body, Open in Browser).
  Create a branch directly from an issue, auto-named from its number/title/type (editable),
  with a base-branch picker and a dirty-working-tree confirmation.

- **Repo Status Panel:** One-line summary of the current repo, branch (detached HEAD flagged in red), branch
  scope, and ahead/behind sync status.

- **Accents & Unicode:** files with accented or non-Latin names (`Lumière.mp3`) can be staged,
  and accented text displays correctly in diffs, commit history and stash names.

- **Gitot Logger:** Git and Gitot output are routed through Gitot's own dock logger to keep the Godot output
  panel clean. The console's **Info** menu: Reflog (last 20), Repo size (`git count-objects -vH`), Copy log,
  Clear log. After a big commit only the summary line (`N files changed, ...`) is printed, not the file list.

- **Beginner-friendly messages:** commit / push / pull / fetch / stash results are worded in plain language,
  and a failure shows git's raw error plus the common causes.

More details per feature: [Wiki](../../wiki).


## 🛠 Installation

1. Copy `addons/gitot/` into your project's `addons/` folder.
2. Enable **Gitot** under Project Settings → Plugins.

#### Requirements

- Godot 4.7+
- `git` installed and available on your system `PATH`.
- `git-lfs` **(optional but Recommended, only needed for the Gitot LFS panel)**.
- A GitHub Personal Access Token ([PAT](#github-personal-access-token)), **(optional, only needed for the Issues integration)**.


## 📖 Documentation

Full documentation lives in the **[Wiki](../../wiki)**:
[Settings](../../wiki/Settings) · [Branches](../../wiki/Branches) · [Stash Manager](../../wiki/Stash-Manager) · [Git LFS](../../wiki/Git-LFS) · [Issues Tracker](../../wiki/Issues-Tracker) · [Architecture](../../wiki/Architecture)


## ⚠ Known Limitations

- After a `Pull`, a branch `Switch`, a `Restore`, or a `Stash Pop`, Godot has no API to reload an open script
  tab. Gitot recompiles the script's class and shows a toast, but the tab's visible text only updates on the
  next **editor focus change**. To avoid it altogether, close the affected script tab _before_ switching
  branches, pulling or popping.
- Validated on Windows only. Non-ASCII text is verified on Windows-1252 only.

All other limitations (editor refresh, branches, stash, diff viewer, LFS): see **[Troubleshooting](../../wiki/Troubleshooting)** in the wiki.


## 🔑 Credential Handling

#### SSH

Pushing/pulling relies on your system Git's own credential handling (SSH agent, Git Credential Manager, etc.).
**Gitot does not manage credentials!** Gitot does not suppress OS-level credential prompts (e.g. Windows Git
Credential Manager popups). If push/pull hangs waiting on such a prompt, it will be automatically killed after
120 seconds. Configure a working credential helper or SSH agent so `git push`/`git pull` succeed from a
terminal before relying on Gitot for sync.

#### GitHub Personal Access Token

Only needed to use the **GitHub Issues Tracker Board** feature.

> [!CAUTION]
> 
> **Gitot** stores your GitHub PAT locally in plaintext at `user://gitot_auth.cfg` (outside `res://`, so it is
> never committed to your repository).
> 
> **This is not encrypted.** Godot/GDScript cannot access your OS-level credential store (Windows Credential
> Manager, macOS Keychain, etc.) without a native extension, which is outside this plugin's scope. **Anyone
> with access to your local user account can read this file.** And the Godot hot-reload and `_exit_tree()`
> make it not possible to auto clear the PAT when uninstalling/disabling Gitot. **You must clear your token
> before uninstalling/disabling**

> [!TIP]
> 
> **PAT Recommendations:**
> 
> - Use a **fine-grained token** scoped to Repo Access and with Issues Access read/write only. **Never an
> admin or org-wide token!**
> - Use the **Clear Token** button in the Gitot Issues Panel toolbar **before
> uninstalling or disabling the plugin**, or when working on a shared machine!
> - If you do not intend to use this feature, opt-out in settings to unload it completely!
> - Check the GitHub Personal Access Token [documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).


## 💬 Feedback & Support

- **Bug reports:** use [Issues](../../issues) - include your OS, Godot version, and steps to reproduce.
- **Feature ideas, questions, general feedback:** use [Discussions](../../discussions) instead. Issues are
  kept strictly for actionable bugs.


## 💝 Sponsor This Project

**Gitot** is developed and maintained solo, in my own time, alongside an ongoing personal Godot game project
_(stopped cause of hardware issue)_. If Gitot has saved you time or you'd like to see development continue,
sponsoring is the most direct way to help, it goes straight toward the hours and the hardware this project and
my game project runs on.

<a href='https://ko-fi.com/sigkgames' target='_blank'><img height='48' style='border:0px;height:48px;'
src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

No pressure! Using Gitot, reporting bugs, and sharing feedback in Discussions is just as valuable to the
project.


## 🧪 Testing

Last run v0.15.1: **17 suites, 137 tests, 0 failures** (Godot 4.7.2, Windows).

- **Automated:** [GdUnit4](https://github.com/MikeSchulze/gdUnit4) cover the pure logic: parsers
  (status, diff, log, stash, branch, LFS, paths), the runner (shell contract, encoding, shell-safety whitelist),
  the engine (command classes, branch-name safety), the push planner, and the UI helpers (sync symbols, counts,
  tooltips, titles, LFS dashboard texts and stats, issue header).
- **Manual:** the UI flows were tested in the editor (stage / commit / amend / push / pull, branches,
  remote delete, tags, shelf, issues, LFS panel, console menu).
- **Not covered:** UI scenes and node wiring have no automated tests, and the LFS flows against a real LFS remote
  (Install LFS, push / pull / prune of real objects, the not-installed views) have not been exercised yet.

Details: [[Testing](../../wiki/Testing) in the wiki.


## 🗃 Changelog

See **[CHANGELOG.md](CHANGELOG.md)**. Latest: **v0.15.1**.


## © License

Copyright (c) 2026-present SigK - under the [MIT License](LICENSE).