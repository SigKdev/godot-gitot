## git_log_panel.gd
## Commit history section: count-filtered Tree list (message/author/date).
## RefCounted, constructor-injected — matches GitotBranchPanel/GitotTagPanel pattern.
class_name GitLogPanel
extends RefCounted

const COUNT_OPTIONS: PackedInt32Array = [10, 20, 30]

var _git_engine: GitEngine
var _tree: Tree
var _count_dropdown: OptionButton


## @param git_engine: shared engine instance, used to re-request log on filter change.
## @param fold: FoldableContainer hosting the log section; dropdown is added to its title bar.
## @param tree: 3-column Tree (Message/Author/Date), hide_root expected true.
func _init(git_engine: GitEngine, fold: FoldableContainer, tree: Tree) -> void:
	_git_engine = git_engine
	_tree = tree

	_setup_tree_columns()
	_setup_count_dropdown(fold)


## Requests a fresh log using the currently selected count.
## Called on manual refresh (RefreshStatButton) and after state-changing commands.
func refresh() -> void:
	_git_engine.get_log(COUNT_OPTIONS[_count_dropdown.selected])


## Populates the Tree from parsed GitLogParser entries.
## @param entries: Array[Dictionary] with "message"/"author"/"date" keys.
func populate(entries: Array[Dictionary]) -> void:
	_tree.clear()
	var root: TreeItem = _tree.create_item()

	for entry in entries:
		var item: TreeItem = _tree.create_item(root)
		item.set_text(0, entry["message"])
		item.set_text(1, entry["author"])
		item.set_text(2, entry["date_relative"])
		item.set_tooltip_text(2, entry["date_short"])
		item.set_tooltip_text(0, entry["message"]) # Full message on hover if truncated.


func _setup_tree_columns() -> void:
	_tree.hide_root = true
	_tree.columns = 3
	_tree.set_column_title(0, "Message")
	_tree.set_column_title(1, "Author")
	_tree.set_column_title(2, "Date")
	_tree.column_titles_visible = true
	_tree.set_column_expand(0, true) # Message gets remaining space.
	_tree.set_column_expand(1, false)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(1, 60)
	_tree.set_column_custom_minimum_width(2, 80)


func _setup_count_dropdown(fold: FoldableContainer) -> void:
	_count_dropdown = OptionButton.new()
	for count in COUNT_OPTIONS:
		_count_dropdown.add_item(str(count))
	_count_dropdown.item_selected.connect(_on_count_selected)
	fold.add_title_bar_control(_count_dropdown)


func _on_count_selected(_index: int) -> void:
	refresh()
