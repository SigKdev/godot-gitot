## github_panel.gd
## Central panel for the GitHub Issues Task Board.
@tool
extends Control

const IssueCardScene: PackedScene = preload("res://addons/gitot/ui/issue_card.tscn")

const AuthDialogScene: PackedScene = preload("res://addons/gitot/ui/github_auth_dialog.tscn")

const REMOTE_URL_PATTERN: String = "github\\.com[:/]([^/]+)/([^/.]+)"

@onready var _api: GithubApi = %GithubApi

## Injected the same way git_engine is injected into the dock (setter, not direct assignment).
var _git_engine: GitEngine

## Called by the editor when the user switches to/away from this tab.
var has_fetched: bool = false


func _ready() -> void:
	%ClearTokenButton.pressed.connect(_on_clear_token_pressed)
	%RefreshButton.pressed.connect(fetch_current_repo_issues)
	_api.request_succeeded.connect(_on_request_succeeded)
	_api.auth_failed.connect(_on_auth_failed)
	_api.request_failed.connect(_on_request_failed)

## Populates the issue list, skipping pull requests.
## Reminder: skip pull requests (item has "pull_request" key) when parsing issues.
func _on_request_succeeded(data: Variant) -> void:
	%RefreshButton.disabled = false
	%RefreshButton.text = "Refresh Issues"
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
		%RefreshButton.text = "No issues (Refresh)"
		%StatusLabel.visible = false


func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine


## Parses owner/repo from the origin remote and triggers the fetch.
func fetch_current_repo_issues() -> void:
	var remote_url: String = _git_engine.get_remote_url()
	var regex: RegEx = RegEx.new()
	regex.compile(REMOTE_URL_PATTERN)
	var match_result: RegExMatch = regex.search(remote_url)

	if not match_result:
		print_rich("[color=orange]Gitot WARNING: could not parse owner/repo from remote '%s'.[/color]" % remote_url)
		return

	_api.fetch_issues(match_result.get_string(1), match_result.get_string(2))
	%RefreshButton.disabled = true
	%RefreshButton.text = "Loading..."
	%StatusLabel.visible = false


## Clears the stored PAT and resets the panel to its pre-fetch state.
func _on_clear_token_pressed() -> void:
	GithubAuth.clear_token()
	has_fetched = false
	for child: Node in %IssueList.get_children():
		child.queue_free()


func _on_auth_failed() -> void:
	%RefreshButton.disabled = false
	%StatusLabel.visible = false
	print_rich("[color=orange]Gitot WARNING: Github token invalid/expired — re-auth needed.[/color]")
	var dialog: ConfirmationDialog = AuthDialogScene.instantiate()
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: fetch_current_repo_issues(), CONNECT_ONE_SHOT)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _on_request_failed(status_code: int) -> void:
	%RefreshButton.disabled = false
	%RefreshButton.text = "Failed! (Try Again)"
	%StatusLabel.visible = true
	if status_code == 0:
		%StatusLabel.text = "[b][color=orange]Network error - check your connection[/color][/b]"
		print_rich("[color=orange]Gitot WARNING: load issues request failed; Network error - check your connection.[/color]")
	else:
		%StatusLabel.text = "[b][color=orange]Failed to load issues (status %d)[/color][/b]" % status_code
		print_rich("[color=orange]Gitot WARNING: load issues request failed (status %d).[/color]" % status_code)
