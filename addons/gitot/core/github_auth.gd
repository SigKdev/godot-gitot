## github_auth.gd
## Handles local storage of the GitHub Personal Access Token (PAT).
## !! Stored in plaintext outside res:// — see README for security notes !!
## Never touches res:// or version-controlled paths.
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
		print_rich("[color=red]Gitot ERROR: failed to save token (error %d)[/color]" % err)
		return false
	return true

## Returns the stored token, or an empty string if none exists.
static func load_token() -> String:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(CONFIG_PATH)
	if err != OK:
		return ""
	return config.get_value(SECTION, KEY_TOKEN, "")

## Clears the stored token (used on 401 / auth_failed).
static func clear_token() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, KEY_TOKEN, "")
	config.save(CONFIG_PATH)
