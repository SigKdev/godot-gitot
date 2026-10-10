## gitot_logger.gd
## Static logger: formatted (BBCode) lines to the Output panel, a capped history and an optional
## UI listener. EXTREME also goes to printerr.
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


## Raw git output: "[" is escaped so text like "[main abc1234] msg" can never be read as a BBCode tag.
static func g(message: String) -> void:
	_print(message.replace("[", "[lb]"), Level.GIT)


## One shape for every failure: what failed (names the subject), git's raw message, then an
## optional hint. An empty raw message or hint is skipped.
static func fail(title: String, raw: String, hint: String = "") -> void:
	e(title)
	var text: String = raw.strip_edges()
	if not text.is_empty():
		g(text)
	if not hint.is_empty():
		h(hint)


static func _print(message: String, level: Level) -> void:
	var prefix := "[color=deep_sky_blue][Gitot][/color]"
	var color := "white"

	match level:
		Level.SUCCESS:
			color = "forest_green"
			prefix = "[color=forest_green][Gitot Success][/color]"
		Level.WARNING:
			color = "orange"
			prefix = "[color=orange][Gitot Warning][/color]"
		Level.ERROR:
			color = "firebrick"
			prefix = "[color=firebrick][Gitot Error][/color]"
		Level.EXTREME:
			color = "red"
			prefix = "[color=red][Gitot Fatal][/color]"
		Level.GIT:
			color = "dark_gray"
			prefix = "[color=dark_gray][git raw][/color]"
		Level.HINT:
			color = "dark_gray"
			prefix = "[color=dark_gray][Gitot Hint][/color]"
		Level.INFO:
			color = "gray"
			prefix = "[color=gray][Gitot][/color]"

	var formatted := "%s [color=%s]%s[/color]" % [prefix, color, message]
	_history.append(formatted)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	if _on_log.is_valid():
		_on_log.call(formatted)

	if level == Level.EXTREME:
		print_rich(formatted)
		printerr("Gitot: " + message)
	else:
		print_rich(formatted)
