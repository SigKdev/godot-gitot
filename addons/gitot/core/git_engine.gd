## git_engine.gd
## Core git operations for Gitot.
## Command API and signal. Process execution is delegated to GitRunner.
class_name GitEngine
extends RefCounted

## Emitted when a git command finishes.
## @param command: identifies which operation completed.
## @param exit_code: 0 on success.
## @param output: raw stdout lines.
## @param context: data captured by the wrapper at call time, e.g. {"branch": "x"}.
## Empty if the command needs none. It travels with its own call, so it can't be mixed up with another.
signal command_completed(
	command: Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
)

## Re-emitted from GitRunner: a write op started (true) / finished (false). Drives UI busy states.
signal write_busy_changed(busy: bool)

## Identifies which git operation a command_completed signal refers to.
## Enum key names double as display strings via Command.keys()[cmd].capitalize()
## (e.g. STASH_POP -> "Stash Pop") — keep key names matching that pattern.
enum Command {
	STATUS,
	DIFF,
	DIFF_FULL,
	COMMIT_FILES,
	DIFF_COMMIT,
	COMMIT,
	AMEND,
	STAGE,
	UNSTAGE,
	STASH,
	STASH_POP,
	STASH_LIST,
	STASH_DROP,
	FETCH,
	AHEAD_BEHIND,
	PUSH,
	PULL,
	BRANCHES,
	SWITCH,
	CREATE_BRANCH,
	DELETE_BRANCH,
	DELETE_REMOTE_BRANCH,
	LOG,
	TAG,
	TAG_COLLISION_CHECK,
	PUSH_TAG,
	LAST_COMMIT_MSG,
	REFLOG,
	RESTORE_FILE,
	LFS_VERSION,
	LFS_STATE,
	LFS_LS_FILES,
	LFS_TRACK,
	LFS_UNTRACK,
	LFS_INSTALL,
	LFS_PULL,
	LFS_PRUNE,
	COUNT_OBJECTS,
}

## Canonical status args. --untracked-files=all forces recursion into
## untracked directories instead of collapsing them to one folder entry.
const STATUS_ARGS: PackedStringArray = [
	"status",
	"--porcelain=v2",
	"--untracked-files=all",
	"--no-renames",
]

## Unit separator (0x1F) — safe delimiter unlikely to appear in git log fields.
const UNIT_SEP: String = char(0x1F)

## Format string for `git log`: hash, author, relative date, subject - separated
## by Unit Separator since commit subjects can contain any printable char.
## GDScript doesn't support \x escapes - only \uXXXX (4-digit unicode)
# const LOG_FORMAT: String = "--pretty=format:%h\u001f%an\u001f%ar\u001f%ad\u001f%s"
const LOG_FORMAT: String = "--pretty=format:%h" + UNIT_SEP + "%an" + UNIT_SEP + "%ar" + UNIT_SEP + "%ad" + UNIT_SEP + "%s"

## Format string for `git stash list`: selector, full hash (stable preview key),
## relative date, absolute date (tooltip), subject. Unit Separator-delimited like LOG_FORMAT.
const STASH_LIST_FORMAT: String = "--format=%gd" + UNIT_SEP + "%H" + UNIT_SEP + "%cr" + UNIT_SEP + "%ci" + UNIT_SEP + "%s"

## Format string for `git branch -a`: refname, HEAD marker, upstream, trackshort, track,
## commit date (unix = sort key, relative = display, exact = tooltip), short hash, subject.
## Unit Separator-delimited like LOG_FORMAT - "|" is a valid ref-name character.
## Column order must match GitBranchParser.Field.
const BRANCH_LIST_FORMAT: String = (
	"--format=%(refname)" + UNIT_SEP + "%(HEAD)" + UNIT_SEP + "%(upstream:short)" + UNIT_SEP
	+ "%(upstream:trackshort)" + UNIT_SEP + "%(upstream:track)" + UNIT_SEP + "%(committerdate:unix)"
	+ UNIT_SEP + "%(committerdate:relative)" + UNIT_SEP + "%(committerdate:format:%Y-%m-%d %H:%M)"
	+ UNIT_SEP + "%(objectname:short)" + UNIT_SEP + "%(subject)"
)

## Branch names this plugin may send to origin (strict subset of git's rules, see delete_remote_branch()):
## starts with a letter/digit, then letters, digits and . _ / - only. Also excludes every shell metacharacter.
const SAFE_BRANCH_PATTERN: String = "^[A-Za-z0-9][A-Za-z0-9._/-]*$"

