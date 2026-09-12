## gitot_status_tree.gd
## Owns Staged/Unstaged file trees: population, staging/unstaging, bulk actions, size guard.
## Pure UI unit (SoC), no knowledge of commit/push/pull/tag flows.
class_name GitotStatusTree
extends RefCounted

const STATUS_COLORS: Dictionary = {
	GitStatusParser.FileStatus.NEW_FILE: Color.CORNFLOWER_BLUE, #Color.LIME_GREEN,
	GitStatusParser.FileStatus.DELETED: Color.INDIAN_RED,
	GitStatusParser.FileStatus.CONFLICT: Color.ORANGE,
	GitStatusParser.FileStatus.MODIFIED: Color.FOREST_GREEN,
}

## TreeItem button id for the "open file in editor" action.
const BUTTON_OPEN_FILE: int = 0

## Extensions Gitot will open directly in the script editor.
## Excludes scenes, .uid, imported binaries (audio/video/textures).
const OPENABLE_EXTENSIONS: PackedStringArray = ["gd", "cs", "gdshader", "gdshaderinc"]

## Assigned by gitot_dock.gd right after construction.
var git_engine: GitEngine

var _unstaged_tree: Tree
var _staged_tree: Tree
var _unstaged_fold: FoldableContainer
var _staged_fold: FoldableContainer


func _init(unstaged_tree: Tree, staged_tree: Tree, unstaged_fold: FoldableContainer, staged_fold: FoldableContainer) -> void:
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
	_populate_tree(_staged_tree, parsed["staged"], _staged_fold, "Staged")
	_populate_tree(_unstaged_tree, parsed["unstaged"], _unstaged_fold, "Unstaged", true)


## Clears and refills a Tree from parsed status entries {"path", "status"}.
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
		if status == GitStatusParser.FileStatus.MODIFIED:
			item.set_icon(0, EditorInterface.get_base_control().get_theme_icon("ImportCheck", "EditorIcons"))
			item.set_tooltip_text(0, "Modified File")
		if status == GitStatusParser.FileStatus.DELETED:
			item.set_icon(0, EditorInterface.get_base_control().get_theme_icon("MissingNode", "EditorIcons"))
			item.set_tooltip_text(0, "Deleted File")
		if status == GitStatusParser.FileStatus.NEW_FILE:
			item.set_icon(0, EditorInterface.get_base_control().get_theme_icon("Line2D", "EditorIcons"))
			item.set_tooltip_text(0, "Untracked File")
		if status == GitStatusParser.FileStatus.CONFLICT:
			item.set_icon(0, EditorInterface.get_base_control().get_theme_icon("NodeWarning", "EditorIcons"))
			item.set_tooltip_text(0, "⚠ Merge conflict — resolve before staging ⚠")
		if check_size and _is_oversized(ProjectSettings.globalize_path("res://" + entry["path"])):
			item.set_icon(0, EditorInterface.get_base_control().get_theme_icon("StatusWarning", "EditorIcons"))
			item.set_tooltip_text(0, "⚠ Exceeds your Size Guard — excluded from Staging ⚠")
		if entry["path"].get_extension().to_lower() in OPENABLE_EXTENSIONS:
			item.add_button(0, EditorInterface.get_base_control().get_theme_icon("ShaderDock", "EditorIcons"), BUTTON_OPEN_FILE, false, "Open file in editor")


## Creates and wires the Stage All / Unstage All buttons into each fold header.
func _setup_bulk_buttons() -> void:
	var stage_all: Button = Button.new()
	stage_all.icon = EditorInterface.get_base_control().get_theme_icon("MoveDown", "EditorIcons")
	stage_all.flat = true
	stage_all.tooltip_text = "Stage All"
	stage_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stage_all.pressed.connect(_on_stage_all_pressed)
	_unstaged_fold.add_title_bar_control(stage_all)

	var unstage_all: Button = Button.new()
	unstage_all.icon = EditorInterface.get_base_control().get_theme_icon("MoveUp", "EditorIcons")
	unstage_all.flat = true
	unstage_all.tooltip_text = "Unstage All"
	unstage_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	unstage_all.pressed.connect(_on_unstage_all_pressed)
	_staged_fold.add_title_bar_control(unstage_all)


## Double-click on an unstaged/untracked item stages it, unless it exceeds the size guard.
func _on_unstaged_item_activated() -> void:
	var selected: TreeItem = _unstaged_tree.get_selected()
	if not selected or selected == _unstaged_tree.get_root():
		return
	var path: String = selected.get_text(0)
	var abs_path: String = ProjectSettings.globalize_path("res://" + path)
	if _is_oversized(abs_path):
		GitotLogger.e("'%s' exceeds Size Guard and was not staged." % path)
		return
	git_engine.run_fast("stage", ["add", "--", path])


## Double-click on a staged item unstages it.
func _on_staged_item_activated() -> void:
	var selected: TreeItem = _staged_tree.get_selected()
	if not selected: # Guards the fast-double-click null crash (was open FIXME in gitot_dock.gd)
		return
	git_engine.run_fast("unstage", ["restore", "--staged", selected.get_text(0)])


## Swaps to a pointing-hand cursor only while hovering a row's button (e.g. "open file").
func _on_tree_gui_input(event: InputEvent, tree: Tree) -> void:
	if not event is InputEventMouseMotion:
		return
	var over_button: bool = tree.get_button_id_at_position(event.position) != -1
	tree.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over_button else Control.CURSOR_ARROW


## Opens the clicked row's file in the editor (script editor for scripts, inspector/2D-3D for other resources).
func _on_tree_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	if id != BUTTON_OPEN_FILE:
		return
	var res_path: String = "res://" + item.get_text(0)
	if not ResourceLoader.exists(res_path):
		GitotLogger.w("'%s' has no importable resource to open." % res_path)
		return
	EditorInterface.edit_resource(load(res_path))


## Stages every unstaged/untracked file, skipping (and reporting) any that exceed the size guard.
func _on_stage_all_pressed() -> void:
	var paths: Array[String] = _get_tree_paths(_unstaged_tree)
	if paths.is_empty():
		return
	var to_stage: Array[String] = []
	for path: String in paths:
		var abs_path: String = ProjectSettings.globalize_path("res://" + path)
		if _is_oversized(abs_path):
			GitotLogger.w("Staging skipped '%s' - exceeds Size Guard." % path)
		else:
			to_stage.append(path)
	if to_stage.is_empty():
		return
	git_engine.run_fast("stage", ["add", "--"] + to_stage)


## Unstages every currently staged file. No size guard — unstaging never writes objects.
func _on_unstage_all_pressed() -> void:
	if _staged_tree.get_root() == null or _staged_tree.get_root().get_child(0) == null:
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


## @return: true if the file exists and is at/above the configured threshold (0 = guard disabled).
func _is_oversized(abs_path: String) -> bool:
	if GitotSettings.get_value("large_file_mb") == 0:
		return false
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		return false # Unreadable/missing — let git report the real error, not gitot.
	return file.get_length() >= _max_file_size_bytes()
