## github_issue_list.gd
## Issue list: 6-column Tree with header-click sorting.
## RefCounted, constructor-injected — matches the GitotLogPanel pattern.
class_name GithubIssueList
extends RefCounted

## Emitted on row click, and after a refresh when the selected issue still exists.
## Consumers must be idempotent (same issue may be re-emitted with fresh data).
signal issue_selected(entry: Dictionary)

## Emitted after a refresh when the previously selected issue is gone.
signal selection_cleared

enum Col {
	NUMBER,
	TITLE,
	DATE,
	TYPE,
	PRIORITY,
	LABELS,
}

const COLUMN_TITLES: PackedStringArray = ["#", "Title", "Date", "Type", "Priority", "Labels"]
const COLUMN_MIN_WIDTHS: PackedInt32Array = [45, 80, 90, 70, 70, 100]

var _tree: Tree
var _filter: GithubIssueFilter
var _entries: Array[Dictionary] = [] # Full normalized data (filters, step 5, act on this).
var _sort_column: int = Col.NUMBER
var _sort_ascending: bool = false # Default: newest first.


## @param tree: Tree with 6 columns; configured here.
func _init(tree: Tree, filter: GithubIssueFilter) -> void:
	_tree = tree
	_filter = filter
	_setup_columns()
	_tree.item_selected.connect(_on_item_selected)
	_tree.column_title_clicked.connect(_on_column_title_clicked)
	_filter.changed.connect(_refresh_and_notify)


## Replaces the data. Keeps the selection if that issue still exists.
## @param entries: Array[Dictionary] from GithubIssueParser.parse().
func populate(entries: Array[Dictionary]) -> void:
	_entries = entries
	_filter.update_options(entries)
	_refresh_and_notify()


## Rebuilds the rows, then syncs the detail pane: fresh data if the selected issue
## is still visible, cleared if it vanished (refresh or filtered out).
func _refresh_and_notify() -> void:
	var previous: int = _selected_number()
	_rebuild()
	var selected: TreeItem = _tree.get_selected()
	if selected:
		issue_selected.emit(selected.get_metadata(0)) # Idempotent: keeps body scroll.
	elif previous >= 0:
		selection_cleared.emit()


func _setup_columns() -> void:
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW # Whole-row highlight, not a single cell.
	_tree.columns = COLUMN_TITLES.size()
	_tree.column_titles_visible = true
	for col: int in COLUMN_TITLES.size():
		_tree.set_column_expand(col, col == Col.TITLE) # Only the title takes spare width.
		_tree.set_column_clip_content(col, true) # Long text is cut, never widens the column.
		_tree.set_column_custom_minimum_width(col, COLUMN_MIN_WIDTHS[col])
	_update_titles()


## Sorts, then rebuilds all rows. Selection is restored silently (signals blocked)
## so a sort click does not re-emit issue_selected and reset the detail pane.
func _rebuild() -> void:
	var selected_number: int = _selected_number()
	var sorted: Array[Dictionary] = []
	sorted.assign(_entries)
	sorted.sort_custom(_is_before)

	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var to_reselect: TreeItem = null
	for entry: Dictionary in sorted:
		if not _filter.matches(entry):
			continue
		var item: TreeItem = _add_row(root, entry)
		if entry["number"] == selected_number:
			to_reselect = item

	if to_reselect:
		_tree.set_block_signals(true)
		to_reselect.select(Col.NUMBER)
		_tree.set_block_signals(false)
		_tree.scroll_to_item(to_reselect)


func _add_row(root: TreeItem, entry: Dictionary) -> TreeItem:
	var item: TreeItem = _tree.create_item(root)
	var labels: String = ", ".join(GithubIssueParser.label_names(entry))
	item.set_text(Col.NUMBER, "#%d" % entry["number"])
	item.set_text(Col.TITLE, entry["title"])
	item.set_text(Col.DATE, entry["date_relative"])
	item.set_text(Col.TYPE, entry["type"])
	item.set_text(Col.PRIORITY, entry["priority"])
	item.set_text(Col.LABELS, labels)
	item.set_tooltip_text(Col.TITLE, entry["title"]) # Full title on hover.
	item.set_tooltip_text(Col.DATE, entry["date_short"])
	item.set_tooltip_text(Col.LABELS, labels)
	item.set_text_overrun_behavior(Col.TITLE, TextServer.OVERRUN_TRIM_ELLIPSIS)
	item.set_text_overrun_behavior(Col.LABELS, TextServer.OVERRUN_TRIM_ELLIPSIS)
	item.set_metadata(0, entry) # Row -> full entry (body, url... for the detail pane).
	return item


func _selected_number() -> int:
	var item: TreeItem = _tree.get_selected()
	return (item.get_metadata(0) as Dictionary)["number"] if item else -1


## Value the current sort column compares on; null = "no value" (always sorted last).
func _sort_key(entry: Dictionary) -> Variant:
	var text: String
	match _sort_column:
		Col.NUMBER:
			return entry["number"]
		Col.DATE:
			return entry["created_at"]
		Col.PRIORITY:
			return entry["priority_rank"] if entry["priority_rank"] >= 0 else null
		Col.TITLE:
			text = entry["title"]
		Col.TYPE:
			text = entry["type"]
		_:
			text = ", ".join(GithubIssueParser.label_names(entry))
	return text.to_lower() if not text.is_empty() else null


## sort_custom comparator. Empty values go last in BOTH directions;
## ties fall back to newest-first so the order is deterministic.
func _is_before(a: Dictionary, b: Dictionary) -> bool:
	var key_a: Variant = _sort_key(a)
	var key_b: Variant = _sort_key(b)
	if key_a == key_b:
		return a["number"] > b["number"]
	if key_a == null or key_b == null:
		return key_b == null
	return key_a < key_b if _sort_ascending else key_a > key_b


## Shows a ▲/▼ marker on the active sort column.
func _update_titles() -> void:
	for col: int in COLUMN_TITLES.size():
		var marker: String = ""
		if col == _sort_column:
			marker = " ▲" if _sort_ascending else " ▼"
		_tree.set_column_title(col, COLUMN_TITLES[col] + marker)


func _on_column_title_clicked(column: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return
	if column == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = column
		_sort_ascending = true
	_update_titles()
	_rebuild()


func _on_item_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if item:
		issue_selected.emit(item.get_metadata(0) as Dictionary)
