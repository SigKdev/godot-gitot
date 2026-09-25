## gitot_diff_panel.gd
## Bottom-dock full-context diff viewer. Read-only CodeEdit rendering of
## parsed hunks from GitDiffParser.parse_full(), with per-line +/- coloring
## and click-to-hunk navigation. Independent from GitotDiffGutter (SoC —
## separate listener on GitEngine.command_completed, see gitot.gd wiring).
@tool
class_name GitotDiffPanel
extends Control

## Emitted when the panel's own refresh button is pressed.
signal refresh_requested(file_path: String)

## Emitted when a file row is selected in commit mode (repo-relative path).
signal commit_file_selected(path: String)

const COLOR_ADDED: Color = Color(0.133, 0.545, 0.133, 0.2)
const COLOR_DELETED: Color = Color(0.3, 0.13, 0.13, 0.6)
const COLOR_HEADER: Color = Color(0.2, 0.2, 0.2)
const SIGN_GUTTER_NAME: String = "diff_sign"
const LINE_NUM_GUTTER_NAME: String = "diff_line_no"

var _line_num_gutter_idx: int = -1
var _current_file_path: String = ""
var _sign_gutter_idx: int = -1
var _current_hunks: Array[Dictionary] = [] # stored for jump_to_source_line() and future refresh

@onready var _code_edit: CodeEdit = %DiffCodeEdit
@onready var _files_list: GitotCommitFilesList = %CommitFilesList


func _ready() -> void:
	_code_edit.editable = false
	_code_edit.gutters_draw_line_numbers = false # replaced below

	# built-in count is rendered-line, not source-line
	_code_edit.add_gutter(-1)
	_line_num_gutter_idx = _code_edit.get_gutter_count() - 1
	_code_edit.set_gutter_name(_line_num_gutter_idx, LINE_NUM_GUTTER_NAME)
	_code_edit.set_gutter_type(_line_num_gutter_idx, CodeEdit.GUTTER_TYPE_STRING)

	_code_edit.add_gutter(-1)
	_sign_gutter_idx = _code_edit.get_gutter_count() - 1
	_code_edit.set_gutter_name(_sign_gutter_idx, SIGN_GUTTER_NAME)
	_code_edit.set_gutter_type(_sign_gutter_idx, CodeEdit.GUTTER_TYPE_STRING)
	_code_edit.set_gutter_width(_sign_gutter_idx, 10)

	%RefreshDiffPanelButton.pressed.connect(_on_refresh_pressed)
	_files_list.file_selected.connect(commit_file_selected.emit)


## Renders all hunks of one file: a @@ header before each hunk, then its lines.
## Text is built once (single .text assignment), THEN colored/signed in a second
## pass — reassigning .text mid-loop wipes prior per-line state.
func show_diff(file_path: String, hunks: Array[Dictionary]) -> void:
	_current_file_path = file_path
	_current_hunks = hunks
	%DiffFilePathLabel.text = "[b]File:[/b]  %s" % file_path

	var render_lines: Array[Dictionary] = []
	for hunk: Dictionary in hunks:
		render_lines.append(_make_header_line(hunk))
		render_lines.append_array(_make_numbered_lines(hunk))

	var max_digits: int = 3 # floor: Same as Godot default (001 not 1)
	for entry: Dictionary in render_lines:
		if entry.has("line_no"):
			entry["line_no"] = str(entry["line_no"]).pad_zeros(max_digits)
	_code_edit.set_gutter_width(_line_num_gutter_idx, max_digits * 8 + 4) # 8 px/digit is a monospace-width approximation (not exact font metrics)

	var texts: PackedStringArray = []
	for entry: Dictionary in render_lines:
		texts.append(entry["text"])
	_code_edit.text = "\n".join(texts)

	for i in range(render_lines.size()):
		match render_lines[i]["type"]:
			"header":
				_code_edit.set_line_background_color(i, COLOR_HEADER)
			"add":
				_code_edit.set_line_background_color(i, COLOR_ADDED)
				_code_edit.set_line_gutter_text(i, _sign_gutter_idx, "+")
				_code_edit.set_line_gutter_item_color(i, _sign_gutter_idx, Color.LIME_GREEN)
				_code_edit.set_line_gutter_text(
					i,
					_line_num_gutter_idx,
					str(render_lines[i]["line_no"]),
				)
				_code_edit.set_line_gutter_item_color(i, _line_num_gutter_idx, Color(0.5, 0.5, 0.5))
			"del":
				_code_edit.set_line_background_color(i, COLOR_DELETED)
				_code_edit.set_line_gutter_text(i, _sign_gutter_idx, "-")
				_code_edit.set_line_gutter_item_color(i, _sign_gutter_idx, Color.RED)
				_code_edit.set_line_gutter_text(
					i,
					_line_num_gutter_idx,
					str(render_lines[i]["line_no"]),
				)
				_code_edit.set_line_gutter_item_color(i, _line_num_gutter_idx, Color(0.5, 0.5, 0.5))
			"context":
				_code_edit.set_line_gutter_text(
					i,
					_line_num_gutter_idx,
					str(render_lines[i]["line_no"]),
				)
				_code_edit.set_line_gutter_item_color(i, _line_num_gutter_idx, Color(0.5, 0.5, 0.5))


