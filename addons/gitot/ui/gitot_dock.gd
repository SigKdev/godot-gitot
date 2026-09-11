## gitot_dock.gd
## Displays staged/unstaged file trees and triggers manual status refresh.
# Receives a GitEngine reference from the plugin (SoC: this script owns UI only).
@tool
class_name GitotDock
extends Control


## Injected by gitot.gd on dock creation.
var git_engine: GitEngine

var diff_gutter: GitotDiffGutter
var _status_tree: GitotStatusTree
var _tag_panel: GitotTagPanel
var _orchestrator: GitSyncOrchestrator


## Assigns the shared GitEngine instance.
## Called once by gitot.gd after instantiation.
func set_git_engine(engine: GitEngine) -> void:
	git_engine = engine
	git_engine.command_completed.connect(_on_status_result)


func set_sync_orchestrator(orchestrator: GitSyncOrchestrator) -> void:
	_orchestrator = orchestrator
	orchestrator.push_state_changed.connect(_on_push_state_changed)
	orchestrator.tag_retry_needed.connect(_on_tag_retry_needed)
	
## Assigns the shared GitotDiffGutter instance.
## Called once by gitot.gd after instantiation.
func set_diff_gutter(gutter: GitotDiffGutter) -> void:
	diff_gutter = gutter


func _ready() -> void:
	%RefreshStatButton.pressed.connect(_refresh_status)
	%RefreshStatButton.icon = EditorInterface.get_base_control().get_theme_icon("Loop", "EditorIcons")
	%CommitButton.pressed.connect(_on_commit_pressed)
	%PushButton.pressed.connect(_on_push_pressed)
	%PullButton.pressed.connect(_on_pull_pressed)
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	%RefreshDiffButton.icon = EditorInterface.get_base_control().get_theme_icon("Paint", "EditorIcons")
	_status_tree = GitotStatusTree.new(%UnstagedTree, %StagedTree, %UnstagedFold, %StagedFold)
	_status_tree.git_engine = git_engine
	_refresh_status() # Populate trees immediately instead of waiting for manual git status refresh
	
	_tag_panel = GitotTagPanel.new(%TagVersioningToggle, %TagPanel, %UseProjectToggle, %TagNameEdit, %UseCommitToggle, %TagMessageEdit)

	%SettingsToggleButton.icon = EditorInterface.get_base_control().get_theme_icon("GDScript", "EditorIcons")
	%SettingsToggleButton.pressed.connect(
		func() -> void: %SettingsPanel.visible = not %SettingsPanel.visible
	)
	%PushConfirmDialog.confirmed.connect(_do_push)

	%UseCommitToggle.toggled.connect(func(on: bool) -> void: %TagMessageEdit.visible = not on)

	if _orchestrator:
		%RetryTagPushButton.pressed.connect(_orchestrator.retry_tag_push)


## Disconnects this dock from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if git_engine and git_engine.command_completed.is_connected(_on_status_result):
		git_engine.command_completed.disconnect(_on_status_result)


## Manual fallback Triggers a fresh git status query for unreliable save signal.
## (e.g. during editor startup, before the setter runs)
## Shared refresh call. Guards against git_engine not yet injected.
func _refresh_status() -> void:
	if not git_engine:
		return
	git_engine.run_fast("status", GitEngine.STATUS_ARGS)


## Auto-refreshes status when the editor window regains focus,
## gated by the "auto_refresh_on_focus" setting.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if GitotSettings.get_value("auto_refresh_on_focus"):
			_refresh_status()


## Triggers a diff gutter refresh.
## Manual fallback for unreliable save signal.
func _on_refresh_diff_pressed() -> void:
	diff_gutter.refresh_current_script()


## Uses porcelain=v2 for reliable status parsing.
func _on_status_result(command_name: String, exit_code: int, output: Array) -> void:
	if command_name == "commit":
		if exit_code == 0:
			print_rich("[color=green]Gitot: Commit successful.[/color]")
		else:
			print_rich("[color=red]Gitot ERROR: Commit failed.[/color]")
		return

	if command_name in ["push", "pull"]:
		if command_name == "pull":
			%PullButton.disabled = false
			%PullButton.text = "Pull"

		# Strip internal exit-code marker before showing git's raw output to the user.
		var clean_output: String = output[0].replace("EXITCODE:0", "").replace("EXITCODE:1", "").strip_edges()
		if exit_code == 0:
			print_rich("[color=green]Gitot: %s finished.[/color]" % command_name.capitalize())
		else:
			print_rich("[color=red]Gitot ERROR: %s failed.[/color]" % command_name.capitalize())
		if not clean_output.is_empty():
			print(clean_output)
		if command_name == "pull" and exit_code == 0:
			EditorInterface.get_resource_filesystem().scan()
		return

	# Used for refreshing the status tree.
	if command_name != "status" or output.is_empty():
		return
	_status_tree.populate(GitStatusParser.parse(output[0]))


## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if message.is_empty():
		print_rich("[color=orange]Gitot WARNING: commit message is empty, commit aborted.[/color]")
		return
	git_engine.run_fast("commit", ["commit", "-m", message])
	%CommitMessageInput.text = ""


func _on_push_state_changed(pushing: bool) -> void:
	%PushButton.disabled = pushing
	%PushButton.text = "Pushing..." if pushing else "Push"

func _on_tag_retry_needed(needed: bool) -> void:
	%RetryTagPushButton.visible = needed


## Pushes current branch to its remote tracking branch.
## Gated by the "confirm_push" setting to avoid accidental remote pushes.
func _on_push_pressed() -> void:
	if GitotSettings.get_value("confirm_push"):
		%PushConfirmDialog.popup_centered()
	else:
		_do_push()


## Executes the actual push — called directly or after dialog confirmation.
func _do_push() -> void:
	var tag_input: Dictionary = _tag_panel.get_tag_input(git_engine.get_last_commit_message())
	if _tag_panel.is_enabled():
		if tag_input["tag_name"].is_empty():
			print_rich("[color=orange]Gitot WARNING: tag name is empty, push aborted.[/color]")
			return
		if tag_input["tag_message"].is_empty():
			print_rich("[color=orange]Gitot WARNING: tag message is empty, push aborted.[/color]")
			return
	_orchestrator.start_push(tag_input)


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	%PullButton.disabled = true
	%PullButton.text = "Pulling..."
	git_engine.run_network("pull", ["pull"])
