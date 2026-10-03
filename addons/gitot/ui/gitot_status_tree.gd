## gitot_status_tree.gd
## Owns Staged/Unstaged file trees: population, staging/unstaging, bulk actions, size guard.
## Pure UI unit, no knowledge of commit/push/pull/tag flows.
class_name GitotStatusTree
extends RefCounted

const STATUS_COLORS: Dictionary = {
	GitStatusParser.FileStatus.NEW_FILE: Color.FOREST_GREEN,
	GitStatusParser.FileStatus.MODIFIED: Color.ORANGE,
	GitStatusParser.FileStatus.DELETED: Color.INDIAN_RED,
	GitStatusParser.FileStatus.CONFLICT: Color.RED,
}

## TreeItem button id for the "open file in editor" action.
const BUTTON_OPEN_FILE: int = 0

## Extensions Gitot will open directly in the script editor.
## Excludes scenes, .uid, imported binaries (audio/video/textures).
const OPENABLE_EXTENSIONS: PackedStringArray = ["gd", "cs", "gdshader", "gdshaderinc"]

## TreeItem button id for the "track this file type with LFS" action (Size Guard rows only).
const BUTTON_TRACK_LFS: int = 1

## Assigned by gitot_dock.gd right after construction.
var _git_engine: GitEngine

var _unstaged_tree: Tree
var _staged_tree: Tree
var _unstaged_fold: FoldableContainer
var _staged_fold: FoldableContainer
## Optional: files LFS stores as pointers are exempt from the Size Guard.
var _lfs: GitLfs


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
	var root: TreeItem = tree.create_item() # required even with hide_root; acts as invisible parent
	fold_container.title = "%s (%d)" % [title, entries.size()]
	var max_bytes: int = _max_file_size_bytes() if check_size else 0
	for entry: Dictionary in entries:
		var item: TreeItem = tree.create_item(root)
		item.set_text(0, entry["path"])
		var status: GitStatusParser.FileStatus = entry["status"]
		if STATUS_COLORS.has(status):
			item.set_custom_color(0, STATUS_COLORS[status])
		if status == GitStatusParser.FileStatus.MODIFIED:
			item.set_icon(0, GitotUi.get_icon("Edit"))
			item.set_icon_modulate(0, Color.ORANGE)
			item.set_tooltip_text(0, "Modified File")
		if status == GitStatusParser.FileStatus.DELETED:
			item.set_icon(0, GitotUi.get_icon("Close"))
			item.set_icon_modulate(0, Color.INDIAN_RED)
			item.set_tooltip_text(0, "Deleted File")
		if status == GitStatusParser.FileStatus.NEW_FILE:
			item.set_icon(0, GitotUi.get_icon("Add"))
			item.set_icon_modulate(0, Color.FOREST_GREEN)
			item.set_tooltip_text(0, "Untracked File")
		if status == GitStatusParser.FileStatus.CONFLICT:
			item.set_icon(0, GitotUi.get_icon("NodeWarning"))
			item.set_icon_modulate(0, Color.RED)
			item.set_tooltip_text(0, "⚠ Merge conflict - resolve before staging ⚠")
		if (
			check_size and status != GitStatusParser.FileStatus.CONFLICT
			and _violates_guard(entry["path"], max_bytes)
		):
			item.set_icon(0, GitotUi.get_icon("StatusWarning"))
			item.set_icon_modulate(0, Color.ORANGE)
			item.set_tooltip_text(0, "⚠ Exceeds your Size Guard - excluded from Staging ⚠")
			if _lfs != null and _lfs.is_ready():
				var pattern: String = _lfs_pattern(entry["path"])
				item.add_button(
					0,
					GitotUi.get_icon("Pin"),
					BUTTON_TRACK_LFS,
					false,
					"Track '%s' with Git LFS and allow staging.\nApplies to ALL matching files."
					% pattern,
				)
		if entry["path"].get_extension().to_lower() in OPENABLE_EXTENSIONS:
			item.add_button(
				0,
				GitotUi.get_icon("ShaderDock"),
				BUTTON_OPEN_FILE,
				false,
				"Open file in editor",
			)
			item.set_button_color(0, item.get_button_by_id(0, BUTTON_OPEN_FILE), Color.DARK_GRAY)


## Creates and wires the Stage All / Unstage All buttons into each fold header.
func _setup_bulk_buttons() -> void:
	var stage_all: Button = Button.new()
	stage_all.icon = GitotUi.get_icon("ArrowDown")
	stage_all.flat = true
	stage_all.tooltip_text = "Stage All"
	stage_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stage_all.pressed.connect(_on_stage_all_pressed)
	_unstaged_fold.add_title_bar_control(stage_all)

	var unstage_all: Button = Button.new()
	unstage_all.icon = GitotUi.get_icon("ArrowUp")
	unstage_all.flat = true
	unstage_all.tooltip_text = "Unstage All"
	unstage_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	unstage_all.pressed.connect(_on_unstage_all_pressed)
	_staged_fold.add_title_bar_control(unstage_all)


## Enter/double-click on unstaged rows stages every selected row (Size Guard applies).
func _on_unstaged_item_activated() -> void:
	_stage_paths(_get_selected_paths(_unstaged_tree))


## Enter/double-click on staged rows unstages every selected row.
## "--" ends option parsing (safe for odd names) and enables chunking in GitRunner.
func _on_staged_item_activated() -> void:
	var paths: Array[String] = _get_selected_paths(_staged_tree)
	if paths.is_empty():
		return
	_git_engine.run_fast(GitEngine.Command.UNSTAGE, ["restore", "--staged", "--"] + paths)


## Swaps to a pointing-hand cursor only while hovering a row's button (e.g. "open file").
func _on_tree_gui_input(event: InputEvent, tree: Tree) -> void:
	if not event is InputEventMouseMotion:
		return
	var over_button: bool = tree.get_button_id_at_position(event.position) != -1
	tree.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if over_button else Control.CURSOR_ARROW
	)


## Opens the clicked row's file in the editor
## (script editor for scripts, inspector/2D-3D for other resources).
func _on_tree_button_clicked(
	item: TreeItem,
	_column: int,
	id: int,
	_mouse_button_index: int,
) -> void:
	if id == BUTTON_TRACK_LFS:
		_lfs.track(_lfs_pattern(item.get_text(0))) # Result: GitLfs logs, status refresh re-evaluates the row.
		return
	if id != BUTTON_OPEN_FILE:
		return
	var res_path: String = "res://" + item.get_text(0)
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
	_git_engine.run_fast(GitEngine.Command.STAGE, ["add", "--"] + to_stage)


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
		paths.append(item.get_text(0))
		item = item.get_next()
	return paths


## Paths of ALL selected rows. get_selected() would only return the focused one in multi-select.
func _get_selected_paths(tree: Tree) -> Array[String]:
	var paths: Array[String] = []
	var item: TreeItem = tree.get_next_selected(null) # null = start from the top.
	while item:
		paths.append(item.get_text(0))
		item = tree.get_next_selected(item)
	return paths


func _max_file_size_bytes() -> int:
	return int(GitotSettings.get_value("large_file_mb")) * 1024 * 1024


## @return: true if the file exists and is at/above the given threshold (0 = guard disabled).
func _is_oversized(abs_path: String, max_bytes: int) -> bool:
	if max_bytes == 0:
		return false
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		return false # Unreadable/missing - let git report the real error, not gitot.
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
