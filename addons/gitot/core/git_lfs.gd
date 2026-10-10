## git_lfs.gd
## Git LFS facade: commands in, typed signals out. Command plumbing stays in GitEngine
## (Command enum, run_fast/run_network); parsing stays in GitLfsParser.
class_name GitLfs
extends RefCounted

## Emitted when detect_state() finishes. repo_uses_lfs is independent of the state:
## a freshly cloned LFS project is NO_BINARY + true.
signal state_detected(state: State, repo_uses_lfs: bool)
signal files_listed(files: Array[Dictionary])

## Emitted when the local listing failed. The previous list stays; the panel uses this to drop its
## "Loading" text.
signal files_list_failed

## Emitted after a successful track/untrack: .gitattributes changed, re-read get_patterns().
signal patterns_changed

## Emitted when `git lfs pull` ends. On success, pointer files became real assets.
signal pull_finished(success: bool)

## Emitted when LFS becomes (or stops being) READY: the Size Guard exemption depends on it.
signal ready_changed

enum State {
	NO_BINARY, ## `git lfs version` fails.
	NOT_INITIALIZED, ## Binary present, LFS filter not configured.
	READY, ## Filter configured.
}

## Same root GitRunner anchors its git calls to. Assumes it is the repo root.
const ATTRIBUTES_PATH: String = "res://.gitattributes"

## Godot text formats: they must stay in regular Git (diff/merge). `.import` and `.uid`
## are also tiny and hold import settings / resource IDs.
const KEEP_IN_GIT: PackedStringArray = [
	"gd",
	"gdshader",
	"gdshaderinc",
	"gdextension",
	"tscn",
	"tres",
	"import",
	"uid",
	"godot",
	"cfg",
]

var _engine: GitEngine
## Last detected state == READY. False until the first detect_state() completes.
var _is_ready: bool = false


func _init(engine: GitEngine) -> void:
	_engine = engine
	_engine.command_completed.connect(_on_command_completed)


func teardown() -> void:
	if _engine.command_completed.is_connected(_on_command_completed):
		_engine.command_completed.disconnect(_on_command_completed)


#region Requests
## Starts the async state chain (see _on_command_completed). Result: state_detected.
func detect_state() -> void:
	_engine.run_fast(GitEngine.Command.LFS_VERSION, ["lfs", "version"])


## Result: files_listed (rows merged with the upstream tree, see GitLfsParser.merge_scopes).
## --json gives exact byte sizes (no "1.2 MB" parsing). Two reads in a chain: upstream tree first
## (fails when the branch has no upstream: then nothing is remote), then this checkout.
func list_files() -> void:
	_engine.run_fast(
		GitEngine.Command.LFS_LS_FILES,
		["lfs", "ls-files", "--json", "@{u}"],
		{ "stage": "remote" },
	)


## Writes a rule to .gitattributes. Only affects files added AFTER the rule exists.
## Refuses Godot text formats (see KEEP_IN_GIT); untrack is never blocked.
## @return: false if the pattern was rejected (nothing ran).
func track(pattern: String) -> bool:
	var clean: String = pattern.strip_edges()
	if clean.get_extension().to_lower() in KEEP_IN_GIT:
		GitotLogger.w(
			"'%s' is a Godot text format: keep it in regular Git so it diffs and merges." % clean
		)
		return false
	return _run_pattern(GitEngine.Command.LFS_TRACK, "track", clean)


## @return: false if the pattern was rejected (nothing ran).
func untrack(pattern: String) -> bool:
	return _run_pattern(GitEngine.Command.LFS_UNTRACK, "untrack", pattern)


## `git lfs install`: LFS filters in the GLOBAL git config + hooks of this repo. Idempotent.
func install() -> void:
	_engine.run_fast(GitEngine.Command.LFS_INSTALL, ["lfs", "install"])


## Downloads LFS objects for the checked-out commit. Network op (static args only).
func pull() -> void:
	_engine.run_network(GitEngine.Command.LFS_PULL, ["lfs", "pull"])


## Deletes the local cache of old/unreferenced LFS objects. Caller must confirm first.
func prune() -> void:
	_engine.run_fast(GitEngine.Command.LFS_PRUNE, ["lfs", "prune"])
#endregion


## Patterns of the LFS rules in the root .gitattributes. One small local file read, no spawn.
func get_patterns() -> PackedStringArray:
	var text: String = ""
	if FileAccess.file_exists(ATTRIBUTES_PATH):
		text = FileAccess.get_file_as_string(ATTRIBUTES_PATH)
	return GitLfsParser.parse_patterns(text)


## True once detect_state() found LFS READY (see covers()).
func is_ready() -> bool:
	return _is_ready


## True if LFS will store `path` (repo-relative) as a pointer, so the Size Guard doesn't apply.
## Needs LFS READY (otherwise `git add` stores the raw file) and a matching rule. Only rules
## without "/" are matched, against the file name, as gitattributes does. Anything else
## (path rules, [..] classes, escapes) returns false: the guard stays on (fail-safe).
func covers(path: String) -> bool:
	if not _is_ready:
		return false
	var file_name: String = path.get_file()
	for pattern: String in get_patterns():
		if not pattern.contains("/") and file_name.match(pattern):
			return true
	return false


