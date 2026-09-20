## gitot_status_panel.gd
## Compact repo-state summary line: branch, sync status, dirty counts.
class_name GitotStatusPanel
extends RefCounted

const MAX_BRANCH_CHARS: int = 24

var _label: RichTextLabel
var _repo_name: String = ""
var _branch: String = ""
var _ahead: int = 0
var _behind: int = 0
var _branch_scope: String = ""


func _init(label: RichTextLabel) -> void:
	_label = label


## Sets the static "owner/repo" label. Called once in _ready() - never changes mid-session.
func update_repo(name: String) -> void:
	_repo_name = name
	_render()


func update_branch(branch: String, scope: String = "") -> void:
	_branch = branch
	_branch_scope = scope
	_render()


## Updates sync status. Returns true if ahead/behind changed since last call,
## so the caller can decide whether to log (avoid spam on redundant refreshes).
func update_sync(ahead: int, behind: int) -> bool:
	var changed: bool = ahead != _ahead or behind != _behind
	_ahead = ahead
	_behind = behind
	_render()
	return changed


func _render() -> void:
	var branch_display: String = _branch
	if branch_display.is_empty():
		branch_display = "[color=red](detached HEAD)[/color]"
	elif branch_display.length() > MAX_BRANCH_CHARS:
		branch_display = branch_display.left(MAX_BRANCH_CHARS - 1) + "…"

	var scope_display: String = ""
	if not _branch_scope.is_empty():
		scope_display = " %s" % _branch_scope

	var sync_text: String = "[color=lime_green]↑%d[/color] [color=orange]↓%d[/color]" % [
		_ahead,
		_behind,
	]

	_label.text = "[font_size=11]%s  ·  [b]%s[/b]%s  ·  %s[/font_size]" % [
		_repo_name,
		branch_display,
		scope_display,
		sync_text,
	]
