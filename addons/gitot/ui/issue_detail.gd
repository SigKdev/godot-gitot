## issue_detail.gd
## Right pane of the Issues tab: metadata header, actions, Markdown body.
## Display only: never touches git (branch creation is emitted up in step 6).
@tool
class_name IssueDetail
extends PanelContainer

## Emitted when the user asks to create a branch. The parent forwards it to git.
signal create_branch_requested(branch_name: String, base: String)

const EMPTY_VALUE: String = "—"

var _url: String = ""
var _number: int = -1 # Issue currently shown; guards the branch name against overwrites.
var _branch_names: PackedStringArray = [] # BaseBranchDropdown index -> branch name.
var _current_branch: String = "" # HEAD at the last refresh; the selection follows it only when it moves.


static func _esc(text: String) -> String:
	# GitHub text is free-form and may contain "[" (BBCode injection).
	return text.replace("[", "[lb]")


## Escaped value, or a dash when GitHub has none (unset type/priority).
static func _field(value: String) -> String:
	return _esc(value) if not value.is_empty() else EMPTY_VALUE


## Black or white text depending on the pill's background luminance.
static func _readable_text_color(bg: Color) -> Color:
	var luminance: float = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color.BLACK if luminance > 0.6 else Color.WHITE


## Label pills as inline BBCode: [bgcolor] gives one RichTextLabel, no extra nodes.
static func _label_pills(labels: Array) -> String:
	if labels.is_empty():
		return "[color=gray]No labels[/color]"
	var pills: PackedStringArray = []
	for label: Dictionary in labels:
		var bg: Color = Color.html(label["color"])
		pills.append(
			"[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]"
			% [bg.to_html(false), _readable_text_color(bg).to_html(false), _esc(label["name"])],
		)
	return "  ".join(pills)


static func _header_bbcode(entry: Dictionary) -> String:
	return "[b][font_size=16]#%d  %s[/font_size][/b]\n%s  ·  %s  ·  Type: %s  ·  Priority: %s\n%s" % [
		entry["number"],
		_esc(entry["title"]),
		_esc(entry["author"]),
		entry["date_short"],
		_field(entry["type"]),
		_field(entry["priority"]),
		_label_pills(entry["labels"]),
	]


func _ready() -> void:
	%OpenButton.pressed.connect(_on_open_pressed)
	%CreateBranchButton.pressed.connect(_request_branch)
	%BranchNameEdit.text_submitted.connect(_request_branch) # Enter key.
	clear()


## Refreshes the base-branch choices. Keeps the current selection if that
## branch still exists, otherwise falls back to the current branch.
## @param branches: Array[Dictionary] from GitBranchParser.parse() (local only).
func set_base_branches(branches: Array[Dictionary]) -> void:
	var previous: String = _selected_base()
	var current: String = ""
	_branch_names.clear()
	%BaseBranchDropdown.clear()
	for branch: Dictionary in branches:
		if branch["is_remote"]:
			continue
		_branch_names.append(branch["name"])
		%BaseBranchDropdown.add_item(branch["name"])
		if branch["is_current"]:
			current = branch["name"]
	# Follow HEAD when it moved (switch/create/first fill); otherwise keep the user's manual pick.
	var head_moved: bool = current != _current_branch
	var target: String = current if head_moved or not _branch_names.has(previous) else previous
	_current_branch = current
	%BaseBranchDropdown.select(_branch_names.find(target))


## Shows one normalized entry (GithubIssueParser). Idempotent: the list re-emits
## the selected issue after a refresh, so an unchanged body keeps its scroll position.
func show_issue(entry: Dictionary) -> void:
	_url = entry["url"]
	# The list re-emits the same issue on refresh/filter: keep a manually edited name.
	if entry["number"] != _number:
		_number = entry["number"]
		%BranchNameEdit.text = entry["branch_name"]
	%HeaderLabel.text = _header_bbcode(entry)
	%ActionRow.visible = true
	if %BodyEdit.text != entry["body"]:
		%BodyEdit.text = entry["body"]
		%BodyEdit.scroll_vertical = 0


## Empty state: nothing selected.
func clear() -> void:
	_url = ""
	_number = -1
	%HeaderLabel.text = "[i]Select an issue.[/i]"
	%BodyEdit.text = ""
	%ActionRow.visible = false


func _selected_base() -> String:
	var index: int = %BaseBranchDropdown.selected
	return _branch_names[index] if index >= 0 else ""


func _on_open_pressed() -> void:
	if not _url.is_empty():
		OS.shell_open(_url)


## The optional argument lets one handler serve both the button (no args)
## and text_submitted (String).
func _request_branch(_text: String = "") -> void:
	var branch_name: String = %BranchNameEdit.text.strip_edges()
	if branch_name.is_empty():
		GitotLogger.w("Branch name is empty. Creation aborted!")
		return
	create_branch_requested.emit(branch_name, _selected_base())
