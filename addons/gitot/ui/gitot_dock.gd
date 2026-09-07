## gitot_dock.gd
## Displays staged/unstaged file trees and triggers manual status refresh.
# Receives a GitEngine reference from the plugin (SoC: this script owns UI only).
@tool
class_name GitotDock
extends Control

## Files at or above this size (bytes) are blocked from staging.
## TODO: 50MB per MVP spec. Needs to be configurable.
const MAX_FILE_SIZE_BYTES: int = 50 * 1024 * 1024

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
	%RefreshButton.pressed.connect(_on_refresh_pressed)
	%UnstagedTree.item_activated.connect(_on_unstaged_item_activated)
	%StagedTree.item_activated.connect(_on_staged_item_activated)
	%CommitButton.pressed.connect(_on_commit_pressed)
	%PushButton.pressed.connect(_on_push_pressed)
	%PullButton.pressed.connect(_on_pull_pressed)
	%PullButton.tooltip_text = "Note: changed scripts already open in the script editor, Godot may not refresh it; a restart may be needed (known Godot engine limitation)."
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	_on_refresh_pressed() # Populate trees immediately instead of waiting for manual refresh
# FIXME: openening editor trigger this ERROR: res://addons/gitot/ui/gitot_dock.gd:51 - Invalid call. Nonexistent function 'run_fast' in base 'Nil'.

## Disconnects this dock from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if git_engine and git_engine.command_completed.is_connected(_on_status_result):
		git_engine.command_completed.disconnect(_on_status_result)


## Triggers a fresh git status query.
## Manual fallback for unreliable save signal.
func _on_refresh_pressed() -> void:
	git_engine.run_fast("status", ["status", "--porcelain=v2"])


## Triggers a diff gutter refresh.
## Manual fallback for unreliable save signal.
func _on_refresh_diff_pressed() -> void:
	diff_gutter.refresh_current_script()


## 
## Uses porcelain=v2 for reliable status parsing.
func _on_status_result(command_name: String, exit_code: int, output: Array) -> void:
	if command_name == "commit":
		if exit_code == 0:
			print_rich("[color=green]Gitot: Commit successful.[/color]")
		else:
			print_rich("[color=red]Gitot ERROR: Commit failed.[/color]")
		return

	if command_name in ["push", "pull"]:
		# Strip our internal exit-code marker before showing git's raw output to the user.
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
	_populate_tree(%StagedTree, parsed["staged"])
	_populate_tree(%UnstagedTree, parsed["unstaged"] + parsed["untracked"])


## Clears and refills a Tree with one flat list of file paths.
func _populate_tree(tree: Tree, paths: Array) -> void:
	tree.clear()
	var root: TreeItem = tree.create_item()
	for path: String in paths:
		var item: TreeItem = tree.create_item(root)
		item.set_text(0, path)


## Double-click on an unstaged/untracked item stages it, unless it exceeds the size guard.
func _on_unstaged_item_activated() -> void:
	var path: String = %UnstagedTree.get_selected().get_text(0)
	var abs_path: String = ProjectSettings.globalize_path("res://" + path)
# FIXME: When clicking to fast to stage file, get an ERROR: res://addons/gitot/ui/gitot_dock.gd:107 - Attempt to call function 'get_text' in base 'null instance' on a null instance.

	# Check if the file exceeds the size guard.
	if DirAccess.dir_exists_absolute(abs_path):
		var oversized: String = _find_oversized_file(abs_path)
		if oversized != "":
			print_rich("[color=red]Gitot ERROR: '%s' exceeds 50MB and was not staged.[/color]" % oversized)
			return
	elif FileAccess.file_exists(abs_path):
		var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
		if not file:
			print_rich("[color=red]Gitot ERROR: could not open '%s' to check size (%s).[/color]" % [path, error_string(FileAccess.get_open_error())])
			return
		if file.get_length() >= MAX_FILE_SIZE_BYTES:
			print_rich("[color=red]Gitot ERROR: '%s' exceeds 50MB and was not staged.[/color]" % path)
			return

	git_engine.run_fast("stage", ["add", path])


## Double-click on a staged item unstages it.
func _on_staged_item_activated() -> void:
	var path: String = %StagedTree.get_selected().get_text(0)
	git_engine.run_fast("unstage", ["restore", "--staged", path])
# FIXME: When clicking to fast to unstage file, get an ERROR: res://addons/gitot/ui/gitot_dock.gd:127 - Attempt to call function 'get_text' in base 'null instance' on a null instance.


## Recursively scans a directory for the first file at/above the size guard threshold.
## @return: absolute path of the offending file, or "" if the directory is clean.
func _find_oversized_file(dir_abs_path: String) -> String:
	var dir: DirAccess = DirAccess.open(dir_abs_path)
	if not dir:
		return ""
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var entry_path: String = dir_abs_path.path_join(entry)
			if dir.current_is_dir():
				var found: String = _find_oversized_file(entry_path)
				if found != "":
					return found
			else:
				var file: FileAccess = FileAccess.open(entry_path, FileAccess.READ)
				if file and file.get_length() >= MAX_FILE_SIZE_BYTES:
					return entry_path
		entry = dir.get_next()
	return ""


## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if message.is_empty():
		return
	git_engine.run_fast("commit", ["commit", "-m", message])
	%CommitMessageInput.text = ""


## Pushes current branch to its remote tracking branch.
func _on_push_pressed() -> void:
	git_engine.run_network("push", ["push"])


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	git_engine.run_network("pull", ["pull"])
