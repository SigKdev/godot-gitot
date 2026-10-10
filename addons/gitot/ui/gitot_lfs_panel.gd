## gitot_lfs_panel.gd
## "Gitot LFS" bottom panel shell: left dashboard (state, actions, stats, patterns) + file list.
## READY shows both; any other GitLfs.State shows only the dashboard as a simple setup guide.
## Display only - all LFS logic lives in GitLfs (injected with set_lfs() before the panel enters the tree).
@tool
class_name GitotLfsPanel
extends Control

const GET_LFS_URL: String = "https://git-lfs.com"

## Common Godot binary assets. Text formats (.gd, .tscn, .tres, .import) stay in regular Git.
const PRESETS: Dictionary = {
	"Textures": ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.tga", "*.exr", "*.hdr"],
	"Art source": ["*.psd", "*.psb", "*.kra", "*.aseprite", "*.afdesign", "*.afphoto"],
	"3D": ["*.blend", "*.fbx", "*.glb", "*.gltf", "*.obj"],
	"Audio": ["*.wav", "*.ogg", "*.mp3", "*.flac"],
	"Video": ["*.ogv", "*.mp4", "*.webm", "*.mov"],
	"Fonts": ["*.ttf", "*.otf", "*.woff2"],
	"Godot binary (if large)": ["*.scn", "*.res", "*.lmbake"],
}

## State label texts. CHECKING_TEXT and LOADING_TEXT cover the wait for git, so a blank list is
## never labelled "ready".
const READY_TEXT: String = "Git LFS is ready."
const CHECKING_TEXT: String = "Checking Git LFS..."
const LOADING_TEXT: String = "Loading LFS files..."

const POINTER_WARNING: String = "This project uses LFS: tracked assets stay pointer files until it is installed."

var _lfs: GitLfs
## Detection is lazy (first time the panel is shown): no extra git spawn at editor startup.
var _has_refreshed: bool = false

@onready var _state_label: Label = %StateLabel
@onready var _hint_label: RichTextLabel = %HintLabel
@onready var _setup_view: Control = %SetupView
@onready var _steps_label: Label = %StepsLabel
@onready var _get_lfs_button: Button = %GetLfsButton
@onready var _install_button: Button = %InstallButton
@onready var _ready_view: Control = %ReadyView
@onready var _stats_label: RichTextLabel = %StatsLabel
@onready var _note_button: Button = %NoteButton
@onready var _files_tree: Tree = %FilesTree
@onready var _pattern_list: ItemList = %PatternList
@onready var _pattern_edit: LineEdit = %PatternEdit
@onready var _presets_button: MenuButton = %PresetsButton
@onready var _lfs_actions: Control = %LfsActions
@onready var _pull_button: Button = %PullButton


func _ready() -> void:
	if _lfs == null:
		return # Scene opened in the scene editor: nothing injected.
	_setup_files_tree()
	_lfs.files_listed.connect(_populate_files)
	_lfs.files_list_failed.connect(_on_files_list_failed)
	_lfs.patterns_changed.connect(_populate_patterns)
	%TrackButton.pressed.connect(_on_track_pressed)
	%UntrackButton.pressed.connect(_on_untrack_pressed)
	_pattern_edit.text_submitted.connect(
		func(_text: String) -> void:
			_on_track_pressed(),
	)
	_setup_presets()
	# Icon-only buttons (their tooltips say what they do). Untrack icon is recolored white.
	_presets_button.icon = GitotUi.get_icon("RegEx")
	%TrackButton.icon = GitotUi.get_icon("Pin")
	%UntrackButton.icon = GitotUi.get_icon_white("PinJoint2D")
	_lfs.state_detected.connect(_on_state_detected)
	%RefreshButton.icon = GitotUi.get_icon("Reload")
	%RefreshButton.pressed.connect(_lfs.detect_state)
	_get_lfs_button.pressed.connect(
		func() -> void:
			OS.shell_open(GET_LFS_URL),
	)
	_install_button.pressed.connect(_on_install_pressed)
	_pull_button.icon = GitotUi.get_icon("MoveDown")
	_pull_button.pressed.connect(_on_pull_pressed)
	%PruneButton.icon = GitotUi.get_icon("Remove")
	%PruneButton.pressed.connect(%PruneConfirmDialog.popup_centered)
	%PruneConfirmDialog.confirmed.connect(_lfs.prune)
	_lfs.pull_finished.connect(_on_pull_finished)
	_hint_label.meta_clicked.connect(
		func(meta: Variant) -> void:
			OS.shell_open(str(meta)),
	)
	# Notes: shown by default, hideable; the choice persists. Set BEFORE connecting (no save on init).
	_note_button.icon = GitotUi.get_icon("Info")
	_note_button.button_pressed = GitotSettings.get_value("lfs_note_visible")
	_hint_label.visible = _note_button.button_pressed
	_note_button.toggled.connect(_on_note_toggled)
	visibility_changed.connect(_on_visibility_changed)


