## gitot_repo_init.gd
## "Initialize repository" use case of a project folder without git: `git init -b main`, then a Godot
## .gitignore if the folder has none. RefCounted, constructor-injected - same pattern as GitotBranchCreator.
class_name GitotRepoInit
extends RefCounted

## Emitted after a successful init. The dock re-probes the folder and loads the panels.
signal initialized

const BUTTON_ICON: String = "Add"

var _git_engine: GitEngine
var _button: Button


## @param button: scene button of the "no repository" view; icon and signal are wired here.
func _init(git_engine: GitEngine, button: Button) -> void:
	_git_engine = git_engine
	_button = button
	GitotUi.set_busy(_button, false, BUTTON_ICON)
	_button.pressed.connect(_on_pressed)


func _on_pressed() -> void:
	GitotUi.set_busy(_button, true, BUTTON_ICON) # Blocks a second click while git runs.
	_git_engine.init_repo(_on_init_done)


## Finished `git init`: logs it, adds the .gitignore, announces success.
func _on_init_done(exit_code: int, output: Array[String]) -> void:
	GitotUi.set_busy(_button, false, BUTTON_ICON)
	var raw: String = output[0].strip_edges() if not output.is_empty() else ""
	if exit_code != 0:
		GitotLogger.fail(
			"Could not initialize a git repository in the project folder.",
			raw,
			"Common fail causes: git older than 2.28 (no 'git init -b'), or the project folder is not writable.",
		)
		return
	GitotLogger.s("Git repository initialized on branch '%s'." % GitEngine.DEFAULT_BRANCH)
	if not raw.is_empty():
		GitotLogger.g(raw)
	_report_gitignore(GitIgnore.create_if_missing("res://"))
	GitotLogger.h("Nothing is committed yet: stage and commit your files ('main' then appears in Branches), then press Push: it asks for the repository URL.")
	initialized.emit()


## One info/warning line for the outcome of the .gitignore step (a failure there never undoes the init).
func _report_gitignore(result: GitIgnore.Result) -> void:
	match result:
		GitIgnore.Result.CREATED:
			GitotLogger.i("Created .gitignore: the Godot cache (.godot/) and imported translations are ignored.")
		GitIgnore.Result.EXISTS:
			GitotLogger.i(".gitignore already exists - left unchanged.")
		GitIgnore.Result.FAILED:
			GitotLogger.w("Could not create .gitignore. Add one yourself: .godot/ must not be committed.")
