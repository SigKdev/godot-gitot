# Changelog

All notable changes to Gitot. Latest first.

## v0.16.0

feat: status letters & FileSystem tooltip. refactor: explicit output messages - one failure shape

Tested with GdUnit4 (19 suites, 152 tests, 0 failures) and by hand in the editor.

feat: status in the Staged / Unstaged lists

- Each row shows its status as a colored icon (default) or as a colored letter before the path: `U` untracked,
  `A` added, `M` modified, `D` deleted, `C` conflict. Never both.
- New setting **Status letters** (`status_letters`, default off). Toggling it repaints the lists with one
  `git status` (the row selection is cleared).
- Size Guard rows keep their warning icon in both modes.

feat: git status in the FileSystem dock

- Hovering a changed file adds one line to Godot's tooltip: `Git (staged): M`, `Git (unstaged): M`,
  colored like the lists. Unchanged files keep Godot's own tooltip.
- Always on, no setting. The data is the last status parse: no extra git call, no cost per hover.

feat: messages name what they concern

- Success and info lines name the branch, repo, tag or file: `Commit saved locally on branch 'dev'.`,
  `Commits pushed to 'owner/repo' on branch 'dev'.`, `Pulled from 'owner/repo' into branch 'dev'.`,
  `Fetched from 'owner/repo': ...`, `Switched to branch 'x'.`, `Tag 'v1' pushed to 'owner/repo'.`,
  `Current branch 'dev' is 10 ahead, 0 behind origin.`
- A forced push says so: `Commits force-pushed to ... Origin's diverged commits were replaced.`
- The tag line names the repo, not a branch: a tag belongs to a commit, and Retry can run after a branch switch.
- Push / pull no longer claim "new commits merged" or "nothing was uploaded": exit 0 also covers "Already up to
  date", a conflicted pull leaves a merge in progress, an LFS push can upload objects before failing. Git's raw
  line follows the result.
- Empty-input and cancel warnings say what did not happen (`Commit message is empty - nothing was committed.`).
- Startup: `'git' binary found. Plugin ready.` The Fatal line says what to do (install git, restart the editor).

refactor

- `GitotStatusTree.STATUS_VISUALS` (letter, icon, color, tip) is the single source for both the lists and the
  tooltip.
- A row's path is stored in the item metadata (`_path_of()`): the cell text is display-only, so stage, unstage,
  Open file and Track with LFS never parse it.

fix: failures

- Every command failure logs the same three lines: an error naming the subject (`Push of branch 'dev' to
  'owner/repo' failed.`), git's raw message, and a `Common causes` hint. Added for stash, pop, drop, local and
  remote branch delete, restore, switch, create, reflog, repo size, stage / unstage, tag push, tag creation,
  LFS pull and track / untrack. A hint only lists causes git is known to produce: LFS install / prune show the raw
  message only.
- Tag push failure is reported by the result router (it names the Retry button; the core has no UI knowledge).
  Tag creation failure reads `Commits pushed, but tag 'v1' could not be created.` (the old text said the push was
  aborted, but it had already happened).
- GitHub issue-loading failures are logged as errors (were warnings).

refactor: logger and state

- `GitotLogger.fail(title, raw, hint)`: the single failure shape (error, raw, hint). Empty raw / hint are skipped.
- New `Level.HINT` / `GitotLogger.h()`, prefix `[Gitot Hint]`, for advice lines: causes, "unfocus/focus the editor
  window", "Commit .gitattributes ...", recovery tips. Fatal (`x`) is kept for "Gitot cannot work": git missing, or
  the dock without its engine.
- `GitotRepoState` gains `branch` and `repo` (written by the router from the branch list, the remote URL and
  switch / create). Messages fall back to `HEAD` / `origin` until known.
- `GitEngine` context: `PUSH` carries `{force}`, `PUSH_TAG` carries `{tag}`.
- Known limit: after a branch switch made outside Gitot, the ahead/behind line can name the previous branch for
  one refresh.
<hr>

## v0.15.2
fix: console leak, UI freezes while a write runs, hot-reload null regex - refactor: dock split, typed branch entries, one sync state

Tested with GdUnit4 (18 suites, 146 tests, 0 failures) and by hand in the editor.

fix: stability

- Console label cap: `queue_free()` keeps a node counted until frame end, so a burst of lines removed only one label. The oldest label is now detached first (`remove_child`).
- Write lock: `GitRunner.run_fast()` blocks only writes while a write runs; reads always run. Before, a read dropped during a write never completed: the commit diff viewer could stay stuck for the session, and the push-time commit-message lookup and the LFS state check could hang.
- `git status` runs with `--no-optional-locks`: a background refresh can no longer take `index.lock` from a commit or stage.
- `stash pop`, `remote get-url` and the changed-files lookup after a switch/pull are async. `GitRunner.execute_bounded()` (a busy-wait that could block the UI up to 5 s) is removed. Pop lists the touched files first, then pops with that list as context (`GitEngine.to_file_list()`, `remote_url_of()`).
- Diff gutter: the "already connected" guard tested the unbound callable and was never true. The bound callable is now built once, tested and connected (no duplicate `hunk_clicked`).
- Static regexes (tag name, branch name, shell whitelist, hunk headers, issue slug) are compiled on first use. A `static var` initializer is not re-run on editor hot-reload and left them `null` ("Cannot call method 'search' on a null value" on save).
- `GitRunner._poll_process` ignores a pid after `teardown()` (hot-reload).
- Diff parser: an added line starting with `++ b/` is no longer read as a file header (checked only outside a hunk).
- `create_tag` / `push_tag` reject a leading `-`. `network_timeout_sec` is clamped to 30 s minimum (a hand-edited `0` killed every network op).
- `GithubApi` creates its `HTTPRequest` in `_ready()` (no node leak if never in the tree).
- A tag name that already exists on another commit now raises an editor toast (it was only logged).
- Stage / unstage and the LFS "ready" event refresh only the file lists (one `git status`) instead of the full 5-command refresh.
- First open of the LFS tab shows "Loading LFS files..." until the list arrives.
- Startup check `git rev-parse --show-prefix`: warns once if the Godot project is not the repository root.