func set_lfs(lfs: GitLfs) -> void:
	_lfs = lfs


## Reloads the LFS file list while the active view is on screen (two chained git reads).
## Called by gitot.gd after commands that move the index/HEAD, and after a pull.
func refresh_files() -> void:
	if not (_files_tree.visible and is_visible_in_tree()):
		return
	if _files_tree.get_root() == null: # First load: no list yet, say so instead of "ready".
		_state_label.text = LOADING_TEXT
	_lfs.list_files()


## Bottom panels are hidden until their tab is selected. Updates are skipped while hidden (see
## refresh_files()), so every show reloads the file list; the first one also re-detects the state
## (startup detection ran hidden and loaded no list).
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	if _has_refreshed:
		refresh_files()
	else:
		_has_refreshed = true
		_state_label.text = CHECKING_TEXT
		_lfs.detect_state() # state_detected -> refresh_files(): panel is visible now, so the list loads.


func _on_pull_pressed() -> void:
	GitotUi.set_busy(_pull_button, true, "MoveDown") # Re-armed by pull_finished.
	_lfs.pull()


func _on_pull_finished(success: bool) -> void:
	GitotUi.set_busy(_pull_button, false, "MoveDown")
	if success:
		refresh_files() # "Remote" rows (pointer here) turn into "Local + Remote".


func _on_install_pressed() -> void:
	_install_button.disabled = true # Re-armed by the next state_detected.
	_lfs.install()


func _on_note_toggled(shown: bool) -> void:
	_hint_label.visible = shown
	GitotSettings.set_value("lfs_note_visible", shown)


func _on_files_list_failed() -> void:
	_state_label.text = READY_TEXT # Nothing to wait for any more; the previous list stays.


## READY = dashboard + file list. Anything else = dashboard only, as a setup guide with the one
## button that fixes the state.
func _on_state_detected(state: GitLfs.State, repo_uses_lfs: bool) -> void:
	var is_ready: bool = state == GitLfs.State.READY
	_ready_view.visible = is_ready
	_files_tree.visible = is_ready
	_lfs_actions.visible = is_ready
	_setup_view.visible = not is_ready
	_get_lfs_button.visible = state == GitLfs.State.NO_BINARY
	_install_button.visible = state == GitLfs.State.NOT_INITIALIZED
	_install_button.disabled = false
	_state_label.text = _state_text(state, repo_uses_lfs)
	_steps_label.text = _steps_text(state)
	if is_ready:
		_populate_patterns()
		refresh_files() # Skipped while hidden (startup detection): the first show reloads. Result: files_listed.


static func _state_text(state: GitLfs.State, repo_uses_lfs: bool) -> String:
	match state:
		GitLfs.State.NO_BINARY:
			return "Git LFS is not installed." + ("\n" + POINTER_WARNING if repo_uses_lfs else "")
		GitLfs.State.NOT_INITIALIZED:
			return "Git LFS is installed but not initialized."
	return READY_TEXT


## Numbered setup steps; finished ones are marked so the user sees where they stand.
static func _steps_text(state: GitLfs.State) -> String:
	var installed: bool = state != GitLfs.State.NO_BINARY
	var initialized: bool = state == GitLfs.State.READY
	return "\n".join(
		[
			"1. Install Git LFS (git-lfs.com), then click Refresh." + (" (done)" if installed else ""),
			"2. Click Install LFS (once per computer)." + (" (done)" if initialized else ""),
			"3. Track your big assets with the Patterns menu (e.g. *.png, *.glb, *.wav).",
			"4. Commit .gitattributes and your assets, then Push.",
		]
	)


func _setup_files_tree() -> void:
	_files_tree.set_column_title(0, "File")
	_files_tree.set_column_title(1, "Size")
	_files_tree.set_column_title(2, "Status")
	_files_tree.set_column_expand(1, false) # File gets the remaining space.
	_files_tree.set_column_expand(2, false)
	_files_tree.set_column_custom_minimum_width(1, 80)
	_files_tree.set_column_custom_minimum_width(2, 125)


## Patterns come straight from .gitattributes: no git call, so no async step.
func _populate_patterns() -> void:
	var patterns: PackedStringArray = _lfs.get_patterns()
	_pattern_list.clear()
	for pattern: String in patterns:
		var index: int = _pattern_list.add_item(pattern)
		_pattern_list.set_item_tooltip(index, pattern) # Full pattern if the row is cut.
	_mark_tracked_presets(patterns)


