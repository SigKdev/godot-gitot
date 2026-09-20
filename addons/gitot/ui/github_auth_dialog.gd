## github_auth_dialog.gd
## Modal for entering/updating the GitHub PAT.
## Pre-fills with the existing token (if any) and saves on confirm.
@tool
extends ConfirmationDialog


func _ready() -> void:
	%TokenInput.text = GithubAuth.load_token()
	confirmed.connect(_on_confirmed)


## Persists the entered token when the user presses OK.
func _on_confirmed() -> void:
	var token: String = %TokenInput.text.strip_edges()
	if token.is_empty():
		GitotLogger.w("Token field was empty - existing token unchanged.")
		return
	GithubAuth.save_token(token)
