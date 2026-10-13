## git_runner.gd
## Process execution for Gitot: worker threads, timeouts, shell redirect, write lock.
## Git-domain agnostic: knows nothing about GitEngine.Command or its signal.
class_name GitRunner
extends RefCounted

## Emitted when the write lock is taken (true) or released (false). UI shows a busy state from it,
## so any write (commit, stage, stash...) is covered without per-button wiring.
signal write_busy_changed(busy: bool)

## Max chars of path arguments per git call. Windows CreateProcess caps the WHOLE command
## line at 32767; 24000 leaves headroom for "git -C <root> add --" and arg quoting.
const MAX_ARGS_CHARS: int = 24000

## Whitelist for every argument interpolated into run_network()'s shell string: letters, digits
## and . _ / - @ + : only. Space, quotes and & | < > ^ % ! ; $ ` ( ) { } # ~ * ? [ \ all have a
## meaning in cmd.exe or sh, yet are legal in git ref names, so a blacklist can never be complete.
const SHELL_SAFE_PATTERN: String = "^[A-Za-z0-9._/@+:-]+$"

## Chars that still act INSIDE the double quotes around the project root and the log path in
## run_network()'s shell string: `%` expands in cmd.exe; `$`, backtick and `\` in sh; `"` ends the
## quote in both. Everything else (spaces, `&`, `^`...) is literal there, so paths are NOT
## whitelisted like args: a space in "C:/Users/John Doe/..." must keep working.
const QUOTE_UNSAFE_WINDOWS: PackedStringArray = ["\"", "%"]
const QUOTE_UNSAFE_POSIX: PackedStringArray = ["\"", "$", "`", "\\"]

## Written by the shell after git's output: "EXITCODE:0" (success) or "EXITCODE:1" (failure).
const EXIT_MARKER: String = "EXITCODE:"

## PID -> temp log path of running network operations (push, pull...), so a mid-operation kill
## (timeout or teardown) can also remove the orphaned log file.
var _active_pids: Dictionary[int, String] = { }

## True while a write op is executing. Blocks any other WRITE from racing it on index.lock;
## reads are never blocked, so every read always completes.
var _write_busy: bool = false

## Absolute project root, anchors every git call regardless of editor CWD.
static func _project_root() -> String:
	return ProjectSettings.globalize_path("res://")


## Builds the shell + args that redirect a git call's stdout/stderr to log_path and
## append a trailing exit-status marker. Used by run_network() only.
## SECURITY: run_network() refuses unsafe args and paths first (_shell_refusal).
static func _shell_invocation(args: PackedStringArray, log_path: String) -> Array:
	var git_cmd: String = (
		"git -C \"%s\" %s > \"%s\" 2>&1 && echo %s0 >> \"%s\" || echo %s1 >> \"%s\""
		% [_project_root(), " ".join(args), log_path, EXIT_MARKER, log_path, EXIT_MARKER, log_path]
	)
	var shell: String = "cmd" if OS.get_name() == "Windows" else "sh"
	var shell_args: PackedStringArray = (
		["/C", git_cmd] if OS.get_name() == "Windows" else ["-c", git_cmd]
	)
	return [shell, shell_args]


## True if arg can be placed in the shell string of run_network() without being interpreted.
## Single source of truth for that rule; also used to validate names BEFORE they are created.
static func is_shell_safe(arg: String) -> bool:
	return GitotRegex.compiled(SHELL_SAFE_PATTERN).search(arg) != null


## True if a path can sit inside the double quotes of the shell string without being interpreted
## (see QUOTE_UNSAFE_WINDOWS). `windows` picks the shell: cmd.exe or sh.
static func is_quoted_path_safe(path: String, windows: bool) -> bool:
	var unsafe: PackedStringArray = QUOTE_UNSAFE_WINDOWS if windows else QUOTE_UNSAFE_POSIX
	for ch: String in unsafe:
		if path.contains(ch):
			return false
	return true


## "" if everything run_network() interpolates into the shell string is safe, else why the call is
## refused. `paths` are the quoted ones (project root, log file).
static func _shell_refusal(args: PackedStringArray, paths: PackedStringArray) -> String:
	for arg: String in args:
		if not is_shell_safe(arg):
			return "Refused: '%s' has characters that are unsafe for the shell." % arg
	for path: String in paths:
		if not is_quoted_path_safe(path, OS.get_name() == "Windows"):
			return "Refused: the path '%s' has characters that are unsafe for the shell." % path
	return ""


