## github_api.gd
## Thin authenticated wrapper around HTTPRequest for the GitHub REST API.
## Emits raw parsed JSON on success; never touches local git state (SoC).
@tool
class_name GithubApi
extends Node

## Emitted when a request succeeds. [param data] is the parsed JSON body.
signal request_succeeded(data: Variant)
## Emitted on 401 — token is invalid/expired/revoked.
signal auth_failed
## Emitted on any other failure (network, non-200/401 status).
signal request_failed(status_code: int)

const API_BASE: String = "https://api.github.com"
const USER_AGENT: String = "Gitot-Godot-Plugin"

var _http: HTTPRequest = HTTPRequest.new()

func _ready() -> void:
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

## Sends a GET request to [param endpoint] (e.g. "/repos/owner/repo/issues").
func get_endpoint(endpoint: String) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		GitotLogger.w("GitHub request already in progress - ignoring.")
		return
	var token: String = GithubAuth.load_token()
	var headers: PackedStringArray = [
		"Authorization: Bearer %s" % token,
		"User-Agent: %s" % USER_AGENT,
		"Accept: application/vnd.github+json",
	]
	_http.request(API_BASE + endpoint, headers)

## Fetches up to 100 open issues for [param owner]/[param repo].
## Note: repos with more than 100 open issues are truncated in v1 — no pagination.
func fetch_issues(owner: String, repo: String) -> void:
	get_endpoint("/repos/%s/%s/issues?per_page=100&state=open" % [owner, repo])


## Fetches all labels defined for [param owner]/[param repo].
# func fetch_labels(owner: String, repo: String) -> void:
	# get_endpoint("/repos/%s/%s/labels?per_page=100" % [owner, repo])


## Routes the raw HTTPRequest response to the correct outcome signal.
func _on_request_completed(_result: int, status_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if status_code == 401:
		auth_failed.emit()
		return
	if status_code != 200:
		request_failed.emit(status_code)
		return

	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	request_succeeded.emit(json)
