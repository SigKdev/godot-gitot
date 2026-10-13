## gitot_commit_flow.gd
## Commit use case: commit / amend, the amend confirmation, and the commit area's busy and amend
## wording. UI nodes are injected (mirrors GitotPushFlow); the only git calls are the two commits.
class_name GitotCommitFlow
extends RefCounted

## Commit area wording, normal vs amend mode (see _refresh_ui).
const COMMIT_PLACEHOLDER: String = "Commit Message (multiline supported)"
const AMEND_PLACEHOLDER: String = "Leave empty to keep the previous message"

var _git_engine: GitEngine
var _state: GitotRepoState
var _input: TextEdit
var _commit_button: Button
var _amend_toggle: CheckButton
var _confirm_dialog: ConfirmationDialog
## Mirrors GitEngine.write_busy_changed: a git write (commit, stage, stash...) is running.
var _busy: bool = false


func _init(
	git_engine: GitEngine,
	state: GitotRepoState,
	input: TextEdit,
	commit_button: Button,
	amend_toggle: CheckButton,
	confirm_dialog: ConfirmationDialog,
) -> void:
	_git_engine = git_engine
	_state = state
	_input = input
	_commit_button = commit_button
	_amend_toggle = amend_toggle
	_confirm_dialog = confirm_dialog
	_commit_button.pressed.connect(_on_commit_pressed)
	_amend_toggle.toggled.connect(func(_on: bool) -> void: _refresh_ui())
	_confirm_dialog.confirmed.connect(_do_amend)
	_confirm_dialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Amend cancelled."),
	)
	_git_engine.write_busy_changed.connect(_on_write_busy_changed)
	_refresh_ui()


## Disconnects from the shared GitEngine. Called by the dock's teardown().
func teardown() -> void:
	if _git_engine.write_busy_changed.is_connected(_on_write_busy_changed):
		_git_engine.write_busy_changed.disconnect(_on_write_busy_changed)


## True if HEAD is already on the upstream (ahead == 0 with an upstream set): amending rewrites history.
static func _is_pushed(has_upstream: bool, ahead: int) -> bool:
	return has_upstream and ahead == 0


## A pushed commit always asks; a local-only one asks when "confirm_amend" is on.
static func _needs_amend_confirm(pushed: bool, confirm_setting: bool) -> bool:
	return pushed or confirm_setting


## Empty message keeps the existing one (--no-edit).
static func _amend_args(message: String) -> PackedStringArray:
	if message.is_empty():
		return PackedStringArray(["commit", "--amend", "--no-edit"])
	return PackedStringArray(["commit", "--amend", "-m", message])


## Commit button: commits the staged files with the input's message, or starts the amend.
func _on_commit_pressed() -> void:
	if _amend_toggle.button_pressed:
		_start_amend()
		return
	var message: String = _input.text.strip_edges()
	if message.is_empty():
		GitotLogger.w("Commit message is empty - nothing was committed.")
		return
	_git_engine.run_fast(GitEngine.Command.COMMIT, ["commit", "-m", message], { }, _on_done)


## Confirms before amending when the commit is pushed or "confirm_amend" is on.
func _start_amend() -> void:
	var pushed: bool = _is_pushed(_state.has_upstream, _state.ahead)
	if _needs_amend_confirm(pushed, GitotSettings.get_value(GitotSettings.KEY_CONFIRM_AMEND)):
		_confirm_dialog.dialog_text = GitotUi.amend_confirm_text(
			_state.branch_label(),
			_input.text.strip_edges(),
			pushed,
		)
		_confirm_dialog.popup_centered()
		return
	_do_amend()


## Runs the amend, called directly or after the dialog is confirmed.
func _do_amend() -> void:
	_git_engine.run_fast(
		GitEngine.Command.AMEND,
		_amend_args(_input.text.strip_edges()),
		{ },
		_on_done,
	)


## Commit / amend answered. The input is kept on failure so the user can fix the cause and retry
## without retyping.
func _on_done(exit_code: int, _output: Array[String]) -> void:
	if exit_code == 0:
		_input.text = ""
		_amend_toggle.button_pressed = false


## Busy state from the runner's write lock: covers commit, amend, stage, stash... in one place.
func _on_write_busy_changed(busy: bool) -> void:
	_busy = busy
	_refresh_ui()


## Single place that decides the commit area's wording from two states: busy and amend mode.
## Amend is blocked while busy (a toggle mid-write would race the running command).
func _refresh_ui() -> void:
	var amend: bool = _amend_toggle.button_pressed
	_commit_button.disabled = _busy
	_amend_toggle.disabled = _busy
	_commit_button.icon = GitotUi.get_icon("Time") if _busy else null
	if _busy:
		_commit_button.text = "Working..."
	else:
		_commit_button.text = "Amend!" if amend else "Commit"
		_commit_button.tooltip_text = "Amend last commit" if amend else "Commit staged changes"
	_input.placeholder_text = AMEND_PLACEHOLDER if amend else COMMIT_PLACEHOLDER
