## gitot_dock.gd
## Displays staged/unstaged file trees and triggers manual status refresh.
# Receives a GitEngine reference from the plugin (SoC: this script owns UI only).
@tool
class_name GitotDock
extends Control


## Injected by gitot.gd on dock creation.
var git_engine: GitEngine
var _log_console: GitotLogConsole
var _status_tree: GitotStatusTree
var _log_panel: GitLogPanel
var _tag_panel: GitotTagPanel
var _orchestrator: GitSyncOrchestrator
var _branch_panel: GitotBranchPanel
var diff_gutter: GitotDiffGutter


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
	%StashButton.pressed.connect(_on_stash_pressed)
	%StashButton.icon = EditorInterface.get_base_control().get_theme_icon("Bake", "EditorIcons")
	%PopButton.pressed.connect(_on_pop_pressed)
	%PopButton.icon = EditorInterface.get_base_control().get_theme_icon("LightmapGIData", "EditorIcons")
	%PushButton.pressed.connect(_on_push_pressed)
	%PushButton.icon = EditorInterface.get_base_control().get_theme_icon("MoveUp", "EditorIcons")
	%PullButton.pressed.connect(_on_pull_pressed)
	%PullButton.icon = EditorInterface.get_base_control().get_theme_icon("MoveDown", "EditorIcons")
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	%RefreshDiffButton.icon = EditorInterface.get_base_control().get_theme_icon("Paint", "EditorIcons")
	_status_tree = GitotStatusTree.new(%UnstagedTree, %StagedTree, %UnstagedFold, %StagedFold)
	_status_tree.git_engine = git_engine
	_log_panel = GitLogPanel.new(git_engine, %GitlogFold, %GitlogTree)
	_refresh_status() # Populate trees immediately instead of waiting for manual git status refresh
	_log_console = GitotLogConsole.new(%LogList, %LogScroll)
	
	_tag_panel = GitotTagPanel.new(%TagVersioningToggle, %TagPanel, %UseProjectToggle, %TagNameEdit, %UseCommitToggle, %TagMessageEdit)
	
	_branch_panel = GitotBranchPanel.new(
	git_engine, %BranchDropdown, %CreateBranchButton, %NewBranchDialog, %NewBranchNameInput
	)
	%CreateBranchButton.icon = EditorInterface.get_base_control().get_theme_icon("Add", "EditorIcons")
	if git_engine:
		git_engine.list_branches()

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
	if _log_console:
		_log_console.teardown()


## Public passthrough for gitot.gd (composition root owns *when* to refresh).
func refresh_log() -> void:
	_log_panel.refresh()


## Manual fallback Triggers a fresh git status query for unreliable save signal.
## (e.g. during editor startup, before the setter runs)
## Shared refresh call. Guards against git_engine not yet injected.
func _refresh_status() -> void:
	if not git_engine:
		return
	git_engine.run_fast("status", GitEngine.STATUS_ARGS)
	_log_panel.refresh()


## Notifies Godot about files changed by the branch switch. update_file()
## refreshes EditorFileSystem's cache; any of those files currently open
## in a scene tab also needs an explicit reload_scene_from_path(), since
## update_file() alone doesn't touch the open tab's in-memory ResourceLoader cache.
func _notify_changed_files() -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()

	for relative_path in git_engine.get_changed_files_since_switch():
		var res_path: String = "res://" + relative_path
		if not FileAccess.file_exists(res_path):
			continue
		fs.update_file(res_path)
		if res_path in open_scenes:
			EditorInterface.reload_scene_from_path(res_path)


## Auto-refreshes status when the editor window regains focus,
## gated by the "auto_refresh_on_focus" setting.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if GitotSettings.get_value("auto_refresh_on_focus"):
			_refresh_status()


# TODO: diff gutter refresh
## Triggers a diff gutter refresh.
## Manual fallback for unreliable save signal.
func _on_refresh_diff_pressed() -> void:
	diff_gutter.refresh_current_script()


## Uses porcelain=v2 for reliable status parsing.
func _on_status_result(command_name: String, exit_code: int, output: Array) -> void:
	if command_name == "commit":
		if exit_code == 0:
			GitotLogger.s("Commit successful.")
		else:
			GitotLogger.x("Commit failed.")
		return

	if command_name == "stash":
		if exit_code == 0:
			if output[0].contains("No local changes to save"):
				GitotLogger.w("Nothing to stash.")
			else:
				GitotLogger.s("Changes stashed.")
		else:
			GitotLogger.e("Stash failed.")
			if not output.is_empty():
				GitotLogger.g(output[0])
		return

	if command_name == "stash_pop":
		if exit_code == 0:
			GitotLogger.s("Stash popped.")
		else:
			GitotLogger.e("Pop failed (conflict or empty stack). Check files for conflict markers.")
			if not output.is_empty():
				GitotLogger.g(output[0])
		return

	if command_name in ["push", "pull"]:
		if command_name == "pull":
			%PullButton.disabled = false
			%PullButton.text = "Pull"

		# Strip internal exit-code marker before showing git's raw output to the user.
		var clean_output: String = output[0].replace("EXITCODE:0", "").replace("EXITCODE:1", "").strip_edges()
		if exit_code == 0:
			GitotLogger.s("%s finished." % command_name.capitalize())
		else:
			GitotLogger.e("%s failed." % command_name.capitalize())
		if not clean_output.is_empty():
			GitotLogger.g(clean_output) # git's raw stderr
		if command_name == "pull" and exit_code == 0:
			EditorInterface.get_resource_filesystem().scan()
		return

	if command_name == "branches":
		if not output.is_empty():
			_branch_panel.populate(GitBranchParser.parse(output[0]))
		return

	if command_name in ["switch", "create_branch"]:
		if exit_code == 0:
			GitotLogger.s("%s successful, now on '[color=gray]%s[/color]'" % [command_name.capitalize(), git_engine.get_current_branch()])
			_notify_changed_files()
		else:
			GitotLogger.e("%s failed." % command_name.capitalize())
			if not output.is_empty():
				GitotLogger.g(output[0]) # git's raw stderr
		git_engine.list_branches()
		return

	if command_name == "log":
		if not output.is_empty():
			_log_panel.populate(GitLogParser.parse(output[0]))
		return

	# Used for refreshing the status tree.
	if command_name != "status" or output.is_empty():
		return
	_status_tree.populate(GitStatusParser.parse(output[0]))


## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if message.is_empty():
		GitotLogger.w("Commit message is empty. Commit aborted!")
		return
	git_engine.run_fast("commit", ["commit", "-m", message])
	%CommitMessageInput.text = ""


## Shelves all uncommitted changes onto the stash stack.
func _on_stash_pressed() -> void:
	git_engine.stash_push()


## Reapplies and removes the most recent stash entry.
func _on_pop_pressed() -> void:
	git_engine.stash_pop()


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
			GitotLogger.w("Tag name is empty. Push aborted!")
			return
		if tag_input["tag_message"].is_empty():
			GitotLogger.w("Tag message is empty. Push aborted!")
			return
	_orchestrator.start_push(tag_input)


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	%PullButton.disabled = true
	%PullButton.text = "Pulling..."
	git_engine.run_network("pull", ["pull"])
