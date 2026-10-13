## gitot_diff_gutter.gd
## Applies color diff gutters to the active script's CodeEdit.
## Triggered by resource_saved and manual refresh.
class_name GitotDiffGutter
extends RefCounted

## Emitted when the user clicks a marked line in the diff gutter.
## @param file_path: res:// path of the script whose gutter was clicked.
## @param line: 0-based CodeEdit line index (native Godot convention, not git's 1-based).
signal hunk_clicked(file_path: String, line: int)

const COLOR_ADDED: Color = Color.FOREST_GREEN
const COLOR_MODIFIED: Color = Color.DARK_ORANGE
const GUTTER_NAME: String = "gitot_diff_gutter"

var _git_engine: GitEngine
## Instance ids of the CodeEdits that got the gutter, so teardown() can take it back out. Ids, not
## references: an editor tab closed meanwhile is freed, and instance_from_id() then gives null.
var _edit_ids: Array[int] = []


func _init(engine: GitEngine) -> void:
	_git_engine = engine


## Clears the markers and hides the gutter in every editor that still has it open.
## Called by gitot.gd on exit, so a disabled plugin leaves no stale markers behind.
func teardown() -> void:
	for id: int in _edit_ids:
		var code_edit: CodeEdit = instance_from_id(id) as CodeEdit
		if code_edit:
			_hide_gutter(code_edit)
	_edit_ids.clear()


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
		{ },
		_on_diff_result.bind(script.resource_path), # The result knows which script it was for.
	)


## Ensures the given CodeEdit has the gutter registered exactly once,
## checked by name rather than object identity (more reliable across tab switches).
func _ensure_gutter(code_edit: CodeEdit) -> int:
	var gutter_idx: int = -1
	for i: int in range(code_edit.get_gutter_count()):
		if code_edit.get_gutter_name(i) == GUTTER_NAME:
			gutter_idx = i
			break

	if gutter_idx == -1:
		code_edit.add_gutter(-1)
		gutter_idx = code_edit.get_gutter_count() - 1
		code_edit.set_gutter_name(gutter_idx, GUTTER_NAME)
		code_edit.set_gutter_type(gutter_idx, CodeEdit.GUTTER_TYPE_STRING)
		code_edit.set_gutter_width(gutter_idx, 4)

	code_edit.set_gutter_draw(gutter_idx, true) # Hidden again by teardown(); a re-enabled plugin reuses it.
	code_edit.set_gutter_clickable(gutter_idx, true)
	# Test the same bound Callable that is connected: a bare method never equals a bound one.
	var on_clicked: Callable = _on_gutter_clicked.bind(gutter_idx)
	if not code_edit.gutter_clicked.is_connected(on_clicked):
		code_edit.gutter_clicked.connect(on_clicked)
	if not _edit_ids.has(code_edit.get_instance_id()):
		_edit_ids.append(code_edit.get_instance_id())

	return gutter_idx


## Blanks the marker of every line of the gutter.
func _clear_markers(code_edit: CodeEdit, gutter_idx: int) -> void:
	for line: int in range(code_edit.get_line_count()):
		code_edit.set_line_gutter_text(line, gutter_idx, "")
		code_edit.set_line_gutter_item_color(line, gutter_idx, Color(0, 0, 0, 0))


## Inverse of _ensure_gutter(): clears the markers, hides the gutter and drops the click connection.
## Hidden, not removed: CodeEdit.remove_gutter() raised an index error in the tests (Godot 4.7).
func _hide_gutter(code_edit: CodeEdit) -> void:
	for i: int in range(code_edit.get_gutter_count()):
		if code_edit.get_gutter_name(i) != GUTTER_NAME:
			continue
		var on_clicked: Callable = _on_gutter_clicked.bind(i)
		if code_edit.gutter_clicked.is_connected(on_clicked):
			code_edit.gutter_clicked.disconnect(on_clicked)
		_clear_markers(code_edit, i)
		code_edit.set_gutter_draw(i, false)
		code_edit.set_gutter_clickable(i, false)
		return


## Applies parsed diff line states to the gutter of the requested script, if it is still the active tab.
func _on_diff_result(exit_code: int, output: Array[String], script_path: String) -> void:
	if exit_code != 0 or output.is_empty():
		return

	var current_script: Script = EditorInterface.get_script_editor().get_current_script()
	if not current_script or current_script.resource_path != script_path:
		return

	var current_editor: ScriptEditorBase = EditorInterface.get_script_editor().get_current_editor()
	if not current_editor:
		return
	var code_edit: CodeEdit = current_editor.get_base_editor() as CodeEdit
	if not code_edit:
		return

	var gutter_idx: int = _ensure_gutter(code_edit)

	_clear_markers(code_edit, gutter_idx) # Before applying the new ones.

	# Apply the parsed line states to the gutter.
	var line_states: Dictionary = GitDiffParser.parse(output[0])
	for line_num: int in line_states:
		var color: Color = (
			COLOR_ADDED
			if line_states[line_num] == GitDiffParser.LineState.ADDED
			else COLOR_MODIFIED
		)
		# Diff line numbers are 1-based; CodeEdit lines are 0-based.
		var target_line: int = line_num - 1
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
