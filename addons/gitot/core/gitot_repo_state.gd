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

## False = the branch was never pushed (counts are then meaningless, kept at 0).
var has_upstream: bool = false
## Commits HEAD has that its upstream lacks.
var ahead: int = 0
## Commits its upstream has that HEAD lacks.
var behind: int = 0


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
