## gitot_diff_gutter.gd
## Applies color diff gutters to the active script's CodeEdit.
## Triggered by resource_saved and manual refresh.
class_name GitotDiffGutter
extends RefCounted

## Emitted when the user clicks a marked line in the diff gutter.
## @param file_path: res:// path of the script whose gutter was clicked.
## @param line: 0-based CodeEdit line index (native Godot convention, not git's 1-based).
signal hunk_clicked(file_path: String, line: int)

const COLOR_ADDED: Color = "forest_green"
const COLOR_MODIFIED: Color = "dark_orange"
const GUTTER_NAME: String = "gitot_diff_gutter"

var _git_engine: GitEngine


func _init(engine: GitEngine) -> void:
	_git_engine = engine
	_git_engine.command_completed.connect(_on_diff_result)


## Runs diff for the currently active script and refreshes its gutter.
func refresh_current_script() -> void:
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	var script: Script = script_editor.get_current_script()
	if not script:
		return
	var path: String = ProjectSettings.globalize_path(script.resource_path)
	_git_engine.run_fast(
		GitEngine.Command.DIFF,
		["diff", "-U0", "--no-ext-diff", "HEAD", "--", path],
	)


## Disconnects gutter from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if _git_engine and _git_engine.command_completed.is_connected(_on_diff_result):
		_git_engine.command_completed.disconnect(_on_diff_result)


## Ensures the given CodeEdit has the gutter registered exactly once,
## checked by name rather than object identity (more reliable across tab switches).
func _ensure_gutter(code_edit: CodeEdit) -> int:
	var gutter_idx: int = -1
	for i in range(code_edit.get_gutter_count()):
		if code_edit.get_gutter_name(i) == GUTTER_NAME:
			gutter_idx = i
			break

	if gutter_idx == -1:
		code_edit.add_gutter(-1)
		gutter_idx = code_edit.get_gutter_count() - 1
		code_edit.set_gutter_name(gutter_idx, GUTTER_NAME)
		code_edit.set_gutter_type(gutter_idx, CodeEdit.GUTTER_TYPE_STRING)
		code_edit.set_gutter_width(gutter_idx, 4)

	code_edit.set_gutter_clickable(gutter_idx, true)
	if not code_edit.gutter_clicked.is_connected(_on_gutter_clicked):
		code_edit.gutter_clicked.connect(_on_gutter_clicked.bind(gutter_idx))

	return gutter_idx


## Applies parsed diff line states to the active CodeEdit's gutter.
func _on_diff_result(command: GitEngine.Command, exit_code: int, output: Array) -> void:
	if command != GitEngine.Command.DIFF or exit_code != 0 or output.is_empty():
		return

	var current_editor: ScriptEditorBase = EditorInterface.get_script_editor().get_current_editor()
	if not current_editor:
		return
	var code_edit: CodeEdit = current_editor.get_base_editor() as CodeEdit
	if not code_edit:
		return

	var gutter_idx: int = _ensure_gutter(code_edit)

	# Clear previous markers before applying new ones.
	for line in range(code_edit.get_line_count()):
		code_edit.set_line_gutter_text(line, gutter_idx, "")
		code_edit.set_line_gutter_item_color(line, gutter_idx, Color(0, 0, 0, 0))

	# Apply the parsed line states to the gutter.
	var line_states: Dictionary = GitDiffParser.parse(output[0])
	for line_num: int in line_states:
		var color: Color = (
			COLOR_ADDED
			if line_states[line_num] == GitDiffParser.LineState.ADDED
			else COLOR_MODIFIED
		)
		var target_line: int = line_num - 1
		# Diff line numbers are 1-based; CodeEdit lines are 0-based.
		code_edit.set_line_gutter_text(target_line, gutter_idx, "▌")
		code_edit.set_line_gutter_item_color(target_line, gutter_idx, color)


## Filters CodeEdit's gutter_clicked, then re-emits with the owning
## script's path (gutter_clicked only gives line/column index, not file identity).
func _on_gutter_clicked(clicked_line: int, clicked_gutter: int, gutter_idx: int) -> void:
	if clicked_gutter != gutter_idx:
		return
	var script: Script = EditorInterface.get_script_editor().get_current_script()
	if not script:
		return
	hunk_clicked.emit(script.resource_path, clicked_line)
