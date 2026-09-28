## github_panel.gd
## Central panel for the GitHub Issues Task Board.
@tool
class_name GithubPanel
extends Control

enum RefreshButtonState {
	IDLE, # Ready to fetch. Label varies (default/failed/empty-result).
	LOADING, # Request in flight. Disabled.
	NEEDS_AUTH, # No valid PAT. Clicking re-opens the auth dialog.
}

const AuthDialogScene: PackedScene = preload("res://addons/gitot/ui/github_auth_dialog.tscn")

## Hard cap: 8 pages × 50 = 400 issues. A solo/small-team repo scope by design.
const MAX_ISSUE_PAGES: int = 8

## Called by the editor when the user switches to/away from this tab.
var has_fetched: bool = false
var _git_engine: GitEngine
var _issue_list: GithubIssueList
var _dirty_count: int = 0
var _pending_branch: String = ""
var _pending_base: String = ""
var _issues_owner: String = ""
var _issues_repo: String = ""
var _issues_page: int = 1
var _issues_accumulated: Array = [] # Raw JSON items across pages, parsed once complete.

@onready var _api: GithubApi = %GithubApi
@onready var _detail: IssueDetail = %IssueDetail


func _ready() -> void:
	_issue_list = GithubIssueList.new(
		%IssueTree,
		GithubIssueFilter.new(%TypeFilter, %PriorityFilter, %LabelFilter),
	)
	_issue_list.issue_selected.connect(_detail.show_issue)
	_issue_list.selection_cleared.connect(_detail.clear)

	_git_engine.command_completed.connect(_on_command_completed)
	%CreateBranchConfirmDialog.confirmed.connect(_on_create_branch_confirmed)
	_detail.create_branch_requested.connect(_on_create_branch_requested)

	%ClearTokenButton.pressed.connect(_on_clear_token_pressed)
	%RefreshButton.pressed.connect(fetch_current_repo_issues)

	_api.request_succeeded.connect(_on_request_succeeded)
	_api.auth_failed.connect(_on_auth_failed)
	_api.request_failed.connect(_on_request_failed)


func set_plugin_version(plugin_version: String) -> void:
	%GitotVersion2.text = "[b][font_size=24]Gitot[/font_size][/b] [font_size=11]v%s[/font_size]" % plugin_version


func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine


## Parses owner/repo from the origin remote and triggers the fetch.
func fetch_current_repo_issues() -> void:
	var remote_url: String = _git_engine.get_remote_url()
	var owner_repo: Dictionary = GitEngine.parse_owner_repo(remote_url)

	if owner_repo.is_empty():
		GitotLogger.w("Could not parse owner/repo from remote '%s'." % remote_url)
		return

	_issues_owner = owner_repo["owner"]
	_issues_repo = owner_repo["repo"]
	_issues_page = 1
	_issues_accumulated.clear()
	_api.fetch_issues(_issues_owner, _issues_repo, _issues_page)
	_set_refresh_state(RefreshButtonState.LOADING)
	%StatusLabel.visible = false


## Keeps the base-branch dropdown current whenever the branch list refreshes
## (already triggered by switch/create/fetch elsewhere — see gitot_result_router.gd).
func _on_command_completed(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
) -> void:
	if command == GitEngine.Command.BRANCHES and exit_code == 0 and not output.is_empty():
		_detail.set_base_branches(GitBranchParser.parse(output[0]))
	elif command == GitEngine.Command.STATUS and exit_code == 0 and not output.is_empty():
		var parsed: Dictionary = GitStatusParser.parse(output[0])
		_dirty_count = parsed["staged"].size() + parsed["unstaged"].size()


## The result (log, head_moved, branch/status refresh) is handled by the shared router.
func _on_create_branch_requested(branch_name: String, base: String) -> void:
	if _dirty_count == 0:
		_git_engine.create_branch(branch_name, base)
		return
	_pending_branch = branch_name
	_pending_base = base
	%CreateBranchConfirmDialog.dialog_text = (
		"You have %d uncommitted change(s); they will move with you.\nCancel and commit or stash first if you don't want that.\nCreate '%s' from '%s'?"
		% [_dirty_count, branch_name, base]
	)
	%CreateBranchConfirmDialog.popup_centered()


func _on_create_branch_confirmed() -> void:
	_git_engine.create_branch(_pending_branch, _pending_base)


## Refresh button's text/disabled state,
## every transition goes through here so none can forget to reset either.
func _set_refresh_state(state: RefreshButtonState, label: String = "Refresh Issues") -> void:
	match state:
		RefreshButtonState.IDLE:
			%RefreshButton.text = label
			%RefreshButton.disabled = false
		RefreshButtonState.LOADING:
			%RefreshButton.text = "Loading..."
			%RefreshButton.disabled = true
		RefreshButtonState.NEEDS_AUTH:
			%RefreshButton.text = "Enter PAT"
			%RefreshButton.disabled = false


## Accumulates one page; chains to the next page if this one was full and
## under MAX_ISSUE_PAGES, otherwise finalizes (parses + populates the list).
func _on_request_succeeded(data: Variant) -> void:
	if not data is Array:
		_set_refresh_state(RefreshButtonState.IDLE)
		%StatusLabel.visible = false
		return

	_issues_accumulated.append_array(data)
	if data.size() == GithubApi.ISSUES_PER_PAGE and _issues_page < MAX_ISSUE_PAGES:
		_issues_page += 1
		_api.fetch_issues(_issues_owner, _issues_repo, _issues_page) # Stays in LOADING state.
		return

	_set_refresh_state(RefreshButtonState.IDLE)
	%StatusLabel.visible = false
	var entries: Array[Dictionary] = GithubIssueParser.parse(_issues_accumulated)
	_issue_list.populate(entries)
	if entries.is_empty():
		_set_refresh_state(RefreshButtonState.IDLE, "No issues (Refresh)")


## Clears the stored PAT and resets the panel to its pre-fetch state.
func _on_clear_token_pressed() -> void:
	GithubAuth.clear_token()
	has_fetched = false
	_set_refresh_state(RefreshButtonState.NEEDS_AUTH)
	_issue_list.populate([])


func _on_auth_failed() -> void:
	_set_refresh_state(RefreshButtonState.NEEDS_AUTH)
	%StatusLabel.visible = false
	GitotLogger.w("Github token invalid/expired, re-auth needed!")
	var dialog: ConfirmationDialog = AuthDialogScene.instantiate()
	add_child(dialog)
	dialog.confirmed.connect(
		func() -> void:
			fetch_current_repo_issues(),
		CONNECT_ONE_SHOT,
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _on_request_failed(status_code: int) -> void:
	_set_refresh_state(RefreshButtonState.IDLE, "Failed! (Try Again)")
	%StatusLabel.visible = true
	if status_code == 0:
		%StatusLabel.text = "[b][color=orange]Network error - check your connection[/color][/b]"
		GitotLogger.w("Load issues request failed; Network error - Check your connection!")
	else:
		%StatusLabel.text = "[b][color=orange]Failed to load issues (status %d)[/color][/b]" % status_code
		GitotLogger.w("Load issues request failed (status %d)" % status_code)
