## gitot_sync_results.gd
## Results of the sync commands: fetch, ahead/behind, push, pull and tag push. Logs the outcome and
## stores the ahead/behind state. Split from GitotResultRouter, which only dispatches.
class_name GitotSyncResults
extends RefCounted

## Emitted after a successful pull: it moves HEAD like a switch, so the dock requests the same
## HEAD@{1}..HEAD changed-file listing (answered by files_changed).
signal head_moved

## The commands handle() answers; the router dispatches on this list.
const COMMANDS: Array[GitEngine.Command] = [
	GitEngine.Command.FETCH,
	GitEngine.Command.AHEAD_BEHIND,
	GitEngine.Command.PUSH,
	GitEngine.Command.PULL,
	GitEngine.Command.PUSH_TAG,
]

var _git_engine: GitEngine
var _repo_state: GitotRepoState
## False until the first ahead/behind answer: that one is the startup read and logs nothing.
var _startup_read_done: bool = false


func _init(git_engine: GitEngine, repo_state: GitotRepoState) -> void:
	_git_engine = git_engine
	_repo_state = repo_state


## Handles FETCH, AHEAD_BEHIND, PUSH, PULL and PUSH_TAG.
func handle(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	match command:
		GitEngine.Command.FETCH:
			_handle_fetch_result(exit_code, output)
		GitEngine.Command.AHEAD_BEHIND:
			_handle_ahead_behind_result(exit_code, output)
		GitEngine.Command.PUSH, GitEngine.Command.PULL:
			_handle_push_pull_result(command, exit_code, output, context)
		GitEngine.Command.PUSH_TAG:
			_handle_push_tag_result(exit_code, output, context)


## Fetch: new remote branches only become visible afterwards, so refresh the branch list and the
## ahead/behind counts.
func _handle_fetch_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotMessages.log_failure(
			"Fetch from '%s' failed." % _repo_state.repo_label(),
			output,
			GitotMessages.network_hint(exit_code),
		)
		return
	GitotLogger.s("Fetched from '%s': its latest branches are downloaded." % _repo_state.repo_label())
	GitotMessages.log_git_output(output)
	_git_engine.list_branches()
	_git_engine.get_ahead_behind() # New remote refs change the sync status.


## Ahead/behind of HEAD vs its upstream: stored once in the repo state, panels redraw from it.
func _handle_ahead_behind_result(exit_code: int, output: Array[String]) -> void:
	var startup_read: bool = not _startup_read_done
	_startup_read_done = true
	if exit_code != 0 or output.is_empty():
		_repo_state.set_sync(false, 0, 0) # No upstream (or git failed): counts are meaningless.
		return
	var parts: PackedStringArray = output[0].strip_edges().split("\t")
	if parts.size() != 2:
		return
	var behind: int = int(parts[0])
	var ahead: int = int(parts[1])
	if _repo_state.set_sync(true, ahead, behind) and (ahead > 0 or behind > 0) and not startup_read:
		GitotLogger.i(
			"Current branch '%s' is %d ahead, %d behind origin." % [_repo_state.branch_label(), ahead, behind]
		)


func _handle_push_pull_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	var is_pull: bool = command == GitEngine.Command.PULL
	if exit_code == 0:
		GitotLogger.s(_push_pull_success(is_pull, context.get("force", false)))
		GitotMessages.log_git_output(output)
		if is_pull:
			head_moved.emit() # pull moves HEAD like a switch - same HEAD@{1}..HEAD diff applies
		return
	var hint: String = (
		"Common fail causes: your uncommitted changes would be overwritten (commit or stash them first), or a merge conflict (resolve the marked files)."
		if is_pull
		else "Common fail causes: not signed in / no permission on GitHub, origin has newer commits (Pull first), or the branch has no commit yet (commit first)."
	)
	GitotMessages.log_failure(
		(
			"Pull from '%s' into branch '%s' failed." % [_repo_state.repo_label(), _repo_state.branch_label()]
			if is_pull
			else "Push of branch '%s' to '%s' failed." % [_repo_state.branch_label(), _repo_state.repo_label()]
		),
		output,
		GitotMessages.network_hint(exit_code, hint),
	)


## Success line of a finished push/pull, naming the repo and branch it concerned.
## Exit 0 also covers "Everything up-to-date": git's raw line, logged right after, tells.
func _push_pull_success(is_pull: bool, forced: bool) -> String:
	if is_pull:
		return "Pulled from '%s' into branch '%s'." % [_repo_state.repo_label(), _repo_state.branch_label()]
	if forced:
		return (
			"Commits force-pushed to '%s' on branch '%s'. Origin's diverged commits were replaced."
			% [_repo_state.repo_label(), _repo_state.branch_label()]
		)
	return "Commits pushed to '%s' on branch '%s'." % [_repo_state.repo_label(), _repo_state.branch_label()]


## Tag push finished: success names the repo (a tag belongs to a commit, not a branch, and a retry may
## run after a branch switch). The retry state itself is kept by GitSyncOrchestrator.
## @param context: {"tag": name}.
func _handle_push_tag_result(exit_code: int, output: Array[String], context: Dictionary) -> void:
	var tag: String = context.get("tag", "")
	if exit_code == 0:
		GitotLogger.s("Tag '%s' pushed to '%s'." % [tag, _repo_state.repo_label()])
		return
	GitotMessages.log_failure(
		"Tag '%s' was created locally but could not be pushed to '%s'." % [tag, _repo_state.repo_label()],
		output,
		GitotMessages.network_hint(
			exit_code,
			"Common fail causes: not signed in / no permission on GitHub, or the tag already exists on origin.",
		),
	)
	GitotLogger.h("Use the tag Retry button next to Push to push it again.")
