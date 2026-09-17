## gitot_dock.gd
## Default dock for the Gitot plugin. Contains all UI elements,
## and delegates git commands to the shared GitEngine instance.
@tool
class_name GitotDock
extends Control

var _git_engine: GitEngine
var _ready_initialized: bool = false

var _diff_gutter: GitotDiffGutter
var _log_console: GitotLogConsole
var _status_tree: GitotStatusTree
var _status_panel: GitotStatusPanel
var _log_panel: GitLogPanel
var _tag_panel: GitotTagPanel
var _orchestrator: GitSyncOrchestrator
var _branch_panel: GitotBranchPanel

const PLUGIN_CONFIG_PATH: String = "res://addons/gitot/plugin.cfg"


## Determines whether a branch exists locally, remotely, or both.
static func _get_branch_scope(
	branch_name: String,
	branches: Array[Dictionary],
) -> String:
	var local_exists: bool = false
	var remote_exists: bool = false

	for branch: Dictionary in branches:
		if branch["is_remote"]:
			if branch["name"] == "origin/" + branch_name:
				remote_exists = true
		elif branch["name"] == branch_name:
			local_exists = true

	if local_exists and remote_exists:
		return "(Local + Remote)"
	if remote_exists:
		return "(Remote)"
	return "(Local)"


func _ready() -> void:
	if not _git_engine:
		# GitEngine not yet injected — known Godot editor-plugin timing quirk where
		# a @tool dock's _ready() can fire before the EditorPlugin's _enter_tree()
		# finishes calling set_git_engine(). Retry once the current frame's
		# synchronous injection work has completed.
		_ready.call_deferred()
		return
	if _ready_initialized:
		return
	_ready_initialized = true

	#region Version label
	var plugin_version: String = _read_plugin_version()
	%GitotVersion.text = (
		"[b][font_size=14]Gitot[/font_size][/b] [font_size=9]v%s[/font_size]" % plugin_version
	)
	call_deferred("_set_github_panel_version", plugin_version)
	#endregion

	#region Toolbar buttons
	%RefreshStatButton.pressed.connect(_refresh_status)
	%RefreshStatButton.icon = _icon("Loop")
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	%RefreshDiffButton.icon = _icon("Paint")
	%CommitButton.pressed.connect(_on_commit_pressed)
	%StashButton.pressed.connect(_on_stash_pressed)
	%StashButton.icon = _icon("Bake")
	%PopButton.pressed.connect(_on_pop_pressed)
	%PopButton.icon = _icon("LightmapGIData")
	%PushButton.pressed.connect(_on_push_pressed)
	%PushButton.icon = _icon("MoveUp")
	%PullButton.pressed.connect(_on_pull_pressed)
	%PullButton.icon = _icon("MoveDown")
	%FetchButton.pressed.connect(_on_fetch_pressed)
	%FetchButton.icon = _icon("AssetStore")
	#endregion

	#region Panel construction
	# order matters: status_tree/status_panel/log_panel,
	#must exist before _refresh_status() reads them below.
	_status_tree = GitotStatusTree.new(
		_git_engine,
		%UnstagedTree,
		%StagedTree,
		%UnstagedFold,
		%StagedFold,
	)
	_status_panel = GitotStatusPanel.new(%GitStatusLabel)

	var owner_repo: Dictionary = GitEngine.parse_owner_repo(_git_engine.get_remote_url())
	_status_panel.update_repo("%s/%s" % [owner_repo.get("owner", ""), owner_repo.get("repo", "")])
	_log_panel = GitLogPanel.new(_git_engine, %GitlogFold, %GitlogTree)
	_refresh_status() # Populate trees immediately instead of waiting for manual git status refresh
	_log_console = GitotLogConsole.new(%LogList, %LogScroll)

	_tag_panel = GitotTagPanel.new(
		%TagVersioningToggle,
		%TagPanel,
		%UseProjectToggle,
		%TagNameEdit,
		%UseCommitToggle,
		%TagMessageEdit,
	)

	_branch_panel = GitotBranchPanel.new(
		_git_engine,
		%BranchDropdown,
		%CreateBranchButton,
		%NewBranchDialog,
		%NewBranchNameInput,
	)
	%CreateBranchButton.icon = _icon("Add")
	if _git_engine:
		_git_engine.list_branches()
		_status_panel.update_branch(_git_engine.get_current_branch())
	#endregion

	#region Settings & dialogs
	%SettingsToggleButton.icon = _icon("GDScript")
	%SettingsToggleButton.pressed.connect(
		func() -> void:
			%SettingsPanel.visible = not %SettingsPanel.visible,
	)
	%PushConfirmDialog.confirmed.connect(_do_push)

	%UseCommitToggle.toggled.connect(
		func(on: bool) -> void:
			%TagMessageEdit.visible = not on,
	)

	if _orchestrator:
		%RetryTagPushButton.pressed.connect(_orchestrator.retry_tag_push)
	#endregion