## Resolves a source-file line (git's 1-based new-file numbering)
## to its rendered CodeEdit line, then scrolls/highlights it.
## ("del" lines don't exist in the new file, so they don't consume a new-file line number).
## Mirrors show_diff()'s separator insertion so line counting stays in sync.
func jump_to_source_line(source_line: int) -> void:
	var rendered_line: int = 0
	for hunk: Dictionary in _current_hunks:
		rendered_line += 1 # header line
		var new_file_line: int = hunk["new_start"]
		for entry: Dictionary in hunk["lines"]:
			if entry["type"] != "del":
				if new_file_line == source_line:
					_code_edit.set_caret_line(rendered_line)
					_code_edit.center_viewport_to_caret()
					return
				new_file_line += 1
			rendered_line += 1


## Commit mode: file list visible, refresh button hidden (a commit's diff never changes,
## and the button would re-diff the working tree). Working-tree callers pass false.
func set_commit_mode(enabled: bool) -> void:
	%CommitColumn.visible = enabled # Hide the whole column: an empty one still keeps its split slot.
	_files_list.visible = enabled
	%RefreshDiffPanelButton.visible = not enabled
	%CommitInfoLabel.visible = enabled


## Shows a commit's changed files; the list auto-selects the first row.
func show_commit_files(files: Array[Dictionary]) -> void:
	set_commit_mode(true)
	_files_list.show_files(files)
	if files.is_empty():
		_code_edit.clear() # e.g. merge commit: avoid leaving a stale diff on screen.
		%DiffFilePathLabel.text = "[i]No file changes to show.[/i]"


## Commit header: message / author / exact date / hash, same fields as the history list.
## BBCode is escaped: commit messages and author names are free text and may contain "[".
func show_commit_info(entry: Dictionary) -> void:
	var message: String = String(entry["message"]).replace("[", "[lb]")
	var author: String = String(entry["author"]).replace("[", "[lb]")
	%CommitInfoLabel.text = "[b]%s[/b]  ·  %s  ·  %s  ·  [color=gray]%s[/color]" % [
		message,
		author,
		entry["date_short"],
		entry["hash"],
	]
	%CommitInfoLabel.visible = true


## Builds the @@ header for one hunk, matching git's own -U3 format. old_count/
## new_count are derived from the hunk's line list (del+context / add+context).
func _make_header_line(hunk: Dictionary) -> Dictionary:
	var old_count: int = 0
	var new_count: int = 0
	for entry: Dictionary in hunk["lines"]:
		if entry["type"] != "add":
			old_count += 1
		if entry["type"] != "del":
			new_count += 1
	var text: String = "@@ -%d,%d +%d,%d @@" % [
		hunk["old_start"],
		old_count,
		hunk["new_start"],
		new_count,
	]
	return { "type": "header", "text": text }


func _make_numbered_lines(hunk: Dictionary) -> Array[Dictionary]:
	var old_line: int = hunk["old_start"]
	var new_line: int = hunk["new_start"]
	var result: Array[Dictionary] = []
	for entry: Dictionary in hunk["lines"]:
		var numbered: Dictionary = entry.duplicate()
		match entry["type"]:
			"del":
				numbered["line_no"] = old_line
				old_line += 1
			"add":
				numbered["line_no"] = new_line
				new_line += 1
			_: # context
				numbered["line_no"] = new_line
				old_line += 1
				new_line += 1
		result.append(numbered)
	return result


func _on_refresh_pressed() -> void:
	if not _current_file_path.is_empty():
		refresh_requested.emit(_current_file_path)
