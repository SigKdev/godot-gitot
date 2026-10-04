## gitot_ui.gd
## Shared editor-UI helpers: theme icons, title-bar buttons, sync-status display rules.
class_name GitotUi
extends RefCounted

## GitBranchParser "sync" (upstream:trackshort) -> symbol. Symbols, not git's localized "track"
## text, so the UI never depends on the user's git language. Single source for every sync display.
const SYNC_SYMBOLS: Dictionary[String, String] = { ">": "↑", "<": "↓", "<>": "↑↓", "=": "✓" }


## Color per sync key (see sync_key); no upstream and unknown state are drawn gray/orange by sync_color().
const SYNC_COLORS: Dictionary[String, Color] = {
	">": Color.FOREST_GREEN,
	"<": Color.INDIAN_RED,
	"<>": Color.ORANGE,
	"=": Color.FOREST_GREEN,
}


## Sync symbol of a branch vs its upstream: "—" no upstream, "gone" upstream set but unknown
## state (remote branch deleted), otherwise an arrow/check from SYNC_SYMBOLS.
## @param sync: GitBranchParser trackshort (see sync_key() to build one from counts).
static func sync_symbol(has_upstream: bool, sync: String) -> String:
	if not has_upstream:
		return "—"
	return SYNC_SYMBOLS.get(sync, "gone")


## Color matching sync_symbol(): gray = no upstream, orange = upstream set but state unknown ("gone").
static func sync_color(has_upstream: bool, sync: String) -> Color:
	if not has_upstream:
		return Color.GRAY
	return SYNC_COLORS.get(sync, Color.ORANGE)


## Plain-language meaning of a sync state and the action that resolves it (tooltips).
## @param upstream: short upstream ref ("origin/main"), "" = none.
## @param sync: GitBranchParser trackshort.
static func sync_tooltip(upstream: String, sync: String) -> String:
	if upstream.is_empty():
		return "No upstream: this branch only exists on your computer.\nPush to publish it."
	match sync:
		"=":
			return "Up to date with %s." % upstream
		">":
			return "Ahead of %s: your commits are not uploaded yet.\nPush to upload them." % upstream
		"<":
			return "Behind %s: it has newer commits.\nPull to get them." % upstream
		"<>":
			return (
				"Diverged from %s: each side has commits the other lacks.\n" % upstream
				+ "Normal after an amend (Push will ask to force-push). Otherwise Pull first."
			)
	return "%s no longer exists (deleted remotely?).\nPush to recreate it, or delete this local branch." % upstream


## Counts shown next to a sync arrow: " 2" ahead, " 1" behind, " 2/1" diverged, "" when in sync.
## Single source for the status line and the branch header.
## @param key: sync_key() result.
static func sync_counts(key: String, ahead: int, behind: int) -> String:
	match key:
		">":
			return " %d" % ahead
		"<":
			return " %d" % behind
		"<>":
			return " %d/%d" % [ahead, behind]
	return ""


## Tooltip of the dock's Push button: what pressing it will do given the current counts.
## Mirrors GitSyncOrchestrator.plan_push() (same inputs, so the text never disagrees with the action).
static func push_tooltip(has_upstream: bool, ahead: int, behind: int) -> String:
	var outcome: String
	if not has_upstream:
		outcome = "First push of this branch: publishes it to origin\nand sets it as the upstream."
	elif behind > 0 and ahead == 0:
		return "Push blocked: origin has %d newer commit(s).\nPull first, then push." % behind
	elif behind > 0:
		outcome = (
			"Diverged (↑%d ↓%d), e.g. after an amend.\n" % [ahead, behind]
			+ "Push asks first, then force-pushes (--force-with-lease):\n"
			+ "origin's %d commit(s) are replaced by yours." % behind
		)
	elif ahead > 0:
		outcome = "Uploads your %d unpushed commit(s) to origin." % ahead
	else:
		outcome = "Nothing new to upload: up to date with origin."
	return "Push\n%s\nAlso pushes the tag, if one is set." % outcome


## Trackshort key (">" ahead, "<" behind, "<>" diverged, "=" in sync) from commit counts.
static func sync_key(ahead: int, behind: int) -> String:
	if ahead > 0 and behind > 0:
		return "<>"
	if ahead > 0:
		return ">"
	return "<" if behind > 0 else "="


## Where something lives: "Local + Remote", "Local", "Remote" ("" for neither).
## One wording for branches and LFS files.
static func scope_label(local: bool, remote: bool) -> String:
	if local and remote:
		return "Local + Remote"
	if local:
		return "Local"
	return "Remote" if remote else ""


## Shortens text to max_chars with a trailing "…" (display only).
static func ellipsize(text: String, max_chars: int) -> String:
	return text if text.length() <= max_chars else text.left(max_chars - 1) + "…"


## Single source for editor-theme icon lookup.
## @param icon_name: EditorIcons theme entry (e.g. "Loop", "Time").
static func get_icon(icon_name: String) -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(icon_name, &"EditorIcons")


## Busy state for long-running op buttons: disabled + "Time" icon while running, idle icon after.
static func set_busy(button: Button, busy: bool, idle_icon: String) -> void:
	button.disabled = busy
	button.icon = get_icon("Time" if busy else idle_icon)


## Editor icon recolored pure white (alpha kept): for icons that are hard to read on a dark button.
## Falls back to the original icon if its pixels can't be read. Cheap: icons are ~16-32 px.
static func get_icon_white(icon_name: String) -> Texture2D:
	var source: Texture2D = get_icon(icon_name)
	var image: Image = source.get_image()
	if image == null:
		return source
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, image.get_pixel(x, y).a))
	return ImageTexture.create_from_image(image)


## Flat icon button added to a FoldableContainer's title bar.
## @param toggle: true -> toggle button (state = button_pressed).
static func add_title_button(
	fold: FoldableContainer,
	icon_name: String,
	tooltip: String,
	toggle: bool = false,
) -> Button:
	var button: Button = Button.new()
	button.flat = true
	button.toggle_mode = toggle
	button.icon = get_icon(icon_name)
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fold.add_title_bar_control(button)
	return button