## Splits a redirected git-call log into [success: bool, cleaned text: String].
## Only a marker that ends the log counts: git's own output may contain the same words, and a
## killed shell leaves no marker at all (= failure, text kept whole).
static func _parse_log(log_content: String) -> Array:
	var text: String = log_content.strip_edges()
	var at: int = text.rfind(EXIT_MARKER)
	var code: String = text.substr(at + EXIT_MARKER.length()) if at != -1 else ""
	if code != "0" and code != "1":
		return [false, text]
	return [code == "0", text.left(at).strip_edges()]


## Windows: OS.execute() decodes the pipe with the ANSI code page, so UTF-8 text comes back garbled
## ("é" -> "Ã©"). Re-encoding with that same code page restores the raw bytes git wrote;
## they are then decoded once, as UTF-8. No-op elsewhere (UTF-8 already) and on ASCII.
static func _fix_encoding(text: String) -> String:
	# ASCII-only text (and "") is identical in every encoding: skip the conversion. The OS call
	# rejects empty input (error 87), and this keeps the common case cheap.
	if OS.get_name() != "Windows" or text.to_utf8_buffer().size() == text.length():
		return text
	var bytes: PackedByteArray = text.to_multibyte_char_buffer() # Back to the raw bytes git wrote.
	return bytes.get_string_from_utf8() if not bytes.is_empty() else text


## Splits args after the "--" separator so each call's paths fit MAX_ARGS_CHARS.
## No "--" or short list -> a single chunk.
static func _chunk_args(args: PackedStringArray) -> Array[PackedStringArray]:
	var chunks: Array[PackedStringArray] = []
	var sep: int = args.find("--")
	if sep == -1:
		chunks.append(args)
		return chunks
	var head: PackedStringArray = args.slice(0, sep + 1) # e.g. ["add", "--"]
	var current: PackedStringArray = head.duplicate()
	var used: int = 0
	for i: int in range(sep + 1, args.size()):
		var cost: int = args[i].length() + 3 # separator + worst-case quotes
		if used + cost > MAX_ARGS_CHARS and current.size() > head.size():
			chunks.append(current)
			current = head.duplicate()
			used = 0
		current.append(args[i])
		used += cost
	chunks.append(current)
	return chunks


## OS.execute() appends one entry per call, so a chunked command yields one entry per chunk.
## Merges them into a single entry: consumers read output[0] and must also see the failing chunk.
## No output at all stays empty.
static func _merge_outputs(output: Array[String]) -> Array[String]:
	var merged: Array[String] = []
	if not output.is_empty():
		merged.append("".join(PackedStringArray(output)))
	return merged


## True while a write op holds the lock (see _write_busy).
func is_write_busy() -> bool:
	return _write_busy


## Takes the write lock. False = another write holds it: the caller must drop its call (_drop_write).
func _try_lock_write() -> bool:
	if _write_busy:
		return false
	_write_busy = true
	write_busy_changed.emit(true)
	return true


## Logs a write that could not take the lock and still completes it (exit -1), or the caller's busy
## UI (init, LFS install, pop, push button) never resets.
func _drop_write(label: String, on_done: Callable) -> void:
	GitotLogger.i("%s skipped: Git is still finishing the previous change. Try again." % label.capitalize())
	var skipped: Array[String] = ["Skipped: another git write is running."]
	on_done.call_deferred(-1, skipped)


## Runs a local git command off the main thread. NOT for push/pull (see run_network).
## @param label: command name, used in logs.
## @param is_write: mutates index/tree/refs. Takes the write lock; a write is dropped (logged,
## on_done gets -1) while another is held. Reads always run.
## @param on_done: Callable(exit_code: int, output: Array[String]), called on the main thread.
## Always called, also for a dropped write (exit_code -1).
func run_fast(label: String, args: PackedStringArray, is_write: bool, on_done: Callable) -> void:
	if is_write and not _try_lock_write():
		_drop_write(label, on_done)
		return
	WorkerThreadPool.add_task(_execute_and_report.bind(args, is_write, on_done))