## Auto-refreshes status when the editor window regains focus,
## gated by the "auto_refresh_on_focus" setting.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if GitotSettings.get_value("auto_refresh_on_focus"):
			_refresh_status()


func _read_plugin_version() -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(PLUGIN_CONFIG_PATH) != OK:
		return ""
	return str(config.get_value("plugin", "version", ""))


func _set_github_panel_version(plugin_version: String) -> void:
	var github_panel: Node = EditorInterface.get_editor_main_screen().find_child(
		"GithubPanel",
		true,
		false,
	)
	if github_panel and github_panel.has_method("set_plugin_version"):
		github_panel.set_plugin_version(plugin_version)


## Assigns the shared GitEngine instance.
## Called once by gitot.gd after instantiation.
func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine
	_git_engine.command_completed.connect(_on_status_result)


func set_sync_orchestrator(orchestrator: GitSyncOrchestrator) -> void:
	_orchestrator = orchestrator
	orchestrator.push_state_changed.connect(_on_push_state_changed)
	orchestrator.tag_retry_needed.connect(_on_tag_retry_needed)


## Assigns the shared GitotDiffGutter instance.
## Called once by gitot.gd after instantiation.
func set_diff_gutter(gutter: GitotDiffGutter) -> void:
	_diff_gutter = gutter


## Disconnects this dock from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if _git_engine and _git_engine.command_completed.is_connected(_on_status_result):
		_git_engine.command_completed.disconnect(_on_status_result)
	if _log_console:
		_log_console.teardown()


## Public passthrough for gitot.gd (composition root owns *when* to refresh).
func refresh_log() -> void:
	_log_panel.refresh()


## Manual fallback Triggers a fresh git status query for unreliable save signal.
## (e.g. during editor startup, before the setter runs)
## Shared refresh call. Guards against git_engine not yet injected.
func _refresh_status() -> void:
	if not _git_engine:
		return
	_git_engine.run_fast(GitEngine.Command.STATUS, GitEngine.STATUS_ARGS)
	_git_engine.get_ahead_behind()
	_log_panel.refresh()


## Notifies Godot about files changed by the branch switch. update_file()
## refreshes EditorFileSystem's cache; any of those files currently open
## in a scene tab also needs an explicit reload_scene_from_path(), since
## update_file() alone doesn't touch the open tab's in-memory ResourceLoader cache.
func _notify_changed_files() -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()

	for relative_path in _git_engine.get_changed_files_since_switch():
		var res_path: String = "res://" + relative_path
		if not FileAccess.file_exists(res_path):
			continue
		fs.update_file(res_path)
		if res_path in open_scenes:
			EditorInterface.reload_scene_from_path(res_path)


## Button icon helper. Avoids repeating the long EditorInterface.get_base_control() chain.
func _icon(name: String) -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(name, &"EditorIcons")


## Triggers a diff gutter refresh.
## Manual fallback for unreliable save signal.
func _on_refresh_diff_pressed() -> void:
	_diff_gutter.refresh_current_script()

#region Status Result
## Routes a finished GitEngine command to its domain handler.
func _on_status_result(command: GitEngine.Command, exit_code: int, output: Array) -> void:
	match command:
		GitEngine.Command.COMMIT:
			_handle_commit_result(exit_code)
		GitEngine.Command.STASH, GitEngine.Command.STASH_POP:
			_handle_stash_result(command, exit_code, output)
		GitEngine.Command.FETCH, GitEngine.Command.AHEAD_BEHIND, GitEngine.Command.PUSH, GitEngine.Command.PULL:
			_handle_sync_result(command, exit_code, output)
		GitEngine.Command.BRANCHES, GitEngine.Command.SWITCH, GitEngine.Command.CREATE_BRANCH:
			_handle_branch_result(command, exit_code, output)
		GitEngine.Command.LOG:
			_handle_log_result(output)
		GitEngine.Command.STATUS:
			_handle_status_result(output)


## Handles the result of a commit command, logging success or failure.
func _handle_commit_result(exit_code: int) -> void:
	if exit_code == 0:
		GitotLogger.s("Commit successful.")
	else:
		GitotLogger.x("Commit failed.")


## Handles the result of a stash or stash_pop command, logging success or failure.
func _handle_stash_result(command: GitEngine.Command, exit_code: int, output: Array) -> void:
	if command == GitEngine.Command.STASH:
		if exit_code == 0:
			if not output.is_empty() and output[0].contains("No local changes to save"):
				GitotLogger.w("Nothing to stash.")
			else:
				GitotLogger.s("Changes stashed.")
		else:
			GitotLogger.e("Stash failed.")
			if not output.is_empty():
				GitotLogger.g(output[0])
		return

	# stash_pop
	if exit_code == 0:
		GitotLogger.s("Stash popped.")
	else:
		GitotLogger.e("Pop failed (conflict or empty stack). Check files for conflict markers.")
		if not output.is_empty():
			GitotLogger.g(output[0])


