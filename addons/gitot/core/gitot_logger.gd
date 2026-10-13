## gitot_logger.gd
## Static logger: formatted (BBCode) lines to the Output panel (setting echo_to_output), a capped history
## and an optional UI listener. EXTREME always reaches the Output panel and printerr.
class_name GitotLogger
extends RefCounted

enum Level {
	INFO,
	SUCCESS,
	WARNING,
	ERROR,
	EXTREME,
	GIT,
	HINT, # Advice that follows an error or a result: "Common fail causes: ...", what to do next.
}

const MAX_HISTORY: int = 200

## Per level: prefix label and color (the message takes the same color).
const STYLES: Dictionary[Level, Array] = {
	Level.INFO: ["Gitot", "gray"],
	Level.SUCCESS: ["Gitot Success", "forest_green"],
	Level.WARNING: ["Gitot Warning", "orange"],
	Level.ERROR: ["Gitot Error", "firebrick"],
	Level.EXTREME: ["Gitot Fatal", "red"],
	Level.GIT: ["git raw", "dark_gray"],
	Level.HINT: ["Gitot Hint", "dark_gray"],
}

static var _history: Array[String] = []

## Optional dock listener, set via set_listener(). Kept decoupled: logger
## never references UI types directly, just calls back if one is registered.
static var _on_log: Callable


## Copy of the formatted lines so far (oldest first), for a console opened late.
static func get_history() -> Array[String]:
	return _history.duplicate()


## Forgets the history (the console's Clear), so a reopened console does not backfill cleared lines.
static func clear_history() -> void:
	_history.clear()


## Registers a callback invoked with each formatted log line.
## Pass an empty Callable() to unregister (call this in teardown to avoid
## a dangling reference to a freed dock on plugin disable).
static func set_listener(callback: Callable) -> void:
	_on_log = callback


## Level shortcuts: i = info, s = success, w = warning, h = hint, e = error, x = extreme (fatal).
static func i(message: String) -> void:
	_print(message, Level.INFO)


static func s(message: String) -> void:
	_print(message, Level.SUCCESS)


static func w(message: String) -> void:
	_print(message, Level.WARNING)


static func h(message: String) -> void:
	_print(message, Level.HINT)


static func e(message: String) -> void:
	_print(message, Level.ERROR)


static func x(message: String) -> void:
	_print(message, Level.EXTREME)


## Raw git output (like every message, "[" is escaped in _print).
static func g(message: String) -> void:
	_print(message, Level.GIT)


## One shape for every failure: what failed (names the subject), git's raw message, then an
## optional hint. An empty raw message or hint is skipped.
static func fail(title: String, raw: String, hint: String = "") -> void:
	e(title)
	var text: String = raw.strip_edges()
	if not text.is_empty():
		g(text)
	if not hint.is_empty():
		h(hint)


## "[" is escaped so text like "[main abc1234] msg" or "Level[1].tscn" is never read as a BBCode tag.
static func _print(message: String, level: Level) -> void:
	var style: Array = STYLES[level]
	var color: String = style[1]
	var text: String = message.replace("[", "[lb]")
	var formatted: String = "[color=%s][%s][/color] [color=%s]%s[/color]" % [color, style[0], color, text]
	_history.append(formatted)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	if _on_log.is_valid():
		_on_log.call(formatted)

	# Fatal lines always reach Godot's Output: Gitot may be unable to show its own console.
	if level == Level.EXTREME or GitotSettings.get_value(GitotSettings.KEY_ECHO_TO_OUTPUT):
		print_rich(formatted)
	if level == Level.EXTREME:
		printerr("Gitot: " + message)
