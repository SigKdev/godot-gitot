## gitot_diff_panel.gd
## Bottom-dock full-context diff viewer. Read-only CodeEdit rendering of
## parsed hunks from GitDiffParser.parse_full(), with per-line +/- coloring,
## per-hunk collapse, and click-to-hunk navigation.
@tool
class_name GitotDiffPanel
extends Control

## Render cap (chars): CodeEdit + per-line coloring gets slow past a few thousand lines.
const MAX_DIFF_CHARS: int = 200_000

## Emitted when the panel's own refresh button is pressed.
signal refresh_requested(file_path: String)

## Emitted when a file row is selected in commit mode (repo-relative path).
signal commit_file_selected(path: String)

## Emitted after the user confirms restoring a file to an older commit's content.
signal restore_file_requested(commit_hash: String, path: String)

const COLOR_ADDED: Color = Color(0.133, 0.545, 0.133, 0.25)
const COLOR_DELETED: Color = Color(0.3, 0.13, 0.13, 0.6)
const COLOR_HEADER: Color = Color(0.22, 0.545, 0.992, 0.11)
const SIGN_GUTTER_NAME: String = "diff_sign"
const LINE_NUM_GUTTER_NAME: String = "diff_line_no"
const FOLD_GUTTER_NAME: String = "diff_fold"
const LINE_PAD_DIGITS: int = 3 # floor: Same as Godot default (001 not 1)

var _line_num_gutter_idx: int = -1
var _sign_gutter_idx: int = -1
var _fold_gutter_idx: int = -1
var _current_file_path: String = ""
var _current_hunks: Array[Dictionary] = [] # stored for jump_to_source_line() and _rebuild_view()
var _current_commit_hash: String = ""
var _collapsed_hunks: Dictionary = { } # hunk_index(int) -> true, only collapsed ones
var _hunk_header_lines: Array[int] = [] # rendered line of each hunk's header, valid for current render only
var _gdscript_highlighter: CodeHighlighter

@onready var _code_edit: CodeEdit = %DiffCodeEdit
@onready var _files_list: GitotCommitFilesList = %CommitFilesList


func _ready() -> void:
	_code_edit.editable = false
	_code_edit.gutters_draw_line_numbers = false # replaced below

	_gdscript_highlighter = _make_gdscript_highlighter()

	# Line numbers gutter
	# built-in count is rendered-line, not source-line
	_code_edit.add_gutter(-1)
	_line_num_gutter_idx = _code_edit.get_gutter_count() - 1
	_code_edit.set_gutter_name(_line_num_gutter_idx, LINE_NUM_GUTTER_NAME)
	_code_edit.set_gutter_type(_line_num_gutter_idx, CodeEdit.GUTTER_TYPE_STRING)

	# +/- gutter
	_code_edit.add_gutter(-1)
	_sign_gutter_idx = _code_edit.get_gutter_count() - 1
	_code_edit.set_gutter_name(_sign_gutter_idx, SIGN_GUTTER_NAME)
	_code_edit.set_gutter_type(_sign_gutter_idx, CodeEdit.GUTTER_TYPE_STRING)
	_code_edit.set_gutter_width(_sign_gutter_idx, 10)

	# Fold gutter
	_code_edit.add_gutter(-1)
	_fold_gutter_idx = _code_edit.get_gutter_count() - 1
	_code_edit.set_gutter_name(_fold_gutter_idx, FOLD_GUTTER_NAME)
	_code_edit.set_gutter_type(_fold_gutter_idx, CodeEdit.GUTTER_TYPE_ICON)
	_code_edit.set_gutter_width(_fold_gutter_idx, 16)
	_code_edit.set_gutter_clickable(_fold_gutter_idx, true)
	_code_edit.gutter_clicked.connect(_on_gutter_clicked)

	%RefreshDiffPanelButton.pressed.connect(_on_refresh_pressed)

	%FoldButton.pressed.connect(_on_fold_pressed)
	%FoldButton.icon = GitotUi.get_icon("CollapseTree")
	%FoldButton.tooltip_text = "Click to fold all header"

	%RestoreFileButton.pressed.connect(
		func() -> void:
			if not _current_file_path.is_empty(): # guards the no-file-changes commit case
				%RestoreConfirmDialog.popup_centered(),
	)
	%RestoreConfirmDialog.confirmed.connect(_on_restore_confirmed)

	_files_list.file_selected.connect(commit_file_selected.emit)

	%CommitInfoLabel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	%CommitInfoLabel.tooltip_text = "Click to copy commit hash"
	%CommitInfoLabel.gui_input.connect(_on_commit_info_gui_input)