## Git ref-name rules that make a tag name invalid (see `git check-ref-format`):
## whitespace/control chars and ~ ^ : ? * [ \ | ".." | "@{" | lone "@" | leading "-" or "/"
## | trailing "/" or "." | "//" | ".lock" component | component starting with ".".
const INVALID_TAG_PATTERN: String = r"[\x00-\x20\x7f~^:?*\[\\]|\.\.|@\{|^@$|^[-/]|[/.]$|//|\.lock(/|$)|(^|/)\."

## Commands that mutate the index, working tree, or refs. Only these need
## mutual exclusion — read-only commands (STATUS, LOG, DIFF, BRANCHES, ...)
## are safe to run concurrently with each other on WorkerThreadPool.
const WRITE_COMMANDS: Array[Command] = [
	Command.COMMIT,
	Command.AMEND,
	Command.STAGE,
	Command.UNSTAGE,
	Command.STASH,
	Command.STASH_POP,
	Command.STASH_DROP,
	Command.SWITCH,
	Command.CREATE_BRANCH,
	Command.DELETE_BRANCH,
	Command.TAG,
	Command.RESTORE_FILE,
	Command.LFS_TRACK,
	Command.LFS_UNTRACK,
	Command.LFS_INSTALL,
	Command.LFS_PRUNE,
]

## Max reflog entries shown by the console's Reflog button.
const REFLOG_COUNT: int = 20

## Process execution layer (threads, timeouts, write lock). See GitRunner.
var _runner: GitRunner = GitRunner.new()


func _init() -> void:
	_runner.write_busy_changed.connect(write_busy_changed.emit)


#region check version
## Checks if 'git' is callable from the OS PATH.
static func is_git_available() -> bool:
	return not get_git_version().is_empty()


## "2.45.0.windows.1" from "git version 2.45.0.windows.1"; "" if git is missing.
static func get_git_version() -> String:
	return _first_line(["--version"]).trim_prefix("git version ")


## "3.5.1" from "git-lfs/3.5.1 (GitHub; ...)"; "" if git-lfs is not installed.
static func get_lfs_version() -> String:
	return _first_line(["lfs", "version"]).get_slice(" ", 0).trim_prefix("git-lfs/")
#endregion


## Splits a git remote URL (SSH or HTTPS form) into owner and repo name.
## @return: {"owner": String, "repo": String}, or {} if the URL has fewer than 2 path segments.
static func parse_owner_repo(url: String) -> Dictionary:
	var cleaned: String = url.trim_suffix(".git")
	var parts: PackedStringArray = cleaned.split("/")
	if parts.size() < 2:
		return { }
	return { "owner": parts[-2].split(":")[-1], "repo": parts[-1] }


## True if git would accept tag_name. Checked BEFORE the push so a bad name can't leave
## a pushed commit without its tag.
static func is_valid_tag_name(tag_name: String) -> bool:
	return not tag_name.is_empty() and RegEx.create_from_string(INVALID_TAG_PATTERN).search(
			tag_name
		) == null


## Runs `git <args>` synchronously (startup checks only) and returns the first stdout line.
## stderr is merged (read_stderr=true) so a missing `git lfs` stays silent in the editor console.
## @return: "" on a non-zero exit code or empty output.
static func _first_line(args: PackedStringArray) -> String:
	var output: Array[String] = []
	if OS.execute("git", args, output, true) != 0 or output.is_empty():
		return ""
	return output[0].get_slice("\n", 0).strip_edges()


## Turns an GitRunner.execute_bounded() name-list result into {"reliable": bool, "files": PackedStringArray}.
## reliable=false means git failed - NOT "nothing changed".
static func _to_file_list(result: Array) -> Dictionary:
	if result[0] != 0:
		return { "reliable": false, "files": PackedStringArray() }
	var stdout: String = String(result[1]).strip_edges()
	var files: PackedStringArray = PackedStringArray()
	for line: String in stdout.split("\n", false): # Empty stdout -> no lines.
		files.append(GitPath.unquote(line))
	return { "reliable": true, "files": files }


## Runs a fast, local git command (read or write) off the main thread.
## Use for: status, diff, add, restore, commit. [b]NOT for push/pull[/b] [i](see run_network)[/i].
## @param context: optional per-call data, returned unchanged in command_completed
func run_fast(command: Command, args: PackedStringArray, context: Dictionary = { }) -> void:
	_runner.run_fast(
		Command.keys()[command],
		args,
		command in WRITE_COMMANDS,
		_relay.bind(command, context),
	)


