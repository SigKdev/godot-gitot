## gitot_remote_prompt.gd
## Asks for the repository URL when Push finds no origin, then adds it (`git remote add origin <url>`).
## The result (log, repo state, resuming the push) is handled by GitotResultRouter.
class_name GitotRemotePrompt
extends RefCounted

var _git_engine: GitEngine
var _dialog: ConfirmationDialog
var _url_edit: LineEdit


## @param dialog: scene dialog that hosts url_edit.
## @param url_edit: URL field inside the dialog; Enter confirms.
func _init(git_engine: GitEngine, dialog: ConfirmationDialog, url_edit: LineEdit) -> void:
	_git_engine = git_engine
	_dialog = dialog
	_url_edit = url_edit
	_dialog.register_text_enter(_url_edit)
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Push cancelled - no remote was added."),
	)


## Opens the dialog with an empty field.
func prompt() -> void:
	_url_edit.clear()
	_fit_wrapped_labels()
	_dialog.popup_centered()
	_url_edit.grab_focus()


## An autowrap Label has no width before its first layout, so on the first open its minimum
## height (and the dialog's) is computed far too tall. Giving it the input's width first fixes it.
func _fit_wrapped_labels() -> void:
	var width: float = _url_edit.get_combined_minimum_size().x
	for label: Label in _dialog.find_children("*", "Label", true, false):
		label.size.x = width
		label.update_minimum_size()


## The engine validates the URL (SSOT) and reports a refusal through the router like any failure.
func _on_confirmed() -> void:
	_git_engine.add_remote(_url_edit.text.strip_edges())
