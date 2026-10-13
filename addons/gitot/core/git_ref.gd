## Name rules for refs that reach git or origin (tags, branches). Pure text logic, no git process.
class_name GitRef
extends RefCounted

## Git ref-name rules that make a tag name invalid (see `git check-ref-format`):
## whitespace/control chars and ~ ^ : ? * [ \ | ".." | "@{" | lone "@" | leading "-" or "/"
## | trailing "/" or "." | "//" | ".lock" component | component starting with ".".
const INVALID_TAG_PATTERN: String = r"[\x00-\x20\x7f~^:?*\[\\]|\.\.|@\{|^@$|^[-/]|[/.]$|//|\.lock(/|$)|(^|/)\."

## Branch names this plugin may send to origin (strict subset of git's rules, see delete_remote_branch()):
## starts with a letter/digit, then letters, digits and . _ / - only. Also excludes every shell metacharacter.
const SAFE_BRANCH_PATTERN: String = "^[A-Za-z0-9][A-Za-z0-9._/-]*$"


## True if git would accept tag_name. Checked BEFORE the push so a bad name can't leave
## a pushed commit without its tag.
static func is_valid_tag_name(tag_name: String) -> bool:
	return not tag_name.is_empty() and GitotRegex.compiled(INVALID_TAG_PATTERN).search(tag_name) == null


## True if name is a branch name this plugin will send to origin (see SAFE_BRANCH_PATTERN).
static func is_safe_branch_name(branch_name: String) -> bool:
	return GitotRegex.compiled(SAFE_BRANCH_PATTERN).search(branch_name) != null