## Fetch / ahead-behind / push / pull — everything touching remote sync status.
func _handle_sync_result(command: GitEngine.Command, exit_code: int, output: Array) -> void:
	if command == GitEngine.Command.FETCH:
		%FetchButton.disabled = false
		%FetchButton.icon = _icon("AssetStore")
		if exit_code == 0:
			GitotLogger.s("Fetch finished.")
			_git_engine.list_branches() # new remote branches only become visible after fetch
			_git_engine.get_ahead_behind() # keep sync status current with new remote refs
		else:
			GitotLogger.e("Fetch failed.")
		if not output[0].is_empty():
			GitotLogger.g(output[0])
		return

	if command == GitEngine.Command.AHEAD_BEHIND:
		if exit_code != 0 or output.is_empty():
			_status_panel.update_sync(0, 0)
			return
		var parts: PackedStringArray = output[0].strip_edges().split("\t")
		if parts.size() != 2:
			return
		var behind: int = int(parts[0])
		var ahead: int = int(parts[1])
		if _status_panel.update_sync(ahead, behind) and (ahead > 0 or behind > 0):
			GitotLogger.i("Current branch is %d ahead, %d behind origin." % [ahead, behind])
		return

	# push / pull
	if command == GitEngine.Command.PULL:
		%PullButton.disabled = false
		%PullButton.icon = _icon("MoveDown")

	var display_name: String = GitEngine.Command.keys()[command].capitalize()
	if exit_code == 0:
		GitotLogger.s("%s finished." % display_name)
	else:
		GitotLogger.e("%s failed." % display_name)
	if not output[0].is_empty():
		GitotLogger.g(output[0]) # git's raw stderr
	if command == GitEngine.Command.PULL and exit_code == 0:
		EditorInterface.get_resource_filesystem().scan()


## Branch list refresh, switch, and create — everything that changes HEAD or the dropdown.
func _handle_branch_result(command: GitEngine.Command, exit_code: int, output: Array) -> void:
	if command == GitEngine.Command.BRANCHES:
		if not output.is_empty():
			var branches: Array[Dictionary] = GitBranchParser.parse(output[0])
			var branch_scopes: Dictionary[String, String] = {}

			for branch: Dictionary in branches:
				if branch["is_remote"]:
					branch_scopes[branch["name"]] = "Remote"
				else:
					branch_scopes[branch["name"]] = _get_branch_scope(
						branch["name"],
						branches,
					)

			_branch_panel.populate(branches, branch_scopes)

			var current_branch: String = _git_engine.get_current_branch()
			_status_panel.update_branch(
				current_branch,
				branch_scopes.get(current_branch, ""),
			)
		return

	# switch / create_branch
	var display_name: String = GitEngine.Command.keys()[command].capitalize()
	if exit_code == 0:
		GitotLogger.s(
			"%s successful, now on '[color=gray]%s[/color]'"
			% [display_name, _git_engine.get_current_branch()]
		)
		_notify_changed_files()
	else:
		GitotLogger.e("%s failed." % display_name)
		if not output.is_empty():
			GitotLogger.g(output[0]) # git's raw stderr
	_git_engine.list_branches()
	_status_panel.update_branch(_git_engine.get_current_branch())


## Handles the result of a log command, populating the log panel.
func _handle_log_result(output: Array) -> void:
	if not output.is_empty():
		_log_panel.populate(GitLogParser.parse(output[0]))


## Refreshes the status tree.
func _handle_status_result(output: Array) -> void:
	if output.is_empty():
		return
	var parsed: Dictionary = GitStatusParser.parse(output[0])
	_status_tree.populate(parsed)
#endregion

## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if message.is_empty():
		GitotLogger.w("Commit message is empty. Commit aborted!")
		return
	_git_engine.run_fast(GitEngine.Command.COMMIT, ["commit", "-m", message])
	%CommitMessageInput.text = ""


## Shelves all uncommitted changes onto the stash stack.
func _on_stash_pressed() -> void:
	_git_engine.stash_push()


## Reapplies and removes the most recent stash entry.
func _on_pop_pressed() -> void:
	_git_engine.stash_pop()


func _on_push_state_changed(pushing: bool) -> void:
	%PushButton.disabled = pushing
	%PushButton.icon = (
		_icon("Time")
		if pushing
		else EditorInterface \
				.get_base_control() \
				.get_theme_icon("MoveUp", "EditorIcons")
	)


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
	var tag_input: Dictionary = _tag_panel.get_tag_input(_git_engine.get_last_commit_message())
	if _tag_panel.is_enabled():
		if tag_input["tag_name"].is_empty():
			GitotLogger.w("Tag name is empty. Push aborted!")
			return
		if tag_input["tag_message"].is_empty():
			GitotLogger.w("Tag message is empty. Push aborted!")
			return
	_orchestrator.start_push(tag_input)


## Fetches remote refs (no working-tree changes).
func _on_fetch_pressed() -> void:
	%FetchButton.disabled = true
	%FetchButton.icon = _icon("Time")
	_git_engine.fetch()


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	%PullButton.disabled = true
	%PullButton.icon = _icon("Time")
	_git_engine.pull()
