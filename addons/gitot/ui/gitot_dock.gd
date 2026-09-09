## gitot_dock.gd
## Displays staged/unstaged file trees and triggers manual status refresh.
# Receives a GitEngine reference from the plugin (SoC: this script owns UI only).
@tool
class_name GitotDock
extends Control


## Color per status category. MODIFIED stays default (no override).
const STATUS_COLORS: Dictionary = {
	GitStatusParser.FileStatus.NEW_FILE: Color.LIME_GREEN,
	GitStatusParser.FileStatus.DELETED: Color.INDIAN_RED,
	GitStatusParser.FileStatus.CONFLICT: Color.ORANGE,
}

## Injected by gitot.gd on dock creation.
var git_engine: GitEngine
var diff_gutter: GitotDiffGutter


## Assigns the shared GitEngine instance.
## Called once by gitot.gd after instantiation.
func set_git_engine(engine: GitEngine) -> void:
	git_engine = engine
	git_engine.command_completed.connect(_on_status_result)


## Assigns the shared GitotDiffGutter instance.
## Called once by gitot.gd after instantiation.
func set_diff_gutter(gutter: GitotDiffGutter) -> void:
	diff_gutter = gutter


func _ready() -> void:
	%RefreshStatButton.pressed.connect(_refresh_status)
	%RefreshStatButton.icon = EditorInterface.get_base_control().get_theme_icon("Loop", "EditorIcons")
	%UnstagedTree.item_activated.connect(_on_unstaged_item_activated)
	%StagedTree.item_activated.connect(_on_staged_item_activated)
	%CommitButton.pressed.connect(_on_commit_pressed)
	%PushButton.pressed.connect(_on_push_pressed)
	%PullButton.pressed.connect(_on_pull_pressed)
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	%RefreshDiffButton.icon = EditorInterface.get_base_control().get_theme_icon("Paint", "EditorIcons")
	_setup_bulk_buttons()
	_refresh_status() # Populate trees immediately instead of waiting for manual git status refresh
	%SettingsToggleButton.icon = EditorInterface.get_base_control().get_theme_icon("GDScript", "EditorIcons")
	%SettingsToggleButton.pressed.connect(
		func() -> void: %SettingsPanel.visible = not %SettingsPanel.visible
	)
	%PushConfirmDialog.confirmed.connect(_do_push)


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
		if command_name == "push":
			%PushButton.disabled = false
			%PushButton.text = "Push"
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
	var parsed: Dictionary = GitStatusParser.parse(output[0])
	_populate_tree(%StagedTree, parsed["staged"], %StagedFold, "Staged")
	_populate_tree(%UnstagedTree, parsed["unstaged"], %UnstagedFold, "Unstaged", true)


## Clears and refills a Tree from parsed status entries {"path", "status"}.
## fold_container's title carries the label + count; the tree itself is headerless.
func _populate_tree(tree: Tree, entries: Array, fold_container: FoldableContainer, title: String, check_size: bool = false) -> void:
	tree.clear()
	var root: TreeItem = tree.create_item() # required even with hide_root; acts as invisible parent
	fold_container.title = "%s (%d)" % [title, entries.size()]
	for entry: Dictionary in entries:
		var item: TreeItem = tree.create_item(root)
		item.set_text(0, entry["path"])
		var status: GitStatusParser.FileStatus = entry["status"]
		if STATUS_COLORS.has(status):
			item.set_custom_color(0, STATUS_COLORS[status])
		if status == GitStatusParser.FileStatus.CONFLICT:
			item.set_icon(0, get_theme_icon("NodeWarning", "EditorIcons"))
			item.set_tooltip_text(0, "⚠ Merge conflict — resolve before staging ⚠")
		elif check_size and _is_oversized(ProjectSettings.globalize_path("res://" + entry["path"])):
			item.set_icon(0, get_theme_icon("StatusWarning", "EditorIcons"))
			item.set_tooltip_text(0, "⚠ Exceeds 50MB — excluded from Staging ⚠")


