## gitot_status_tree.gd
## Owns Staged/Unstaged file trees: population, staging/unstaging, bulk actions, size guard.
## Pure UI unit, no knowledge of commit/push/pull/tag flows.
class_name GitotStatusTree
extends RefCounted

## Per-status look. Letter mode shows "letter" before the path, icon mode shows "icon" (setting: status_letters).
const STATUS_VISUALS: Dictionary = {
	GitStatusParser.FileStatus.UNTRACKED: { "letter": "U", "icon": "Add", "color": Color.FOREST_GREEN, "tip": "Untracked File" },
	GitStatusParser.FileStatus.NEW_FILE: { "letter": "A", "icon": "Add", "color": Color.FOREST_GREEN, "tip": "Added File" },
	GitStatusParser.FileStatus.MODIFIED: { "letter": "M", "icon": "Edit", "color": Color.ORANGE, "tip": "Modified File" },
	GitStatusParser.FileStatus.DELETED: { "letter": "D", "icon": "Close", "color": Color.INDIAN_RED, "tip": "Deleted File" },
	GitStatusParser.FileStatus.CONFLICT: { "letter": "C", "icon": "NodeWarning", "color": Color.RED, "tip": "⚠ Merge conflict - resolve before staging ⚠" },
}

## TreeItem button id for the "open file in editor" action.
const BUTTON_OPEN_FILE: int = 0

## Extensions Gitot will open directly in the script editor.
## Excludes scenes, .uid, imported binaries (audio/video/textures).
const OPENABLE_EXTENSIONS: PackedStringArray = ["gd", "cs", "gdshader", "gdshaderinc"]

## TreeItem button id for the "track this file type with LFS" action (Size Guard rows only).
const BUTTON_TRACK_LFS: int = 1

## Single column: hover and selection cover the whole row.
const COL_PATH: int = 0

var _git_engine: GitEngine

var _unstaged_tree: Tree
var _staged_tree: Tree
var _unstaged_fold: FoldableContainer
var _staged_fold: FoldableContainer
## Optional: files LFS stores as pointers are exempt from the Size Guard.
var _lfs: GitLfs
var _stage_all_button: Button
var _unstage_all_button: Button


func _init(
	git_engine: GitEngine,
	unstaged_tree: Tree,
	staged_tree: Tree,
	unstaged_fold: FoldableContainer,
	staged_fold: FoldableContainer,
	lfs: GitLfs,
) -> void:
	_git_engine = git_engine
	_lfs = lfs
	_unstaged_tree = unstaged_tree
	_staged_tree = staged_tree
	_unstaged_fold = unstaged_fold
	_staged_fold = staged_fold
	_unstaged_tree.button_clicked.connect(_on_tree_button_clicked)
	_staged_tree.button_clicked.connect(_on_tree_button_clicked)
	_unstaged_tree.gui_input.connect(_on_tree_gui_input.bind(_unstaged_tree))
	_staged_tree.gui_input.connect(_on_tree_gui_input.bind(_staged_tree))
	_unstaged_tree.item_activated.connect(_on_unstaged_item_activated)
	_staged_tree.item_activated.connect(_on_staged_item_activated)
	_setup_bulk_buttons()


## Clears and refills both trees from a parsed git-status result {"staged", "unstaged"}.
func populate(parsed: Dictionary) -> void:
	var was_empty: bool = _is_empty(_staged_tree) # Captured before clear() to detect the transition.
	_populate_tree(_staged_tree, parsed["staged"], _staged_fold, "Staged")
	_populate_tree(_unstaged_tree, parsed["unstaged"], _unstaged_fold, "Unstaged", true)
	if parsed["staged"].is_empty():
		_staged_fold.folded = true
	elif was_empty:
		_staged_fold.folded = false # Reopen only when files arrive, so manual folds survive refreshes.


