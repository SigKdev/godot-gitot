## gitot_branch_deleter.gd
## Delete button of the Branches section: a title-bar button acting on the selected row.
## Safe delete only (`git branch -d`: git refuses unmerged branches); always confirmed.
## RefCounted, constructor-injected - same pattern as GitotBranchCreator.
class_name GitotBranchDeleter
extends RefCounted

var _git_engine: GitEngine
var _confirm_dialog: ConfirmationDialog
var _delete_button: Button
## Deletable branch of the selected row ("" = none).
var _selected_name: String = ""
## Branch awaiting confirmation (the selection can change while the dialog is open).
var _pending_name: String = ""


## @param fold: its title bar hosts the delete button.
func _init(git_engine: GitEngine, fold: FoldableContainer, confirm_dialog: ConfirmationDialog) -> void:
	_git_engine = git_engine
	_confirm_dialog = confirm_dialog

	_delete_button = GitotUi.add_title_button(fold, "Remove", "Delete the selected local branch")
	_delete_button.pressed.connect(_on_delete_pressed)
	_confirm_dialog.confirmed.connect(
		func() -> void:
			_git_engine.delete_branch(_pending_name),
	)
	_confirm_dialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Branch deletion cancelled."),
	)
	on_selection_changed({ })


## Connected to GitotBranchPanel.selection_changed. Only a local, non-current branch is
## deletable: git refuses the checked-out one; remote refs would need a push (out of scope).
func on_selection_changed(branch: Dictionary) -> void:
	var deletable: bool = (
		not branch.is_empty() and not branch["is_remote"] and not branch["is_current"]
	)
	_selected_name = branch["name"] if deletable else ""
	_delete_button.disabled = not deletable


func _on_delete_pressed() -> void:
	_pending_name = _selected_name
	_confirm_dialog.dialog_text = (
		"Delete local branch '%s'?\nGit refuses if it has unmerged commits." % _pending_name
	)
	_confirm_dialog.popup_centered()
