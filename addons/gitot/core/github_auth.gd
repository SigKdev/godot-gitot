## github_auth.gd
## Handles local storage of the GitHub Personal Access Token (PAT).
## WARNING: stored in plaintext in user:// (outside res://, never committed). See the wiki page
## "Credentials and GitHub Token" for the security notes.
@tool
class_name GithubAuth
extends RefCounted

const CONFIG_PATH: String = "user://gitot_auth.cfg"
const SECTION: String = "auth"
const KEY_TOKEN: String = "pat"


## Saves the token to disk. Returns true on success.
static func save_token(token: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, KEY_TOKEN, token)
	var err: Error = config.save(CONFIG_PATH)
	if err != OK:
		GitotLogger.e("Could not save the GitHub token: %s." % error_string(err))
		return false
	return true


## Returns the stored token, or an empty string if none exists.
static func load_token() -> String:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(CONFIG_PATH)
	if err != OK:
		return ""
	return config.get_value(SECTION, KEY_TOKEN, "")


## Clears the stored token (Clear Token button, 401 / auth_failed, Issues disabled in Settings).
static func clear_token() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, KEY_TOKEN, "")
	config.save(CONFIG_PATH)
