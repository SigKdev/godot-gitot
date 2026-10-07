## gitot_branch_panel.gd
## Branches section: list (name / sync / last commit), Fetch button (toolbar row of the scene) and a
## right-aligned sync status of the current branch in the fold title bar.
## Double-click switches branch. UI-only — no OS.execute() calls.
class_name GitotBranchPanel
extends RefCounted

## Emitted when the selected row changes, and after every populate().
## @param branch: the selected entry incl. remote_ref / remote_hash (its copy on origin,
## "" if none; see _annotate_remote), null if nothing is selected.
signal selection_changed(branch: GitBranchEntry)

const FOLD_TITLE: String = "Branches"
const COL_NAME: int = 0
const COL_SYNC: int = 1
const COL_DATE: int = 2
const FETCH_ICON: String = "AssetStore"

## Longest branch name shown in the fold title (the full name stays in the list).
const TITLE_BRANCH_CHARS: int = 24

var _git_engine: GitEngine
var _fold: FoldableContainer
var _tree: Tree
var _fetch_button: Button
## Title-bar status of the current branch (symbol, colored), sticks to the right of the bar.
var _status_label: Label
## Current local branch row (null = none), for the title-bar status.
var _current: GitBranchEntry = null
## Ahead/behind of HEAD vs its upstream (rev-list: no localized text involved).
var _state: GitotRepoState


## Hides remote entries that already have a local counterpart
## (e.g. "main" + "origin/main"); remote-only branches stay.
static func _filter_redundant_remotes(branches: Array[GitBranchEntry]) -> Array[GitBranchEntry]:
	var local_names: Array[String] = []
	for branch: GitBranchEntry in branches:
		if not branch.is_remote:
			local_names.append(branch.name)

	var result: Array[GitBranchEntry] = []
	for branch: GitBranchEntry in branches:
		if branch.is_remote and branch.name.trim_prefix("origin/") in local_names:
			continue
		result.append(branch)
	return result


## Sets remote_ref ("origin/<name>" or "") and remote_hash (that ref's tip) on an entry, so the
## delete buttons know which remote copy exists. Only "origin" is supported, like the list filter.
## @param remote_hashes: remote ref name -> tip hash, from the unfiltered list.
static func _annotate_remote(branch: GitBranchEntry, remote_hashes: Dictionary[String, String]) -> void:
	var ref: String = branch.name if branch.is_remote else "origin/" + branch.name
	var exists: bool = ref.begins_with("origin/") and remote_hashes.has(ref)
	branch.remote_ref = ref if exists else ""
	branch.remote_hash = remote_hashes[ref] if exists else ""


## Display order: current branch, other local branches, remote-only;
## newest commit first inside each group.
static func _is_before(a: GitBranchEntry, b: GitBranchEntry) -> bool:
	if a.is_current != b.is_current:
		return a.is_current
	if a.is_remote != b.is_remote:
		return b.is_remote # a is local, b is remote
	return a.date_unix > b.date_unix


static func _sync_text(branch: GitBranchEntry) -> String:
	if branch.is_remote:
		return ""
	# "—" never pushed, "gone" upstream configured but remote branch deleted (see GitotUi).
	return GitotUi.sync_symbol(not branch.upstream.is_empty(), branch.sync)


## Fold title: "Branches (4)  ·  on main". Plain text only (FoldableContainer has no icon/BBCode);
## the sync status lives in its own label, see _update_status().
static func _title(shown: Array[GitBranchEntry]) -> String:
	var title: String = "%s (%d)" % [FOLD_TITLE, shown.size()]
	for branch: GitBranchEntry in shown:
		if branch.is_current:
			return "%s  ·  on %s" % [title, GitotUi.ellipsize(branch.name, TITLE_BRANCH_CHARS)]
	return title


## Hover text of a sync cell / the title status: what the state means and what to do about it.
static func _sync_tooltip(branch: GitBranchEntry) -> String:
	if branch.is_remote:
		return "Only on the remote.\nDouble-click to create a local branch that tracks it."
	return GitotUi.sync_tooltip(branch.upstream, branch.sync)


static func _tooltip(branch: GitBranchEntry, scope: String) -> String:
	var title: String = branch.name + ("  ·  " + scope if not scope.is_empty() else "")
	var lines: PackedStringArray = [title]
	if not branch.upstream.is_empty():
		# "track" is git's localized text: display only, never parsed.
		lines.append(("Upstream: %s %s" % [branch.upstream, branch.track]).strip_edges())
	lines.append("%s  ·  %s" % [branch.commit_hash, branch.date_exact])
	lines.append(branch.subject)
	return "\n".join(lines)


