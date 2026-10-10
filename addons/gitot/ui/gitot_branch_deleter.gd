## gitot_branch_deleter.gd
## Delete buttons of the Branches section (scene toolbar row), acting on the selected row:
##  - local: `git branch -d` (git refuses unmerged branches);
##  - origin: `git push origin --delete` (the GitHub copy: removed for everyone, so extra warning).
## Both are always confirmed and share one dialog. RefCounted, constructor-injected.
class_name GitotBranchDeleter
extends RefCounted

const REMOTE_ICON: String = "Unlinked"

var _git_engine: GitEngine
var _confirm_dialog: ConfirmationDialog
var _delete_button: Button
var _delete_remote_button: Button
## Selected row: deletable local branch ("" = none), its origin copy name without "origin/" ("" = none)
## and that copy's tip hash.
var _local_name: String = ""
var _remote_name: String = ""
var _remote_hash: String = ""
## A running origin delete keeps its button disabled whatever the selection does.
var _remote_busy: bool = false
## What the open dialog will do, frozen at click time (the selection can change while it is open).
var _pending_remote: bool = false
var _pending_name: String = ""
var _pending_hash: String = ""
var _pending_on_remote: bool = false


## @param delete_button / delete_remote_button: scene buttons; icons and signals are wired here.
func _init(
	git_engine: GitEngine,
	delete_button: Button,
	delete_remote_button: Button,
	confirm_dialog: ConfirmationDialog,
) -> void:
	_git_engine = git_engine
	_confirm_dialog = confirm_dialog

	_delete_button = delete_button
	_delete_button.icon = GitotUi.get_icon("Remove")
	_delete_button.pressed.connect(_on_delete_pressed.bind(false))
	_delete_remote_button = delete_remote_button
	_delete_remote_button.icon = GitotUi.get_icon(REMOTE_ICON)
	_delete_remote_button.pressed.connect(_on_delete_pressed.bind(true))
	_confirm_dialog.confirmed.connect(_on_confirmed)
	_confirm_dialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Branch deletion cancelled."),
	)
	on_selection_changed(null)


## Connected to GitotBranchPanel.selection_changed (entry incl. remote_ref/remote_hash).
## Local delete: a local, non-current branch (git refuses the checked-out one).
## Origin delete: any row that has an origin copy.
## @param branch: the selected entry, null = nothing selected.
func on_selection_changed(branch: GitBranchEntry) -> void:
	var local_ok: bool = branch != null and not branch.is_remote and not branch.is_current
	_local_name = branch.name if local_ok else ""
	_remote_name = branch.remote_ref.trim_prefix("origin/") if branch != null else ""
	_remote_hash = branch.remote_hash if branch != null else ""
	_refresh_buttons()


## Called by the dock when the origin delete finished (success or failure).
func on_remote_delete_finished() -> void:
	_remote_busy = false
	GitotUi.set_busy(_delete_remote_button, false, REMOTE_ICON)
	_refresh_buttons()


func _refresh_buttons() -> void:
	_delete_button.disabled = _local_name.is_empty()
	_delete_remote_button.disabled = _remote_name.is_empty() or _remote_busy


## Freezes the target and asks. Wording differs because the two deletes differ in reach.
func _on_delete_pressed(remote: bool) -> void:
	_pending_remote = remote
	if remote:
		_pending_name = _remote_name
		_pending_hash = _remote_hash
		_confirm_dialog.title = "Delete on GitHub?"
		_confirm_dialog.ok_button_text = "Delete on origin"
		_confirm_dialog.dialog_text = (
			"Delete '%s' on origin (GitHub)?\n\n" % _pending_name
			+ "The branch disappears for everyone using this repository.\n"
			+ "Your local copy, if any, is not touched. Last commit: %s.\n" % _pending_hash
			+ "GitHub refuses default and protected branches."
		)
	else:
		_pending_name = _local_name
		_pending_on_remote = not _remote_name.is_empty()
		_confirm_dialog.title = "Delete branch?"
		_confirm_dialog.ok_button_text = "Delete"
		_confirm_dialog.dialog_text = (
			"Delete local branch '%s'?\nGit refuses if it has unmerged commits." % _pending_name
		)
		if _pending_on_remote:
			_confirm_dialog.dialog_text += (
				"\n\nIt also exists on origin (GitHub) and STAYS there. "
				+ "To remove that copy too, select 'origin/%s' afterwards and use the remote-delete button."
				% _pending_name
			)
	_confirm_dialog.popup_centered()


func _on_confirmed() -> void:
	if not _pending_remote:
		_git_engine.delete_branch(_pending_name, _pending_on_remote)
		return
	# Deleting on origin prints no hash: log the old tip so a mistake stays recoverable.
	GitotLogger.h(
		"Tip of 'origin/%s' was %s. To restore it: git push origin %s:refs/heads/%s"
		% [_pending_name, _pending_hash, _pending_hash, _pending_name]
	)
	_remote_busy = true
	GitotUi.set_busy(_delete_remote_button, true, REMOTE_ICON)
	_git_engine.delete_remote_branch(_pending_name)