## Renders all hunks of one file, fully expanded. See _rebuild_view() for the
## actual line-building/styling — this only resets per-file state.
func show_diff(file_path: String, hunks: Array[Dictionary]) -> void:
	_current_file_path = file_path
	_code_edit.syntax_highlighter = _gdscript_highlighter if file_path.get_extension() == "gd" else null
	_current_hunks = hunks
	_collapsed_hunks.clear()
	%DiffFilePathLabel.text = "[b]File:[/b]  %s" % file_path
	_rebuild_view()


## Resolves a source-file line (git's 1-based new-file numbering) to its
## rendered CodeEdit line, expanding its hunk first if collapsed, then
## scrolls/highlights it.
func jump_to_source_line(source_line: int) -> void:
	for idx: int in _current_hunks.size():
		var hunk: Dictionary = _current_hunks[idx]
		var new_file_line: int = hunk["new_start"]
		var offset: int = 0
		for entry: Dictionary in hunk["lines"]:
			if entry["type"] != "del":
				if new_file_line == source_line:
					if _collapsed_hunks.has(idx):
						_collapsed_hunks.erase(idx)
						_rebuild_view()
					_code_edit.set_caret_line(_hunk_header_lines[idx] + 1 + offset)
					_code_edit.center_viewport_to_caret()
					return
				new_file_line += 1
			offset += 1


## Commit mode: file list visible, refresh button hidden (a commit's diff never changes,
## and the button would re-diff the working tree). Working-tree callers pass false.
func set_commit_mode(enabled: bool) -> void:
	%CommitColumn.visible = enabled # Hide the whole column: an empty one still keeps its split slot.
	_files_list.visible = enabled
	%RefreshDiffPanelButton.visible = not enabled
	%CommitInfoLabel.visible = enabled
	%RestoreFileButton.visible = enabled


## Shows a commit's changed files; the list auto-selects the first row.
func show_commit_files(files: Array[Dictionary]) -> void:
	set_commit_mode(true)
	_files_list.show_files(files)
	if files.is_empty():
		_code_edit.clear() # e.g. merge commit: avoid leaving a stale diff on screen.
		_current_file_path = "" # also blocks a stale Restore (see RestoreFileButton guard in _ready())
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
	_current_commit_hash = entry["hash"]
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


## Full-rebuild-on-toggle keeps buffer text and per-line gutter/color state
## always in lockstep (patching individual lines risked them drifting apart).
func _rebuild_view() -> void:
	var render_lines: Array[Dictionary] = []
	_hunk_header_lines.resize(_current_hunks.size())
	for idx: int in _current_hunks.size():
		var hunk: Dictionary = _current_hunks[idx]
		_hunk_header_lines[idx] = render_lines.size()
		render_lines.append(_make_header_line(hunk))
		if not _collapsed_hunks.has(idx):
			render_lines.append_array(_make_numbered_lines(hunk))

	for entry: Dictionary in render_lines:
		if entry.has("line_no"):
			entry["line_no"] = str(entry["line_no"]).pad_zeros(LINE_PAD_DIGITS)
	_code_edit.set_gutter_width(_line_num_gutter_idx, LINE_PAD_DIGITS * 8 + 4) # 8 px/digit is a monospace-width approximation (not exact font metrics)

	var texts: PackedStringArray = []
	for entry: Dictionary in render_lines:
		texts.append(entry["text"])
	_code_edit.text = "\n".join(texts) # single assignment: reassigning mid-loop wipes prior per-line state

	for i: int in range(render_lines.size()):
		_style_line(i, render_lines[i])
	for idx: int in _current_hunks.size():
		_code_edit.set_line_gutter_icon(
			_hunk_header_lines[idx],
			_fold_gutter_idx,
			(
				GitotUi.get_icon("CodeFoldedRightArrow")
				if _collapsed_hunks.has(idx)
				else GitotUi.get_icon("CodeFoldDownArrow")
			),
		)

	%FoldButton.icon = (
		GitotUi.get_icon("ExpandTree")
		if (not _current_hunks.is_empty() and _collapsed_hunks.size() == _current_hunks.size())
		else GitotUi.get_icon("CollapseTree")
	)
	%FoldButton.tooltip_text = (
		"Click to unfold all header"
		if (not _current_hunks.is_empty() and _collapsed_hunks.size() == _current_hunks.size())
		else "Click to fold all header"
	)