## @param fold: hosts the section; its title shows the count and current branch, a label added to
## its title bar shows that branch's sync status.
## @param tree: 3-column Tree (set up here).
## @param fetch_button: scene button (toolbar row); icon and signal are wired here.
## @param state: ahead/behind source; the title status is redrawn whenever it changes.
func _init(
	git_engine: GitEngine,
	fold: FoldableContainer,
	tree: Tree,
	fetch_button: Button,
	state: GitotRepoState,
) -> void:
	_git_engine = git_engine
	_state = state
	_state.changed.connect(_render_status)
	_fold = fold
	_tree = tree
	_fetch_button = fetch_button
	_fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # Title shares the bar with the status.
	_setup_tree()
	_fetch_button.icon = GitotUi.get_icon(FETCH_ICON)
	_fetch_button.pressed.connect(_on_fetch_pressed)
	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP # Needed for the tooltip.
	_status_label.mouse_default_cursor_shape = Control.CURSOR_HELP
	_fold.add_title_bar_control(_status_label)


## Rebuilds the list from a fresh branch list. Called by the router on the "branches" result.
## @param branches: from GitBranchParser.parse().
## @param branch_scopes: branch name -> scope text (tooltip only).
func populate(branches: Array[GitBranchEntry], branch_scopes: Dictionary[String, String]) -> void:
	var selected: GitBranchEntry = _selected_branch()
	var selected_name: String = selected.name if selected else ""
	var remote_hashes: Dictionary[String, String] = { }
	for branch: GitBranchEntry in branches:
		if branch.is_remote:
			remote_hashes[branch.name] = branch.commit_hash
	var shown: Array[GitBranchEntry] = _filter_redundant_remotes(branches)
	for branch: GitBranchEntry in shown:
		_annotate_remote(branch, remote_hashes)
	shown.sort_custom(_is_before)

	_tree.clear()
	var root: TreeItem = _tree.create_item()
	for branch: GitBranchEntry in shown:
		_add_row(root, branch, branch_scopes.get(branch.name, ""))

	var target: TreeItem = _find_item(selected_name)
	if target == null:
		target = root.get_first_child()
	if target:
		target.select(COL_NAME)
	_fold.title = _title(shown)
	_update_status(shown)
	selection_changed.emit(_selected_branch())


## Remembers the current local branch (none = status hidden), then redraws the status.
func _update_status(shown: Array[GitBranchEntry]) -> void:
	_current = null
	for branch: GitBranchEntry in shown:
		if branch.is_current and not branch.is_remote:
			_current = branch
			break
	_render_status()


func _render_status() -> void:
	_status_label.visible = _current != null
	if _current == null:
		return
	var has_upstream: bool = not _current.upstream.is_empty()
	_status_label.text = _status_text(_current, _state.ahead, _state.behind)
	_status_label.add_theme_color_override("font_color", GitotUi.sync_color(has_upstream, _current.sync))
	_status_label.tooltip_text = "Current branch '%s'\n%s" % [_current.name, _sync_tooltip(_current)]


## Symbol + counts ("↑ 2"). The counts come from a separate git call, so they are only shown when
## they agree with this branch's own sync state (they can be briefly stale after a switch).
static func _status_text(branch: GitBranchEntry, ahead: int, behind: int) -> String:
	var text: String = _sync_text(branch)
	if not branch.upstream.is_empty() and GitotUi.sync_key(ahead, behind) == branch.sync:
		text += GitotUi.sync_counts(branch.sync, ahead, behind)
	return text


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


func _add_row(root: TreeItem, branch: GitBranchEntry, scope: String) -> void:
	var item: TreeItem = _tree.create_item(root)
	item.set_metadata(COL_NAME, branch) # Row -> branch data (name, is_remote, is_current).
	item.set_icon(
		COL_NAME,
		GitotUi.get_icon("ReplicationDock" if branch.is_remote else "VcsBranches"),
	)
	item.set_text(COL_NAME, branch.name)
	item.set_text_overrun_behavior(COL_NAME, TextServer.OVERRUN_TRIM_ELLIPSIS)
	item.set_tooltip_text(COL_NAME, _tooltip(branch, scope))
	item.set_text(COL_SYNC, _sync_text(branch))
	item.set_text_alignment(COL_SYNC, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_tooltip_text(COL_SYNC, _sync_tooltip(branch))
	item.set_text(COL_DATE, branch.date_relative)
	item.set_tooltip_text(COL_DATE, branch.date_exact)
	if branch.is_current:
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
	var branch: GitBranchEntry = _entry(item)
	if branch.is_current:
		return # Already on it: a no-op switch would still trigger a stale file refresh.
	if branch.is_remote:
		_git_engine.track_remote_branch(branch.name)
	else:
		_git_engine.switch_branch(branch.name)


func _entry(item: TreeItem) -> GitBranchEntry:
	return item.get_metadata(COL_NAME) as GitBranchEntry


## The selected row's branch entry, or null if nothing is selected.
func _selected_branch() -> GitBranchEntry:
	var item: TreeItem = _tree.get_selected()
	return _entry(item) if item else null


func _on_item_selected() -> void:
	selection_changed.emit(_selected_branch())


## Row with the given branch name, or null (also for "" and an empty tree).
func _find_item(branch_name: String) -> TreeItem:
	var root: TreeItem = _tree.get_root()
	if root == null:
		return null
	for item: TreeItem in root.get_children():
		if _entry(item).name == branch_name:
			return item
	return null