## Runs a network git command (push/pull) with a kill-on-timeout guard.
## Output is captured via shell redirection to a temp file, since
## OS.create_process() alone does not expose stdout/stderr.
## @param command: identifies the operation (e.g. Command.PUSH).
## @param args: git subcommand arguments (e.g. ["push", "origin", "main"]). Every argument must pass
## GitRunner.is_shell_safe(), otherwise nothing runs and the command completes with exit code -1.
## @param context: optional per-call data, returned unchanged in command_completed.
func run_network(command: Command, args: PackedStringArray, context: Dictionary = { }) -> void:
	_runner.run_network(Command.keys()[command], args, _relay.bind(command, context))


## Returns the "origin" remote URL, or an empty string on failure.
func get_remote_url() -> String:
	var result: Array = _runner.execute_bounded(["remote", "get-url", "origin"])
	if result[0] != 0:
		return ""
	return String(result[1]).strip_edges()


## Requests HEAD's full commit message (subject + body), for tag-message prefill.
## Async — result arrives via command_completed(Command.LAST_COMMIT_MSG, ...).
func request_last_commit_message() -> void:
	run_fast(Command.LAST_COMMIT_MSG, ["log", "-1", "--pretty=%B"])


## Lists the last `count` commits on the current branch. Fast/local op.
## Result output[0] is fed to GitLogParser.parse().
## @param count: max number of commits to fetch (dropdown-controlled: 10/20/30).
func get_log(count: int) -> void:
	run_fast(Command.LOG, ["log", "-n", str(count), LOG_FORMAT, "--date=format:%Y-%m-%d %H:%M"])


## Requests the repository's object-store size (`git count-objects -vH`, human-readable units).
## Read-only/local. Result arrives via command_completed(COUNT_OBJECTS, ...).
func get_repo_size() -> void:
	run_fast(Command.COUNT_OBJECTS, ["count-objects", "-vH"])


## Requests the most recent reflog entries. Read-only/local, so it runs via run_fast
## and is not in WRITE_COMMANDS. Result arrives via command_completed(REFLOG, ...).
func get_reflog() -> void:
	run_fast(Command.REFLOG, ["reflog", "-n", str(REFLOG_COUNT)])


## Returns files changed by the most recent `switch`/`create_branch` (reflog diff).
## Used to call EditorFileSystem.update_file() precisely instead of a full scan().
## @return: {"reliable": bool, "files": PackedStringArray}. reliable=false means
## HEAD@{1} doesn't exist yet (first switch) or git failed — NOT "nothing changed".
func get_changed_files_since_switch() -> Dictionary:
	return _to_file_list(_runner.execute_bounded(["diff", "--name-only", "HEAD@{1}", "HEAD"]))


#region Branches
## Lists branches. Fast/local op — routes through run_fast.
## Result output[0] is fed to GitBranchParser.parse().
func list_branches() -> void:
	run_fast(Command.BRANCHES, ["branch", "-a", BRANCH_LIST_FORMAT])


## Switches to an existing local branch. Uncommitted changes that don't
## conflict with the target branch's content silently follow the user —
## caller MUST trigger a status refresh + filesystem scan regardless of
## exit_code (see gitot.gd STATUS_TRIGGERING_COMMANDS).
## @param branch_name: existing local branch name.
func switch_branch(branch_name: String) -> void:
	run_fast(Command.SWITCH, ["switch", branch_name], { "branch": branch_name })


## Creates a new local branch and switches to it in one atomic op.
## @param branch_name: new branch name (git ref-name rules enforced by git itself).
## @param base: existing local branch to start from; empty = current HEAD (today's behavior).
func create_branch(branch_name: String, base: String = "") -> void:
	var args: PackedStringArray = ["switch", "-c", branch_name]
	if not base.is_empty():
		args.append(base)
	run_fast(Command.CREATE_BRANCH, args, { "branch": branch_name })


## Creates a local branch tracking a remote-only branch and switches to it.
## @param remote_name: full remote ref, e.g. "origin/feature-x".
func track_remote_branch(remote_name: String) -> void:
	var local_name: String = remote_name.trim_prefix("origin/")
	run_fast(
		Command.CREATE_BRANCH,
		["switch", "-c", local_name, "--track", remote_name],
		{ "branch": local_name },
	)