## Pattern goes through the args array (no shell). Empty or "-"-prefixed patterns are
## refused: the latter could be read as an option by git-lfs.
func _run_pattern(command: GitEngine.Command, verb: String, pattern: String) -> bool:
	var clean: String = pattern.strip_edges()
	if clean.is_empty() or clean.begins_with("-"):
		GitotLogger.w("Invalid LFS pattern: '%s'." % pattern)
		return false
	_engine.run_fast(command, ["lfs", verb, clean], { "pattern": clean })
	return true


## Result routing. LFS_VERSION -> LFS_STATE is the state chain, LS_FILES and TRACK/UNTRACK emit
## signals, the other commands only log. A failed listing keeps the previous data, like the stash list.
func _on_command_completed(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	var raw: String = output[0] if not output.is_empty() else ""
	match command:
		GitEngine.Command.LFS_VERSION:
			if exit_code != 0:
				_emit_state(State.NO_BINARY)
			else:
				# Exit 1 = key unset = `git lfs install` never ran (global or local).
				_engine.run_fast(
					GitEngine.Command.LFS_STATE,
					["config", "--get", "filter.lfs.process"],
				)
		GitEngine.Command.LFS_STATE:
			_emit_state(State.READY if exit_code == 0 else State.NOT_INITIALIZED)
		GitEngine.Command.LFS_INSTALL:
			_log_outcome(exit_code, raw, "Git LFS initialized.", "Git LFS install failed.")
			detect_state() # The write lock is already released at this point.
		GitEngine.Command.LFS_PULL:
			_log_outcome(
				exit_code,
				raw,
				"LFS pull finished.",
				"LFS pull failed.",
				"Common fail causes: no internet, or the LFS storage of origin is not reachable.",
			)
			if exit_code == -1 and raw.begins_with("Timed out"): # run_network()'s timeout output.
				GitotLogger.h(
					"Raise the network timeout in Settings and pull again: files already downloaded are skipped."
				)
			pull_finished.emit(exit_code == 0)
		GitEngine.Command.LFS_PRUNE:
			_log_outcome(exit_code, raw, "LFS prune finished.", "LFS prune failed.")
		GitEngine.Command.LFS_LS_FILES:
			_handle_files_result(exit_code, raw, context)
		GitEngine.Command.LFS_TRACK, GitEngine.Command.LFS_UNTRACK:
			_handle_rule_result(command, exit_code, raw, context)


## Stage "remote": keep the upstream list (empty on failure = no upstream), then read this checkout.
## Stage "local": merge both and publish. On failure the previous list is kept.
func _handle_files_result(exit_code: int, raw: String, context: Dictionary) -> void:
	if context.get("stage", "") == "remote":
		var remote_files: Array[Dictionary] = (
			GitLfsParser.parse_files(raw) if exit_code == 0 else ([] as Array[Dictionary])
		)
		_engine.run_fast(
			GitEngine.Command.LFS_LS_FILES,
			["lfs", "ls-files", "--json"],
			{ "stage": "local", "remote": remote_files },
		)
		return
	if exit_code != 0:
		files_list_failed.emit()
		return
	var remote_list: Array[Dictionary] = context.get("remote", [] as Array[Dictionary])
	files_listed.emit(GitLfsParser.merge_scopes(GitLfsParser.parse_files(raw), remote_list))


## track / untrack share one handler: both only rewrite .gitattributes.
func _handle_rule_result(
	command: GitEngine.Command,
	exit_code: int,
	raw: String,
	context: Dictionary,
) -> void:
	var is_track: bool = command == GitEngine.Command.LFS_TRACK
	var pattern: String = context["pattern"]
	if exit_code != 0:
		GitotLogger.fail(
			"LFS %s failed for '%s'." % ["track" if is_track else "untrack", pattern],
			raw,
		)
		return
	GitotLogger.s("LFS pattern '%s' %s." % [pattern, "tracked" if is_track else "untracked"])
	if is_track:
		GitotLogger.h("Commit .gitattributes so collaborators and CI get the rule.")
	patterns_changed.emit()
	var text: String = raw.strip_edges()
	if not text.is_empty():
		GitotLogger.g(text) # '"*.png" already supported'.


## Success/failure line, then git-lfs's own output, for commands with no parsed result.
func _log_outcome(
	exit_code: int,
	raw: String,
	ok_text: String,
	fail_text: String,
	hint: String = "",
) -> void:
	if exit_code != 0:
		GitotLogger.fail(fail_text, raw, hint)
		return
	GitotLogger.s(ok_text)
	var text: String = raw.strip_edges()
	if not text.is_empty():
		GitotLogger.g(text)


func _emit_state(state: State) -> void:
	var is_ready: bool = state == State.READY
	if is_ready != _is_ready:
		_is_ready = is_ready
		ready_changed.emit()
	state_detected.emit(state, not get_patterns().is_empty())
