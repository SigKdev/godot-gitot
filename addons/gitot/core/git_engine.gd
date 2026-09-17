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
signal command_completed(command: Command, exit_code: int, output: Array)

## Identifies which git operation a command_completed signal refers to.
## Enum key names double as display strings via Command.keys()[cmd].capitalize()
## (e.g. STASH_POP -> "Stash Pop") — keep key names matching that pattern.
enum Command {
	STATUS,
	DIFF,
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
	PUSH_TAG,
}

## Timeout for network operations (push/pull), in seconds.
const NETWORK_TIMEOUT_SEC: float = 30.0

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

## PIDs of currently running network operations (push/pull), so they can be
## killed if the plugin is disabled mid-operation.
var _active_pids: Array[int] = []


## Checks if 'git' is callable from the OS PATH.
static func is_git_available() -> bool:
	var output: Array = []
	return OS.execute("git", ["--version"], output) == 0


## Returns the absolute path to the project root, used to anchor every
## git call so it always targets this repo regardless of editor CWD.
static func _project_root() -> String:
	return ProjectSettings.globalize_path("res://")


## Splits a git remote URL (SSH or HTTPS form) into owner and repo name.
## @return: {"owner": String, "repo": String}, or {} if the URL has fewer than 2 path segments.
static func parse_owner_repo(url: String) -> Dictionary:
	var cleaned: String = url.trim_suffix(".git")
	var parts: PackedStringArray = cleaned.split("/")
	if parts.size() < 2:
		return {}
	return {"owner": parts[-2].split(":")[-1], "repo": parts[-1]}


## Runs a fast, local git command (read or write) off the main thread.
## Use for: status, diff, add, restore, commit. [b]NOT for push/pull[/b] [i](see run_network)[/i].
func run_fast(command: Command, args: PackedStringArray) -> void:
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
	var log_path: String = "user://gitot_%s_%d.log" % [Command.keys()[command], Time.get_ticks_usec()]
	var abs_log_path: String = ProjectSettings.globalize_path(log_path)

	# Build the full command: redirect output, then append the real exit status
	# as a trailing marker line. && / || are supported by both cmd and sh,
	# avoiding cmd's %errorlevel% delayed-expansion pitfalls.
	# SECURITY: this shell string only ever receives static, hardcoded args
	# (push/pull with no user-supplied values). Never interpolate user input
	# (branch names, messages, paths) into this string without escaping.
	var git_cmd: String = (
		"git -C \"%s\" %s > \"%s\" 2>&1 && echo EXITCODE:0 >> \"%s\" || echo EXITCODE:1 >> \"%s\""
		% [_project_root(), " ".join(args), abs_log_path, abs_log_path, abs_log_path]
	)
	var shell: String = "cmd" if OS.get_name() == "Windows" else "sh"
	var shell_args: PackedStringArray = (
		["/C", git_cmd]
		if OS.get_name() == "Windows"
		else ["-c", git_cmd]
	)

	# Create the process and store the PID.
	var pid: int = OS.create_process(shell, shell_args)
	if pid == -1:
		call_deferred(
			"emit_signal",
			"command_completed",
			command,
			-1,
			["Failed to start process."],
		)
		return

	_active_pids.append(pid)
	# Poll the process for completion.
	_poll_process.call_deferred(pid, command, abs_log_path, Time.get_ticks_msec())


## Returns the "origin" remote URL, or an empty string on failure.
func get_remote_url() -> String:
	var output: Array = []
	var exit_code: int = OS.execute(
		"git",
		["-C", _project_root(), "remote", "get-url", "origin"],
		output,
	)
	if exit_code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()


## Returns HEAD's full commit message, or empty string on failure (e.g. no commits yet).
func get_last_commit_message() -> String:
	var output: Array = []
	var exit_code: int = OS.execute(
		"git",
		["-C", _project_root(), "log", "-1", "--pretty=%B"],
		output,
	)
	if exit_code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()


## Returns files changed by the most recent `switch`/`create_branch` (reflog diff).
## Sync/local — mirrors get_remote_url()/get_last_commit_message() pattern.
## Used to call EditorFileSystem.update_file() precisely instead of a full scan().
## @return: paths relative to project root (e.g. "scenes/player.tscn"). Empty on
## first-ever switch (no HEAD@{1} yet) or any git failure.
func get_changed_files_since_switch() -> PackedStringArray:
	var output: Array = []
	var exit_code: int = OS.execute(
		"git",
		["-C", _project_root(), "diff", "--name-only", "HEAD@{1}", "HEAD"],
		output,
	)
	if exit_code != 0 or output.is_empty():
		return PackedStringArray()
	return PackedStringArray(output[0].strip_edges().split("\n", false))


