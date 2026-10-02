## gitot_branch_panel.gd
## Branches section: list (name / sync / last commit) +
## Fetch button in the fold title bar.
## Double-click switches branch. UI-only — no OS.execute() calls.
class_name GitotBranchPanel
extends RefCounted

## Emitted when the selected row changes, and after every populate().
## @param branch: the selected entry (see GitBranchParser), {} if nothing is selected.
signal selection_changed(branch: Dictionary)

const FOLD_TITLE: String = "Branches"
const COL_NAME: int = 0
const COL_SYNC: int = 1
const COL_DATE: int = 2
const FETCH_ICON: String = "AssetStore"

## GitBranchParser "sync" (upstream:trackshort) -> cell text. Symbols, not git's
## localized "track" text, so the cell never depends on the user's git language.
const SYNC_SYMBOLS: Dictionary[String, String] = { ">": "↑", "<": "↓", "<>": "↑↓", "=": "✓" }

var _git_engine: GitEngine
var _fold: FoldableContainer
var _tree: Tree
var _fetch_button: Button


## Hides remote entries that already have a local counterpart
## (e.g. "main" + "origin/main"); remote-only branches stay.
static func _filter_redundant_remotes(branches: Array[Dictionary]) -> Array[Dictionary]:
	var local_names: Array[String] = []
	for branch: Dictionary in branches:
		if not branch["is_remote"]:
			local_names.append(branch["name"])

	var result: Array[Dictionary] = []
	for branch: Dictionary in branches:
		if branch["is_remote"] and branch["name"].trim_prefix("origin/") in local_names:
			continue
		result.append(branch)
	return result


## Display order: current branch, other local branches, remote-only;
## newest commit first inside each group.
static func _is_before(a: Dictionary, b: Dictionary) -> bool:
	if a["is_current"] != b["is_current"]:
		return a["is_current"]
	if a["is_remote"] != b["is_remote"]:
		return b["is_remote"] # a is local, b is remote
	return a["date_unix"] > b["date_unix"]


static func _sync_text(branch: Dictionary) -> String:
	if branch["is_remote"]:
		return ""
	if branch["upstream"].is_empty():
		return "—" # never pushed / no upstream
	# Upstream configured but no trackshort symbol -> the remote branch is gone.
	return SYNC_SYMBOLS.get(branch["sync"], "gone")


static func _tooltip(branch: Dictionary, scope: String) -> String:
	var title: String = branch["name"] + ("  ·  " + scope if not scope.is_empty() else "")
	var lines: PackedStringArray = [title]
	if not branch["upstream"].is_empty():
		# "track" is git's localized text: display only, never parsed.
		lines.append(("Upstream: %s %s" % [branch["upstream"], branch["track"]]).strip_edges())
	lines.append("%s  ·  %s" % [branch["hash"], branch["date_exact"]])
	lines.append(branch["subject"])
	return "\n".join(lines)


## @param fold: hosts the section; its title shows the branch count.
## @param tree: 3-column Tree (set up here).
func _init(git_engine: GitEngine, fold: FoldableContainer, tree: Tree) -> void:
	_git_engine = git_engine
	_fold = fold
	_tree = tree
	_setup_tree()
	_fetch_button = GitotUi.add_title_button(_fold, FETCH_ICON, "Fetch remote updates")
	_fetch_button.pressed.connect(_on_fetch_pressed)


## Rebuilds the list from a fresh branch list. Called by the router on the "branches" result.
## @param branches: Array[Dictionary] from GitBranchParser.parse().
## @param branch_scopes: branch name -> scope text (tooltip only).
func populate(branches: Array[Dictionary], branch_scopes: Dictionary[String, String]) -> void:
	var selected_name: String = _selected_branch().get("name", "")
	var shown: Array[Dictionary] = _filter_redundant_remotes(branches)
	shown.sort_custom(_is_before)

	_tree.clear()
	var root: TreeItem = _tree.create_item()
	for branch: Dictionary in shown:
		_add_row(root, branch, branch_scopes.get(branch["name"], ""))

	var target: TreeItem = _find_item(selected_name)
	if target == null:
		target = root.get_first_child()
	if target:
		target.select(COL_NAME)
	_fold.title = "%s (%d)" % [FOLD_TITLE, shown.size()]
	selection_changed.emit(_selected_branch())


## Called by the dock when the fetch result arrives (success or failure).
func on_fetch_finished() -> void:
	GitotUi.set_busy(_fetch_button, false, FETCH_ICON)


func _setup_tree() -> void:
	_tree.hide_root = true
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.set_column_title(COL_NAME, "Branch")
	_tree.set_column_title(COL_SYNC, "Sync")
	_tree.set_column_title(COL_DATE, "Updated")
	_tree.set_column_expand(COL_NAME, true) # Name gets the remaining space.
	_tree.set_column_clip_content(COL_NAME, true) # Ellipsis instead of widening the dock.
	_tree.set_column_expand(COL_SYNC, false)
	_tree.set_column_expand(COL_DATE, false)
	_tree.set_column_custom_minimum_width(COL_SYNC, 44)
	_tree.set_column_custom_minimum_width(COL_DATE, 80)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_selected.connect(_on_item_selected)


func _add_row(root: TreeItem, branch: Dictionary, scope: String) -> void:
	var item: TreeItem = _tree.create_item(root)
	item.set_metadata(COL_NAME, branch) # Row -> branch data (name, is_remote, is_current).
	item.set_icon(
		COL_NAME,
		GitotUi.get_icon("ReplicationDock" if branch["is_remote"] else "VcsBranches"),
	)
	item.set_text(COL_NAME, branch["name"])
	item.set_text_overrun_behavior(COL_NAME, TextServer.OVERRUN_TRIM_ELLIPSIS)
	item.set_tooltip_text(COL_NAME, _tooltip(branch, scope))
	item.set_text(COL_SYNC, _sync_text(branch))
	item.set_text_alignment(COL_SYNC, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_text(COL_DATE, branch["date_relative"])
	item.set_tooltip_text(COL_DATE, branch["date_exact"])
	if branch["is_current"]:
		item.set_custom_color(
			COL_NAME,
			EditorInterface.get_editor_theme().get_color("accent_color", "Editor"),
		)


func _on_fetch_pressed() -> void:
	GitotUi.set_busy(_fetch_button, true, FETCH_ICON)
	_git_engine.fetch()


## Double-click (or Enter/Space): switch to a local branch, or create a tracking
## branch for a remote-only one (atomic `switch -c --track`).
func _on_item_activated() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var branch: Dictionary = _entry(item)
	if branch["is_current"]:
		return # Already on it: a no-op switch would still trigger a stale file refresh.
	if branch["is_remote"]:
		_git_engine.track_remote_branch(branch["name"])
	else:
		_git_engine.switch_branch(branch["name"])


func _entry(item: TreeItem) -> Dictionary:
	return item.get_metadata(COL_NAME) as Dictionary


## The selected row's branch entry, or {} if nothing is selected.
func _selected_branch() -> Dictionary:
	var item: TreeItem = _tree.get_selected()
	return _entry(item) if item else { }


func _on_item_selected() -> void:
	selection_changed.emit(_selected_branch())


## Row with the given branch name, or null (also for "" and an empty tree).
func _find_item(branch_name: String) -> TreeItem:
	var root: TreeItem = _tree.get_root()
	if root == null:
		return null
	for item: TreeItem in root.get_children():
		if _entry(item)["name"] == branch_name:
			return item
	return null
