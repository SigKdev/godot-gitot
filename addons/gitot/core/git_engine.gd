## git_engine.gd
## Manages git operations off the main thread.
## Uses WorkerThreadPool for non-blocking execution.
class_name GitEngine
extends RefCounted

## Emitted when a git command finishes.
## @param command_name: identifier for the caller to route the result
## (e.g. "status", "push", "pull").
## @param exit_code: 0 on success.
## @param output: raw stdout lines.
signal command_completed(command_name: String, exit_code: int, output: Array)

## Timeout for network operations (push/pull), in seconds.
const NETWORK_TIMEOUT_SEC: float = 30.0

## PIDs of currently running network operations (push/pull), so they can be
## killed if the plugin is disabled mid-operation.
var _active_pids: Array[int] = []


## Returns the absolute path to the project root, used to anchor every
## git call so it always targets this repo regardless of editor CWD.
static func _project_root() -> String:
	return ProjectSettings.globalize_path("res://")


## Checks if 'git' is callable from the OS PATH.
static func is_git_available() -> bool:
	var output: Array = []
	return OS.execute("git", ["--version"], output) == 0


## Runs a fast, local git command (read or write) off the main thread.
## Use for: status, diff, add, restore, commit. NOT for push/pull (see run_network).
func run_fast(command_name: String, args: PackedStringArray) -> void:
	WorkerThreadPool.add_task(_execute_and_report.bind(command_name, args))


## Runs a network git command (push/pull) with a kill-on-timeout guard.
## Output is captured via shell redirection to a temp file, since
## OS.create_process() alone does not expose stdout/stderr.
## @param command_name: identifier for the caller (e.g. "push").
## @param args: git subcommand arguments (e.g. ["push", "origin", "main"]).
func run_network(command_name: String, args: PackedStringArray) -> void:
	var log_path: String = "user://gitot_%s.log" % command_name
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
	var shell_args: PackedStringArray = ["/C", git_cmd] if OS.get_name() == "Windows" else ["-c", git_cmd]

	# Create the process and store the PID.
	var pid: int = OS.create_process(shell, shell_args)
	if pid == -1:
		call_deferred("emit_signal", "command_completed", command_name, -1, ["Failed to start process."])
		return

	_active_pids.append(pid)
	# Poll the process for completion.
	_poll_process.call_deferred(pid, command_name, abs_log_path, Time.get_ticks_msec())


## Returns the "origin" remote URL, or an empty string on failure.
func get_remote_url() -> String:
	var output: Array = []
	var exit_code: int = OS.execute("git", ["-C", _project_root(), "remote", "get-url", "origin"], output)
	if exit_code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()


## Kills any push/pull processes still running. Called by gitot.gd on exit.
func teardown() -> void:
	for pid in _active_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_active_pids.clear()


## Polls a running process; kills it if it exceeds NETWORK_TIMEOUT_SEC.
## Reads the redirected log file once the process ends.
func _poll_process(pid: int, command_name: String, log_path: String, start_time_ms: int) -> void:
	if OS.is_process_running(pid):
		var elapsed_sec: float = (Time.get_ticks_msec() - start_time_ms) / 1000.0
		if elapsed_sec > NETWORK_TIMEOUT_SEC:
			OS.kill(pid) # Kill the process if it exceeds the timeout.
			_active_pids.erase(pid)
			emit_signal("command_completed", command_name, -1, ["Timed out after %ds." % int(NETWORK_TIMEOUT_SEC)])
			return
		# Not done yet - check again next frame via a short deferred delay.
		await Engine.get_main_loop().create_timer(0.5).timeout
		_poll_process(pid, command_name, log_path, start_time_ms)
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
	output.append(log_content)
	emit_signal("command_completed", command_name, 0 if success else 1, output)


## Runs on a WorkerThreadPool thread. Must not touch UI directly.
func _execute_and_report(command_name: String, args: PackedStringArray) -> void:
	var output: Array = []
	var full_args: PackedStringArray = PackedStringArray(["-C", _project_root()]) + args
	var exit_code: int = OS.execute("git", full_args, output)
	# Route result back to main thread - required by signals.
	# Signals from a worker thread are not guaranteed safe against UI nodes.
	# Deferring the signal emission ensures it runs in the main thread.
	# Deferring is safe because signals are thread-safe by design.
	call_deferred("emit_signal", "command_completed", command_name, exit_code, output)