## Deletes a local branch, safe mode only: `-d` makes git refuse unmerged branches
## (merged into its upstream, or into HEAD when it has none). Caller must confirm first.
## Git's output contains the old tip SHA (recoverable via `git branch <name> <sha>`).
## @param branch_name: existing local branch, not the checked-out one (git refuses that too).
## @param on_remote: a copy exists on origin; only travels in the context so the result can remind the user.
func delete_branch(branch_name: String, on_remote: bool = false) -> void:
	run_fast(
		Command.DELETE_BRANCH,
		["branch", "-d", branch_name],
		{ "branch": branch_name, "on_remote": on_remote },
	)


## True if name is a branch name this plugin will send to origin (see SAFE_BRANCH_PATTERN).
static func is_safe_branch_name(branch_name: String) -> bool:
	return RegEx.create_from_string(SAFE_BRANCH_PATTERN).search(branch_name) != null


## Deletes a branch on origin: `git push origin --delete refs/heads/<name>`. Network op, caller
## must confirm first. Safe by construction: only the named ref is touched, never a force push,
## "refs/heads/" avoids a tag of the same name being hit, and the name must pass is_safe_branch_name()
## (it ends up in a shell string). The server may still refuse (default/protected branch): its message
## is shown. Restore after a mistake: `git push origin <old tip sha>:refs/heads/<name>` (caller logs the sha).
## Completes with exit code -1 and no git call when the name is unsafe.
## @param branch_name: name WITHOUT the "origin/" prefix.
func delete_remote_branch(branch_name: String) -> void:
	var context: Dictionary = { "branch": branch_name }
	if not is_safe_branch_name(branch_name):
		var failure: Array[String] = [
			"Branch name '%s' has unsupported characters: delete it from a terminal or on GitHub." % branch_name,
		]
		_relay.call_deferred(-1, failure, Command.DELETE_REMOTE_BRANCH, context)
		return
	run_network(
		Command.DELETE_REMOTE_BRANCH,
		["push", "origin", "--delete", "refs/heads/" + branch_name],
		context,
	)

#endregion


## Checks whether tag_name already points at HEAD, to resolve a failed create_tag().
## "~0" peels an annotated tag to its commit (plain rev-parse gives the tag object's SHA, never == HEAD).
## Exit != 0 means the tag doesn't exist, so create_tag failed for another reason.
## @param create_error: git's output from the failed create_tag, returned in the context.
func check_tag_collision(tag_name: String, create_error: String = "") -> void:
	run_fast(
		Command.TAG_COLLISION_CHECK,
		["rev-parse", tag_name + "~0", "HEAD"],
		{ "error": create_error },
	)


#region Stash
## Lists all stash entries (no cap: terminal-made ones must stay droppable).
## Read-only -> not in WRITE_COMMANDS. Result output[0] is fed to GitStashParser.parse().
func list_stashes() -> void:
	run_fast(Command.STASH_LIST, ["stash", "list", STASH_LIST_FORMAT])


## Stashes staged + unstaged + untracked changes, resetting the working tree to HEAD.
## @param message: optional name. Empty -> no -m, git's default "WIP on <branch>: ..." subject.
## Passed via args array (no shell), so no escaping is needed.
func stash_push(message: String = "") -> void:
	var args: PackedStringArray = ["stash", "push", "-u"]
	var clean: String = message.strip_edges()
	if not clean.is_empty():
		args.append_array(["-m", clean])
	run_fast(Command.STASH, args)


## Reapplies stash entry `index` and removes it from the stack.
## On conflict, git writes conflict markers and keeps the entry.
## The touched-file list is gathered first so the dock can refresh precisely afterwards.
func stash_pop(index: int = 0) -> void:
	assert(index >= 0, "GitEngine.stash_pop: negative index")
	var ref: String = "stash@{%d}" % index # int-built only; and no '^' (cmd.exe escape char).
	# context = {"reliable", "files"} (see _to_file_list), gathered BEFORE the pop since the entry
	# is gone afterwards. Skipped while a write is in flight: run_fast() would drop this pop anyway,
	# so don't block up to LOCAL_TIMEOUT_SEC on a git call for nothing.
	var context: Dictionary = { }
	if not _runner.is_write_busy():
		# --include-untracked (Git >= 2.32) lists stash -u files; --no-renames = D + A.
		context = _to_file_list(
			_runner.execute_bounded(
				["stash", "show", "--name-only", "--include-untracked", "--no-renames", ref]
			)
		)
	run_fast(Command.STASH_POP, ["stash", "pop", ref], context)


