## gitot_commit_files_list.gd
## Changed-files list for one commit ("M  path"). Pure UI: emits the selection,
## no git logic - the caller fetches data and requests the file's diff.
@tool
class_name GitotCommitFilesList
extends ItemList

## Emitted when a row is selected (click, or auto-select of the first row).
signal file_selected(path: String)

## Row color per git status letter; other letters (e.g. T) keep the default color.
const STATUS_COLORS: Dictionary = { "A": Color.FOREST_GREEN, "M": Color.ORANGE, "D": Color.RED }


func _ready() -> void:
	item_selected.connect(_on_item_selected)


## Replaces the rows from GitDiffParser.parse_name_status() entries and
## auto-selects the first one so the diff view is never left stale.
func show_files(files: Array[Dictionary]) -> void:
	clear()
	for file: Dictionary in files:
		var index: int = add_item("%s  %s" % [file["status"], file["path"]])
		set_item_metadata(index, file["path"]) # Path stays the SSOT, not the display text.
		set_item_tooltip(index, file["path"]) # Full path if the row is clipped.
		if STATUS_COLORS.has(file["status"]):
			set_item_custom_fg_color(index, STATUS_COLORS[file["status"]])
	if item_count > 0:
		select(0)
		_on_item_selected(0) # select() alone doesn't emit item_selected.


func _on_item_selected(index: int) -> void:
	file_selected.emit(get_item_metadata(index))
