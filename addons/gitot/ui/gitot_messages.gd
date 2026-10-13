## gitot_messages.gd
## Log helpers shared by the result handlers (router, branch results): one failure layout and one
## network hint, so every failure reads the same.
class_name GitotMessages
extends RefCounted


## Failure report: what happened (error line), git's raw reason, then a hint.
static func log_failure(title: String, output: Array[String], hint: String) -> void:
	GitotLogger.fail(title, output[0] if not output.is_empty() else "", hint)


## Git's own output (e.g. "[main abc1234] message"), logged raw: proof of what git did.
static func log_git_output(output: Array[String]) -> void:
	if not output.is_empty() and not output[0].is_empty():
		GitotLogger.g(output[0])


## Hint for a failed network op: Gitot's own timeout/refusal (exit -1) takes precedence over the generic one.
## Not a status text match (git's messages are localized): only the exit code.
static func network_hint(
	exit_code: int,
	fallback: String = "Common fail causes: no internet, or origin is not reachable.",
) -> String:
	if exit_code == -1:
		return "No answer in time (or the command was refused). Check your connection, or raise 'Network timeout' in the Gitot settings."
	return fallback
