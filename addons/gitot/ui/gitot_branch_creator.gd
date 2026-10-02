## gitot_branch_creator.gd
## Inline "new branch" row of the Branches section: "+" toggle in the fold title bar,
## name field + Create button, optional confirmation ("confirm_create_branch" setting).
## RefCounted, constructor-injected - same pattern as GitotStashPanel.
class_name GitotBranchCreator
extends RefCounted

var _git_engine: GitEngine
var _fold: FoldableContainer
var _row: Control
var _name_edit: LineEdit
var _confirm_dialog: ConfirmationDialog
var _add_button: Button
## Name awaiting confirmation (the field could change while the dialog is open).
var _pending_name: String = ""


## @param fold: hosts the row; the "+" toggle is added to its title bar.
## @param row: container of name_edit + create_button, hidden until "+" is toggled on.
func _init(
	git_engine: GitEngine,
	fold: FoldableContainer,
	row: Control,
	name_edit: LineEdit,
	create_button: Button,
	confirm_dialog: ConfirmationDialog,
) -> void:
	_git_engine = git_engine
	_fold = fold
	_row = row
	_name_edit = name_edit
	_confirm_dialog = confirm_dialog

	_add_button = GitotUi.add_title_button(
		_fold,
		"Add",
		"New local branch\n(from the current branch)",
		true,
	)
	_add_button.toggled.connect(_on_add_toggled)
	create_button.pressed.connect(_on_create_pressed)
	_name_edit.text_submitted.connect(_on_create_pressed) # Enter key.
	_confirm_dialog.confirmed.connect(
		func() -> void:
			_create(_pending_name),
	)
	_confirm_dialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Branch creation cancelled."),
	)
	_row.visible = false


func _on_add_toggled(on: bool) -> void:
	_row.visible = on
	if on:
		_fold.folded = false # The row lives inside the fold.
		_name_edit.grab_focus()
	else:
		_name_edit.clear()


## The optional argument lets one handler serve both the button (no args)
## and text_submitted (String).
func _on_create_pressed(_text: String = "") -> void:
	var branch_name: String = _name_edit.text.strip_edges()
	if branch_name.is_empty():
		GitotLogger.w("Branch name is empty. Creation aborted!")
		return
	if not GitotSettings.get_value("confirm_create_branch"):
		_create(branch_name)
		return
	_pending_name = branch_name
	_confirm_dialog.dialog_text = (
		"Create branch '%s' from the current branch\nand switch to it?" % branch_name
	)
	_confirm_dialog.popup_centered()


## Result (log, head_moved, list refresh) is handled by the shared router.
func _create(branch_name: String) -> void:
	_git_engine.create_branch(branch_name)
	_add_button.button_pressed = false # Collapses the row and clears the field.
