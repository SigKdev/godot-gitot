## gitot_push_flow.gd
## Push use case: plan (blocked / force / normal), confirmation dialog, tag input validation,
## hand-off to GitSyncOrchestrator. UI nodes are injected; no git call is made here.
class_name GitotPushFlow
extends RefCounted

var _git_engine: GitEngine
var _orchestrator: GitSyncOrchestrator
var _state: GitotRepoState
var _tag_panel: GitotTagPanel
var _confirm_dialog: ConfirmationDialog
var _default_confirm_text: String = ""
## Decided once in start(), reused when the (possibly deferred) push begins.
var _needs_force_push: bool = false


func _init(
	git_engine: GitEngine,
	orchestrator: GitSyncOrchestrator,
	state: GitotRepoState,
	tag_panel: GitotTagPanel,
	confirm_dialog: ConfirmationDialog,
) -> void:
	_git_engine = git_engine
	_orchestrator = orchestrator
	_state = state
	_tag_panel = tag_panel
	_confirm_dialog = confirm_dialog
	_default_confirm_text = _confirm_dialog.dialog_text
	_confirm_dialog.confirmed.connect(_do_push)
	_confirm_dialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Push cancelled."),
	)


# TODO: an explicit "abandon this tag" escape hatch if the user wants to push a new commit without resolving the stuck tag first.
## Entry point of the Push button: pushes the current branch to its remote tracking branch.
## Gated by the "confirm_push" setting to avoid accidental remote pushes.
func start() -> void:
	# Decided from the cached ahead/behind counts: no git call on the UI thread.
	var plan: GitSyncOrchestrator.PushPlan = GitSyncOrchestrator.plan_push(
		_state.has_upstream,
		_state.ahead,
		_state.behind,
	)
	_needs_force_push = plan == GitSyncOrchestrator.PushPlan.FORCE_CONFIRM
	if plan == GitSyncOrchestrator.PushPlan.BLOCKED_BEHIND:
		# Forcing from here would rewind origin and delete its newer commits.
		GitotLogger.w(
			"Push blocked: origin has %d newer commit(s) you don't have. Pull first, then push again."
			% _state.behind
		)
		return
	if _needs_force_push:
		_confirm_dialog.dialog_text = (
			"Your branch and origin have diverged (↑%d ↓%d).\n" % [_state.ahead, _state.behind]
			+ "This is normal after an amend or rebase.\n\n"
			+ "Force push (--force-with-lease) will REPLACE origin's %d commit(s) with yours.\n" % _state.behind
			+ "If you did not rewrite history, Cancel and Pull first."
		)
		_confirm_dialog.popup_centered()
		return
	_confirm_dialog.dialog_text = _default_confirm_text
	if GitotSettings.get_value("confirm_push"):
		_confirm_dialog.popup_centered()
	else:
		_do_push()


## Continues the push once the async commit-message fetch completes (GitEngine.Command.LAST_COMMIT_MSG).
func on_last_commit_message(exit_code: int, output: Array[String]) -> void:
	var message: String = (
		String(output[0]).strip_edges()
		if (exit_code == 0 and not output.is_empty())
		else ""
	)
	_start_with_tag_input(message)


## Executes the actual push - called directly or after dialog confirmation.
## Skips the async commit-message fetch when it isn't needed (push without tag).
func _do_push() -> void:
	if _tag_panel.is_enabled() and _tag_panel.uses_commit_message():
		_git_engine.request_last_commit_message()
	else:
		_start_with_tag_input("")


## Resolves tag input, validates it, hands off to the orchestrator.
func _start_with_tag_input(last_commit_message: String) -> void:
	var tag_input: Dictionary = _tag_panel.get_tag_input(last_commit_message)
	if _tag_panel.is_enabled():
		if tag_input["tag_name"].is_empty():
			GitotLogger.w("Tag name is empty. Push aborted!")
			return
		if not GitEngine.is_valid_tag_name(tag_input["tag_name"]):
			GitotLogger.w(
				"'%s' is not a valid git tag name (no spaces, ~ ^ : ? * [ \\ ..). Push aborted!"
				% tag_input["tag_name"]
			)
			return
		if tag_input["tag_message"].is_empty():
			GitotLogger.w("Tag message is empty. Push aborted!")
			return
	_orchestrator.start_push(tag_input, _needs_force_push)