refactor: structure

- `GitotDock` 538 -> ~390 lines: `_ready()` is split into setup steps, and three modules are extracted: `GitotEditorSync` (editor refresh after git changed files), `GitotPushFlow` (push use case, tag input validation), `GitotWorkingDiff` (working-tree diff mode, mirrors `GitotCommitLogDiff`).
- `GitotRepoState` (new, `core/`): single source for upstream / ahead / behind with a `changed` signal. The router writes it, the status panel, branch panel and push flow read it. The router's 60-line sync handler is split (fetch, ahead/behind, push/pull). `stash_popped` is replaced by `files_changed`.
- `GitBranchEntry` (new, `core/`): typed branch row replaces the Dictionary (`GitBranchParser.parse()` returns `Array[GitBranchEntry]`; `hash` is now `commit_hash`).
- `GitSyncOrchestrator` no longer touches `EditorInterface` (emits `tag_conflict`; the dock shows the toast).
- `GitotLogger`: history is private (`get_history()`, `clear_history()`); EXTREME prints `[Gitot Fatal]`.
- `MAX_DIFF_CHARS` moved to `GitotDiffPanel`. Typed `for` loops, plan/history comments and dead code removed.
<hr>

## v0.15.1
fix: shell injection surface - safer push and remote delete - clearer messages - feat: LFS dashboard

Tested with GdUnit4 (17 suites, 137 tests, 0 failures) and by hand in the editor.

fix: shell injection surface - refresh

- `run_network()` builds a shell string and only a few characters (`$`, backslash, `;`, `&`) were blocked (tags only). `GitRunner.is_shell_safe()`
  (`[A-Za-z0-9._/@+:-]`) is now enforced for every argument; `create_tag` checks up front so no unpushable tag is
  created.
- Alt+S refreshes the unstaged list (`resource_saved` + `scene_saved`, coalesced into one `git status`).

fix: safety

- `GitSyncOrchestrator.plan_push(has_upstream, ahead, behind)` replaces `needs_force_push()`: `NORMAL`,
  `FORCE_CONFIRM` (diverged, dialog with the counts), `BLOCKED_BEHIND` (only behind: refused, "Pull first").
  Decided from the router's counts, no git call. This fixes a forced push that could rewind origin.
- Push tooltip says what it will do now (first push, N commits, up to date, blocked, diverged); built on hover
  from the same counts (`GitotUi.push_tooltip()`).
- **Delete on origin** button: only `git push origin --delete refs/heads/<name>`, name whitelist, own confirm
  dialog, old tip hash logged for restore. Deleting a local branch that also exists on origin says so.

refactor: panels

- Busy state while a write runs (`write_busy_changed` runner -> engine): Commit shows "Working...", Stage All /
  Unstage All disabled; message and amend are cleared only on success.
- Amend is a toggle (CheckButton) with a tooltip; the button and placeholder follow the mode.
- After a big commit only the summary line is logged, not the file list.
- Fetch / `+` / Delete / Delete on origin moved to a button row defined in the scene. The title keeps the
  branch (`Branches (4)  ·  on main`); the current branch's sync status with counts (`↑ 2`, `↓ 1`, `↑↓ 2/1`)
  is right-aligned in the title bar. Sync tooltips detail the state and the fix, without GitHub wording.
- `GitotUi` is the single source for sync symbols, colors, counts and tooltips (status line and header share it).
- Issues header: `owner/repo · N open`, Refresh, Clear PAT (no Gitot label / version).
- Console **Info** menu: Reflog (last 20), Repo size (`git count-objects -vH`), Copy log, Clear log.
- Plain-language messages for commit, push, pull, fetch, stash, stage; failures show git's raw error and the
  common causes.
- A toast + log warn when a branch switch changes Gitot's own files (restart the editor).

feat: Gitot LFS panel dashboard

- The header is gone: a left dashboard (resizable split) holds the state, Refresh, **Download** (`git lfs pull`),
  **Prune**, **Info**, stats and the tracked patterns, beside the files list.
- Stats (`GitLfsParser.summarize()`, pure): files and total size, on this computer, on GitHub, to upload, to
  download, missing, largest file. "On GitHub" is an estimate from origin's file list as of the last fetch (no
  LFS quota API exists).
- Without git-lfs, or before `git lfs install`, only the dashboard shows, as a 4-step setup guide (finished steps
  marked) with the one button that fixes the state. Fixed a missing line break before the pointer warning.
- The bottom notes can be hidden with **Info**; the choice is saved (`lfs_note_visible`). Long patterns are
  cut with "…" and have a tooltip.
- Track / Untrack are icon-only (`Pin`, `PinJoint2D` recolored white by `GitotUi.get_icon_white()`); the
  Patterns menu has the `RegEx` icon.
- Files list status uses the branch wording: `Local + Remote`, `Local`, `Remote`, `Missing` (`ls-files @{u}`
  merged by `GitLfsParser.merge_scopes()`).

**TODO:** Known untested: the LFS panel against a real LFS remote (Install LFS click, real objects,
the not-installed views), GitHub's wording when refusing to delete a default / protected branch.
<hr>

## v0.15.0
feat: Git LFS support - fix: non-ASCII text, Stage All on large lists, multi-select staging, invalid tag names

feat: LFS engine layer

- `GitEngine.Command`: `LFS_VERSION`, `LFS_STATE`, `LFS_LS_FILES`, `LFS_TRACK`, `LFS_UNTRACK`, `LFS_INSTALL`,
  `LFS_PULL`, `LFS_PRUNE`. Track / Untrack / Install / Prune are in `WRITE_COMMANDS`; Pull runs through
  `run_network()`.
- `GitLfs` (new, `core/`): facade owning its own results (the router did not grow). Signals: `state_detected`,
  `files_listed`, `patterns_changed`, `ready_changed`, `pull_finished`. Rejects empty or `-`-prefixed patterns
  and Godot text formats.
- `GitLfsParser` (new, `core/`, static): `ls-files --json` (`files` can be `null`; 0-byte files are not
  listed) and `.gitattributes` patterns. Verified against real git-lfs output (3.4.1).

