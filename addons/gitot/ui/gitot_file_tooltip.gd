## gitot_file_tooltip.gd
## Appends each file's git status to the FileSystem dock hover tooltip.
@tool
class_name GitotFileTooltip
extends EditorResourceTooltipPlugin

## Staged first, so the order of the lines is stable.
const SIDES: PackedStringArray = ["staged", "unstaged"]

## Repo-relative path -> { "staged": FileStatus, "unstaged": FileStatus } (missing key = none on that side).
var _status_by_path: Dictionary = { }


## Rebuilds the lookup from a parsed status result {"staged", "unstaged"}.
func update(parsed: Dictionary) -> void:
	_status_by_path.clear()
	for side: String in SIDES:
		for entry: Dictionary in parsed[side]:
			var sides: Dictionary = _status_by_path.get_or_add(entry["path"], { })
			sides[side] = entry["status"]


## Any file type can have a git status.
func _handles(_type: String) -> bool:
	return true


## Hover: one dictionary lookup, no git call. Unchanged files and folders get the default tooltip.
func _make_tooltip_for_path(path: String, _metadata: Dictionary, base: Control) -> Control:
	var sides: Dictionary = _status_by_path.get(path.trim_prefix("res://"), { })
	for side: String in SIDES:
		if not sides.has(side):
			continue
		var visual: Dictionary = GitotStatusTree.STATUS_VISUALS[sides[side]]
		var label: Label = Label.new()
		label.text = "Git (%s): %s" % [side, visual["letter"]]
		label.add_theme_color_override("font_color", visual["color"])
		base.add_child(label) # Appended under Godot's name/type/size labels.
	return base