## One click = track (reversible with Untrack). Tracked items are marked by _mark_tracked_presets().
func _setup_presets() -> void:
	var popup: PopupMenu = _presets_button.get_popup()
	for category: String in PRESETS:
		popup.add_separator(category)
		for pattern: String in PRESETS[category]:
			popup.add_check_item(pattern)
	popup.index_pressed.connect(
		func(index: int) -> void:
			_lfs.track(popup.get_item_text(index)),
	)


## Presets already in .gitattributes are checked and disabled: nothing left to track.
func _mark_tracked_presets(patterns: PackedStringArray) -> void:
	var popup: PopupMenu = _presets_button.get_popup()
	for index: int in popup.item_count:
		if popup.is_item_separator(index):
			continue
		var tracked: bool = popup.get_item_text(index) in patterns
		popup.set_item_checked(index, tracked)
		popup.set_item_disabled(index, tracked)


func _on_track_pressed() -> void:
	if _lfs.track(_pattern_edit.text): # false = rejected (empty / leading "-"), logged by GitLfs.
		_pattern_edit.clear()


func _on_untrack_pressed() -> void:
	var selected: PackedInt32Array = _pattern_list.get_selected_items()
	if not selected.is_empty():
		_lfs.untrack(_pattern_list.get_item_text(selected[0]))


## One row per LFS file. Status uses the same words as the branch list (GitotUi.scope_label):
## Local = full file on this computer, Remote = same content in origin's tree (as of the last fetch).
## @param files: GitLfsParser.merge_scopes() rows.
func _populate_files(files: Array[Dictionary]) -> void:
	_files_tree.clear()
	var root: TreeItem = _files_tree.create_item()
	for file: Dictionary in files:
		var local: bool = file["local"]
		var remote: bool = file["remote"]
		var item: TreeItem = _files_tree.create_item(root)
		item.set_text(0, file["path"])
		item.set_tooltip_text(0, file["path"]) # Full path on hover if truncated.
		item.set_text(1, String.humanize_size(file["size"]))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text(2, GitotUi.scope_label(local, remote) if local or remote else "Missing")
		item.set_icon(2, GitotUi.get_icon(_status_icon(local, remote)))
		item.set_tooltip_text(2, _status_tooltip(local, remote))
	_stats_label.text = _stats_bbcode(GitLfsParser.summarize(files))
	_state_label.text = READY_TEXT # Ends the "Loading" text of the first load.


## Dashboard stats as a 2-column BBCode table. Rows for "nothing to do" counters are omitted.
## @param stats: GitLfsParser.summarize() result.
static func _stats_bbcode(stats: Dictionary) -> String:
	if stats["count"] == 0:
		return "No LFS files yet. Track a pattern: matching files then show up here."
	var rows: Array[Array] = [
		["Files", str(stats["count"])],
		["Total size", String.humanize_size(stats["total"])],
		["On this computer", _count_size(stats["local"], stats["local_size"])],
		["On Remote", _count_size(stats["remote"], stats["remote_size"])],
	]
	if stats["unpushed"] > 0:
		rows.append(["To upload", _count_size(stats["unpushed"], stats["unpushed_size"])])
	if stats["to_pull"] > 0:
		rows.append(["To download", _count_size(stats["to_pull"], stats["to_pull_size"])])
	if stats["missing"] > 0:
		rows.append(["Missing", str(stats["missing"])])
	rows.append(
		[
			"Largest",
			"%s (%s)" % [
				GitotUi.ellipsize(str(stats["largest_path"]).get_file(), 24).replace("[", "[lb]"),
				String.humanize_size(stats["largest_size"]),
			],
		]
	)
	var table: String = "[table=2]"
	for row: Array in rows:
		table += "[cell][color=gray]%s  [/color][/cell][cell]%s[/cell]" % row
	return table + "[/table]\n[font_size=11][color=gray]Remote = origin as of your last fetch, current files only (GitHub also counts old versions).[/color][/font_size]"


static func _count_size(count: int, size: int) -> String:
	return "%d  ·  %s" % [count, String.humanize_size(size)]


## Push/pull icons double as the hint for the action that fixes the row.
static func _status_icon(local: bool, remote: bool) -> String:
	if local and remote:
		return "StatusSuccess"
	if local:
		return "MoveUp" # Not on GitHub yet: Commit + Push.
	return "MoveDown" if remote else "StatusWarning" # Pointer only here: Pull.


static func _status_tooltip(local: bool, remote: bool) -> String:
	if local and remote:
		return "Full file on this computer, and on GitHub (as of your last fetch)."
	if local:
		return "Full file on this computer only: not on GitHub yet.\nCommit and Push to upload it."
	if remote:
		return "On GitHub, but this computer only has a pointer.\nUse the Download button on the left (LFS pull)."
	return "Only a pointer here, and not found on GitHub (as of your last fetch).\nFetch, then pull."