feat: Gitot LFS panel

- Bottom panel; its files list loads on first open, while the LFS state is detected at startup
  (needed by the Size Guard exemption and the Track-with-LFS button). Views: missing binary,
  not initialized (Install LFS), active (files tree + patterns).
- **Patterns** menu: one click tracks a preset (Textures, Art source, 3D, Audio, Video, Fonts, Godot binary).
  Pattern field for custom rules. Pull (repair) and Prune (confirmation). Hints for network timeouts.
- `GitotDock` rescans the filesystem after a successful LFS Pull. Track / Untrack refresh status.

feat: Large-File Guard and LFS

- Files covered by an LFS rule are exempt, only when LFS is `READY` (`GitotStatusTree._violates_guard()`, one
  test for the tree icon, double-click stage and Stage All).
- Flagged files get a **Track with LFS** button (rule from the extension, or the file name when there is
  none).

fix: Stage All with hundreds of files

- Windows caps a command line at 32,767 characters, so `git add -- <829 paths>` failed to spawn
  ("Could not create child process", empty git output). `GitRunner._chunk_args()` (new, static) splits the
  paths after `--` into batches of at most `MAX_ARGS_CHARS`, run sequentially inside the same write lock; the
  first failure stops the batch. Applies to every `-- <paths>` command.

fix: multi-select staging

- Enter on several selected rows now stages / unstages all of them (`GitotStatusTree._get_selected_paths()`;
  `Tree.get_selected()` only returns the focused row). Unstage now passes `--`.
- Stage All and Enter share `_stage_paths()`, so the Size Guard filter exists once.

fix: tag push

- The failure of `git tag` was swallowed and matched on English text ("already exists"), which breaks on a
  localized git. The orchestrator now asks git instead: `check_tag_collision()` runs
  `rev-parse <tag>~0 HEAD`; a failure means the tag doesn't exist and git's real message is logged.
- `~0` peels the annotated tag to its commit; the old comparison used the tag object's SHA, so the "retry on
  the same commit" path never matched.
