## issue_card.gd
## A single issue card: title, label pills, body preview, browser link.
@tool
extends PanelContainer

var _issue_url: String = ""

func _ready() -> void:
	%BodyLabel.visible = false
	%Chevron.gui_input.connect(_on_title_input)
	#%Chevron.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	%TitleLabel.gui_input.connect(_on_title_input)
	#%TitleLabel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	%OpenButton.icon = EditorInterface.get_base_control().get_theme_icon("ExternalLink", "EditorIcons")
	%OpenButton.expand_icon = false
	%OpenButton.add_theme_constant_override("icon_max_width", 11)
	%OpenButton.pressed.connect(_on_open_pressed)

## Populates the card from a raw GitHub issue JSON dictionary.
func setup(issue: Dictionary) -> void:
	%TitleLabel.text = "#%d  %s" % [issue.get("number", 0), issue.get("title", "")]
	%BodyLabel.text = issue.get("body", "")
	_issue_url = issue.get("html_url", "")

	for label: Dictionary in issue.get("labels", []):
		var pill: Label = Label.new()
		pill.text = label.get("name", "")
		var color_hex: String = label.get("color", "ffffff")
		var bg_color: Color = Color.html(color_hex)
		pill.add_theme_color_override("font_color", _readable_text_color(bg_color))
		pill.add_theme_stylebox_override("normal", _make_pill_stylebox(bg_color))
		%LabelsRow.add_child(pill)
	
	var author: String = issue.get("user", {}).get("login", "unknown")
	var created: String = issue.get("created_at", "").left(10) # YYYY-MM-DD from ISO 8601
	%MetaLabel.text = "by %s · %s" % [author, created]


## Builds a rounded colored background for a label pill.
func _make_pill_stylebox(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style


## Returns black or white text depending on background luminance, for readability.
func _readable_text_color(bg: Color) -> Color:
	var luminance: float = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color.BLACK if luminance > 0.6 else Color.WHITE


## Toggles the body preview when the title is clicked.
func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		%BodyLabel.visible = not %BodyLabel.visible
		%Chevron.text = "▾" if %BodyLabel.visible else "▸"


func _on_open_pressed() -> void:
	if _issue_url != "":
		OS.shell_open(_issue_url)
