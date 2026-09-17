## gitot_branch_panel.gd
## Branch dropdown (switch) + new-branch dialog. UI-only — no OS.execute() calls.
class_name GitotBranchPanel
extends RefCounted

## Max characters shown for a branch name in the dropdown before truncating
## with an ellipsis. PopupMenu items have no pixel-based truncation API,
## so we truncate the string itself for both button and popup consistency.
const MAX_BRANCH_NAME_CHARS: int = 24

var _git_engine: GitEngine
var _branch_dropdown: OptionButton
var _new_branch_dialog: ConfirmationDialog
var _new_branch_name_input: LineEdit

## Tracks dropdown index -> branch name, since OptionButton items are index-based.
var _branch_names: PackedStringArray = []

var _branch_is_remote: Array[bool] = []


## Filters out remote entries that already have a matching local branch.
## e.g. "origin/main" is hidden when local "main" already tracks it.
## tooltips show the full name and scope (local/remote) for all entries.
## Filters out remote entries that already have a matching local branch —
## avoids redundant dropdown clutter (e.g. "main" + "origin/main" both showing).
static func _filter_redundant_remotes(branches: Array[Dictionary]) -> Array[Dictionary]:
	var local_names: Array[String] = []

	for branch: Dictionary in branches:
		if not branch["is_remote"]:
			local_names.append(branch["name"])

	var result: Array[Dictionary] = []

	for branch: Dictionary in branches:
		if branch["is_remote"] and branch["name"].trim_prefix("origin/") in local_names:
			continue
		result.append(branch)

	return result


func _init(
	git_engine: GitEngine,
	branch_dropdown: OptionButton,
	create_branch_button: Button,
	new_branch_dialog: ConfirmationDialog,
	new_branch_name_input: LineEdit,
) -> void:
	_git_engine = git_engine
	_branch_dropdown = branch_dropdown
	_new_branch_dialog = new_branch_dialog
	_new_branch_name_input = new_branch_name_input

	_branch_dropdown.item_selected.connect(_on_branch_selected)
	create_branch_button.pressed.connect(_on_create_button_pressed)
	_new_branch_dialog.confirmed.connect(_on_dialog_confirmed)


## Rebuilds the dropdown from a fresh branch list. Called by dock on "branches" result.
## Remote entries with a matching local branch are filtered out (redundant —
## e.g. "origin/main" hidden when local "main" already tracks it).
## @param branches: Array[Dictionary] from GitBranchParser.parse().
func populate(
	branches: Array[Dictionary],
	branch_scopes: Dictionary[String, String],
) -> void:
	_branch_dropdown.clear()
	_branch_names.clear()
	_branch_is_remote.clear()

	var filtered: Array[Dictionary] = _filter_redundant_remotes(branches)
	var base_control: Control = EditorInterface.get_base_control()
	var local_icon: Texture2D = base_control.get_theme_icon("VcsBranches", "EditorIcons")
	var remote_icon: Texture2D = base_control.get_theme_icon("ReplicationDock", "EditorIcons")

	var current_index: int = 0
	for i in filtered.size():
		var branch: Dictionary = filtered[i]
		_branch_dropdown.add_icon_item(
			remote_icon if branch["is_remote"] else local_icon,
			_truncate(branch["name"]),
		)
		var scope: String = branch_scopes.get(branch["name"], "")
		var tooltip: String = branch["name"]
		if not scope.is_empty():
			tooltip += "  ·  " + scope
		_branch_dropdown.set_item_tooltip(i, tooltip)
		_branch_names.append(branch["name"])
		_branch_is_remote.append(branch["is_remote"])
		if branch["is_current"]:
			current_index = i

	_branch_dropdown.select(current_index)


## Switches to the selected branch. If it's a remote-only entry, creates a
## local branch tracking it in one atomic op instead of a plain switch.
func _on_branch_selected(index: int) -> void:
	if _branch_is_remote[index]:
		_git_engine.track_remote_branch(_branch_names[index])
	else:
		_git_engine.switch_branch(_branch_names[index])


func _on_create_button_pressed() -> void:
	_new_branch_name_input.text = ""
	_new_branch_dialog.popup_centered()
	_new_branch_name_input.grab_focus()


func _on_dialog_confirmed() -> void:
	var name: String = _new_branch_name_input.text.strip_edges()
	if name.is_empty():
		GitotLogger.w("Branch name is empty. Creation aborted!")
		return
	_git_engine.create_branch(name)


## Truncates a display name with an ellipsis if it exceeds MAX_BRANCH_NAME_CHARS.
func _truncate(text: String) -> String:
	if text.length() <= MAX_BRANCH_NAME_CHARS:
		return text
	return text.substr(0, MAX_BRANCH_NAME_CHARS - 1) + "…"
