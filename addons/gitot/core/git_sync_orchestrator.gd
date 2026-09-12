## git_sync_orchestrator.gd
## Owns the push -> create-tag -> push-tag state machine.
## Domain orchestration (SoC): reacts to GitEngine results and issues the next git command.
## Dock only calls start_push()/retry_tag_push() and reacts to the two signals below.
class_name GitSyncOrchestrator
extends RefCounted

## Emitted when a push starts/ends — dock updates the Push button state.
signal push_state_changed(pushing: bool)
## Emitted when a tag was created but its push failed (true), or on success/reset (false).
signal tag_retry_needed(needed: bool)

var _git_engine: GitEngine
var _pending_tag: Dictionary = {}


func _init(git_engine: GitEngine) -> void:
	_git_engine = git_engine
	_git_engine.command_completed.connect(_on_command_completed)


## Starts a push, chained with tag creation if tag_input has a non-empty tag_name.
func start_push(tag_input: Dictionary) -> void:
	_pending_tag = tag_input
	push_state_changed.emit(true)
	_git_engine.run_network("push", ["push"])


## Re-attempts pushing the tag that was created locally but failed to push.
func retry_tag_push() -> void:
	tag_retry_needed.emit(false)
	_git_engine.push_tag(_pending_tag["tag_name"])


func _on_command_completed(command_name: String, exit_code: int, output: Array) -> void:
	match command_name:
		"push":
			push_state_changed.emit(false)
			if exit_code == 0 and not _pending_tag.get("tag_name", "").is_empty():
				_git_engine.create_tag(_pending_tag["tag_name"], _pending_tag["tag_message"])
		"tag":
			if exit_code == 0:
				_git_engine.push_tag(_pending_tag["tag_name"])
			elif output[0].contains("already exists"):
				# Tag likely survived a prior failed push_tag attempt — push it as-is
				# instead of erroring. Known limitation: if a same-named tag was
				# created manually pointing at a different commit, this pushes THAT
				# tag. Documented in README.
				GitotLogger.w("⚠ Tag '%s' already exists locally - Pushing as-is! ⚠" % _pending_tag["tag_name"])
				_git_engine.push_tag(_pending_tag["tag_name"])
			else:
				GitotLogger.e("Tag creation failed. Tag push aborted!")
				_pending_tag = {}
		"push_tag":
			if exit_code == 0:
				GitotLogger.s("Tag pushed")
				tag_retry_needed.emit(false)
				_pending_tag = {}
			else:
				GitotLogger.e("Tag '%s' created locally but failed to push. Retry pushing with new tag button on the dock" % _pending_tag["tag_name"])
				tag_retry_needed.emit(true)