## Runs a network git command (push/pull) with a kill-on-timeout guard.
## Output is captured via shell redirection to a temp file, since
## OS.create_process() alone does not expose stdout/stderr.
## @param label: command name, used in the log file name.
## @param is_write: the command moves HEAD, the tree or the pushed commit (pull, push): same write lock
## and drop rule as run_fast(). The lock is released right before on_done, so a follow-up write
## issued from it (push -> tag) can take it.
## @param on_done: Callable(exit_code: int, output: Array[String]).
func run_network(label: String, args: PackedStringArray, is_write: bool, on_done: Callable) -> void:
	# Time.get_ticks_usec() disambiguates concurrent same-named ops (e.g. two fetches);
	# the real PID isn't known until after OS.create_process() returns, too late for this path.
	var log_path: String = ProjectSettings.globalize_path(
		"user://gitot_%s_%d.log" % [label, Time.get_ticks_usec()]
	)

	# SECURITY: args and both paths are joined into a shell string. Refuse anything unsafe
	# (see SHELL_SAFE_PATTERN, QUOTE_UNSAFE_*) instead of trying to escape it for two different shells.
	var refusal: String = _shell_refusal(args, PackedStringArray([_project_root(), log_path]))
	if not refusal.is_empty():
		var refused: Array[String] = [refusal]
		on_done.call_deferred(-1, refused) # Before the lock: nothing to release.
		return

	if is_write and not _try_lock_write():
		_drop_write(label, on_done)
		return

	var shell_invocation: Array = _shell_invocation(args, log_path)
	var pid: int = OS.create_process(shell_invocation[0], shell_invocation[1])
	if pid == -1:
		var failure: Array[String] = ["Failed to start process."]
		_finish.call_deferred(-1, failure, is_write, on_done)
		return

	_active_pids[pid] = log_path
	_poll_process.call_deferred(pid, log_path, Time.get_ticks_msec(), is_write, on_done)


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
func _poll_process(pid: int, log_path: String, start_time_ms: int, is_write: bool, on_done: Callable) -> void:
	# teardown() cleared the pid (process killed, log removed): stop polling, never report.
	if not _active_pids.has(pid):
		return
	if OS.is_process_running(pid):
		var elapsed_sec: float = (Time.get_ticks_msec() - start_time_ms) / 1000.0
		# Read per poll (cached Dictionary lookup) so a settings change applies to in-flight ops.
		var timeout_sec: int = GitotSettings.get_value(GitotSettings.KEY_NETWORK_TIMEOUT_SEC)
		if elapsed_sec > timeout_sec:
			OS.kill(pid)
			_active_pids.erase(pid)
			if FileAccess.file_exists(log_path):
				DirAccess.remove_absolute(log_path) # Orphaned log from the killed process.
			var timeout_output: Array[String] = ["Timed out after %ds." % timeout_sec]
			_finish(-1, timeout_output, is_write, on_done)
			return
		# Not done yet - poll again after a 0.5s delay.
		await Engine.get_main_loop().create_timer(0.5).timeout
		_poll_process(pid, log_path, start_time_ms, is_write, on_done)
		return

	_active_pids.erase(pid)

	var log_content: String = ""
	if FileAccess.file_exists(log_path):
		log_content = FileAccess.get_file_as_string(log_path)
		DirAccess.remove_absolute(log_path) # Temp file already read.

	# The marker is the real exit status of the git command (see _shell_invocation).
	var parsed: Array = _parse_log(log_content)
	var output: Array[String] = [parsed[1]]
	_finish(0 if parsed[0] else 1, output, is_write, on_done)


## Runs on a WorkerThreadPool thread.
func _execute_and_report(args: PackedStringArray, is_write: bool, on_done: Callable) -> void:
	var output: Array[String] = []
	var exit_code: int = 0
	for chunk: PackedStringArray in _chunk_args(args):
		var full_args: PackedStringArray = PackedStringArray(["-C", _project_root()]) + chunk
		exit_code = OS.execute("git", full_args, output, true) # Appends one entry per call.
		if exit_code != 0:
			break # Report the first failure; don't pile more calls onto it.
	for i: int in output.size():
		output[i] = _fix_encoding(output[i])
	call_deferred("_finish", exit_code, _merge_outputs(output), is_write, on_done)


## Main thread: releases the write lock (if held) before reporting.
func _finish(exit_code: int, output: Array[String], is_write: bool, on_done: Callable) -> void:
	if is_write:
		_write_busy = false
		write_busy_changed.emit(false)
	on_done.call(exit_code, output)
