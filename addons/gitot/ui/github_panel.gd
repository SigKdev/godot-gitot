## github_panel.gd
## Issues tab: fetches the open issues of the origin repo and shows them as a list with a detail pane.
@tool
class_name GithubPanel
extends Control

enum RefreshButtonState {
	IDLE, # Ready to fetch. Label varies (default/failed/empty-result).
	LOADING, # Request in flight. Disabled.
	NEEDS_AUTH, # No valid PAT. Clicking re-opens the auth dialog.
}

const AuthDialogScene: PackedScene = preload("res://addons/gitot/ui/github_auth_dialog.tscn")

## Hard cap on fetched pages (MAX_ISSUE_PAGES x GithubApi.ISSUES_PER_PAGE issues).
## Sized for solo/small-team repos.
const MAX_ISSUE_PAGES: int = 8

## Context tag marking the REMOTE_URL request made by this panel (the dock makes its own).
const REMOTE_URL_ISSUES: String = "issues"

## True once gitot.gd requested the issues this session (first tab show); reset when the token is cleared.
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
@onready var _repo_label: Label = %RepoLabel


## Header text: "owner/repo" while the count is unknown (negative), else "owner/repo  ·  3 open".
## The list only holds open issues (state=open) without pull requests, so the count is exact.
static func _header_text(owner: String, repo: String, open_count: int) -> String:
	if owner.is_empty():
		return "Open issues"
	var text: String = "%s/%s" % [owner, repo]
	return text if open_count < 0 else "%s  ·  %d open" % [text, open_count]


func _ready() -> void:
	_issue_list = GithubIssueList.new(
		%IssueTree,
		GithubIssueFilter.new(%TypeFilter, %PriorityFilter, %LabelFilter),
	)
	_issue_list.issue_selected.connect(_detail.show_issue)
	_issue_list.selection_cleared.connect(_detail.clear)

	if not _git_engine:
		return # editor-instantiated scene: no engine injected, nothing to wire
	_git_engine.command_completed.connect(_on_command_completed)
	%CreateBranchConfirmDialog.confirmed.connect(_on_create_branch_confirmed)
	_detail.create_branch_requested.connect(_on_create_branch_requested)

	%ClearTokenButton.pressed.connect(_on_clear_token_pressed)
	%RefreshButton.pressed.connect(fetch_current_repo_issues)

	_api.request_succeeded.connect(_on_request_succeeded)
	_api.auth_failed.connect(_on_auth_failed)
	_api.request_failed.connect(_on_request_failed)


func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine


## Asks git for the origin remote; the fetch starts in _start_issue_fetch() once it answers.
## LOADING at once: the async answer must not leave a window for a second click.
func fetch_current_repo_issues() -> void:
	_set_refresh_state(RefreshButtonState.LOADING)
	%StatusLabel.visible = false
	_git_engine.request_remote_url({ "for": REMOTE_URL_ISSUES })


## Parses owner/repo from the origin URL and starts the first page.
func _start_issue_fetch(remote_url: String) -> void:
	var owner_repo: Dictionary = GitEngine.parse_owner_repo(remote_url)
	if owner_repo.is_empty():
		GitotLogger.w("Could not parse owner/repo from remote '%s'." % remote_url)
		_set_refresh_state(RefreshButtonState.IDLE)
		return

	_issues_owner = owner_repo["owner"]
	_issues_repo = owner_repo["repo"]
	_issues_page = 1
	_issues_accumulated.clear()
	_repo_label.text = _header_text(_issues_owner, _issues_repo, -1)
	_api.fetch_issues(_issues_owner, _issues_repo, _issues_page)


## Handles engine results: REMOTE_URL (our own request) starts the issue fetch, BRANCHES refreshes
## the base-branch dropdown, STATUS updates the uncommitted-change count. BRANCHES and STATUS are
## already requested elsewhere (see gitot_result_router.gd).
func _on_command_completed(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if command == GitEngine.Command.REMOTE_URL:
		if context.get("for", "") == REMOTE_URL_ISSUES: # The dock's own request is not ours.
			_start_issue_fetch(GitEngine.remote_url_of(exit_code, output))
	elif command == GitEngine.Command.BRANCHES and exit_code == 0 and not output.is_empty():
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


## Sets the Refresh button's text and disabled state. Every transition goes through here, so
## neither is left stale.
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
	_repo_label.text = _header_text(_issues_owner, _issues_repo, entries.size())
	if entries.is_empty():
		_set_refresh_state(RefreshButtonState.IDLE, "No issues (Refresh)")


## Clears the stored PAT and resets the panel to its pre-fetch state.
func _on_clear_token_pressed() -> void:
	GithubAuth.clear_token()
	has_fetched = false
	_set_refresh_state(RefreshButtonState.NEEDS_AUTH)
	_repo_label.text = _header_text(_issues_owner, _issues_repo, -1)
	_issue_list.populate([])


func _on_auth_failed() -> void:
	_set_refresh_state(RefreshButtonState.NEEDS_AUTH)
	%StatusLabel.visible = false
	GitotLogger.w("GitHub token is invalid or expired - sign in again.")
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
		GitotLogger.fail(
			"Loading issues from GitHub failed: no answer from the network.",
			"",
			"Common fail causes: no internet, or GitHub is unreachable.",
		)
	else:
		%StatusLabel.text = "[b][color=orange]Failed to load issues (status %d)[/color][/b]" % status_code
		GitotLogger.e("Loading issues from GitHub failed (HTTP status %d)." % status_code)
