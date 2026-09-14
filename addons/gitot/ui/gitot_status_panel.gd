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


func _init(label: RichTextLabel) -> void:
	_label = label


## Sets the static "owner/repo" label. Called once in _ready() — never changes mid-session.
func update_repo(name: String) -> void:
	_repo_name = name
	_render()


func update_branch(branch: String) -> void:
	_branch = branch
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
	var sync_text: String = "[color=lime_green]↑%d[/color] [color=orange]↓%d[/color]" % [_ahead, _behind]
	_label.text = "%s  ·  [b]%s[/b]  ·  %s" % [_repo_name, branch_display, sync_text]


## Extracts "owner/repo" from a git remote URL (SSH or HTTPS form).
static func _parse_repo_name(url: String) -> String:
	var cleaned: String = url.trim_suffix(".git")
	var parts: PackedStringArray = cleaned.split("/")
	if parts.size() < 2:
		return ""
	return "%s/%s" % [parts[-2].split(":")[-1], parts[-1]]
