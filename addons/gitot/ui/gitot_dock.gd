## gitot_dock.gd
## Main dock for the Gitot plugin. Contains all UI elements,
## and delegates git commands to the shared GitEngine instance.
@tool
class_name GitotDock
extends Control

## Forwarded from the history list (signal up; gitot.gd owns the diff panel).
signal commit_selected(entry: Dictionary)

const PLUGIN_CONFIG_PATH: String = "res://addons/gitot/plugin.cfg"

# Caps _ready()'s self-retry when _git_engine never arrives.
const MAX_READY_RETRIES: int = 30

var _ready_retry_count: int = 0

var _git_engine: GitEngine
var _lfs: GitLfs
var _ready_initialized: bool = false
var _diff_gutter: GitotDiffGutter
var _log_console: GitotLogConsole
var _status_tree: GitotStatusTree
var _status_panel: GitotStatusPanel
var _log_panel: GitLogPanel
var _stash_panel: GitotStashPanel
var _tag_panel: GitotTagPanel
var _orchestrator: GitSyncOrchestrator
var _branch_panel: GitotBranchPanel
var _branch_creator: GitotBranchCreator
var _branch_deleter: GitotBranchDeleter
var _result_router: GitotResultRouter
var _default_push_confirm_text: String = ""
## Computed once in _on_push_pressed(), reused by _do_push() -> orchestrator.start_push() -
## avoids a second needs_force_push() git call for the same push action.
var _needs_force_push: bool = false


func _ready() -> void:
	if not _git_engine:
		# GitEngine not yet injected — either the normal @tool-dock timing quirk
		# (resolves within a frame or two) or an orphaned instance the editor
		# spawned outside gitot.gd's flow (never resolves — give up past the cap).
		_ready_retry_count += 1
		if _ready_retry_count > MAX_READY_RETRIES:
			GitotLogger.e("GitEngine never injected - dock disabled.")
			return
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
	%RefreshStatButton.pressed.connect(refresh_status)
	%RefreshStatButton.icon = GitotUi.get_icon("Loop")
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	%RefreshDiffButton.icon = GitotUi.get_icon("Paint")
	%CommitButton.pressed.connect(_on_commit_pressed)
	%PushButton.pressed.connect(_on_push_pressed)
	%PushButton.icon = GitotUi.get_icon("MoveUp")
	%PullButton.pressed.connect(_on_pull_pressed)
	%PullButton.icon = GitotUi.get_icon("MoveDown")
	%KofiButton.icon = GitotUi.get_icon("Heart")
	%KofiButton.pressed.connect(_on_kofibutton_pressed)
	#endregion

	#region Panel construction
	_status_tree = GitotStatusTree.new(
		_git_engine,
		%UnstagedTree,
		%StagedTree,
		%UnstagedFold,
		%StagedFold,
		_lfs,
	)
	_status_panel = GitotStatusPanel.new(%GitStatusLabel)

	var owner_repo: Dictionary = GitEngine.parse_owner_repo(_git_engine.get_remote_url())
	var repo_label: String = "%s/%s" % [owner_repo["owner"], owner_repo["repo"]] if not owner_repo.is_empty() else ""
	_status_panel.update_repo(repo_label)
	_log_panel = GitLogPanel.new(_git_engine, %GitlogFold, %GitlogTree)
	_stash_panel = GitotStashPanel.new(
		_git_engine,
		%StashFold,
		%StashTree,
		%StashNameEdit,
		%StashDropDialog,
	)
	refresh_status() # Populate trees immediately instead of waiting for manual git status refresh
	_log_console = GitotLogConsole.new(_git_engine, %LogList, %LogScroll, %OutputLogFold)
	_log_panel.commit_selected.connect(commit_selected.emit)

	_tag_panel = GitotTagPanel.new(
		%TagVersioningToggle,
		%TagPanel,
		%UseProjectToggle,
		%TagNameEdit,
		%UseCommitToggle,
		%TagMessageEdit,
	)

	_branch_panel = GitotBranchPanel.new(_git_engine, %BranchFold, %BranchTree)
	_branch_creator = GitotBranchCreator.new(
		_git_engine,
		%BranchFold,
		%CreateBranchRow,
		%BranchNameEdit,
		%CreateBranchButton,
		%CreateBranchConfirmDialog,
	)
	_branch_deleter = GitotBranchDeleter.new(_git_engine, %BranchFold, %DeleteBranchConfirmDialog)
	_branch_panel.selection_changed.connect(_branch_deleter.on_selection_changed)

	_result_router = GitotResultRouter.new(
		_git_engine,
		_status_panel,
		_status_tree,
		_branch_panel,
		_log_panel,
		_stash_panel,
	)
	_result_router.head_moved.connect(_notify_changed_files)
	_result_router.stash_popped.connect(_notify_file_list)
	_result_router.file_restored.connect(_notify_single_file_changed)
	#endregion

	#region Settings & dialogs
	%SettingsToggleButton.icon = GitotUi.get_icon("GDScript")
	%SettingsToggleButton.pressed.connect(
		func() -> void:
			%SettingsPanel.visible = not %SettingsPanel.visible,
	)
	%SettingsPanel.stash_cap_changed.connect(_stash_panel.refresh_limits)
	%PushConfirmDialog.confirmed.connect(_do_push)
	%AmendConfirmDialog.confirmed.connect(_do_amend)
	_default_push_confirm_text = %PushConfirmDialog.dialog_text
	%PushConfirmDialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Push cancelled."),
	)
	%AmendConfirmDialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Amend cancelled."),
	)

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
			refresh_status()