- `GitEngine.is_valid_tag_name()` (new, static) rejects names git refuses (spaces, `~ ^ : ? * [ \`, `..`,
  `@{`, ...) **before** the push, so a bad name can't leave a pushed commit without its tag.
  
fix: non-ASCII file names (accents, etc.)

- Git quotes such paths (`"Lumi\303\250re.mp3"`), so Stage All failed as a whole (`git add` is all-or-nothing)
  and the Size Guard could not read the file. `GitPath.unquote()` (new, `core/`, static) decodes git's C-style
  escapes to UTF-8; used by `GitStatusParser`, `GitEngine._to_file_list()`, `GitLfsParser` and
  `GitDiffParser.parse_name_status()`. Quoting is decoded rather than disabled (`core.quotepath=false`)
  because raw UTF-8 read through `OS.execute()` came back garbled on Windows.
- A failed Stage / Unstage now logs git's error instead of failing silently.

fix: garbled non-ASCII text on Windows (diffs, history, stash, tag messages)

- `OS.execute()` decodes the pipe with the Windows ANSI code page, so UTF-8 text from git came back garbled (`é` → `Ã©`,
  `—` → `â€”`) in the diff viewer and anywhere else git text is shown (commit history, stash names, the last commit message
  reused as the tag message).
- `GitRunner._fix_encoding()` (single decode point, `_execute_and_report()`) re-encodes the string with that same code page to
  restore the raw bytes, then decodes them once as UTF-8. Skipped on non-Windows platforms and for ASCII-only or empty
  text (the conversion API rejects empty input).
- Verified on Windows-1252 only: Latin accents, `—`, Cyrillic, Greek, Arabic and Hebrew all render correctly in the diff viewer.
  Other Windows code pages (Chinese, Japanese, Korean) are untested.
<hr>

## v0.14.1
fix: per-call, Stage/Unstage empty list + ref: git_engine>git_runner

fix: per-call `context` replaces the `_last_*` side-channel state

- `command_completed(command, exit_code, output, context)`: the new `context: Dictionary` carries data
  captured at call time: `branch` (switch / create / track), `path` (restore), `{reliable, files}` (stash
  pop). `run_fast()` gains an optional `context` parameter, so existing callers are unaffected.
- `_last_switch_target`, `_last_restored_path`, `_last_popped_files` and their getters are removed. This fixes
  a log mix-up: a switch ignored by the write guard still overwrote the target of the switch in flight, so the
  log could name the wrong branch.
- `stash_popped` now carries the file list, and the dock connects it straight to `_notify_file_list()`
  (`_notify_popped_files()` removed).
- Every `command_completed` handler takes the extra `context` parameter.

fix: Stage All / Unstage All on an empty list

- `TreeItem.get_child(0)` on a childless root raised `Index p_index = 0 is out of bounds`. Replaced by
  `get_first_child()` in `GitotStatusTree._get_tree_paths()`, plus a new `_is_empty()` helper used by the
  Unstage All guard.

fix: Issues tab base-branch dropdown never followed HEAD

- `IssueDetail.set_base_branches()` kept the previous selection whenever that branch still existed, so after a
  switch or create the dropdown stayed on the old branch until a restart. It now selects the current branch
  when HEAD moved (and on first fill) and keeps the user's manual pick across plain refreshes.

refactor: GitRunner extraction - per-call context on `command_completed`

- `GitRunner` (new, `core/`, `RefCounted`): all process execution moved out of `GitEngine` with no behavior
  change - `run_fast()` (`WorkerThreadPool` + write lock), `run_network()` (kill-on-timeout),
  `execute_bounded()` (sync, capped at `LOCAL_TIMEOUT_SEC`), `teardown()`. It is git-domain agnostic: it takes
  a label, an `is_write` flag and a `Callable` instead of a `Command`, so it has no dependency on the engine.
- `GitEngine` keeps the public API (`Command`, `WRITE_COMMANDS`, wrappers, `command_completed`). `run_fast()`
  / `run_network()` keep their signatures and reach the runner through one `_relay()` callback. Early failures
  (spawn failure, unsafe tag name) go through the same path.
- The write-guard warning now reads `<Command> skipped: another git write was still running.`

refactor: UI polish

- The Staged fold closes itself when there is nothing staged and reopens when files arrive. A manual fold is
  not overridden by plain refreshes.
- Status panel shortens `(Local + Remote)` to `(L+R)`. Display-only mapping in `GitotStatusPanel`; the
  router's scope strings are unchanged.
- Startup message now includes the git and git LFS versions:
  `'git' binary verified. Plugin ready! (git x.y.z | LFS x.y.z)`. Without git-lfs it shows `LFS not installed`
  and never blocks startup. New `GitEngine.get_git_version()` / `get_lfs_version()`; `is_git_available()` now
  wraps `get_git_version()`, so startup spawns no extra `git --version`.
- Amended commits are reported as such: `Commit amended.` / `Amend failed.` (`_handle_commit_result()` now
  receives the `Command`).
<hr>

## v0.14.0
ref: Branch list, cleanup - feat: delete branch

refactor: Branch panel rebuilt as a foldable list

- `GitEngine.BRANCH_LIST_FORMAT` (new) and `GitBranchParser` rewritten: name, current/remote flags, upstream,
  sync (`%(upstream:trackshort)`, locale-independent), commit date (unix/relative/exact), short hash, subject.
  Delimiter is `UNIT_SEP`; the old `|` split could break on ref names containing it.
- `GitotBranchPanel`: dropdown replaced by a 3-column `Tree` (name/sync/updated) in the `BranchFold`
  `FoldableContainer`. Double-click switches, or tracks a remote-only branch. Selection survives refreshes (by
  name). Fetch moved from its own button into the fold title bar (fetch / + / delete).
- Push / Pull / Retry Tag stay in their own row.

feat: Inline create branch

- `GitotBranchCreator` (new, `RefCounted`): `+` title-bar toggle shows a name `LineEdit` + Create button under
  the header. Enter or Create confirms through `%CreateBranchConfirmDialog` unless disabled. The
  `NewBranchDialog` window is removed.
- New `confirm_create_branch` setting (default on) with a settings-panel checkbox.

feat: Delete branch

- `Command.DELETE_BRANCH` (in `WRITE_COMMANDS`), `GitEngine.delete_branch(name)` runs `git branch -d`.
- `GitotBranchDeleter` (new, `RefCounted`): trash button enabled only for a selected local, non-current
  branch. Always asks for confirmation, no Force: git refuses unmerged branches and its output is logged. The
  router refreshes the list on success.

refactor: cleanup

- `GitotUi` (new) replaces `GitotIcons`: `get_icon()`, `add_title_button()`, `set_busy()`. The dock's
  `_set_busy()` and the stash panel's title-button code now use it.
- `GitotDock.refresh_status()` now also requests `list_branches()`, so the list refreshes on every
  status-triggering command, on focus-in and on manual refresh. The duplicate `list_branches()` /
  `get_current_branch()` calls in the router's switch/create path are removed.
<hr>

## v0.13.0
fix: network timeout. feat: Stash Manager (Shelf) - list, named stash, drop, refresh after pop

Fix: network timeout: `_poll_process` killed the push at 30s. A large asset push on slow connection will be
killed mid-transfer. Now configurable timeout in settings (default 120s - range: 30/900).

feat: Shelf panel (replaces the toolbar Stash/Pop quick-actions)

- `GitStashParser` (new, `core/`): static parser for `git stash list` (`GitEngine.STASH_LIST_FORMAT`:
  selector, SHA, relative date, absolute date, subject). The subject splits into branch + name (`WIP on` = git
  default, `On` = custom `-m`); an unmatched subject falls back to an empty branch and the raw subject.
- `GitotStashPanel` (new, `RefCounted`): 3-column `Tree` (name/branch/date) in a `FoldableContainer`; Stash /
  Pop / Drop buttons in the title bar, name `LineEdit`, drop `ConfirmationDialog`. Selection survives
  refreshes (by SHA); Drop re-resolves its SHA to the current index before running.
- `GitEngine`: `Command.STASH_LIST` (read-only), `Command.STASH_DROP` (in `WRITE_COMMANDS`); `list_stashes()`,
  `stash_push(message)` (blank = no `-m`, git's default subject), `stash_pop(index)`, `stash_drop(index)`. The
  fixed "Gitot quick-stash" message is gone.
- New `max_stashes` setting (1-50, default 10) with a settings-panel SpinBox; Stash is blocked when the shelf
  is full. Changing the value updates the shelf immediately (`stash_cap_changed`).
- `STASH_DROP` added to `gitot.gd`'s `STATUS_TRIGGERING_COMMANDS`. The shelf refreshes with status on every
  trigger, on focus-in and on manual refresh (`GitotDock.refresh_status()` is now the single refresh path;
  `refresh_log()` removed).

feat: Precise editor refresh after Stash Pop

- `stash_pop(index)` lists the stash's files first
  (`git stash show --name-only --include-untracked --no-renames`, one bounded call), because the entry no
  longer exists afterwards. On success the router emits `stash_popped` and the dock refreshes only those
  files. The blanket "close and reopen any open scripts/scenes" log line is gone.
- `GitEngine._to_file_list()` (new) shared by `get_changed_files_since_switch()` and the pop path;
  `GitotDock._notify_file_list()` shared by branch switch and pop.

refactor: cleanup

- `GitotIcons.get_icon()` (new): single source for editor-theme icon lookup, replacing the private `_icon()`
  copies in the dock, router, and plugin entry point.
- `GitotResultRouter` no longer holds the Fetch/Pull buttons (constructor 8 → 6 parameters); the dock owns
  busy state for Fetch, Pull and Push through one `_set_busy()` helper.
- `GitLogParser.FIELD_SEP` removed; `GitEngine.UNIT_SEP` is the single separator constant.
<hr>

## v0.12.0
feat: GitHub Issues Tracker Board - split list/detail refactor, base-branch picker, pagination

feat: Split list/detail Issues panel (commit-history-style layout)

- `GithubIssueParser` (new, `core/`): static, null-safe normalizer for raw REST issue JSON. casts float
  `number` to `int`, reads native issue `type`, resolves the org `Priority` issue field
  (`issue_field_values`), computes a relative date, and builds the auto branch name (see below).
  `PRIORITY_ORDER` (Low/Medium/High/Urgent, project-specific) is the single source of truth for priority
  ranking.
- `GithubIssueList` (new, `RefCounted`): 6-column `Tree` (number/title/date/type/priority/labels),
  header-click sort (ascending/descending, empty values always last), selection survives sort/refresh/filter.
  Replaces the old scrolling `IssueCard` list.
- `IssueDetail` (new sub-scene): full metadata header (author, date, type, priority, colored label pills via
  inline `[bgcolor]` BBCode), Markdown body in a read-only `CodeEdit`, Open in Browser. Replaces
  `issue_card.tscn`/`.gd` (removed).
- `GithubIssueFilter` (new, `RefCounted`): Type/Priority/Label `OptionButton`s, options built from the fetched
  data (no hardcoded vocabulary), client-side AND filter — instant, no extra requests.

feat: Create branch from an issue

- Auto-generated branch name: `<type-prefix><number>-<title-slug>` (`feature/`, `bugfix/`, `task/` per issue
  type, no prefix if unset/unknown), editable before creating.
- Base-branch picker (`OptionButton`, local branches only, defaults to the current branch);
  `GitEngine.create_branch()` gains an optional `base` parameter (`switch -c <name> [<base>]`), existing
  single-argument callers unaffected.
- Confirmation dialog before creating a branch with a dirty working tree (uncommitted changes move with the
  branch).

feat: Paginated issue fetch

- `GithubApi.fetch_issues()` now pages (`ISSUES_PER_PAGE = 50`); `github_panel.gd` chains requests
  automatically up to `MAX_ISSUE_PAGES = 8` (400 issues), stopping at the first short page. Bounded scope by
  design (solo/small-team repos) rather than a full paged UI.
<hr>

## v0.11.0
feat: Restore file to an older commit's version - fix: editor-refresh reliability - hardening v0.11.0

feat: Restore file (commit-mode diff panel)

- `Command.RESTORE_FILE` / `WRITE_COMMANDS` entry - `git restore --source=<hash> -- <path>`, same
  mutual-exclusion guard as other write commands.
- `GitotDiffPanel`: `%RestoreFileButton` (commit mode only) + `%RestoreConfirmDialog`, guarded against the
  no-file-changes merge-commit case; emits `restore_file_requested(commit_hash, path)`.
- `GitotCommitLogDiff` wires the request to `GitEngine.restore_file()`;
  `GitotResultRouter._handle_restore_result()` logs success/failure and emits `file_restored(path)`.
- `RESTORE_FILE` added to `gitot.gd`'s `STATUS_TRIGGERING_COMMANDS`.

fix: Editor-refresh reliability

- `GitotDock._notify_file_changed()` (new, shared): reloads an open scene tab (`reload_scene_from_path()`) or
  open script (`Script.reload()`) for one file changed on disk outside the editor. Replaces duplicated logic
  previously split between branch-switch and restore-file handling - branch switch now actually reloads open
  scripts' compiled class, which it never did before.
- `GitotResultRouter.branch_switched` renamed `head_moved` and now also fires on a successful pull (pull moves
  HEAD the same way switch does, so the existing `HEAD@{1}..HEAD` diff applies unchanged).
- Stash-pop success logs a blanket "close and reopen any open scripts/scenes" warning - no
  `HEAD@{1}..HEAD`-style diff exists for a pop, so the affected files aren't knowable.
- Toasts/log lines clarify the real fix for a stale open tab: an editor focus change (not closing/reopening
  the tab), which is Godot's own external-change check and the only thing that refreshes a tab's visible text.

fix: Hardening v0.11.0 - correctness, performance, type safety

- Diff viewer hunks are now collapsible via a fold gutter, with a button to fold/unfold all.
- Add a basic syntax highlighting for gdscript file to the Diff viewer.

Correctness:

- `needs_force_push()` no longer misreads `_execute_bounded()`'s collapsed exit code on the no-upstream case -
  first push on a brand-new branch no longer risks a false force-push read.
- Commit/Amend failures now log git's raw output (`GitotLogger.g(output[0])`) instead of failing silently.
- `_on_diff_full_result()` (working-tree diff, `gitot.gd`) now applies the same `MAX_DIFF_CHARS` cap as the
  commit-diff path - a huge working-tree diff can no longer stall the panel.
- Empty/missing remote no longer renders the status panel's repo label as `"/"` - shows blank instead.
- `_execute_bounded()`'s timeout branch now deletes its temp log file on kill, matching `_poll_process()` -
  was leaking a `user://gitot_sync_*.log` on every local query that hit `LOCAL_TIMEOUT_SEC` (stuck lock/gc).

Performance:

- Removed a redundant blocking `get_current_branch()` call from `GitotDock._ready()` - the async
  `list_branches()` result (already fetched on the line above) sets the same label with better data (adds
  Local/Remote scope); was stalling the main thread on every dock init and every hot-reload of Gitot's own
  scripts.
- `needs_force_push()` was called twice per push (dock, for dialog wording; orchestrator, for push args) -
  dock now computes it once and passes it to `GitSyncOrchestrator.start_push(tag_input, force)`.

Type safety:

- `GitSyncOrchestrator._on_command_completed()` / `_handle_tag_collision_result()`: `output: Array` ->
  `Array[String]`, matching `command_completed`'s signature and every other handler.
<hr>

## v0.10.0
feat & fix: amend & copy hash - hardening: result-routing architecture, correctness, type safety

feat: Amend last commit

- `Command.AMEND` / `WRITE_COMMANDS` entry - `commit --amend` (`--no-edit` if the message field is left
  blank), same mutual-exclusion guard as other write commands.
- `gitot_dock.gd`: `%AmendCheckbox` on the commit box, guarded by locally-tracked ahead-count/upstream state -
  amending a commit already on origin requires confirming `%AmendConfirmDialog` first.
- `GitEngine.needs_force_push()` - live check (`git merge-base --is-ancestor @{u} HEAD`, bounded sync call)
  run right before every push, instead of a cached flag - self-corrects for any cause of divergence (amend,
  rebase, reset, branch switch, terminal use), not just amend.
- `GitSyncOrchestrator.start_push()` - uses `needs_force_push()` to choose
  `push --force-with-lease -u origin HEAD` over a plain push.
- `gitot_dock.gd`: push confirmation is forced (regardless of the `confirm_push` setting) whenever the next
  push would be a force-push; both `%PushConfirmDialog` and `%AmendConfirmDialog` log on Cancel (`canceled`
  signal).
- `gitot.gd`: `AMEND` added to `STATUS_TRIGGERING_COMMANDS` so ahead/behind and history refresh the same as
  after a normal commit.

feat: Copy Commit Hash

- `GitotDiffPanel`: commit header now copies commit hash to clipboard on click, with a brief color-flash
  confirmation.

Refactor: Split GitotResultRouter out of gitot_dock.gd

- `gitot_dock.gd`'s `#region Status Result` (dispatcher + six domain handlers, ~150 lines) extracted to new
  `ui/gitot_result_router.gd`; dock now forwards results via `_result_router.route()`, except
  `LAST_COMMIT_MSG` which stays dock-side (push-flow specific).
- `_has_upstream` / `_ahead_count` (amend/push guard state) now owned by `GitotResultRouter`, exposed via
  `has_upstream()` / `ahead_count()`.
- New `branch_switched` signal replaces a direct dock-internal call, keeping the router UI-agnostic beyond its
  injected button/panel refs.

Correctness:

- `_handle_branch_result`'s `BRANCHES` case now gates on `exit_code == 0` before parsing output (was
  output-emptiness only).
- `_ready()` now logs an error if `MAX_READY_RETRIES` is exceeded instead of failing silently.

Type safety:

- `_handle_last_commit_message_result`'s `output: Array` -> `Array[String]` (matches every sibling handler).
- Two untyped `for` loops in `_notify_changed_files()` now typed (`relative_path: String`, `script: Script`).
<hr>

## v0.9.0
feat: Commit history inspection

- `Command.COMMIT_FILES` / `GitEngine.get_commit_files()` - `git show --name-status --format= --no-renames`
  (same `--no-renames` convention as `STATUS_ARGS`, so only A/M/D/T appear).
- `Command.DIFF_COMMIT` / `GitEngine.get_commit_file_diff()` - `git show -U3` for ONE file of a commit,
  reusing `GitDiffParser.parse_full()`. Files are diffed on demand, not per commit, so large commits stay
  cheap.
- `GitDiffParser.parse_name_status()` - `<letter>\t<path>` lines into `{status, path}` entries. The file list
  comes from `--name-status` because `parse_full()` cannot name deleted or binary files.
- `GitLogPanel.commit_selected(commit_hash)` - new signal; each history row now carries its hash as metadata.
  Forwarded upward by `GitotDock.commit_selected`.
- `GitotCommitFilesList` (new): status-colored `ItemList`, auto-selects the first file.
- `GitotDiffPanel`: body wrapped in an `HSplitContainer`; new `set_commit_mode()`, `show_commit_files()` and
  `commit_file_selected`. The refresh button is hidden in commit mode (a commit's diff never changes).
- `GitotCommitLogDiff` (new, `RefCounted`): serializes requests behind a latest-wins gate, since
  `command_completed` carries no request ID and worker threads can finish out of order. Truncates a single
  file diff at 200,000 characters.
- `gitot.gd`: wires history click → presenter → bottom panel; a gutter click cancels commit mode, and the
  working-tree diff result restores the normal layout.

feat: Reflog button

- `Command.REFLOG` / `GitEngine.get_reflog()` - `git reflog -n 20` via `run_fast` (read-only, not in
  `WRITE_COMMANDS`); limit held in `GitEngine.REFLOG_COUNT`.
- `GitotLogConsole`: title-bar Reflog button added via `add_title_bar_control()`, same pattern as the bulk
  stage/unstage buttons and the log count dropdown. `GitEngine` is now constructor-injected, and the
  constructor is `_init(git_engine, log_list, scroll, fold)`.
- `gitot_dock.gd`: `_handle_reflog_result()` prints the raw output through `GitotLogger.g()`, so it lands in
  both the Gitot console and the Godot Output panel; failure logs an error, with git's stderr included.

Also changed unstaged/staged color and icon to fit common git user habit! (Modified in orange and Untracked in
green)

<hr>

## v0.8.1
fix: Hardening v0.8.0. Performance, correctness, reliability, lifecycle, type safety

Performance:

- Settings reads (`GitotSettings.get_value`) now cached in memory instead of hitting disk on every hot-path
  call.
- Six previously-unbounded synchronous `OS.execute()` local queries (`get_current_branch()`,
  `get_remote_url()`, `get_changed_files_since_switch()`, etc.) now route through a shared
  `_execute_bounded()` helper capped at `LOCAL_TIMEOUT_SEC` instead of blocking the main thread indefinitely.
- Push's commit-message read and tag-collision resolution converted from sync to async
  (`request_last_commit_message()`, `check_tag_collision()` via `run_fast`).
- Branch dropdown now derives the current branch from the already-parsed branch list
  (`_get_current_branch_from_list()`) instead of an extra sync git call.

Correctness:

- `GitotDiffPanel` guards against a stale result: a diff response is only rendered if the script tab it was
  requested for is still the active one.
- `_handle_sync_result`'s FETCH and push/pull output reads now guard `output.is_empty()` before indexing
  `output[0]`, matching every other handler.

Reliability:

- `GitEngine.run_fast()` rejects a new write command while one is in flight (`_write_busy`), preventing
  overlapping git processes from tripping `index.lock`.

Lifecycle:

- Temp log files (`user://gitot_*.log`) are now tracked per-PID and cleaned up on both the timeout-kill path
  and `teardown()` — previously leaked on every forced-close during a network op.

Architecture:

- `command_completed`'s `output` parameter, and every handler receiving it, typed `Array[String]` instead of
  bare `Array`.
<hr>

## v0.8.0
feat: Bottom-dock full diff viewer

- `Command.DIFF_FULL` / `GitEngine.diff_full()` - `git diff -U3` against `HEAD`, separate from the gutter's
  `Command.DIFF` (`-U0`). Zero shared state with the shipped, hardened gutter (no regression risk).
- `GitDiffParser.parse_full()` - multi-file-ready hunk parser
  (`{file, hunks: [{old_start, new_start, lines}]}`), additive to the existing `-U0` parser.
- `GitotDiffGutter.hunk_clicked(file_path, line)` - new signal, emitted on gutter click
  (`set_gutter_clickable` was missing entirely before this - gutter had no click behavior).
- `GitotDiffPanel` (new bottom-dock panel): read-only `CodeEdit`, `@@` header per hunk (git's own line span,
  not the rendered line count), dedicated +/- sign gutter, zero-padded real source line numbers in their own
  gutter, per-line background color, file-path label, manual refresh button.
- `gitot.gd`: wires gutter click -> `diff_full()` -> parse -> panel render + jump-to-line. Guards against a
  stale diff result if the active script tab changes before the git process returns.
<hr>

## v0.7.2
fix: harden v0.7.1 - tag collision hardening & feedback for stale resources

Previous retry-on-null-engine fix has a real flaw, it retries unconditionally forever, with no cap. Under
normal conditions \_git_engine gets set within a frame or two and it's harmless. But there's a Godot editor
behavior I didn't account for: the editor can instantiate @tool scenes on its own, most commonly for
filesystem thumbnail/preview generation, completely outside the plugin's own add_control_to_dock() flow. An
instance created that way never gets set_git_engine() called on it at all, ever. With my fix, that orphaned
instance's \_ready() just calls \_ready.call_deferred() on itself, forever, one more queued call every frame,
with nothing ever stopping it. Fixed with a `MAX_READY_RETRIES: int = 30`

Correctness:

- Tag push no longer silently overwrites a same-named tag pointing at a different commit -
  `git_sync_orchestrator.gd` now compares the existing tag's commit against HEAD before reusing it; mismatches
  abort with a clear error instead of pushing.
- Fixed misleading "Push aborted" tag-collision error - the commit push already succeeded by that point;
  message now says so and tells the user to rename and push again to tag it.
- `Push` button is now disabled while a failed tag push is awaiting retry, forcing the dedicated Retry button
  as the single recovery path instead of two buttons silently resolving the same pending state differently.

Reliability:

- `GitEngine.get_changed_files_since_switch()` now distinguishes "nothing changed" from "couldn't determine
  what changed" (no reflog entry yet, or git failure) instead of returning the same empty result for both.
- Editor toast now warns when an open script changed on disk after a branch switch/pull (Godot has no API to
  reload or close a script tab, so this replaces silent staleness with a visible warning).
- Editor toast also warns when changed-file detection itself is unreliable, instead of doing nothing.
<hr>

## v0.7.1
fix: harden v0.7.0 - correctness, lifecycle, security, architecture.

- Add branch scope (local/remote) to the branch dropdown and status panel.

Correctness:

- Dedupe EXITCODE-marker stripping into `GitEngine._poll_process()` instead of duplicating it per-branch in
  the dock.
- Guard `output[0]` access with `is_empty()` in the dock's stash branch and the orchestrator's tag-exists
  branch (real crash risk on empty stdout).
- `fetch` now triggers `get_ahead_behind()` on success - sync status no longer goes stale until the next
  unrelated refresh.
- `GitEngine.pull()` wrapper (was calling `run_network()` directly from the dock, same layer violation already
  fixed for `fetch()`).
- Diff gutter now gates on `exit_code == 0` - a failed `git diff` no longer paints stale/garbage markers.
- Size-guard icon no longer overwrites the conflict icon/tooltip on a file that's both conflicted and
  oversized.
- Empty GitHub PAT can no longer silently overwrite an existing valid token on accidental dialog confirm.
- `GithubApi` now guards against overlapping in-flight requests instead of silently dropping the second call.
- Fixed dock `_ready()` firing before `GitEngine` injection completes (known Godot `@tool`-dock timing quirk),
  now retries via deferred call, guarded against double-init.

Security:

- `create_tag()` rejects shell-unsafe characters (`$`, `` ` ``, `;`, `&`) that are valid git ref characters
  but unsafe once interpolated into `push_tag()`'s shell string.

Lifecycle:

- `GitSyncOrchestrator.teardown()` - disconnects from `GitEngine.command_completed` on plugin exit (was
  relying on free-order luck).
- `GitotLogConsole` caps rendered lines to `GitotLogger.MAX_HISTORY` - was growing one `RichTextLabel` per
  line, unbounded, over a long editor session.
- Network log files disambiguated with a monotonic timestamp instead of just the command name - concurrent
  same-named ops (e.g. two fetches) no longer share/corrupt one log file.
- `GIT_TERMINAL_PROMPT` restored via `OS.unset_environment()` on `_exit_tree()`.

Architecture:

- Split `_on_status_result` (~120-line function) into a thin dispatcher plus six domain handlers.
- Replaced the `command_name: String` signal bus with a typed `GitEngine.Command` enum across `GitEngine`,
  `gitot.gd`, the dock, the orchestrator, the diff gutter, and the status tree - a mistyped/renamed command
  now fails to compile instead of silently mismatching at runtime.
- Consolidated duplicate origin/repo-URL parsing (status panel vs. GitHub panel) into one shared
  `GitEngine.parse_owner_repo()`.
- Removed dead code: `GithubApi.fetch_labels()` (zero callers).
- `GDScript` member ordering brought in line with the style guide across all touched files; repeated
  `EditorIcons` theme lookups extracted to a shared `_icon()` helper.
<hr>

## v0.7.0
feat: Remote Branch Management & Status Panel

- `GitEngine`: `fetch()` wrapper (`git fetch origin`, network op), `get_ahead_behind()`
  (`rev-list --left-right --count @{u}...HEAD`, fast/local), `track_remote_branch()`
  (`switch -c <name> --track origin/<name>`, reuses `"create_branch"` result path).
- Push fixed: `-u origin HEAD` instead of bare `push` - resolves first-push failure on branches with no
  upstream.
- `GitBranchParser`: switched from `%(refname:short)` to `%(refname)` to reliably detect and exclude the
  `origin/HEAD` symbolic-ref alias; added `is_remote` flag.
- `GitotBranchPanel`: filters remote entries that already have a matching local branch (avoids `main` +
  `origin/main` duplicate clutter); cloud vs. branch icon per entry.
- New `GitotStatusPanel` (`RefCounted`, constructor-injected `RichTextLabel`): owner/repo, branch name
  (truncated), branch scope, ahead/behind. Detached HEAD flagged in red.
- `fetch` on success triggers `list_branches()` refresh (new remote branches only become visible after a
  fetch).
<hr>

## v0.6.0
feat: Commit History.

- `GitEngine.get_log()`: `git log` wrapper, `\x1f`-delimited format (hash, author, relative date, short date,
  subject) — avoids delimiter collisions with commit message content.
- `GitLogParser`: static parse into `Array[Dictionary]`, mirrors `GitBranchParser` shape.
- `GitLogPanel`: `RefCounted`, constructor-injected `FoldableContainer` + `Tree` (matches
  `GitotBranchPanel`/`GitotTagPanel` pattern). Count-filter `OptionButton` created in code, injected into fold
  title bar via `add_title_bar_control()`.
- Relative date shown in list; exact short date (`YYYY-MM-DD HH:MM`) on hover tooltip.
- Wired into existing refresh triggers: `STATUS_TRIGGERING_COMMANDS` (commit/push/pull/switch) and manual
  `Refresh Status` fallback.

feat: Stash Quick-Actions

- `GitEngine.stash_push()` / `stash_pop()`: thin wrappers, same pattern as `create_tag`/`switch_branch`.
- `stash push` uses `-u` to include untracked files - matches solo-dev intent of "shelve all WIP", not just
  tracked changes.
- Fixed stash message: `"Gitot quick-stash"`.
- Wired into `STATUS_TRIGGERING_COMMANDS` - stash/pop trigger the same status refresh as stage/commit/switch.
- Pop conflicts are not treated as silent failure: exit code != 0 logs git's raw output and still refreshes
  status so conflicted files are visible immediately.
<hr>

## v0.5.0
feat: Branch Management (switch, create, live scene refresh).

- `GitEngine`: `list_branches()`, `switch_branch()`, `create_branch()`, `get_changed_files_since_switch()`,
  `get_current_branch()`.
- `GitBranchParser`: parses local branch list with current-branch flag.
- `GitotBranchPanel`: dropdown (switch) + create-branch dialog, wired into the existing dock UI (no new
  `.tscn`).
- Scene/resource refresh on switch: precise per-file `update_file()` + `reload_scene_from_path()` for open
  tabs, instead of a full `scan()` - avoids full-project `.import` error noise (read:
  [Limitation](#-known-limitations)).
- Success/error console feedback for switch/create, including resulting branch name.
- Guard against `git_engine` being unset on mid-session script hot-reload.

feat: Gitot Logger

- **`gitot_logger.gd`**: capped history (`MAX_HISTORY = 200`), decoupled push-listener
  (`set_listener`/`_on_log`).
- **`gitot_log_console.gd`** (new, `RefCounted`, constructor-injected - matches
  `GitotStatusTree`/`GitotTagPanel` pattern): backfills history on open, appends new lines at the bottom,
  auto-scrolls via `resized` signal, styled with Godot's own `output_source` console font at a smaller size.
- **`gitot_dock.gd`**: wires `GitotLogConsole.new(%LogList, %LogScroll)` in `_ready()`, tears it down
  properly.
<hr>

## v0.4.0
feat & fix: Tags Versioning, safeguard, cleanup gitot_dock.gd (SoC)...

- Cleaned `gitot_dock.gd`, split into `gitot_status_tree.gd` and `gitot_tag_panel.gd`.
- `GitEngine.create_tag()` / `push_tag()` primitives.
- Dock UI: tag versioning toggle, project-version/manual tag name, commit-message/manual tag message, dynamic
  version label with auto `v` prefix.
- Orchestration chain: chain in `git_sync_orchestrator.gd`: push → tag → push_tag, with per-step console
  feedback.
- Guards: empty tag name, empty tag message, empty commit message - all pre-push, no silent partial states.
- Retry button for failed `push_tag` command. (query directly `git log -1`).
- Self-heal on "tag already exists" (read: [Limitation](#-known-limitations)).
- `read_stderr=true` fix in `_execute_and_report` - makes stderr visible on _every_ `fast command` (status,
  diff, add, restore, commit too), not just tag, which is good for future error handling.
<hr>

## v0.3.0
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

## v0.2.0
feature: GitHub Issues Tracker Board.

- PAT storage (user://, plaintext, scoped-token documented as security boundary).
- Auth modal with retry-on-401 flow.
- HTTPRequest wrapper (github_api.gd), PR-excluded issue fetch.
- Auto-detected owner/repo via git remote parsing.
- Main-screen tab with issue cards, first-tab-open fetch.
- Clear Token button (panel toolbar) for explicit PAT lifecycle control.
<hr>

## v0.1.1
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

## v0.1.0
Initial MVP commit

- **Failsafe startup:** verifies `git` is available before initializing; disables cleanly with a clear error
  if not.
- **Async execution:** local commands (status, diff) run via `WorkerThreadPool`; network commands (push, pull)
  run via a monitored background process with a 30-second timeout guard, so a slow or stalled connection never
  freezes the editor.
- **Git dock:** Staged/Unstaged file trees parsed from `git status --porcelain=v2`, with double-click
  stage/unstage.
- **Commit & Sync:** stage/unstage, commit message input (multiline supported), and Commit / Push / Pull
  buttons (read: [Limitation](#-known-limitations)).
- **Color-only diff gutter:** modified and added lines are marked directly in the script editor's gutter,
  computed from `git diff -U0` against `HEAD`. Updates automatically on save (where Godot's save signal fires
  reliably) with a manual **Refresh Diff** fallback button.
- **Large-file guard:** blocks staging any file ≥50MB to prevent accidental repository bloat.
