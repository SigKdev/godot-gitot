## gitot_branch_results.gd
## Results of the branch commands: list refresh, switch, create, delete (local / remote) and the
## current-branch answer. Updates the branch panel, the status header and the repo state.
## Split from GitotResultRouter, which only dispatches.
class_name GitotBranchResults
extends RefCounted

## Emitted after a successful switch/create: HEAD moved, the dock requests the changed-file listing.
signal head_moved

## Emitted with each parsed branch list, after the branch panel is repainted (one parse for all listeners).
signal branches_parsed(branches: Array[GitBranchEntry])

## The commands handle() answers; the router dispatches on this list.
const COMMANDS: Array[GitEngine.Command] = [
	GitEngine.Command.BRANCHES,
	GitEngine.Command.SWITCH,
	GitEngine.Command.CREATE_BRANCH,
	GitEngine.Command.DELETE_BRANCH,
	GitEngine.Command.DELETE_REMOTE_BRANCH,
	GitEngine.Command.CURRENT_BRANCH,
]

var _git_engine: GitEngine
var _repo_state: GitotRepoState
var _status_panel: GitotStatusPanel
var _branch_panel: GitotBranchPanel


func _init(
	git_engine: GitEngine,
	repo_state: GitotRepoState,
	status_panel: GitotStatusPanel,
	branch_panel: GitotBranchPanel,
) -> void:
	_git_engine = git_engine
	_repo_state = repo_state
	_status_panel = status_panel
	_branch_panel = branch_panel


## Determines whether a branch exists locally, remotely, or both.
static func _get_branch_scope(branch_name: String, branches: Array[GitBranchEntry]) -> String:
	var local_exists: bool = false
	var remote_exists: bool = false

	for branch: GitBranchEntry in branches:
		if branch.is_remote:
			if branch.name == "origin/" + branch_name:
				remote_exists = true
		elif branch.name == branch_name:
			local_exists = true

	var label: String = GitotUi.scope_label(local_exists, remote_exists)
	return "(%s)" % (label if not label.is_empty() else "Local")


## Finds the current branch's name from an already-parsed branch list.
static func _get_current_branch_from_list(branches: Array[GitBranchEntry]) -> String:
	for branch: GitBranchEntry in branches:
		if branch.is_current:
			return branch.name
	return ""


## Handles BRANCHES, SWITCH, CREATE_BRANCH, DELETE_BRANCH, DELETE_REMOTE_BRANCH and CURRENT_BRANCH.
func handle(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	match command:
		GitEngine.Command.BRANCHES:
			_handle_list_result(exit_code, output)
		GitEngine.Command.SWITCH, GitEngine.Command.CREATE_BRANCH:
			_handle_switch_result(command, exit_code, output, context)
		GitEngine.Command.DELETE_BRANCH:
			_handle_delete_result(exit_code, output, context)
		GitEngine.Command.DELETE_REMOTE_BRANCH:
			_handle_delete_remote_result(exit_code, output, context)
		GitEngine.Command.CURRENT_BRANCH:
			_handle_current_branch_result(exit_code, output)


## Branch list: repaints the panel and the header. A failed list (e.g. not a repository) is silent.
func _handle_list_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0 or output.is_empty():
		return
	var branches: Array[GitBranchEntry] = GitBranchParser.parse(output[0])
	var branch_scopes: Dictionary[String, String] = { }

	for branch: GitBranchEntry in branches:
		if branch.is_remote:
			branch_scopes[branch.name] = "Remote"
		else:
			branch_scopes[branch.name] = _get_branch_scope(branch.name, branches)

	_branch_panel.populate(branches, branch_scopes)
	branches_parsed.emit(branches)

	var current_branch: String = _get_current_branch_from_list(branches)
	if current_branch.is_empty():
		# No current entry: an unborn branch (fresh `git init`, no ref until the first commit)
		# or a detached HEAD. Only git can tell which; the answer sets the header.
		_git_engine.request_current_branch()
		return
	_status_panel.update_branch(current_branch, branch_scopes.get(current_branch, ""))
	_repo_state.branch = current_branch


## Switch / create: everything that moves HEAD.
## @param context: {"branch": the target branch}.
func _handle_switch_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	var is_create: bool = command == GitEngine.Command.CREATE_BRANCH
	if exit_code == 0:
		# Set before any later async result arrives, so their messages name the new branch.
		_repo_state.branch = context["branch"]
		GitotLogger.s(
			("Created and switched to branch '%s'." if is_create else "Switched to branch '%s'.")
			% context["branch"]
		)
		head_moved.emit()
	else:
		GitotMessages.log_failure(
			("Could not create branch '%s'." if is_create else "Could not switch to branch '%s'.")
			% context["branch"],
			output,
			(
				"Common fail causes: a branch with that name already exists, or the name is not valid for git."
				if is_create
				else "Common fail causes: uncommitted changes would be overwritten (commit or stash them first), or the branch no longer exists."
			),
		)
	# No branch read here: the status refresh after switch/create re-lists branches and
	# updates the status line (with its scope).


## Git's output ("Deleted branch x (was <sha>)") is logged raw so a mistaken delete
## stays recoverable (`git branch <name> <sha>`); on refusal it carries git's reason.
## @param context: {"branch", "on_remote": a copy exists on origin}.
func _handle_delete_result(exit_code: int, output: Array[String], context: Dictionary) -> void:
	var branch: String = context["branch"]
	if exit_code != 0:
		GitotMessages.log_failure(
			"Could not delete local branch '%s'." % branch,
			output,
			"Common fail causes: the branch is not fully merged (merge it first), or it is the checked-out branch.",
		)
		return
	GitotLogger.s("Local branch '%s' deleted." % branch)
	if context["on_remote"]:
		# Deleting locally never touches GitHub: say so, and where the next step is.
		GitotLogger.w(
			"'%s' still exists on origin. Select 'origin/%s' in the list and use the remote-delete button to remove it too."
			% [branch, branch]
		)
	GitotMessages.log_git_output(output)
	_git_engine.list_branches()


## Branch removed from origin (GitHub). On success git's own line ("- [deleted] x") is logged raw;
## on refusal it carries the server's reason. The local `origin/<name>` ref is dropped by git itself.
## @param context: {"branch": name}.
func _handle_delete_remote_result(exit_code: int, output: Array[String], context: Dictionary) -> void:
	var branch: String = context["branch"]
	var repo: String = _repo_state.repo_label()
	if exit_code != 0:
		GitotMessages.log_failure(
			"Could not delete branch '%s' on '%s'." % [branch, repo],
			output,
			GitotMessages.network_hint(
				exit_code,
				"Common fail causes: GitHub refuses to delete the default branch and protected branches, or you have no permission to push to the repository.",
			),
		)
		return
	GitotLogger.s("Remote branch '%s' deleted on '%s'." % [branch, repo])
	GitotMessages.log_git_output(output)
	_git_engine.list_branches()


## Result of `branch --show-current`, asked when the branch list has no current entry. A name means an
## unborn branch (nothing committed yet, so it is not in the list); empty means a detached HEAD.
func _handle_current_branch_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		return # Silent like the list: the header stays as it was.
	var branch: String = output[0].strip_edges() if not output.is_empty() else ""
	_status_panel.update_branch(branch, _get_branch_scope(branch, []) if not branch.is_empty() else "")
	_repo_state.branch = branch
