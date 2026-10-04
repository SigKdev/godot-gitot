## gitot_status_panel.gd
## Compact repo-state summary line: repo, branch, scope, sync status.
class_name GitotStatusPanel
extends RefCounted

const MAX_BRANCH_CHARS: int = 24

## Display-only shortening; unknown scopes fall through unchanged.
const SCOPE_SHORT: Dictionary = { "(Local + Remote)": "(L+R)" }

var _label: RichTextLabel
var _repo_name: String = ""
var _branch: String = ""
## False until the first branch list arrives: an empty name then means "not loaded", not "detached".
var _branch_known: bool = false
var _branch_scope: String = ""
var _has_upstream: bool = false
var _ahead: int = 0
var _behind: int = 0


func _init(label: RichTextLabel) -> void:
	_label = label


## Sets the static "owner/repo" label. Called once in _ready() - never changes mid-session.
func update_repo(name: String) -> void:
	_repo_name = name
	_render()


func update_branch(branch: String, scope: String = "") -> void:
	_branch = branch
	_branch_known = true
	_branch_scope = SCOPE_SHORT.get(scope, scope) as String
	_render()


## Updates sync status. Returns true if it changed since last call,
## so the caller can decide whether to log (avoid spam on redundant refreshes).
## @param has_upstream: false = branch never pushed (counts are then meaningless).
func update_sync(has_upstream: bool, ahead: int, behind: int) -> bool:
	var changed: bool = (
		has_upstream != _has_upstream or ahead != _ahead or behind != _behind
	)
	_has_upstream = has_upstream
	_ahead = ahead
	_behind = behind
	_render()
	return changed


## Same symbols as the branch list (GitotUi.sync_symbol), plus the counts next to arrows:
## "↑ 2", "↓ 1", "↑↓ 2/1"; "✓" (in sync) and "—" (no upstream) need none.
func _sync_markup() -> String:
	var key: String = GitotUi.sync_key(_ahead, _behind)
	var symbol: String = GitotUi.sync_symbol(_has_upstream, key)
	var color: String = GitotUi.sync_color(_has_upstream, key).to_html(false)
	if not _has_upstream:
		return "[color=#%s]%s[/color]" % [color, symbol]
	return "[color=#%s]%s%s[/color]" % [color, symbol, GitotUi.sync_counts(key, _ahead, _behind)]


func _render() -> void:
	var branch_display: String = "…"
	if _branch_known:
		branch_display = (
			GitotUi.ellipsize(_branch, MAX_BRANCH_CHARS)
			if not _branch.is_empty()
			else "[color=red](detached HEAD)[/color]"
		)

	var scope_display: String = ""
	if not _branch_scope.is_empty():
		scope_display = " %s" % _branch_scope

	_label.text = "%s  ·  [b]%s[/b][font_size=10]%s[/font_size]  ·  %s" % [
		_repo_name,
		branch_display,
		scope_display,
		_sync_markup(),
	]
