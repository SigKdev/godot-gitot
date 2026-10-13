## Field separator shared by the custom `--format` strings and their parsers. Kept apart from GitEngine
## and from the parsers so neither side has to depend on the other.
class_name GitFormat
extends RefCounted

## Field delimiter (unit separator, 0x1F), unlikely to appear in git output.
## Built with char(): GDScript has no \x escape.
const UNIT_SEP: String = char(0x1F)