#region set instances
## Assigns the shared GitEngine instance.
func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine
	_git_engine.command_completed.connect(_on_status_result)


## Assigns the shared GitLfs instance (Size Guard exemption).
func set_lfs(lfs: GitLfs) -> void:
	_lfs = lfs
	_lfs.pull_finished.connect(_on_lfs_pull_finished)


## Assigns the Push chain sync.
func set_sync_orchestrator(orchestrator: GitSyncOrchestrator) -> void:
	_orchestrator = orchestrator
	orchestrator.push_state_changed.connect(_on_push_state_changed)
	orchestrator.tag_retry_needed.connect(_on_tag_retry_needed)


## Assigns the shared GitotDiffGutter instance.
func set_diff_gutter(gutter: GitotDiffGutter) -> void:
	_diff_gutter = gutter
#endregion


## Manual fallback Triggers a fresh git status query for unreliable save signal.
## (e.g. during editor startup, before the setter runs)
## Shared refresh call. Guards against git_engine not yet injected.
func refresh_status() -> void:
	if not _git_engine:
		return
	_git_engine.run_fast(GitEngine.Command.STATUS, GitEngine.STATUS_ARGS)
	_git_engine.get_ahead_behind()
	_git_engine.list_branches()
	_log_panel.refresh()
	_stash_panel.refresh()


## Disconnects this dock from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if _git_engine and _git_engine.command_completed.is_connected(_on_status_result):
		_git_engine.command_completed.disconnect(_on_status_result)
	if _log_console:
		_log_console.teardown()


## LFS pull replaced pointer files with real binaries: ask EditorFileSystem to look for changes.
func _on_lfs_pull_finished(success: bool) -> void:
	if success:
		EditorInterface.get_resource_filesystem().scan()


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


## Refreshes EditorFileSystem's cache for one file changed on disk outside the editor,
## and reloads it if open: reload_scene_from_path() for a scene tab, Script.reload() for a
## script (recompiles the running class - the open tab's visible text only follows an
## editor focus change, which is Godot's own external-change check; nothing else forces it).
## Returns true if an open script tab was reloaded, so callers can warn about it.
func _notify_file_changed(res_path: String) -> bool:
	if not FileAccess.file_exists(res_path):
		return false
	EditorInterface.get_resource_filesystem().update_file(res_path)
	if res_path in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(res_path)
	for script: Script in EditorInterface.get_script_editor().get_open_scripts():
		if script.resource_path == res_path:
			script.reload(true)
			return true
	return false


## Notifies Godot about files changed by the branch switch.
func _notify_changed_files() -> void:
	_notify_file_list(_git_engine.get_changed_files_since_switch())


## Shared by switch/pull and pop: refreshes EditorFileSystem/open tabs per file,
## or warns once if git couldn't list them.
func _notify_file_list(result: Dictionary) -> void:
	if not result["reliable"]:
		EditorInterface.get_editor_toaster().push_toast(
			"Gitot: couldn't verify changed files. Close and reopen any open scripts/scenes to be safe.",
			EditorToaster.SEVERITY_WARNING,
		)
		return

	var stale_scripts: int = 0
	for relative_path: String in result["files"]:
		if _notify_file_changed("res://" + relative_path):
			stale_scripts += 1

	if stale_scripts > 0:
		EditorInterface.get_editor_toaster().push_toast(
			"Gitot: %d open script(s) changed on disk - click away from the editor window and back to refresh."
			% stale_scripts,
			EditorToaster.SEVERITY_WARNING,
		)
		GitotLogger.i(
			"%d open script(s) changed on disk, unfocus/focus the editor window to refresh."
			% stale_scripts,
		)


