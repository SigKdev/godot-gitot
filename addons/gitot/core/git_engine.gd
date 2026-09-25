## git_engine.gd
## Core git operations for Gitot.
## All CLI calls are executed via OS.execute() and routed through this class.
## Uses WorkerThreadPool for non-blocking execution.
class_name GitEngine
extends RefCounted

## Emitted when a git command finishes.
## @param command: identifies which operation completed.
## @param exit_code: 0 on success.
## @param output: raw stdout lines.
signal command_completed(command: Command, exit_code: int, output: Array[String])

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
	STAGE,
	UNSTAGE,
	STASH,
	STASH_POP,
	FETCH,
	AHEAD_BEHIND,
	PUSH,
	PULL,
	BRANCHES,
	SWITCH,
	CREATE_BRANCH,
	LOG,
	TAG,
	TAG_COLLISION_CHECK,
	PUSH_TAG,
	LAST_COMMIT_MSG,
	REFLOG,
}

## Canonical status args. --untracked-files=all forces recursion into
## untracked directories instead of collapsing them to one folder entry.
const STATUS_ARGS: PackedStringArray = [
	"status",
	"--porcelain=v2",
	"--untracked-files=all",
	"--no-renames",
]

## Format string for `git log`: hash, author, relative date, subject - separated
## by \x1f (Unit Separator) since commit subjects can contain any printable char.
## GDScript doesn't support \x escapes - only \uXXXX (4-digit unicode)
## Consumed by GitLogParser.parse().
const LOG_FORMAT: String = "--pretty=format:%h\u001f%an\u001f%ar\u001f%ad\u001f%s"

## Shell metacharacters valid in git ref names but unsafe once interpolated into
## the shell string run_network() builds (see push_tag()). Rejected in create_tag()
## since it gates every path that can lead there.
const UNSAFE_TAG_CHARS: String = "$`;&"

## Timeout for network operations (push/pull), in seconds.
const NETWORK_TIMEOUT_SEC: float = 30.0

## Timeout for the bounded local reads below (get_remote_url, get_current_branch, etc.) —
## short, since these are cheap plumbing commands; a hang past this means a stuck
## lock/gc, not normal latency. Distinct from NETWORK_TIMEOUT_SEC (push/pull).
const LOCAL_TIMEOUT_SEC: float = 5.0

## Commands that mutate the index, working tree, or refs. Only these need
## mutual exclusion — read-only commands (STATUS, LOG, DIFF, BRANCHES, ...)
## are safe to run concurrently with each other on WorkerThreadPool.
const WRITE_COMMANDS: Array[Command] = [
	Command.COMMIT,
	Command.STAGE,
	Command.UNSTAGE,
	Command.STASH,
	Command.STASH_POP,
	Command.SWITCH,
	Command.CREATE_BRANCH,
	Command.TAG,
]

## Max reflog entries shown by the console's Reflog button.
const REFLOG_COUNT: int = 20

## PID → temp log path of currently running network operations (push/pull).
## Tracks both so a mid-operation kill (timeout or teardown) can also remove
## the orphaned log file, not just stop the process.
var _active_pids: Dictionary[int, String] = { }

## True while a WRITE_COMMANDS op is executing. Blocks any other run_fast()
## call (write or read) from racing it on index.lock; reads never block
## each other, and never block while no write is in flight.
var _write_busy: bool = false

## Branch name targeted by the most recent switch/create_branch call, for
## the dock's success log — avoids a redundant git call to re-derive it.
var _last_switch_target: String = ""


## Checks if 'git' is callable from the OS PATH.
static func is_git_available() -> bool:
	var output: Array[String] = []
	return OS.execute("git", ["--version"], output) == 0


## Splits a git remote URL (SSH or HTTPS form) into owner and repo name.
## @return: {"owner": String, "repo": String}, or {} if the URL has fewer than 2 path segments.
static func parse_owner_repo(url: String) -> Dictionary:
	var cleaned: String = url.trim_suffix(".git")
	var parts: PackedStringArray = cleaned.split("/")
	if parts.size() < 2:
		return { }
	return { "owner": parts[-2].split(":")[-1], "repo": parts[-1] }


