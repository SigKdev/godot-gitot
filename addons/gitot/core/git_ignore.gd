## git_ignore.gd
## Default .gitignore for a Godot 4 project, written only when the folder has none.
class_name GitIgnore
extends RefCounted

enum Result {
	CREATED,
	EXISTS, ## A .gitignore is already there: never touched, it may hold the user's own rules.
	FAILED, ## The file could not be written.
}

const FILE_NAME: String = ".gitignore"

## What the Godot docs ("Version control systems", Godot 4.1+) list as generated data to keep out of version
## control: the cache folder and the translations imported from CSV files.
const TEMPLATE: String = "# Godot 4+ specific ignores\n.godot/\n\n# Imported translations (generated from CSV files)\n*.translation\n"


## Writes TEMPLATE to <dir>/.gitignore unless that file already exists.
## @param dir: project folder ("res://" or an absolute path).
static func create_if_missing(dir: String) -> Result:
	var path: String = dir.path_join(FILE_NAME)
	if FileAccess.file_exists(path):
		return Result.EXISTS
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.FAILED
	var written: bool = file.store_string(TEMPLATE)
	file.close()
	return Result.CREATED if written else Result.FAILED