## Permanently removes stash entry `index`. Destructive - caller must confirm first.
## Git's output contains the dropped SHA (recoverable via `git stash store`).
func stash_drop(index: int) -> void:
	assert(index >= 0, "GitEngine.stash_drop: negative index")
	run_fast(Command.STASH_DROP, ["stash", "drop", "stash@{%d}" % index])
#endregion


## Fetches updates from origin without touching the working tree. Network op.
func fetch() -> void:
	run_network(Command.FETCH, ["fetch", "origin"])


## Pulls changes from the remote tracking branch into the current branch. Network op.
func pull() -> void:
	run_network(Command.PULL, ["pull"])


## Compares local HEAD against its upstream. Fast/local op (reads refs only,
## no network) — safe to call after every status-triggering command.
## Output "behind\tahead" fed to caller; empty output/failure means no
## upstream is set (e.g. brand-new unpushed branch) — caller must handle that.
func get_ahead_behind() -> void:
	run_fast(Command.AHEAD_BEHIND, ["rev-list", "--left-right", "--count", "@{u}...HEAD"])


## Runs a full-context diff (-U3) for the bottom-dock diff viewer.
## Separate from the gutter's -U0 Command.DIFF — different consumer, different parser.
## @param path: absolute path to the file (globalized, matches gutter's convention).
func diff_full(path: String) -> void:
	run_fast(Command.DIFF_FULL, ["diff", "-U3", "--no-ext-diff", "HEAD", "--", path])


## Lists files changed by one commit ("<letter>\t<path>" per line). Async.
## --format= drops the commit header; --no-renames matches STATUS_ARGS (renames = D + A).
## @param hash: commit hash (abbreviated is fine).
func get_commit_files(commit_hash: String) -> void:
	run_fast(
		Command.COMMIT_FILES,
		["show", "--name-status", "--format=", "--no-renames", commit_hash],
	)


## Runs a full-context diff (-U3) of ONE file inside a commit, like `git show`.
## Output is fed to GitDiffParser.parse_full() (same consumer as DIFF_FULL).
## @param path: repo-relative path, as returned by get_commit_files().
func get_commit_file_diff(commit_hash: String, path: String) -> void:
	run_fast(
		Command.DIFF_COMMIT,
		["show", "-U3", "--no-ext-diff", "--no-renames", "--format=", commit_hash, "--", path],
	)


## Restores one file's working-tree content to its state at commit_hash.
## Destructive: overwrites any uncommitted changes to that file — caller must confirm first.
## @param commit_hash: commit to restore the file's content from.
## @param path: repo-relative path, as returned by get_commit_files().
func restore_file(commit_hash: String, path: String) -> void:
	run_fast(
		Command.RESTORE_FILE,
		["restore", "--source=" + commit_hash, "--", path],
		{ "path": path },
	)


## Creates an annotated tag on HEAD. Local/fast op, no network involved.
## @param tag_name: tag identifier (e.g. "v0.3.0"). Rejects shell-unsafe characters
## (GitRunner.is_shell_safe) even though git's own ref-name rules allow them — see push_tag().
## @param message: annotation message (commit message or custom, from caller).
func create_tag(tag_name: String, message: String) -> void:
	if not GitRunner.is_shell_safe(tag_name):
		# Typed var required: _relay() takes Array[String], an untyped literal would be rejected.
		var failure: Array[String] = [
			"Tag name '%s' has unsupported characters. Use letters, digits and . _ - / + @ : only." % tag_name,
		]
		_relay.call_deferred(-1, failure, Command.TAG, { })
		return
	run_fast(Command.TAG, ["tag", "-a", tag_name, "-m", message])


## Pushes a tag to origin. Network op — reuses run_network's kill-on-timeout guard.
## SECURITY: tag_name is interpolated into a shell string (see run_network), which refuses
## anything outside GitRunner.SHELL_SAFE_PATTERN; create_tag() applies the same rule up front so a
## tag is never created that cannot be pushed.
## @param tag_name: tag identifier to push (already validated by create_tag).
func push_tag(tag_name: String) -> void:
	run_network(Command.PUSH_TAG, ["push", "origin", tag_name])


## Kills any push/pull processes still running. Called by gitot.gd on exit.
func teardown() -> void:
	_runner.teardown()


## Runner callback → public signal. bind() appends `command` and `context` after (exit_code, output).
func _relay(exit_code: int, output: Array[String], command: Command, context: Dictionary) -> void:
	command_completed.emit(command, exit_code, output, context)
