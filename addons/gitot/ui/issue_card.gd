## issue_card.gd
## A single issue card: title, label pills, body preview, browser link.
@tool
extends PanelContainer

var _issue_url: String = ""

func _ready() -> void:
	%OpenButton.pressed.connect(_on_open_pressed)

## Populates the card from a raw GitHub issue JSON dictionary.
func setup(issue: Dictionary) -> void:
	%TitleLabel.text = "#%d  %s" % [issue.get("number", 0), issue.get("title", "")]
	%BodyLabel.text = issue.get("body", "")
	_issue_url = issue.get("html_url", "")

	for label: Dictionary in issue.get("labels", []):
		var pill: Label = Label.new()
		pill.text = label.get("name", "")
		%LabelsRow.add_child(pill)

func _on_open_pressed() -> void:
	if _issue_url != "":
		OS.shell_open(_issue_url)