## Returns the absolute path to the project root, used to anchor every
## git call so it always targets this repo regardless of editor CWD.
static func _project_root() -> String:
	return ProjectSettings.globalize_path("res://")


## Builds the shell + args that redirect a git call's stdout/stderr to log_path and
## append a trailing exit-status marker. Shared by run_network() (async, timeout-killed)
## and _execute_bounded() (sync, timeout-killed) — single source for this shell contract.
## SECURITY: only ever receives static, hardcoded args (see run_network()).
static func _shell_invocation(args: PackedStringArray, log_path: String) -> Array:
	var git_cmd: String = (
		"git -C \"%s\" %s > \"%s\" 2>&1 && echo EXITCODE:0 >> \"%s\" || echo EXITCODE:1 >> \"%s\""
		% [_project_root(), " ".join(args), log_path, log_path, log_path]
	)
	var shell: String = "cmd" if OS.get_name() == "Windows" else "sh"
	var shell_args: PackedStringArray = (
		["/C", git_cmd] if OS.get_name() == "Windows" else ["-c", git_cmd]
	)
	return [shell, shell_args]


## Runs a fast, local git command (read or write) off the main thread.
## Use for: status, diff, add, restore, commit. [b]NOT for push/pull[/b] [i](see run_network)[/i].
func run_fast(command: Command, args: PackedStringArray) -> void:
	if _write_busy:
		GitotLogger.w("Git write in progress - ignoring %s." % Command.keys()[command])
		return
	if command in WRITE_COMMANDS:
		_write_busy = true
	WorkerThreadPool.add_task(_execute_and_report.bind(command, args))


## Runs a network git command (push/pull) with a kill-on-timeout guard.
## Output is captured via shell redirection to a temp file, since
## OS.create_process() alone does not expose stdout/stderr.
## @param command: identifies the operation (e.g. Command.PUSH).
## @param args: git subcommand arguments (e.g. ["push", "origin", "main"]).
func run_network(command: Command, args: PackedStringArray) -> void:
	# Time.get_ticks_usec() disambiguates concurrent same-named ops (e.g. two
	# fetches in flight); the real PID isn't known until after
	# OS.create_process() returns, too late to embed in this path.
	var log_path: String = "user://gitot_%s_%d.log" % [
		Command.keys()[command],
		Time.get_ticks_usec(),
	]
	var abs_log_path: String = ProjectSettings.globalize_path(log_path)

	# SECURITY: this shell string only ever receives static, hardcoded args
	# (push/pull with no user-supplied values). Never interpolate user input
	# (branch names, messages, paths) into this string without escaping.
	var shell_invocation: Array = _shell_invocation(args, abs_log_path)

	# Create the process and store the PID.
	var pid: int = OS.create_process(shell_invocation[0], shell_invocation[1])
	if pid == -1:
		call_deferred("emit_signal", "command_completed", command, -1, ["Failed to start process."])
		return

	_active_pids[pid] = abs_log_path
	# Poll the process for completion.
	_poll_process.call_deferred(pid, command, abs_log_path, Time.get_ticks_msec())


## Returns the "origin" remote URL, or an empty string on failure.
func get_remote_url() -> String:
	var result: Array = _execute_bounded(["remote", "get-url", "origin"])
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


## Requests the most recent reflog entries. Read-only/local, so it runs via run_fast
## and is not in WRITE_COMMANDS. Result arrives via command_completed(REFLOG, ...).
func get_reflog() -> void:
	run_fast(Command.REFLOG, ["reflog", "-n", str(REFLOG_COUNT)])


## Returns files changed by the most recent `switch`/`create_branch` (reflog diff).
## Used to call EditorFileSystem.update_file() precisely instead of a full scan().
## @return: {"reliable": bool, "files": PackedStringArray}. reliable=false means
## HEAD@{1} doesn't exist yet (first switch) or git failed — NOT "nothing changed".
func get_changed_files_since_switch() -> Dictionary:
	var result: Array = _execute_bounded(["diff", "--name-only", "HEAD@{1}", "HEAD"])
	if result[0] != 0:
		return { "reliable": false, "files": PackedStringArray() }
	var stdout: String = String(result[1]).strip_edges()
	if stdout.is_empty():
		return { "reliable": true, "files": PackedStringArray() }
	return { "reliable": true, "files": PackedStringArray(stdout.split("\n", false)) }


