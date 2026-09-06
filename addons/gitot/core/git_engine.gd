class_name GitEngine
extends RefCounted

## Emitted when a fast local command (status/diff) finishes.
## @param command_name: identifier for the caller to route the result (e.g. "status").
## @param exit_code: 0 on success.
## @param output: raw stdout lines.
signal command_completed(command_name: String, exit_code: int, output: Array)

## Timeout for network operations (push/pull), in seconds.
const NETWORK_TIMEOUT_SEC: float = 30.0


## Checks if 'git' is callable from the OS PATH.
static func is_git_available() -> bool:
	var output: Array = []
	return OS.execute("git", ["--version"], output) == 0


## Runs a fast, local, read-only git command off the main thread.
## Use for: status, diff. NOT for push/pull (see 2.2 — network ops need their own path).
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

	# Build the full command as a single shell line so we can redirect output.
	var git_cmd: String = "git " + " ".join(args) + " > \"%s\" 2>&1" % abs_log_path
	var shell: String = "cmd" if OS.get_name() == "Windows" else "sh"
	var shell_args: PackedStringArray = ["/C", git_cmd] if OS.get_name() == "Windows" else ["-c", git_cmd]

	var pid: int = OS.create_process(shell, shell_args)
	if pid == -1:
		call_deferred("emit_signal", "command_completed", command_name, -1, ["Failed to start process."])
		return

	_poll_process.call_deferred(pid, command_name, abs_log_path, Time.get_ticks_msec())

## Polls a running process; kills it if it exceeds NETWORK_TIMEOUT_SEC.
## Reads the redirected log file once the process ends.
func _poll_process(pid: int, command_name: String, log_path: String, start_time_ms: int) -> void:
	if OS.is_process_running(pid):
		var elapsed_sec: float = (Time.get_ticks_msec() - start_time_ms) / 1000.0
		if elapsed_sec > NETWORK_TIMEOUT_SEC:
			OS.kill(pid)
			emit_signal("command_completed", command_name, -1, ["Timed out after %ds." % int(NETWORK_TIMEOUT_SEC)])
			return
		# Not done yet — check again next frame via a short deferred delay.
		await Engine.get_main_loop().create_timer(0.5).timeout
		_poll_process(pid, command_name, log_path, start_time_ms)
		return

	# Process finished — read captured output.
	var output: Array = []
	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
	output.append(log_content)

	# Git failures print "fatal:" or "error:" to stderr, which we redirected here.
	var success: bool = not (log_content.contains("fatal:") or log_content.contains("error:"))
	emit_signal("command_completed", command_name, 0 if success else 1, output)


## Runs on a WorkerThreadPool thread. Must not touch UI directly.
func _execute_and_report(command_name: String, args: PackedStringArray) -> void:
	var output: Array = []
	var exit_code: int = OS.execute("git", args, output)
	# Route result back to main thread — required, signals from a worker thread
	# are not guaranteed safe against UI nodes.
	call_deferred("emit_signal", "command_completed", command_name, exit_code, output)
