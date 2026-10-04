## gitot_stash_panel.gd
## Shelf section: stash list (name/branch/date) + Stash/Pop/Drop actions.
## RefCounted, constructor-injected - matches GitotLogPanel/GitotBranchPanel pattern.
class_name GitotStashPanel
extends RefCounted

const FOLD_TITLE: String = "Shelf"

var _git_engine: GitEngine
var _fold: FoldableContainer
var _tree: Tree
var _name_edit: LineEdit
var _drop_dialog: ConfirmationDialog
var _stash_button: Button
var _pop_button: Button
var _drop_button: Button
var _count: int = 0
## SHA of the entry awaiting drop confirmation. SHA, not index: indices shift
## whenever the stack changes while the dialog is open.
var _pending_drop_sha: String = ""


## @param fold: hosts the section; Stash/Pop/Drop buttons are added to its title bar.
## @param tree: 3-column Tree (set up here).
## @param name_edit: optional stash name (empty = git's default "WIP on ..." subject).
## @param drop_dialog: confirmation before the destructive drop.
func _init(
	git_engine: GitEngine,
	fold: FoldableContainer,
	tree: Tree,
	name_edit: LineEdit,
	drop_dialog: ConfirmationDialog,
) -> void:
	_git_engine = git_engine
	_fold = fold
	_tree = tree
	_name_edit = name_edit
	_drop_dialog = drop_dialog

	_setup_tree_columns()
	_stash_button = _add_title_button(
		"Bake",
		"Stash all changes (incl. untracked)",
		_on_stash_pressed,
	)
	_pop_button = _add_title_button(
		"LightmapGIData",
		(
			"Pop selected stash.\n" + "⚠ Godot may not refresh scripts open\n"
			+ "in the editor. Close scripts before! ⚠\n" + "If not closed before, click away from\n"
			+ "the editor window and back to refresh.\n" + "But a reload/restart may be needed. ⚠"
		),
		_on_pop_pressed,
	)
	_drop_button = _add_title_button("Remove", "Drop selected stash", _on_drop_pressed)
	_name_edit.text_submitted.connect(
		func(_text: String) -> void:
			_on_stash_pressed(),
	)
	_drop_dialog.confirmed.connect(_do_drop)
	_apply_count(0)


## Requests a fresh stash list (result is routed to populate()).
func refresh() -> void:
	_git_engine.list_stashes()


## Re-applies title/buttons after the cap setting changed (no git call).
func refresh_limits() -> void:
	_apply_count(_count)


## Populates the Tree from GitStashParser entries.
func populate(entries: Array[Dictionary]) -> void:
	var selected_sha: String = _selected_sha()
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	for entry: Dictionary in entries:
		var item: TreeItem = _tree.create_item(root)
		item.set_text(0, entry["name"])
		item.set_tooltip_text(0, entry["name"]) # Full name on hover if truncated.
		item.set_text(1, entry["branch"])
		item.set_text(2, entry["date_relative"])
		item.set_tooltip_text(2, entry["date_full"])
		item.set_metadata(0, entry) # Row -> index (pop/drop) and hash (identity).

	# Keep the user's selection across refreshes (focus-in refresh); else the top entry,
	# so Pop defaults to the latest stash.
	var target: TreeItem = _find_item(selected_sha)
	if target == null:
		target = root.get_first_child()
	if target:
		target.select(0)
	_apply_count(entries.size())


func _setup_tree_columns() -> void:
	_tree.hide_root = true
	_tree.columns = 3
	_tree.set_column_title(0, "Name")
	_tree.set_column_title(1, "Branch")
	_tree.set_column_title(2, "Date")
	_tree.column_titles_visible = true
	_tree.set_column_expand(0, true) # Name gets remaining space.
	_tree.set_column_expand(1, false)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(1, 60)
	_tree.set_column_custom_minimum_width(2, 80)


# func _add_title_button(icon_name: String, tooltip: String, callback: Callable) -> Button:
# 	var button := Button.new()
# 	button.flat = true
# 	button.icon = GitotUi.get_icon(icon_name)
# 	button.tooltip_text = tooltip
# 	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
# 	button.pressed.connect(callback)
# 	_fold.add_title_bar_control(button)
# 	return button
func _add_title_button(icon_name: String, tooltip: String, callback: Callable) -> Button:
	var button: Button = GitotUi.add_title_button(_fold, icon_name, tooltip)
	button.pressed.connect(callback)
	return button


#region Actions
func _on_stash_pressed() -> void:
	# Enter in the name field bypasses the disabled button - re-check here.
	if _count >= _cap():
		GitotLogger.w("Shelf full (%d/%d). Pop or drop a stash first." % [_count, _cap()])
		return
	_git_engine.stash_push(_name_edit.text)
	_name_edit.clear()


func _on_pop_pressed() -> void:
	var item: TreeItem = _tree.get_selected()
	if item:
		_git_engine.stash_pop(_entry(item)["index"])


func _on_drop_pressed() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var entry: Dictionary = _entry(item)
	_pending_drop_sha = entry["hash"]
	_drop_dialog.dialog_text = "Drop stash '%s'?\nThis permanently removes it." % entry["name"]
	_drop_dialog.popup_centered()


## Re-resolves the pending SHA to its CURRENT index (the stack may have shifted
## while the dialog was open); aborts if the entry is gone.
func _do_drop() -> void:
	var item: TreeItem = _find_item(_pending_drop_sha)
	if item == null:
		GitotLogger.w("Stash no longer on the shelf - drop aborted.")
		return
	_git_engine.stash_drop(_entry(item)["index"])
#endregion


#region State
## Title shows "Shelf (count/cap)" even while folded; buttons follow the count.
func _apply_count(count: int) -> void:
	_count = count
	_fold.title = "%s (%d/%d)" % [FOLD_TITLE, count, _cap()]
	_stash_button.disabled = count >= _cap()
	_pop_button.disabled = count == 0
	_drop_button.disabled = count == 0


func _cap() -> int:
	return GitotSettings.get_value("max_stashes") as int


func _entry(item: TreeItem) -> Dictionary:
	return item.get_metadata(0) as Dictionary


func _selected_sha() -> String:
	var item: TreeItem = _tree.get_selected()
	return _entry(item)["hash"] if item else ""


## Row with the given stash SHA, or null (also null for "" and an empty tree).
func _find_item(sha: String) -> TreeItem:
	var root: TreeItem = _tree.get_root()
	if root == null:
		return null
	for item: TreeItem in root.get_children():
		if _entry(item)["hash"] == sha:
			return item
	return null
#endregion