func _style_line(i: int, entry: Dictionary) -> void:
	match entry["type"]:
		"header":
			_code_edit.set_line_background_color(i, COLOR_HEADER)
		"add":
			_code_edit.set_line_background_color(i, COLOR_ADDED)
			_code_edit.set_line_gutter_text(i, _sign_gutter_idx, "+")
			_code_edit.set_line_gutter_item_color(i, _sign_gutter_idx, Color.LIME_GREEN)
			_code_edit.set_line_gutter_text(i, _line_num_gutter_idx, str(entry["line_no"]))
			_code_edit.set_line_gutter_item_color(i, _line_num_gutter_idx, Color(0.5, 0.5, 0.5))
		"del":
			_code_edit.set_line_background_color(i, COLOR_DELETED)
			_code_edit.set_line_gutter_text(i, _sign_gutter_idx, "-")
			_code_edit.set_line_gutter_item_color(i, _sign_gutter_idx, Color.RED)
			_code_edit.set_line_gutter_text(i, _line_num_gutter_idx, str(entry["line_no"]))
			_code_edit.set_line_gutter_item_color(i, _line_num_gutter_idx, Color(0.5, 0.5, 0.5))
		"context":
			_code_edit.set_line_gutter_text(i, _line_num_gutter_idx, str(entry["line_no"]))
			_code_edit.set_line_gutter_item_color(i, _line_num_gutter_idx, Color(0.5, 0.5, 0.5))


func _make_gdscript_highlighter() -> CodeHighlighter:
	var hl: CodeHighlighter = CodeHighlighter.new()
	var keyword_color: Color = Color("ff7085")
	for kw: String in [
		"func",
		"var",
		"const",
		"class_name",
		"extends",
		"signal",
		"if",
		"else",
		"elif",
		"for",
		"while",
		"return",
		"match",
		"in",
		"and",
		"or",
		"not",
		"true",
		"false",
		"null",
		"self",
		"static",
		"class",
		"enum",
		"pass",
		"break",
		"continue",
		"await",
	]:
		hl.add_keyword_color(kw, keyword_color)
	hl.number_color = Color("a1ffe0")
	hl.symbol_color = Color("cdcfd2")
	hl.function_color = Color("66c3ff")
	hl.member_variable_color = Color("c6c6c6")
	hl.add_color_region("#", "", Color("8a8a8aff"), true) # line comment
	hl.add_color_region("\"", "\"", Color("ffeda1"))
	hl.add_color_region("'", "'", Color("ffeda1"))
	return hl


func _on_gutter_clicked(line: int, gutter_idx: int) -> void:
	if gutter_idx != _fold_gutter_idx:
		return
	var idx: int = _hunk_header_lines.find(line)
	if idx == -1:
		return
	if _collapsed_hunks.has(idx):
		_collapsed_hunks.erase(idx)
	else:
		_collapsed_hunks[idx] = true
	_rebuild_view()


func _on_commit_info_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _current_commit_hash.is_empty():
			return
		DisplayServer.clipboard_set(_current_commit_hash)
		%CommitInfoLabel.modulate = Color.LIME_GREEN
		create_tween().tween_property(%CommitInfoLabel, "modulate", Color.WHITE, 0.4)


func _on_fold_pressed() -> void:
	if _collapsed_hunks.size() == _current_hunks.size():
		_collapsed_hunks.clear()
	else:
		for idx: int in _current_hunks.size():
			_collapsed_hunks[idx] = true
	_rebuild_view()


func _on_restore_confirmed() -> void:
	restore_file_requested.emit(_current_commit_hash, _current_file_path)


func _on_refresh_pressed() -> void:
	if not _current_file_path.is_empty():
		refresh_requested.emit(_current_file_path)
