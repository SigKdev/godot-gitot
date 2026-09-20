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

const IssueCardScene: PackedScene = preload("res://addons/gitot/ui/issue_card.tscn")

const AuthDialogScene: PackedScene = preload("res://addons/gitot/ui/github_auth_dialog.tscn")

## Called by the editor when the user switches to/away from this tab.
var has_fetched: bool = false
var _git_engine: GitEngine

@onready var _api: GithubApi = %GithubApi


func _ready() -> void:
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

	_api.fetch_issues(owner_repo["owner"], owner_repo["repo"])
	_set_refresh_state(RefreshButtonState.LOADING)
	%StatusLabel.visible = false


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


## Populates the issue list, skipping pull requests.
## Reminder: skip pull requests (item has "pull_request" key) when parsing issues.
func _on_request_succeeded(data: Variant) -> void:
	_set_refresh_state(RefreshButtonState.IDLE)
	%StatusLabel.visible = false
	if data == null or not data is Array:
		return

	# Clear previous cards before repopulating.
	for child: Node in %IssueList.get_children():
		child.queue_free()

	for item: Dictionary in data:
		if item.has("pull_request"):
			continue # skip PRs — issues-as-tasks only, v1 scope
		var card: PanelContainer = IssueCardScene.instantiate()
		%IssueList.add_child(card)
		card.setup(item)
		%IssueList.add_child(HSeparator.new())

	if %IssueList.get_child_count() == 0:
		_set_refresh_state(RefreshButtonState.IDLE, "No issues (Refresh)")
		%StatusLabel.visible = false


## Clears the stored PAT and resets the panel to its pre-fetch state.
func _on_clear_token_pressed() -> void:
	GithubAuth.clear_token()
	has_fetched = false
	_set_refresh_state(RefreshButtonState.NEEDS_AUTH)
	for child: Node in %IssueList.get_children():
		child.queue_free()


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