#region Branches
## Lists branches. Fast/local op — routes through run_fast.
## Result output[0] is fed to GitBranchParser.parse().
func list_branches() -> void:
	run_fast(Command.BRANCHES, ["branch", "-a", "--format=%(refname)|%(HEAD)"])


## Switches to an existing local branch. Uncommitted changes that don't
## conflict with the target branch's content silently follow the user —
## caller MUST trigger a status refresh + filesystem scan regardless of
## exit_code (see gitot.gd STATUS_TRIGGERING_COMMANDS).
## @param branch_name: existing local branch name.
func switch_branch(branch_name: String) -> void:
	_last_switch_target = branch_name
	run_fast(Command.SWITCH, ["switch", branch_name])


## Creates a new local branch and switches to it in one atomic op.
## @param branch_name: new branch name (git ref-name rules enforced by git itself).
func create_branch(branch_name: String) -> void:
	_last_switch_target = branch_name
	run_fast(Command.CREATE_BRANCH, ["switch", "-c", branch_name])


## Creates a local branch tracking a remote-only branch and switches to it.
## @param remote_name: full remote ref, e.g. "origin/feature-x".
func track_remote_branch(remote_name: String) -> void:
	var local_name: String = remote_name.trim_prefix("origin/")
	_last_switch_target = local_name
	run_fast(Command.CREATE_BRANCH, ["switch", "-c", local_name, "--track", remote_name])


## Returns the current branch name, or empty string on failure (e.g. detached HEAD).
func get_current_branch() -> String:
	var result: Array = _execute_bounded(["branch", "--show-current"])
	if result[0] != 0:
		return ""
	return String(result[1]).strip_edges()


## Branch name targeted by the last switch/create_branch call — see _last_switch_target.
func get_last_switch_target() -> String:
	return _last_switch_target
#endregion


## Checks whether tag_name already points at HEAD, to resolve a "tag already
## exists" collision. One rev-parse call for both SHAs (one per output line)
## instead of two round trips. Result via command_completed(TAG_COLLISION_CHECK, ...).
## @param tag_name: existing local tag to compare against HEAD.
func check_tag_collision(tag_name: String) -> void:
	run_fast(Command.TAG_COLLISION_CHECK, ["rev-parse", tag_name, "HEAD"])


## Stashes all uncommitted changes (staged + unstaged), resetting the working tree to HEAD.
func stash_push() -> void:
	run_fast(Command.STASH, ["stash", "push", "-u", "-m", "Gitot quick-stash"])


## Reapplies the most recent stash entry and removes it from the stack.
## On conflict, git writes conflict markers to files and preserves the stash entry.
func stash_pop() -> void:
	run_fast(Command.STASH_POP, ["stash", "pop"])


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


## Creates an annotated tag on HEAD. Local/fast op, no network involved.
## @param tag_name: tag identifier (e.g. "v0.3.0"). Rejects shell-unsafe characters
## ($, `, ;, &) even though git's own ref-name rules allow them — see push_tag().
## @param message: annotation message (commit message or custom, from caller).
func create_tag(tag_name: String, message: String) -> void:
	for c in UNSAFE_TAG_CHARS:
		if tag_name.contains(c):
			call_deferred(
				"emit_signal",
				"command_completed",
				Command.TAG,
				-1,
				["Tag name contains unsafe character '%s'." % c],
			)
			return
	run_fast(Command.TAG, ["tag", "-a", tag_name, "-m", message])


## Pushes a tag to origin. Network op — reuses run_network's kill-on-timeout guard.
## SECURITY: tag_name is interpolated into a shell string (see run_network).
## Git's ref-name validation (enforced during create_tag) rejects most
## shell-breaking characters, but create_tag()'s UNSAFE_TAG_CHARS check is what
## actually closes the gap for the rest ($, `, ;, &).
## Only call this after create_tag() succeeded on the same tag_name,
## never with a raw, unvalidated user string.
## @param tag_name: tag identifier to push (already validated by create_tag).
func push_tag(tag_name: String) -> void:
	run_network(Command.PUSH_TAG, ["push", "origin", tag_name])


