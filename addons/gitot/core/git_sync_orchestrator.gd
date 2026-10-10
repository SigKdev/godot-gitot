## git_sync_orchestrator.gd
## Owns the push -> create-tag -> push-tag state machine.
## Reacts to GitEngine results and issues the next git command.
class_name GitSyncOrchestrator
extends RefCounted

## Emitted when a push starts (true) or ends (false). The dock uses it for the Push button state.
signal push_state_changed(pushing: bool)

## Emitted when a tag was created but its push failed (true), or on success/reset (false).
signal tag_retry_needed(needed: bool)

## Emitted when the commit was pushed but its tag name already exists on another commit.
## The dock tells the user (core has no UI knowledge).
signal tag_conflict(tag_name: String)

## What a Push click must do, decided from the branch's sync state (see plan_push()).
enum PushPlan {
	NORMAL, ## Plain push (nothing to protect).
	FORCE_CONFIRM, ## Diverged: ask first, then push with --force-with-lease.
	BLOCKED_BEHIND, ## Only behind origin: a push could only rewind it. Refuse, tell to pull.
}

var _git_engine: GitEngine
var _pending_tag: Dictionary = { }


## Pure decision from the ahead/behind counts of HEAD vs its upstream (no git call).
## Why counts and not "is upstream an ancestor of HEAD": that check is also false when HEAD is
## merely BEHIND, and a --force-with-lease push from there rewinds origin and drops its newer commits.
## Behind-only has nothing of ours to publish, so it is never forced.
## @param has_upstream: false = first push of a branch (nothing to diverge from).
static func plan_push(has_upstream: bool, ahead: int, behind: int) -> PushPlan:
	if not has_upstream or behind == 0:
		return PushPlan.NORMAL
	return PushPlan.BLOCKED_BEHIND if ahead == 0 else PushPlan.FORCE_CONFIRM


func _init(git_engine: GitEngine) -> void:
	_git_engine = git_engine
	_git_engine.command_completed.connect(_on_command_completed)


## Starts a push, chained with tag creation if tag_input has a non-empty tag_name.
## @param force: caller-computed needs_force_push() result - avoids a second sync git call here.
func start_push(tag_input: Dictionary, force: bool) -> void:
	_pending_tag = tag_input
	push_state_changed.emit(true)
	var push_args: PackedStringArray = (
		["push", "--force-with-lease", "-u", "origin", "HEAD"]
		if force
		else ["push", "-u", "origin", "HEAD"]
	)
	_git_engine.run_network(GitEngine.Command.PUSH, push_args, { "force": force }) # Context: the result line says "force-pushed".


## Re-attempts pushing the tag that was created locally but failed to push.
func retry_tag_push() -> void:
	tag_retry_needed.emit(false)
	_git_engine.push_tag(_pending_tag["tag_name"])


## Disconnects from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if _git_engine.command_completed.is_connected(_on_command_completed):
		_git_engine.command_completed.disconnect(_on_command_completed)


## Reacts to GitEngine command completion events and issues the next command in the push->tag->push-tag chain.
func _on_command_completed(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	match command:
		GitEngine.Command.PUSH:
			push_state_changed.emit(false)
			if exit_code == 0 and not _pending_tag.get("tag_name", "").is_empty():
				_git_engine.create_tag(_pending_tag["tag_name"], _pending_tag["tag_message"])
		GitEngine.Command.TAG:
			if exit_code == 0:
				_git_engine.push_tag(_pending_tag["tag_name"])
			else:
				# Never match git's error text (localized): let rev-parse decide if the tag exists.
				var error: String = output[0] if not output.is_empty() else ""
				_git_engine.check_tag_collision(_pending_tag["tag_name"], error)
		GitEngine.Command.PUSH_TAG:
			if exit_code == 0:
				tag_retry_needed.emit(false)
				_pending_tag = { }
			else:
				# The failure line is logged by GitotResultRouter (it knows the repo).
				tag_retry_needed.emit(true)
		GitEngine.Command.TAG_COLLISION_CHECK:
			_handle_tag_collision_result(exit_code, output, context)


## Resolves a failed TAG using the result of check_tag_collision() (rev-parse of the tag and HEAD).
## Pushes only if the existing local tag already points at HEAD (retry after a failed push), never
## a same-named tag on another commit. A failed rev-parse means the tag does not exist, so the
## original creation error is reported.
func _handle_tag_collision_result(
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if exit_code != 0:
		# Tag doesn't exist: the creation failed for another reason (name, identity, signing...).
		GitotLogger.fail(
			"Commits pushed, but tag '%s' could not be created." % _pending_tag.get("tag_name", ""),
			context.get("error", ""),
			"Common fail causes: your git name/email is not set (git config --global user.name / user.email), or git rejects the tag name.",
		)
		_pending_tag = { }
		return
	var tag_name: String = _pending_tag.get("tag_name", "")
	var shas: PackedStringArray = (
		String(output[0]).strip_edges().split("\n", false)
		if exit_code == 0 and not output.is_empty()
		else []
	)
	if shas.size() == 2 and shas[0] == shas[1]:
		GitotLogger.w(
			"Tag '%s' already exists locally on this commit - pushing it as-is." % tag_name
		)
		_git_engine.push_tag(tag_name)
	else:
		GitotLogger.e(
			"Commits pushed, but tag '%s' already exists on a different commit - no tag was created. Rename the tag and push again to tag this commit."
			% tag_name
		)
		tag_conflict.emit(tag_name)
		_pending_tag = { }