## Same refresh as _notify_changed_files(), for one known restored path.
func _notify_single_file_changed(relative_path: String) -> void:
	if _notify_file_changed("res://" + relative_path):
		EditorInterface.get_editor_toaster().push_toast(
			"Gitot: '%s' restored - click away from the editor window and back to refresh the open tab."
			% relative_path,
			EditorToaster.SEVERITY_WARNING,
		)
		GitotLogger.i("'%s' restored, unfocus/focus the editor window to refresh." % relative_path)


## Triggers a diff gutter refresh.
## Manual fallback for unreliable save signal.
func _on_refresh_diff_pressed() -> void:
	_diff_gutter.refresh_current_script()


## Routes a finished GitEngine command;
func _on_status_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if command == GitEngine.Command.LAST_COMMIT_MSG:
		_handle_last_commit_message_result(exit_code, output)
		return
	match command:
		GitEngine.Command.FETCH:
			_branch_panel.on_fetch_finished()
		GitEngine.Command.PULL:
			GitotUi.set_busy(%PullButton, false, "MoveDown")
	_result_router.route(command, exit_code, output, context)


## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if %AmendCheckbox.button_pressed:
		_on_amend_pressed()
		return
	if message.is_empty():
		GitotLogger.w("Commit message is empty. Commit aborted!")
		return
	_git_engine.run_fast(GitEngine.Command.COMMIT, ["commit", "-m", message])
	%CommitMessageInput.text = ""


## Guards against amending a commit already on origin (ahead == 0 with an
## upstream set means HEAD == upstream). No upstream at all is always safe.
func _on_amend_pressed() -> void:
	if _result_router.has_upstream() and _result_router.ahead_count() == 0:
		%AmendConfirmDialog.popup_centered()
		return
	_do_amend()


## Executes the amend - called directly or after dialog confirmation.
## Empty message keeps the existing one (--no-edit).
func _do_amend() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	var args: PackedStringArray = (
		["commit", "--amend", "--no-edit"]
		if message.is_empty()
		else ["commit", "--amend", "-m", message]
	)
	_git_engine.run_fast(GitEngine.Command.AMEND, args)
	%CommitMessageInput.text = ""
	%AmendCheckbox.button_pressed = false


func _on_push_state_changed(pushing: bool) -> void:
	GitotUi.set_busy(%PushButton, pushing, "MoveUp")


func _on_tag_retry_needed(needed: bool) -> void:
	%RetryTagPushButton.visible = needed
	%PushButton.disabled = needed


# TODO: an explicit "abandon this tag" escape hatch if I wants to push a new commit without resolving the stuck tag first.
## Pushes current branch to its remote tracking branch.
## Gated by the "confirm_push" setting to avoid accidental remote pushes.
func _on_push_pressed() -> void:
	_needs_force_push = _git_engine.needs_force_push()
	if _needs_force_push:
		%PushConfirmDialog.dialog_text = (
			"Last commit was amended!\nThis push will use --force-with-lease. Continue?"
		)
		%PushConfirmDialog.popup_centered()
		return
	%PushConfirmDialog.dialog_text = _default_push_confirm_text
	if GitotSettings.get_value("confirm_push"):
		%PushConfirmDialog.popup_centered()
	else:
		_do_push()


## Continues _do_push() once the async commit-message fetch completes.
func _handle_last_commit_message_result(exit_code: int, output: Array[String]) -> void:
	var message: String = (
		String(output[0]).strip_edges()
		if (exit_code == 0 and not output.is_empty())
		else ""
	)
	_start_push_with_tag_input(message)


## Resolves tag input, validates it, hands off to the orchestrator.
func _start_push_with_tag_input(last_commit_message: String) -> void:
	var tag_input: Dictionary = _tag_panel.get_tag_input(last_commit_message)
	if _tag_panel.is_enabled():
		if tag_input["tag_name"].is_empty():
			GitotLogger.w("Tag name is empty. Push aborted!")
			return
		if not GitEngine.is_valid_tag_name(tag_input["tag_name"]):
			GitotLogger.w(
				"'%s' is not a valid git tag name (no spaces, ~ ^ : ? * [ \\ ..). Push aborted!"
				% tag_input["tag_name"]
			)
			return
		if tag_input["tag_message"].is_empty():
			GitotLogger.w("Tag message is empty. Push aborted!")
			return
	_orchestrator.start_push(tag_input, _needs_force_push)


## Executes the actual push - called directly or after dialog confirmation.
## Skips the async commit-message fetch when it isn't needed (push without tag)
func _do_push() -> void:
	if _tag_panel.is_enabled() and _tag_panel.uses_commit_message():
		_git_engine.request_last_commit_message()
	else:
		_start_push_with_tag_input("")


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	GitotUi.set_busy(%PullButton, true, "MoveDown")
	_git_engine.pull()


func _on_kofibutton_pressed():
	OS.shell_open("https://ko-fi.com/sigkgames")
