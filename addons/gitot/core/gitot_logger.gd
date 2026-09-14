class_name GitotLogger
extends RefCounted

enum Level { INFO, SUCCESS, WARNING, ERROR, EXTREME, GIT }

## Caps log_history so a long editor session doesn't grow it unbounded.
const MAX_HISTORY: int = 200

static var log_history: Array[String] = []

## Optional dock listener, set via set_listener(). Kept decoupled: logger
## never references UI types directly, just calls back if one is registered.
static var _on_log: Callable


## Registers a callback invoked with each formatted log line.
## Pass an empty Callable() to unregister (call this in teardown to avoid
## a dangling reference to a freed dock on plugin disable).
static func set_listener(callback: Callable) -> void:
	_on_log = callback


static func i(message: String) -> void: _print(message, Level.INFO)
static func s(message: String) -> void: _print(message, Level.SUCCESS)
static func w(message: String) -> void: _print(message, Level.WARNING)
static func e(message: String) -> void: _print(message, Level.ERROR)
static func x(message: String) -> void: _print(message, Level.EXTREME)
static func g(message: String) -> void: _print(message, Level.GIT)

static func _print(message: String, level: Level) -> void:
	var prefix := "[color=cyan][Gitot][/color]"
	var color := "white"
	
	match level:
		Level.SUCCESS:
			color = "lime_green"
			prefix = "[color=lime_green][Gitot Success][/color]"
		Level.WARNING:
			color = "orange"
			prefix = "[color=orange][Gitot Warning][/color]"
		Level.ERROR:
			color = "firebrick"
			prefix = "[color=firebrick][Gitot Error][/color]"
		Level.EXTREME:
			color = "red"
			prefix = "[color=red][Gitot Error][/color]"
		Level.GIT:
			color = "dark_gray"
			prefix = "[color=dark_gray][git raw][/color]"
		Level.INFO:
			color = "white"
			prefix = "[color=cyan][Gitot Info][/color]"
			
	var formatted := "%s [color=%s]%s[/color]" % [prefix, color, message]
	log_history.append(formatted)
	if log_history.size() > MAX_HISTORY:
		log_history.pop_front()

	if _on_log.is_valid():
		_on_log.call(formatted)

	if level == Level.EXTREME:
		print_rich(formatted)
		printerr("Gitot: " + message)
	else:
		print_rich(formatted)