## Clears and refills a Tree from parsed status entries {"path", "status"}.
func _populate_tree(
	tree: Tree,
	entries: Array,
	fold_container: FoldableContainer,
	title: String,
	check_size: bool = false,
) -> void:
	tree.clear()
	var root: TreeItem = tree.create_item() # Required even with hide_root: acts as the invisible parent.
	fold_container.title = "%s (%d)" % [title, entries.size()]
	var max_bytes: int = _max_file_size_bytes() if check_size else 0
	for entry: Dictionary in entries:
		var item: TreeItem = tree.create_item(root)
		var status: GitStatusParser.FileStatus = entry["status"]
		_apply_status_visuals(item, entry["path"], status) # Size Guard below may override the icon/tooltip.
		if (
			check_size and status != GitStatusParser.FileStatus.CONFLICT
			and _violates_guard(entry["path"], max_bytes)
		):
			item.set_icon(COL_PATH, GitotUi.get_icon("StatusWarning"))
			item.set_icon_modulate(COL_PATH, Color.ORANGE)
			item.set_tooltip_text(COL_PATH, "⚠ Exceeds your Size Guard - excluded from Staging ⚠")
			if _lfs != null and _lfs.is_ready():
				var pattern: String = _lfs_pattern(entry["path"])
				item.add_button(
					COL_PATH,
					GitotUi.get_icon("Pin"),
					BUTTON_TRACK_LFS,
					false,
					"Track '%s' with Git LFS and allow staging.\nApplies to ALL matching files."
					% pattern,
				)
		if entry["path"].get_extension().to_lower() in OPENABLE_EXTENSIONS:
			item.add_button(
				COL_PATH,
				GitotUi.get_icon("ShaderDock"),
				BUTTON_OPEN_FILE,
				false,
				"Open file in editor",
			)
			item.set_button_color(COL_PATH, item.get_button_by_id(COL_PATH, BUTTON_OPEN_FILE), Color.DARK_GRAY)


## Text, color and tooltip from STATUS_VISUALS. The path lives in metadata (see _path_of),
## so the cell text is display-only: "M  path" in letter mode, plain path + tinted icon otherwise.
func _apply_status_visuals(item: TreeItem, path: String, status: GitStatusParser.FileStatus) -> void:
	var visual: Dictionary = STATUS_VISUALS[status]
	var color: Color = visual["color"]
	item.set_metadata(COL_PATH, path)
	item.set_custom_color(COL_PATH, color) # One color per cell: letter and path share it.
	item.set_tooltip_text(COL_PATH, visual["tip"])
	if GitotSettings.get_value("status_letters"):
		item.set_text(COL_PATH, "%s  %s" % [visual["letter"], path])
	else:
		item.set_text(COL_PATH, path)
		item.set_icon(COL_PATH, GitotUi.get_icon(visual["icon"]))
		item.set_icon_modulate(COL_PATH, color)


## Repo-relative path of a row. Never read it from the text, which may carry the status letter.
func _path_of(item: TreeItem) -> String:
	return item.get_metadata(COL_PATH)


## Creates and wires the Stage All / Unstage All buttons into each fold header.
func _setup_bulk_buttons() -> void:
	_stage_all_button = GitotUi.add_title_button(_unstaged_fold, "ArrowDown", "Stage All")
	_stage_all_button.pressed.connect(_on_stage_all_pressed)
	_unstage_all_button = GitotUi.add_title_button(_staged_fold, "ArrowUp", "Unstage All")
	_unstage_all_button.pressed.connect(_on_unstage_all_pressed)


## Greys out the bulk buttons while a git write runs (the click would be dropped anyway).
## Called by the dock from GitEngine.write_busy_changed.
func set_busy(busy: bool) -> void:
	_stage_all_button.disabled = busy
	_unstage_all_button.disabled = busy


## Enter/double-click on unstaged rows stages every selected row (Size Guard applies).
func _on_unstaged_item_activated() -> void:
	_stage_paths(_get_selected_paths(_unstaged_tree))


## Enter/double-click on staged rows unstages every selected row.
## "--" ends option parsing (safe for odd names) and enables chunking in GitRunner.
func _on_staged_item_activated() -> void:
	var paths: Array[String] = _get_selected_paths(_staged_tree)
	if paths.is_empty():
		return
	_git_engine.run_fast(
		GitEngine.Command.UNSTAGE,
		["restore", "--staged", "--"] + paths,
		{ "count": paths.size() }, # Only for the "Unstaged N file(s)" log line.
	)