## Lists branches. Fast/local op — routes through run_fast.
## Result output[0] is fed to GitBranchParser.parse().
func list_branches() -> void:
	run_fast(Command.BRANCHES, ["branch", "-a", "--format=%(refname)|%(HEAD)"])


## Lists the last `count` commits on the current branch. Fast/local op.
## Result output[0] is fed to GitLogParser.parse().
## @param count: max number of commits to fetch (dropdown-controlled: 10/20/30).
func get_log(count: int) -> void:
	run_fast(Command.LOG, ["log", "-n", str(count), LOG_FORMAT, "--date=format:%Y-%m-%d %H:%M"])


## Switches to an existing local branch. Uncommitted changes that don't
## conflict with the target branch's content silently follow the user —
## caller MUST trigger a status refresh + filesystem scan regardless of
## exit_code (see gitot.gd STATUS_TRIGGERING_COMMANDS).
## @param branch_name: existing local branch name.
func switch_branch(branch_name: String) -> void:
	run_fast(Command.SWITCH, ["switch", branch_name])


## Creates a new local branch and switches to it in one atomic op.
## @param branch_name: new branch name (git ref-name rules enforced by git itself).
func create_branch(branch_name: String) -> void:
	run_fast(Command.CREATE_BRANCH, ["switch", "-c", branch_name])


## Returns the current branch name, or empty string on failure (e.g. detached HEAD).
func get_current_branch() -> String:
	var output: Array = []
	var exit_code: int = OS.execute(
		"git",
		["-C", _project_root(), "branch", "--show-current"],
		output,
	)
	if exit_code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()


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


## Creates a local branch tracking a remote-only branch and switches to it.
## @param remote_name: full remote ref, e.g. "origin/feature-x".
func track_remote_branch(remote_name: String) -> void:
	var local_name: String = remote_name.trim_prefix("origin/")
	run_fast(Command.CREATE_BRANCH, ["switch", "-c", local_name, "--track", remote_name])


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
	for pid in _active_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_active_pids.clear()


## Polls a running process; kills it if it exceeds NETWORK_TIMEOUT_SEC.
## Reads the redirected log file once the process ends.
func _poll_process(pid: int, command: Command, log_path: String, start_time_ms: int) -> void:
	if OS.is_process_running(pid):
		var elapsed_sec: float = (Time.get_ticks_msec() - start_time_ms) / 1000.0
		if elapsed_sec > NETWORK_TIMEOUT_SEC:
			OS.kill(pid) # Kill the process if it exceeds the timeout.
			_active_pids.erase(pid)
			emit_signal(
				"command_completed",
				command,
				-1,
				["Timed out after %ds." % int(NETWORK_TIMEOUT_SEC)],
			)
			return
		# Not done yet - check again next frame via a short deferred delay.
		await Engine.get_main_loop().create_timer(0.5).timeout
		_poll_process(pid, command, log_path, start_time_ms)
		return

	_active_pids.erase(pid)

	# Process finished - read captured output and extract the real exit marker.
	var output: Array = []
	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
		DirAccess.remove_absolute(log_path) # Clean up temp file now that it's been read

	# The marker is the actual exit status of the git command,
	# not a guess based on stdout/stderr content. (see git_cmd above)
	var success: bool = log_content.contains("EXITCODE:0")
	var clean_output: String = log_content.replace("EXITCODE:0", "").replace("EXITCODE:1", "").strip_edges()
	output.append(clean_output)
	emit_signal("command_completed", command, 0 if success else 1, output)


## Runs on a WorkerThreadPool thread. Must not touch UI directly.
func _execute_and_report(command: Command, args: PackedStringArray) -> void:
	var output: Array = []
	var full_args: PackedStringArray = PackedStringArray(["-C", _project_root()]) + args
	# read_stderr=true: needed to detect specific git error text (e.g. "already exists").
	var exit_code: int = OS.execute("git", full_args, output, true)
	# Route result back to main thread - required by signals.
	# Signals from a worker thread are not guaranteed safe against UI nodes.
	# Deferring the signal emission ensures it runs in the main thread.
	# Deferring is safe because signals are thread-safe by design.
	call_deferred("emit_signal", "command_completed", command, exit_code, output)
