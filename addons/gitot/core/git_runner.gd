## git_runner.gd
## Process execution for Gitot: worker threads, timeouts, shell redirect, write lock.
## Git-domain agnostic: knows nothing about GitEngine.Command or its signal.
class_name GitRunner
extends RefCounted

## Timeout for bounded local reads (execute_bounded). Short: these are cheap plumbing
## commands, a hang past this means a stuck lock/gc, not normal latency.
## Distinct from the user-set "network_timeout_sec" (push/pull).
const LOCAL_TIMEOUT_SEC: float = 5.0

## PID → temp log path of running network operations (push/pull). Tracks both so a
## mid-operation kill (timeout or teardown) can also remove the orphaned log file.
var _active_pids: Dictionary[int, String] = { }

## True while a write op is executing. Blocks any other run_fast() call from racing it
## on index.lock; reads never block each other, and never block while no write is in flight.
var _write_busy: bool = false


## Absolute project root, anchors every git call regardless of editor CWD.
static func _project_root() -> String:
	return ProjectSettings.globalize_path("res://")


## Builds the shell + args that redirect a git call's stdout/stderr to log_path and
## append a trailing exit-status marker. Shared by run_network() and execute_bounded()
## — single source for this shell contract.
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


## Splits a redirected git-call log into [success: bool, cleaned text: String].
static func _parse_log(log_content: String) -> Array:
	var success: bool = log_content.contains("EXITCODE:0")
	var clean: String = log_content \
			.replace("EXITCODE:0", "") \
			.replace("EXITCODE:1", "") \
			.strip_edges()
	return [success, clean]


## True while a write op holds the lock (see _write_busy).
func is_write_busy() -> bool:
	return _write_busy


## Runs a local git command off the main thread. NOT for push/pull (see run_network).
## @param label: command name, used in logs.
## @param is_write: mutates index/tree/refs. Takes the write lock; every call is ignored while held.
## @param on_done: Callable(exit_code: int, output: Array[String]), called on the main thread.
func run_fast(label: String, args: PackedStringArray, is_write: bool, on_done: Callable) -> void:
	if _write_busy:
		GitotLogger.w("%s skipped: another git write was still running." % label.capitalize())
		return
	if is_write:
		_write_busy = true
	WorkerThreadPool.add_task(_execute_and_report.bind(args, is_write, on_done))


## Runs a network git command (push/pull) with a kill-on-timeout guard.
## Output is captured via shell redirection to a temp file, since
## OS.create_process() alone does not expose stdout/stderr.
## @param label: command name, used in the log file name.
## @param on_done: Callable(exit_code: int, output: Array[String]).
func run_network(label: String, args: PackedStringArray, on_done: Callable) -> void:
	# Time.get_ticks_usec() disambiguates concurrent same-named ops (e.g. two fetches);
	# the real PID isn't known until after OS.create_process() returns, too late for this path.
	var log_path: String = ProjectSettings.globalize_path(
		"user://gitot_%s_%d.log" % [label, Time.get_ticks_usec()]
	)

	# SECURITY: this shell string only ever receives static, hardcoded args
	# (push/pull with no user-supplied values). Never interpolate user input
	# (branch names, messages, paths) into it without escaping.
	var shell_invocation: Array = _shell_invocation(args, log_path)
	var pid: int = OS.create_process(shell_invocation[0], shell_invocation[1])
	if pid == -1:
		var failure: Array[String] = ["Failed to start process."]
		on_done.call_deferred(-1, failure)
		return

	_active_pids[pid] = log_path
	_poll_process.call_deferred(pid, log_path, Time.get_ticks_msec(), on_done)


## Runs a local git query synchronously, capped at LOCAL_TIMEOUT_SEC: blocks the calling
## thread up to the cap, then kills the process. Only for one-off reads; hot UI paths
## use run_fast()/run_network() (never blocking).
## @return: [exit_code: int, output: String]. exit_code -1 on timeout/spawn failure.
func execute_bounded(args: PackedStringArray) -> Array:
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
			if FileAccess.file_exists(log_path):
				DirAccess.remove_absolute(log_path) # Orphaned log from the killed process.
			return [-1, ""]
		OS.delay_msec(10)

	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
		DirAccess.remove_absolute(log_path)

	var parsed: Array = _parse_log(log_content)
	return [0 if parsed[0] else 1, parsed[1]]


## Kills any push/pull processes still running and removes their logs. Call on plugin exit.
func teardown() -> void:
	for pid: int in _active_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
		var log_path: String = _active_pids[pid]
		if FileAccess.file_exists(log_path):
			DirAccess.remove_absolute(log_path)
	_active_pids.clear()


## Polls a network process until it ends or exceeds "network_timeout_sec",
## then reports through on_done. Reads the redirected log once the process ends.
func _poll_process(pid: int, log_path: String, start_time_ms: int, on_done: Callable) -> void:
	if OS.is_process_running(pid):
		var elapsed_sec: float = (Time.get_ticks_msec() - start_time_ms) / 1000.0
		# Read per poll (cached Dictionary lookup) so a settings change applies to in-flight ops.
		var timeout_sec: int = GitotSettings.get_value("network_timeout_sec")
		if elapsed_sec > timeout_sec:
			OS.kill(pid)
			_active_pids.erase(pid)
			if FileAccess.file_exists(log_path):
				DirAccess.remove_absolute(log_path) # Orphaned log from the killed process.
			var timeout_output: Array[String] = ["Timed out after %ds." % timeout_sec]
			on_done.call(-1, timeout_output)
			return
		# Not done yet - poll again after a 0.5s delay.
		await Engine.get_main_loop().create_timer(0.5).timeout
		_poll_process(pid, log_path, start_time_ms, on_done)
		return

	_active_pids.erase(pid)

	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
		DirAccess.remove_absolute(log_path) # Temp file already read.

	# The marker is the real exit status of the git command (see _shell_invocation).
	var parsed: Array = _parse_log(log_content)
	var output: Array[String] = [parsed[1]]
	on_done.call(0 if parsed[0] else 1, output)


## Runs on a WorkerThreadPool thread.
func _execute_and_report(args: PackedStringArray, is_write: bool, on_done: Callable) -> void:
	var output: Array[String] = []
	var full_args: PackedStringArray = PackedStringArray(["-C", _project_root()]) + args
	var exit_code: int = OS.execute("git", full_args, output, true)
	call_deferred("_finish_fast", exit_code, output, is_write, on_done)


## Main thread: releases the write lock (if held) before reporting.
func _finish_fast(exit_code: int, output: Array[String], is_write: bool, on_done: Callable) -> void:
	if is_write:
		_write_busy = false
	on_done.call(exit_code, output)
