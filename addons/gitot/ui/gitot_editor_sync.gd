## gitot_editor_sync.gd
## Keeps the editor in step with files git changed on disk (switch, pull, stash pop, restore,
## LFS pull): EditorFileSystem cache, open scenes/scripts, and the warnings the user must act on.
class_name GitotEditorSync
extends RefCounted

## Shared by every HEAD move and stash pop: refreshes EditorFileSystem and open tabs per file,
## or warns once if git couldn't list the files.
## @param result: {"reliable": bool, "files": PackedStringArray} (GitEngine.to_file_list).
func on_files_changed(result: Dictionary) -> void:
	if not result["reliable"]:
		EditorInterface.get_editor_toaster().push_toast(
			"Gitot: couldn't verify changed files. "
			+ "Close and reopen any open scripts/scenes to be safe.",
			EditorToaster.SEVERITY_WARNING,
		)
		return

	var stale_scripts: int = 0
	for relative_path: String in result["files"]:
		if _refresh_file("res://" + relative_path):
			stale_scripts += 1

	if stale_scripts > 0:
		EditorInterface.get_editor_toaster().push_toast(
			(
				"Gitot: %d open script(s) changed on disk - "
				+ "click away from the editor window and back to refresh."
			) % stale_scripts,
			EditorToaster.SEVERITY_WARNING,
		)
		GitotLogger.h(
			"%d open script(s) changed on disk, unfocus/focus the editor window to refresh."
			% stale_scripts,
		)


## Same refresh as on_files_changed(), for one known restored path.
func on_file_restored(relative_path: String) -> void:
	if _refresh_file("res://" + relative_path):
		EditorInterface.get_editor_toaster().push_toast(
			(
				"Gitot: '%s' restored - click away from the editor window "
				+ "and back to refresh the open tab."
			) % relative_path,
			EditorToaster.SEVERITY_WARNING,
		)
		GitotLogger.h("'%s' restored, unfocus/focus the editor window to refresh." % relative_path)


## LFS pull replaced pointer files with real binaries: ask EditorFileSystem to look for changes.
func on_lfs_pull_finished(success: bool) -> void:
	if success:
		EditorInterface.get_resource_filesystem().scan()


## Refreshes EditorFileSystem's cache for one file changed on disk outside the editor,
## and reloads it if open: reload_scene_from_path() for a scene tab, Script.reload() for a
## script (recompiles the running class). The open script tab's text only follows when the editor
## window regains focus (Godot's own external-change check); no public API forces it.
## @return: true if an open script tab was reloaded, so callers can warn about it.
func _refresh_file(res_path: String) -> bool:
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