## Swaps to a pointing-hand cursor only while hovering a row's button (e.g. "open file").
func _on_tree_gui_input(event: InputEvent, tree: Tree) -> void:
	if not event is InputEventMouseMotion:
		return
	var over_button: bool = tree.get_button_id_at_position(event.position) != -1
	tree.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if over_button else Control.CURSOR_ARROW
	)


## Handles the row buttons: "Track with LFS" (Size Guard rows) or "Open file in editor"
## (script editor for scripts, inspector/2D/3D for other resources).
func _on_tree_button_clicked(
	item: TreeItem,
	_column: int,
	id: int,
	_mouse_button_index: int,
) -> void:
	if id == BUTTON_TRACK_LFS:
		_lfs.track(_lfs_pattern(_path_of(item))) # Result: GitLfs logs, status refresh re-evaluates the row.
		return
	if id != BUTTON_OPEN_FILE:
		return
	var res_path: String = "res://" + _path_of(item)
	if not ResourceLoader.exists(res_path):
		GitotLogger.w("'%s' has no importable resource to open." % res_path)
		return
	EditorInterface.edit_resource(load(res_path))


func _on_stage_all_pressed() -> void:
	_stage_paths(_get_tree_paths(_unstaged_tree))


## Stages repo-relative paths, skipping (and logging) Size Guard violators.
func _stage_paths(paths: Array[String]) -> void:
	if paths.is_empty():
		return
	var to_stage: Array[String] = []
	var max_bytes: int = _max_file_size_bytes()
	for path: String in paths:
		if _violates_guard(path, max_bytes):
			GitotLogger.w("Staging skipped '%s' - exceeds Size Guard." % path)
		else:
			to_stage.append(path) # Good files must still go through.
	if to_stage.is_empty():
		return
	if to_stage.size() < paths.size():
		GitotLogger.i(
			"Staged %d/%d files; the rest exceed the Size Guard." % [to_stage.size(), paths.size()]
		)
	_git_engine.run_fast(
		GitEngine.Command.STAGE,
		["add", "--"] + to_stage,
		{ "count": to_stage.size() }, # Only for the "Staged N file(s)" log line.
	)


func _on_unstage_all_pressed() -> void:
	if _is_empty(_staged_tree):
		return
	_git_engine.run_fast(GitEngine.Command.UNSTAGE, ["restore", "--staged", "."])


## True if the tree has no file rows (root always exists after populate, so check its first child).
func _is_empty(tree: Tree) -> bool:
	return tree.get_root() == null or tree.get_root().get_first_child() == null


## Collects every file path currently listed under a tree's root (excludes the root itself).
func _get_tree_paths(tree: Tree) -> Array[String]:
	var paths: Array[String] = []
	var item: TreeItem = tree.get_root().get_first_child() if tree.get_root() else null
	while item:
		paths.append(_path_of(item))
		item = item.get_next()
	return paths


## Paths of ALL selected rows. get_selected() would only return the focused one in multi-select.
func _get_selected_paths(tree: Tree) -> Array[String]:
	var paths: Array[String] = []
	var item: TreeItem = tree.get_next_selected(null) # null = start from the top.
	while item:
		paths.append(_path_of(item))
		item = tree.get_next_selected(item)
	return paths


func _max_file_size_bytes() -> int:
	return int(GitotSettings.get_value("large_file_mb")) * 1024 * 1024


## @return: true if the file exists and is at or above max_bytes (max_bytes 0 = guard disabled: always false).
func _is_oversized(abs_path: String, max_bytes: int) -> bool:
	if max_bytes == 0:
		return false
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		return false # Unreadable or missing: let git report the real error.
	return file.get_length() >= max_bytes


## Size Guard verdict for a repo-relative path: oversized AND not stored by LFS.
## The cheap size check runs first, so LFS patterns are only read for oversized files.
func _violates_guard(path: String, max_bytes: int) -> bool:
	if not _is_oversized(ProjectSettings.globalize_path("res://" + path), max_bytes):
		return false
	return _lfs == null or not _lfs.covers(path)


## "*.ext" for the file's extension, or the bare file name when it has none.
func _lfs_pattern(path: String) -> String:
	var extension: String = path.get_extension()
	return "*." + extension if not extension.is_empty() else path.get_file()
