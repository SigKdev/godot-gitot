## github_issue_filter.gd
## Type / Priority / Label dropdowns + the matching rule (AND across filters).
## Options come from the fetched data, so no vocabulary is hardcoded.
class_name GithubIssueFilter
extends RefCounted

## Emitted only when the USER changes a dropdown (not when options are refreshed).
signal changed

var _type_dropdown: OptionButton
var _priority_dropdown: OptionButton
var _label_dropdown: OptionButton


static func _sorted_keys(set: Dictionary) -> Array:
	var keys: Array = set.keys()
	keys.sort()
	return keys


## Low -> Urgent per GithubIssueParser.PRIORITY_ORDER; unknown options last, A-Z.
static func _priority_before(a: String, b: String) -> bool:
	var rank_a: int = _priority_rank(a)
	var rank_b: int = _priority_rank(b)
	return rank_a < rank_b if rank_a != rank_b else a < b


static func _priority_rank(priority: String) -> int:
	var rank: int = GithubIssueParser.PRIORITY_ORDER.find(priority)
	return rank if rank >= 0 else GithubIssueParser.PRIORITY_ORDER.size()


func _init(type_dd: OptionButton, priority_dd: OptionButton, label_dd: OptionButton) -> void:
	_type_dropdown = type_dd
	_priority_dropdown = priority_dd
	_label_dropdown = label_dd
	for dropdown: OptionButton in [_type_dropdown, _priority_dropdown, _label_dropdown]:
		dropdown.item_selected.connect(_on_item_selected)


## Rebuilds the option lists from fresh data. A choice that still exists is kept,
## otherwise that dropdown falls back to "All ...". Emits nothing.
func update_options(entries: Array[Dictionary]) -> void:
	var types: Dictionary = { } # Used as sets: key -> true.
	var priorities: Dictionary = { }
	var labels: Dictionary = { }
	for entry: Dictionary in entries:
		types[entry["type"]] = true
		priorities[entry["priority"]] = true
		for label_name: String in GithubIssueParser.label_names(entry):
			labels[label_name] = true
	types.erase("") # Unset type/priority is not a filter value.
	priorities.erase("")

	var priority_values: Array = priorities.keys()
	priority_values.sort_custom(_priority_before)
	_fill(_type_dropdown, "All types", _sorted_keys(types))
	_fill(_priority_dropdown, "All priorities", priority_values)
	_fill(_label_dropdown, "All labels", _sorted_keys(labels))


## True when the entry passes every active filter.
func matches(entry: Dictionary) -> bool:
	var type: String = _selected(_type_dropdown)
	var priority: String = _selected(_priority_dropdown)
	var label: String = _selected(_label_dropdown)
	return (
		(type.is_empty() or entry["type"] == type)
		and (priority.is_empty() or entry["priority"] == priority)
		and (label.is_empty() or GithubIssueParser.label_names(entry).has(label))
	)


func _fill(dropdown: OptionButton, all_text: String, values: Array) -> void:
	var previous: String = _selected(dropdown)
	dropdown.clear()
	dropdown.add_item(all_text)
	for value: String in values:
		dropdown.add_item(value)
	# find() = -1 when gone (or previous == "") -> index 0 = "All ...".
	dropdown.select(values.find(previous) + 1)


## Selected value, "" for the "All ..." item.
func _selected(dropdown: OptionButton) -> String:
	return "" if dropdown.selected <= 0 else dropdown.get_item_text(dropdown.selected)


func _on_item_selected(_index: int) -> void:
	changed.emit()
