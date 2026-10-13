## gitot_repo_state.gd
## Single source of truth for the current branch: its name, the origin repo and its sync state vs upstream.
## Written only by GitotResultRouter; panels and the push flow read it.
class_name GitotRepoState
extends RefCounted

## Emitted when has_upstream, ahead or behind changed.
signal changed

## Checked-out branch ("" until the first branch list). Detached HEAD: git's own "(HEAD detached at ...)" text.
## Plain field, no signal: only log messages read it.
var branch: String = ""
## "owner/repo" of origin ("" = no origin, or a URL that is not owner/repo shaped).
var repo: String = ""
## Browser address of origin (see GitRemote.web_url()); "" = no origin, or a URL with no safe web form.
var repo_url: String = ""
## True if a remote named "origin" exists, whatever its URL looks like (`repo` is "" for a URL that is not
## owner/repo shaped). False until the first remote-URL answer; Push asks for a URL while it is false.
var has_origin: bool = false

## False = the branch was never pushed (counts are then meaningless, kept at 0).
var has_upstream: bool = false
## Commits HEAD has that its upstream lacks.
var ahead: int = 0
## Commits its upstream has that HEAD lacks.
var behind: int = 0


## Branch name for messages and dialogs; "HEAD" until the first branch list arrives.
func branch_label() -> String:
	return branch if not branch.is_empty() else "HEAD"


## "owner/repo" for messages and dialogs; "origin" when the URL could not be parsed.
func repo_label() -> String:
	return repo if not repo.is_empty() else "origin"


## Stores a new sync state and emits `changed` if it differs from the previous one.
## @return: true if it changed (callers log only then, to avoid spam on redundant refreshes).
func set_sync(upstream_set: bool, ahead_count: int, behind_count: int) -> bool:
	if upstream_set == has_upstream and ahead_count == ahead and behind_count == behind:
		return false
	has_upstream = upstream_set
	ahead = ahead_count
	behind = behind_count
	changed.emit()
	return true