## Creates and wires the Stage All / Unstage All buttons into each fold header.
func _setup_bulk_buttons() -> void:
	var stage_all: Button = Button.new()
	stage_all.icon = get_theme_icon("MoveDown", "EditorIcons")
	stage_all.text = ""
	stage_all.flat = true
	stage_all.tooltip_text = "Stage All"
	stage_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stage_all.pressed.connect(_on_stage_all_pressed)
	%UnstagedFold.add_title_bar_control(stage_all)

	var unstage_all: Button = Button.new()
	unstage_all.icon = get_theme_icon("MoveUp", "EditorIcons")
	unstage_all.text = ""
	unstage_all.flat = true
	unstage_all.tooltip_text = "Unstage All"
	unstage_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	unstage_all.pressed.connect(_on_unstage_all_pressed)
	%StagedFold.add_title_bar_control(unstage_all)


## Double-click on an unstaged/untracked item stages it, unless it exceeds the size guard.
func _on_unstaged_item_activated() -> void:
	var selected: TreeItem = %UnstagedTree.get_selected()
	if not selected or selected == %UnstagedTree.get_root():
		return
	var path: String = selected.get_text(0)
	var abs_path: String = ProjectSettings.globalize_path("res://" + path)

	if _is_oversized(abs_path): # Check if a file exceeds the size guard.
		print_rich("[color=red]Gitot ERROR: '%s' exceeds 50MB and was not staged.[/color]" % path)
		return

	git_engine.run_fast("stage", ["add", "--", path])


## Double-click on a staged item unstages it.
func _on_staged_item_activated() -> void:
	var path: String = %StagedTree.get_selected().get_text(0)
	git_engine.run_fast("unstage", ["restore", "--staged", path])
# FIXME: When clicking to fast to unstage file, get an ERROR: res://addons/gitot/ui/gitot_dock.gd:127 - Attempt to call function 'get_text' in base 'null instance' on a null instance.


## Stages every unstaged/untracked file, skipping (and reporting) any that exceed the size guard.
func _on_stage_all_pressed() -> void:
	var paths: Array[String] = _get_tree_paths(%UnstagedTree)
	if paths.is_empty():
		return

	var to_stage: Array[String] = []
	for path: String in paths:
		var abs_path: String = ProjectSettings.globalize_path("res://" + path)
		if _is_oversized(abs_path):
			print_rich("[color=orange]Gitot: staging skipped '%s' — exceeds 50MB.[/color]" % path)
		else:
			to_stage.append(path)

	if to_stage.is_empty():
		return
	git_engine.run_fast("stage", ["add", "--"] + to_stage)


## Unstages every currently staged file. No size guard — unstaging never writes objects.
func _on_unstage_all_pressed() -> void:
	if %StagedTree.get_root() == null or %StagedTree.get_root().get_child(0) == null:
		return
	git_engine.run_fast("unstage", ["restore", "--staged", "."])


## Collects every file path currently listed under a tree's root (excludes the root itself).
func _get_tree_paths(tree: Tree) -> Array[String]:
	var paths: Array[String] = []
	var item: TreeItem = tree.get_root().get_child(0) if tree.get_root() else null
	while item:
		paths.append(item.get_text(0))
		item = item.get_next()
	return paths


## Reads the configurable large-file threshold, converted to bytes.
func _max_file_size_bytes() -> int:
	return int(GitotSettings.get_value("large_file_mb")) * 1024 * 1024


## Checks a single file against the size guard.
## @return: true if the file exists and is at/above the threshold.
func _is_oversized(abs_path: String) -> bool:
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		return false # Unreadable/missing — let git report the real error, not gitot.
	return file.get_length() >= _max_file_size_bytes()


## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if message.is_empty():
		return
	git_engine.run_fast("commit", ["commit", "-m", message])
	%CommitMessageInput.text = ""


## Pushes current branch to its remote tracking branch.
## Gated by the "confirm_push" setting to avoid accidental remote pushes.
func _on_push_pressed() -> void:
	if GitotSettings.get_value("confirm_push"):
		%PushConfirmDialog.popup_centered()
	else:
		_do_push()


## Executes the actual push — called directly or after dialog confirmation.
func _do_push() -> void:
	%PushButton.disabled = true
	%PushButton.text = "Pushing..."
	git_engine.run_network("push", ["push"])


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	%PullButton.disabled = true
	%PullButton.text = "Pulling..."
	git_engine.run_network("pull", ["pull"])
