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
	_api.request_succeeded.connect(_on_request_succeeded)
	_api.auth_failed.connect(_on_auth_failed)
	_api.request_failed.connect(_on_request_failed)

## Populates the issue list, skipping pull requests.
## Reminder: skip pull requests (item has "pull_request" key) when parsing issues.
func _on_request_succeeded(data: Variant) -> void:
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


func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine


## Parses owner/repo from the origin remote and triggers the fetch.
func fetch_current_repo_issues() -> void:
	var remote_url: String = _git_engine.get_remote_url()
	var regex: RegEx = RegEx.new()
	regex.compile(REMOTE_URL_PATTERN)
	var match_result: RegExMatch = regex.search(remote_url)

	if not match_result:
		push_warning("GithubPanel: could not parse owner/repo from remote '%s'" % remote_url)
		return

	_api.fetch_issues(match_result.get_string(1), match_result.get_string(2))


## Clears the stored PAT and resets the panel to its pre-fetch state.
func _on_clear_token_pressed() -> void:
	GithubAuth.clear_token()
	has_fetched = false
	for child: Node in %IssueList.get_children():
		child.queue_free()


func _on_auth_failed() -> void:
	print_rich("[color=orange]Gitot WARNING: Github token invalid/expired — re-auth needed.[/color]")
	var dialog: ConfirmationDialog = AuthDialogScene.instantiate()
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: fetch_current_repo_issues(), CONNECT_ONE_SHOT)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _on_request_failed(status_code: int) -> void:
	push_warning("GithubPanel: request failed (status %d)" % status_code)
