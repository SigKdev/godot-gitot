## Remote URL rules and decoding: owner/repo, browsable address, the add_remote() whitelist.
## Pure text logic, no git process.
class_name GitRemote
extends RefCounted

## Remote URLs GitEngine.add_remote() accepts: https without user info (a "user:token@" would be stored in plaintext
## in .git/config), ssh://, and scp-like git@host:path. Everything else (http://, local paths, spaces,
## a leading "-" that git would read as an option) is refused. \z: end of text, not before a final newline.
const URL_PATTERN: String = r"^(https://[^\s/@]+/\S+|ssh://[^\s/]+/\S+|git@[^\s/@:]+:\S+)\z"

## A browsable repo address, as web_url() builds it: https, bare host (no user info, no port), a path.
const WEB_URL_PATTERN: String = r"^https://[^\s/@:]+/\S+\z"


## Splits a git remote URL (SSH or HTTPS form) into owner and repo name.
## @return: {"owner": String, "repo": String}, or {} if the URL has fewer than 2 path segments.
static func parse_owner_repo(url: String) -> Dictionary:
	var cleaned: String = url.trim_suffix(".git")
	var parts: PackedStringArray = cleaned.split("/")
	if parts.size() < 2:
		return { }
	return { "owner": parts[-2].split(":")[-1], "repo": parts[-1] }


## Browser address of a remote: "https://host/owner/repo" from https://host/owner/repo[.git],
## git@host:owner/repo[.git] or ssh://git@host/owner/repo[.git].
## @return: "" for any other form (http, user:token@, port, local path): no link rather than a wrong or leaking one.
static func web_url(remote_url: String) -> String:
	var url: String = remote_url.trim_suffix(".git")
	if url.begins_with("git@"): # scp-like: the ":" separates host and path.
		url = "https://" + url.trim_prefix("git@").replace(":", "/")
	elif url.begins_with("ssh://git@"):
		url = "https://" + url.trim_prefix("ssh://git@")
	return url if GitotRegex.compiled(WEB_URL_PATTERN).search(url) != null else ""


## The origin URL from a finished Command.REMOTE_URL; "" when it failed (no origin).
static func url_of(exit_code: int, output: Array[String]) -> String:
	if exit_code != 0 or output.is_empty():
		return ""
	return output[0].strip_edges()


## True if url is a remote URL GitEngine.add_remote() accepts (see URL_PATTERN).
static func is_valid_url(url: String) -> bool:
	return GitotRegex.compiled(URL_PATTERN).search(url) != null
