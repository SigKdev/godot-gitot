## gitot_diff_gutter.gd
## Applies color-only diff gutters to the active script's CodeEdit.
## Triggered by resource_saved (best-effort) and manual refresh.
class_name GitotDiffGutter
extends RefCounted

## Gutter colors per GitDiffParser.LineState.
const COLOR_ADDED: Color = Color(0.3, 0.8, 0.3)
const COLOR_MODIFIED: Color = Color(0.9, 0.7, 0.2)

## Column index used for our custom gutter on each CodeEdit.
const GUTTER_NAME: String = "gitot_diff_gutter"

var git_engine: GitEngine


func _init(engine: GitEngine) -> void:
	git_engine = engine
	git_engine.command_completed.connect(_on_diff_result)

## Runs diff for the currently active script and refreshes its gutter.
func refresh_current_script() -> void:
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	var script: Script = script_editor.get_current_script()
	if not script:
		return
	var path: String = ProjectSettings.globalize_path(script.resource_path)
	git_engine.run_fast("diff", ["diff", "-U0", "--no-ext-diff", "HEAD", "--", path])

## Ensures the given CodeEdit has our gutter registered exactly once,
## checked by name rather than object identity (more reliable across tab switches).
func _ensure_gutter(code_edit: CodeEdit) -> int:
	for i in range(code_edit.get_gutter_count()):
		if code_edit.get_gutter_name(i) == GUTTER_NAME:
			return i

	code_edit.add_gutter(-1)
	var gutter_idx: int = code_edit.get_gutter_count() - 1
	code_edit.set_gutter_name(gutter_idx, GUTTER_NAME)
	code_edit.set_gutter_type(gutter_idx, CodeEdit.GUTTER_TYPE_STRING)
	code_edit.set_gutter_width(gutter_idx, 4)
	return gutter_idx

## Applies parsed diff line states to the active CodeEdit's gutter.
func _on_diff_result(command_name: String, exit_code: int, output: Array) -> void:
	if command_name != "diff" or output.is_empty():
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

	var line_states: Dictionary = GitDiffParser.parse(output[0])
	for line_num: int in line_states:
		var color: Color = COLOR_ADDED if line_states[line_num] == GitDiffParser.LineState.ADDED else COLOR_MODIFIED
		var target_line: int = line_num - 1
		# Diff line numbers are 1-based; CodeEdit lines are 0-based.
		code_edit.set_line_gutter_text(target_line, gutter_idx, "┃")
		code_edit.set_line_gutter_item_color(target_line, gutter_idx, color)
