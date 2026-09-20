## git_sync_orchestrator.gd
## Owns the push -> create-tag -> push-tag state machine.
## Reacts to GitEngine results and issues the next git command.
class_name GitSyncOrchestrator
extends RefCounted

## Emitted when a push starts/ends — dock updates the Push button state.
signal push_state_changed(pushing: bool)

## Emitted when a tag was created but its push failed (true), or on success/reset (false).
signal tag_retry_needed(needed: bool)

var _git_engine: GitEngine
var _pending_tag: Dictionary = { }


func _init(git_engine: GitEngine) -> void:
	_git_engine = git_engine
	_git_engine.command_completed.connect(_on_command_completed)


## Starts a push, chained with tag creation if tag_input has a non-empty tag_name.
func start_push(tag_input: Dictionary) -> void:
	_pending_tag = tag_input
	push_state_changed.emit(true)
	_git_engine.run_network(GitEngine.Command.PUSH, ["push", "-u", "origin", "HEAD"])


## Re-attempts pushing the tag that was created locally but failed to push.
func retry_tag_push() -> void:
	tag_retry_needed.emit(false)
	_git_engine.push_tag(_pending_tag["tag_name"])


## Disconnects from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if _git_engine.command_completed.is_connected(_on_command_completed):
		_git_engine.command_completed.disconnect(_on_command_completed)


## Reacts to GitEngine command completion events and issues the next command in the push->tag->push-tag chain.
func _on_command_completed(command: GitEngine.Command, exit_code: int, output: Array) -> void:
	match command:
		GitEngine.Command.PUSH:
			push_state_changed.emit(false)
			if exit_code == 0 and not _pending_tag.get("tag_name", "").is_empty():
				_git_engine.create_tag(_pending_tag["tag_name"], _pending_tag["tag_message"])
		GitEngine.Command.TAG:
			if exit_code == 0:
				_git_engine.push_tag(_pending_tag["tag_name"])
			elif not output.is_empty() and output[0].contains("already exists"):
				_handle_tag_collision(_pending_tag["tag_name"])
			else:
				GitotLogger.e("Tag creation failed. Tag push aborted!")
				_pending_tag = { }
		GitEngine.Command.PUSH_TAG:
			if exit_code == 0:
				GitotLogger.s("Tag pushed")
				tag_retry_needed.emit(false)
				_pending_tag = { }
			else:
				GitotLogger.e(
					"Tag '%s' created locally but failed to push. Retry pushing with new tag button on the dock"
					% _pending_tag["tag_name"]
				)
				tag_retry_needed.emit(true)


## Resolves a "tag already exists" TAG failure. Only pushes if the existing local
## tag already points at HEAD (legitimate retry after a prior failed push) -
## never pushes a same-named tag pointing at an unrelated commit.
func _handle_tag_collision(tag_name: String) -> void:
	if _git_engine.get_tag_commit(tag_name) == _git_engine.get_head_commit():
		GitotLogger.w("Tag '%s' already exists locally on this commit - Pushing as-is!" % tag_name)
		_git_engine.push_tag(tag_name)
	else:
		GitotLogger.e(
			"Commit pushed. Tag '%s' already exists on a different commit - tag NOT created. Rename tag and push again to tag this commit."
			% tag_name
		)
		EditorInterface.get_editor_toaster().push_toast(
			"Gitot: Commit pushed, but tag '%s' exists on another commit. Rename tag and push again to tag it."
			% tag_name,
			EditorToaster.SEVERITY_ERROR,
		)
		_pending_tag = { }
