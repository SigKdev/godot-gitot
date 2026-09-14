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


func _init(
	git_engine: GitEngine,
	branch_dropdown: OptionButton,
	create_branch_button: Button,
	new_branch_dialog: ConfirmationDialog,
	new_branch_name_input: LineEdit
) -> void:
	_git_engine = git_engine
	_branch_dropdown = branch_dropdown
	_new_branch_dialog = new_branch_dialog
	_new_branch_name_input = new_branch_name_input

	_branch_dropdown.item_selected.connect(_on_branch_selected)
	create_branch_button.pressed.connect(_on_create_button_pressed)
	_new_branch_dialog.confirmed.connect(_on_dialog_confirmed)


## Rebuilds the dropdown from a fresh branch list. Called by dock on "branches" result.
## @param branches: Array[Dictionary] from GitBranchParser.parse().
func populate(branches: Array[Dictionary]) -> void:
	_branch_dropdown.clear()
	_branch_names.clear()

	var current_index: int = 0
	for i in branches.size():
		var branch: Dictionary = branches[i]
		_branch_dropdown.add_icon_item(
			EditorInterface.get_base_control().get_theme_icon("VcsBranches", "EditorIcons"),
			_truncate(branch["name"])
		)
		_branch_dropdown.set_item_tooltip(i, branch["name"]) # full name on hover
		_branch_names.append(branch["name"]) # full name kept for switch_branch()
		if branch["is_current"]:
			current_index = i

	_branch_dropdown.select(current_index)


func _on_branch_selected(index: int) -> void:
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