## Kills any push/pull processes still running. Called by gitot.gd on exit.
func teardown() -> void:
	for pid: int in _active_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
		var log_path: String = _active_pids[pid]
		if FileAccess.file_exists(log_path):
			DirAccess.remove_absolute(log_path)
	_active_pids.clear()


## Runs a local git query synchronously, capped at LOCAL_TIMEOUT_SEC — blocks the
## calling thread up to the cap, then kills the process. Only for the one-off reads
## below; hot UI paths use run_fast()/run_network() instead (never blocking).
## @return: [exit_code: int, output: String] — exit_code -1 on timeout/spawn failure.
func _execute_bounded(args: PackedStringArray) -> Array:
	var log_path: String = ProjectSettings.globalize_path(
		"user://gitot_sync_%d.log" % Time.get_ticks_usec()
	)
	var shell_invocation: Array = _shell_invocation(args, log_path)
	var pid: int = OS.create_process(shell_invocation[0], shell_invocation[1])
	if pid == -1:
		return [-1, ""]

	var start_msec: int = Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if (Time.get_ticks_msec() - start_msec) / 1000.0 > LOCAL_TIMEOUT_SEC:
			OS.kill(pid)
			return [-1, ""]
		OS.delay_msec(10)

	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
		DirAccess.remove_absolute(log_path)

	var success: bool = log_content.contains("EXITCODE:0")
	var clean: String = log_content \
			.replace("EXITCODE:0", "") \
			.replace("EXITCODE:1", "") \
			.strip_edges()
	return [0 if success else 1, clean]


## Polls a running process; kills it if it exceeds NETWORK_TIMEOUT_SEC.
## Reads the redirected log file once the process ends.
func _poll_process(pid: int, command: Command, log_path: String, start_time_ms: int) -> void:
	if OS.is_process_running(pid):
		var elapsed_sec: float = (Time.get_ticks_msec() - start_time_ms) / 1000.0
		if elapsed_sec > NETWORK_TIMEOUT_SEC:
			OS.kill(pid)
			_active_pids.erase(pid)
			if FileAccess.file_exists(log_path):
				DirAccess.remove_absolute(log_path) # Orphaned log from the killed process.
			emit_signal(
				"command_completed",
				command,
				-1,
				["Timed out after %ds." % int(NETWORK_TIMEOUT_SEC)],
			)
			return
		# Not done yet - poll again after a 0.5s deferred delay.
		await Engine.get_main_loop().create_timer(0.5).timeout
		_poll_process(pid, command, log_path, start_time_ms)
		return

	_active_pids.erase(pid)

	# Process finished - read captured output and extract the real exit marker.
	var output: Array[String] = []
	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
		DirAccess.remove_absolute(log_path) # Clean up temp file now that it's been read

	# The marker is the actual exit status of the git command,
	# not a guess based on stdout/stderr content. (see git_cmd above)
	var success: bool = log_content.contains("EXITCODE:0")
	var clean_output: String = log_content \
			.replace("EXITCODE:0", "") \
			.replace("EXITCODE:1", "") \
			.strip_edges()
	output.append(clean_output)
	emit_signal("command_completed", command, 0 if success else 1, output)


## Runs on a WorkerThreadPool thread.
func _execute_and_report(command: Command, args: PackedStringArray) -> void:
	var output: Array[String] = []
	var full_args: PackedStringArray = PackedStringArray(["-C", _project_root()]) + args
	var exit_code: int = OS.execute("git", full_args, output, true)
	call_deferred("_finish_fast", command, exit_code, output)


## Main-thread: clears the write guard (if applicable) before emitting.
func _finish_fast(command: Command, exit_code: int, output: Array[String]) -> void:
	if command in WRITE_COMMANDS:
		_write_busy = false
	emit_signal("command_completed", command, exit_code, output)
