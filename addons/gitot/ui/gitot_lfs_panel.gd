## gitot_lfs_panel.gd
## "Gitot LFS" bottom panel shell: one view per GitLfs.State. Display only - all LFS
## logic lives in GitLfs (injected with set_lfs() before the panel enters the tree).
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

const POINTER_WARNING: String = "This project uses LFS: tracked assets stay pointer files until it is installed."

var _lfs: GitLfs
## Detection is lazy (first time the panel is shown): no extra git spawn at editor startup.
var _has_refreshed: bool = false

@onready var _state_label: Label = %StateLabel
@onready var _hint_label: RichTextLabel = %HintLabel
@onready var _missing_view: Control = %MissingView
@onready var _install_view: Control = %InstallView
@onready var _install_button: Button = %InstallButton
@onready var _active_view: Control = %ActiveView
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
	_lfs.patterns_changed.connect(_populate_patterns)
	%TrackButton.pressed.connect(_on_track_pressed)
	%UntrackButton.pressed.connect(_on_untrack_pressed)
	_pattern_edit.text_submitted.connect(
		func(_text: String) -> void:
			_on_track_pressed(),
	)
	_setup_presets()
	_lfs.state_detected.connect(_on_state_detected)
	%RefreshButton.icon = GitotUi.get_icon("Reload")
	%RefreshButton.pressed.connect(_lfs.detect_state)
	%GetLfsButton.pressed.connect(
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
	visibility_changed.connect(_on_visibility_changed)


func set_lfs(lfs: GitLfs) -> void:
	_lfs = lfs


## Reloads the LFS file list while the active view is on screen (one git spawn).
## Called by gitot.gd after commands that move the index/HEAD, and after a pull.
func refresh_files() -> void:
	if _active_view.visible and is_visible_in_tree():
		_lfs.list_files()


## Bottom panels are hidden until their tab is selected: first show = first detection;
## later shows reload the file list (updates are skipped while hidden, see refresh_files()).
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	if _has_refreshed:
		refresh_files()
	else:
		_has_refreshed = true
		_lfs.detect_state()


func _on_pull_pressed() -> void:
	GitotUi.set_busy(_pull_button, true, "MoveDown") # Re-armed by pull_finished.
	_lfs.pull()


func _on_pull_finished(success: bool) -> void:
	GitotUi.set_busy(_pull_button, false, "MoveDown")
	if success:
		refresh_files() # Pointer rows turn into Local.


func _on_install_pressed() -> void:
	_install_button.disabled = true # Re-armed by the next state_detected.
	_lfs.install()


func _on_state_detected(state: GitLfs.State, repo_uses_lfs: bool) -> void:
	_missing_view.hide()
	_install_view.hide()
	_active_view.hide()
	_lfs_actions.hide()
	_hint_label.hide()
	_install_button.disabled = false
	match state:
		GitLfs.State.NO_BINARY:
			_missing_view.show()
			_state_label.text = "Git LFS is not installed." + (
				POINTER_WARNING if repo_uses_lfs else ""
			)
		GitLfs.State.NOT_INITIALIZED:
			_install_view.show()
			_state_label.text = "Git LFS is installed but not initialized."
			_hint_label.show()
		GitLfs.State.READY:
			_active_view.show()
			_lfs_actions.show()
			_hint_label.show()
			_state_label.text = "Git LFS is ready."
			_populate_patterns()
			_lfs.list_files() # Result arrives via files_listed -> _populate_files().


func _setup_files_tree() -> void:
	_files_tree.set_column_title(0, "File")
	_files_tree.set_column_title(1, "Size")
	_files_tree.set_column_title(2, "Status")
	_files_tree.set_column_expand(1, false) # File gets the remaining space.
	_files_tree.set_column_expand(2, false)
	_files_tree.set_column_custom_minimum_width(1, 80)
	_files_tree.set_column_custom_minimum_width(2, 110)


## Patterns come straight from .gitattributes: no git call, so no async step.
func _populate_patterns() -> void:
	var patterns: PackedStringArray = _lfs.get_patterns()
	_pattern_list.clear()
	for pattern: String in patterns:
		_pattern_list.add_item(pattern)
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


## @param files: GitLfsParser.parse_files() entries.
func _populate_files(files: Array[Dictionary]) -> void:
	_files_tree.clear()
	var root: TreeItem = _files_tree.create_item()
	for file: Dictionary in files:
		var present: bool = file["present"]
		var item: TreeItem = _files_tree.create_item(root)
		item.set_text(0, file["path"])
		item.set_tooltip_text(0, file["path"]) # Full path on hover if truncated.
		item.set_text(1, String.humanize_size(file["size"]))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text(2, "Local" if present else "Pointer")
		item.set_icon(2, GitotUi.get_icon("StatusSuccess" if present else "StatusWarning"))
		item.set_tooltip_text(
			2,
			(
				"Full object in the working tree."
				if present
				else "Working-tree file is a pointer, not the full object."
			),
		)
