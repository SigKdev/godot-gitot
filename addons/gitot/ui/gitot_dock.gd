## gitot_dock.gd
## Displays staged/unstaged file trees and triggers manual status refresh.
# Receives a GitEngine reference from the plugin (SoC: this script owns UI only).
@tool
class_name GitotDock
extends Control

## Files at or above this size (bytes) are blocked from staging. 50MB per MVP spec.
const MAX_FILE_SIZE_BYTES: int = 50 * 1024 * 1024

## Injected by gitot.gd on dock creation.
var git_engine: GitEngine

var diff_gutter: GitotDiffGutter


## Assigns the shared GitEngine instance. Called once by gitot.gd after instancing.
func set_git_engine(engine: GitEngine) -> void:
	git_engine = engine
	git_engine.command_completed.connect(_on_status_result)


func set_diff_gutter(gutter: GitotDiffGutter) -> void:
	diff_gutter = gutter


func _ready() -> void:
	%RefreshButton.pressed.connect(_on_refresh_pressed)
	%UnstagedTree.item_activated.connect(_on_unstaged_item_activated)
	%StagedTree.item_activated.connect(_on_staged_item_activated)
	%CommitButton.pressed.connect(_on_commit_pressed)
	%PushButton.pressed.connect(_on_push_pressed)
	%PullButton.tooltip_text = "Note: changed scripts already open in the script editor, Godot may not refresh it — a restart may be needed (known Godot engine limitation)."
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)


## Triggers a fresh git status query.
func _on_refresh_pressed() -> void:
	git_engine.run_fast("status", ["status", "--porcelain=v2"])


## Manual fallback to trigger a diff gutter refresh (backup for unreliable save signal).
func _on_refresh_diff_pressed() -> void:
	diff_gutter.refresh_current_script()


## Handles the async status result and repaints the trees.
func _on_status_result(command_name: String, exit_code: int, output: Array) -> void:
	if command_name in ["stage", "unstage", "commit"]:
		if command_name == "commit":
			print_rich("[color=green]Gitot: Commit successful.[/color]")
		git_engine.run_fast("status", ["status", "--porcelain=v2"])
		return

	if command_name in ["push", "pull"]:
		print_rich("[color=green]Gitot: %s finished.[/color]" % command_name.capitalize())
		print(output[0]) # TEMP: inspect actual git output
		if command_name == "pull":
			EditorInterface.get_resource_filesystem().scan()
		git_engine.run_fast("status", ["status", "--porcelain=v2"])
		return

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

	if not DirAccess.dir_exists_absolute(abs_path) and FileAccess.file_exists(abs_path):
		var size: int = FileAccess.open(abs_path, FileAccess.READ).get_length()
		if size >= MAX_FILE_SIZE_BYTES:
			print_rich("[color=red]Gitot ERROR: '%s' exceeds 50MB and was not staged.[/color]" % path)
			#push_error("Gitot: '%s' exceeds 50MB and was not staged." % path)
			return

	git_engine.run_fast("stage", ["add", path])


## Double-click on a staged item unstages it.
func _on_staged_item_activated() -> void:
	var path: String = %StagedTree.get_selected().get_text(0)
	git_engine.run_fast("unstage", ["restore", "--staged", path])


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
