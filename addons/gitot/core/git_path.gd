## git_path.gd
## Decodes git's C-style quoted paths. With the default core.quotepath, git wraps any path holding
## non-ASCII bytes, quotes, backslashes or control chars in "..." and escapes them ("Lumi\303\250re").
## That output is pure ASCII, so it survives OS.execute()'s pipe decoding (raw UTF-8 comes back garbled on Windows).
class_name GitPath
extends RefCounted

## Single-letter escapes git emits, as byte values.
const ESCAPES: Dictionary[String, int] = {
	"a": 7,
	"b": 8,
	"t": 9,
	"n": 10,
	"v": 11,
	"f": 12,
	"r": 13,
	"\"": 34,
	"\\": 92,
}


## "\"Lumi\\303\\250re.mp3\"" or "Lumi\\303\\250re.mp3" -> "Lumière.mp3".
## Surrounding quotes are optional: git status adds them, git-lfs JSON may not. Git always escapes a
## real backslash, so a path without one has nothing to decode and passes through unchanged.
static func unquote(path: String) -> String:
	var body: String = path
	if path.length() >= 2 and path.begins_with("\"") and path.ends_with("\""):
		body = path.substr(1, path.length() - 2)
	elif not path.contains("\\"):
		return path
	var bytes: PackedByteArray = PackedByteArray()
	var i: int = 0
	while i < body.length():
		var c: String = body[i]
		i += 1
		if c != "\\" or i >= body.length():
			bytes.append_array(c.to_utf8_buffer())
			continue
		var octal: String = body.substr(i, 3) # "\303" = one raw byte of the UTF-8 sequence.
		if octal.length() == 3 and octal.is_valid_int():
			bytes.append(octal[0].to_int() * 64 + octal[1].to_int() * 8 + octal[2].to_int())
			i += 3
		else:
			var code: int = ESCAPES.get(body[i], body[i].unicode_at(0))
			bytes.append(code)
			i += 1
	return bytes.get_string_from_utf8() # Bytes -> UTF-8 once, at the end.
