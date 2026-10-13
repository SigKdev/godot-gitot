## gitot_dock.gd
## Main dock: builds the panels (each owns its injected widgets) and wires them to the shared
## GitEngine and GitotResultRouter. Also holds the toolbar, commit and amend logic.
@tool
class_name GitotDock
extends Control

## Forwarded from the history list (signal up; gitot.gd owns the diff panel).
signal commit_selected(entry: GitCommitEntry)

## Forwarded from the result router (signal up; gitot.gd owns the editor-level tooltip).
signal status_parsed(parsed: Dictionary)

## Forwarded from the branch results (signal up; gitot.gd feeds the GitHub panel's base-branch list).
signal branches_parsed(branches: Array[GitBranchEntry])

const PLUGIN_CONFIG_PATH: String = "res://addons/gitot/plugin.cfg"

## Project page behind the Support & Feedback links (opened in the browser).
const REPO_URL: String = "https://github.com/SigKdev/godot-gitot"
const KOFI_URL: String = "https://ko-fi.com/sigkgames"

## Caps _ready()'s self-retry when _git_engine never arrives.
const MAX_READY_RETRIES: int = 30

## Min delay between two focus-in refreshes: a full refresh spawns 5 git processes, and returning
## from the game window or alt-tabbing back and forth must not repeat them.
const FOCUS_REFRESH_COOLDOWN_MSEC: int = 3000

## Commit area wording, normal vs amend mode (see _refresh_commit_ui).
const COMMIT_PLACEHOLDER: String = "Commit Message (multiline supported)"
const AMEND_PLACEHOLDER: String = "Leave empty to keep the previous message"

var _ready_retry_count: int = 0

var _git_engine: GitEngine
var _lfs: GitLfs
var _ready_initialized: bool = false
var _diff_gutter: GitotDiffGutter
var _log_console: GitotLogConsole
var _status_tree: GitotStatusTree
var _status_panel: GitotStatusPanel
var _log_panel: GitotLogPanel
var _stash_panel: GitotStashPanel
var _tag_panel: GitotTagPanel
var _orchestrator: GitSyncOrchestrator
var _branch_panel: GitotBranchPanel
var _branch_creator: GitotBranchCreator
var _branch_deleter: GitotBranchDeleter
var _result_router: GitotResultRouter
var _repo_state: GitotRepoState
var _editor_sync: GitotEditorSync
var _push_flow: GitotPushFlow
var _remote_prompt: GitotRemotePrompt
var _repo_init: GitotRepoInit
## True once the repo probe succeeded (see _on_repo_probe). Until then no git command but the probe runs.
var _repo_confirmed: bool = false
## Mirrors GitEngine.write_busy_changed: a git write (commit, stage, stash...) is running.
var _write_busy: bool = false
## Tick of the last full refresh (see refresh_status). Starts one cooldown back: the first focus-in is due.
var _last_refresh_msec: int = -FOCUS_REFRESH_COOLDOWN_MSEC


## True once the cooldown since the last full refresh has passed.
static func _focus_refresh_due(now_msec: int, last_msec: int) -> bool:
	return now_msec - last_msec >= FOCUS_REFRESH_COOLDOWN_MSEC


func _ready() -> void:
	if not _git_engine:
		# GitEngine not injected yet. Either normal @tool dock timing (resolves within a frame or two)
		# or an instance the editor spawned outside gitot.gd (never resolves): give up past the cap.
		_ready_retry_count += 1
		if _ready_retry_count > MAX_READY_RETRIES:
			GitotLogger.x("Dock disabled: GitEngine was never injected (the plugin failed to start).")
			return
		_ready.call_deferred()
		return
	if _ready_initialized:
		return
	_ready_initialized = true

	_repo_state = GitotRepoState.new()
	_editor_sync = GitotEditorSync.new()
	if _lfs:
		_lfs.pull_finished.connect(_editor_sync.on_lfs_pull_finished)
	_setup_toolbar()
	_build_panels()
	_build_branch_controls()
	_build_router()
	_setup_push_flow()
	_setup_repo_init()
	_setup_settings()
	# Async probe: its answer decides what is shown and loaded (see _on_repo_probe).
	# The router also warns from it if the project is not the repo root.
	_probe_repo()


#region _ready() steps
## Version label, toolbar buttons and the commit/amend area.
func _setup_toolbar() -> void:
	%GitotVersion.text = (
		"[b][font_size=14]Gitot[/font_size][/b] [font_size=9]v%s[/font_size]" % _read_plugin_version()
	)
	%RefreshStatButton.pressed.connect(refresh_status)
	%RefreshStatButton.icon = GitotUi.get_icon("Loop")
	%RefreshDiffButton.pressed.connect(_on_refresh_diff_pressed)
	%RefreshDiffButton.icon = GitotUi.get_icon("Paint")
	%CommitButton.pressed.connect(_on_commit_pressed)
	%AmendCheckButton.toggled.connect(func(_on: bool) -> void: _refresh_commit_ui())
	%AmendConfirmDialog.confirmed.connect(_do_amend)
	%AmendConfirmDialog.canceled.connect(
		func() -> void:
			GitotLogger.w("Amend cancelled."),
	)
	_git_engine.write_busy_changed.connect(_on_write_busy_changed)
	_refresh_commit_ui()
	%PushButton.icon = GitotUi.get_icon("MoveUp")
	%PushButton.mouse_entered.connect(_refresh_push_tooltip) # Tooltip depends on the live counts.
	%PullButton.pressed.connect(_on_pull_pressed)
	%PullButton.icon = GitotUi.get_icon("MoveDown")
	_setup_link_button(%IssueButton, REPO_URL + "/issues")
	_setup_link_button(%FeedbackButton, REPO_URL + "/discussions")
	%KofiButton.icon = GitotUi.get_icon("Heart")
	%KofiButton.pressed.connect(_on_kofibutton_pressed)


## Status, history, shelf, console and tag panels: each owns its injected widgets.
func _build_panels() -> void:
	_status_tree = GitotStatusTree.new(
		_git_engine,
		%UnstagedTree,
		%StagedTree,
		%UnstagedFold,
		%StagedFold,
		_lfs,
	)
	_status_panel = GitotStatusPanel.new(%GitStatusLabel, _repo_state)
	_log_panel = GitotLogPanel.new(_git_engine, %GitlogFold, %GitlogTree)
	_log_panel.commit_selected.connect(commit_selected.emit)
	_stash_panel = GitotStashPanel.new(
		_git_engine,
		%StashFold,
		%StashTree,
		%StashNameEdit,
		%StashDropDialog,
	)
	_log_console = GitotLogConsole.new(_git_engine, %LogList, %LogScroll, %OutputLogFold)
	_tag_panel = GitotTagPanel.new(
		%TagVersioningToggle,
		%TagPanel,
		%UseProjectToggle,
		%TagNameEdit,
		%UseCommitToggle,
		%TagMessageEdit,
	)


## Branch list plus its create/delete controls.
func _build_branch_controls() -> void:
	_branch_panel = GitotBranchPanel.new(_git_engine, %BranchFold, %BranchTree, %FetchBranchButton, _repo_state)
	_branch_creator = GitotBranchCreator.new(
		_git_engine,
		%BranchFold,
		%AddBranchButton,
		%CreateBranchRow,
		%BranchNameEdit,
		%CreateBranchButton,
		%CreateBranchConfirmDialog,
		_repo_state,
	)
	_branch_deleter = GitotBranchDeleter.new(
		_git_engine,
		%DeleteBranchButton,
		%DeleteRemoteBranchButton,
		%DeleteBranchConfirmDialog,
	)
	_branch_panel.selection_changed.connect(_branch_deleter.on_selection_changed)


## Result dispatch; file-changing results are forwarded to the editor sync.
func _build_router() -> void:
	var branch_results: GitotBranchResults = GitotBranchResults.new(
		_git_engine,
		_repo_state,
		_status_panel,
		_branch_panel,
	)
	var sync_results: GitotSyncResults = GitotSyncResults.new(_git_engine, _repo_state)
	_result_router = GitotResultRouter.new(
		_repo_state,
		_status_panel,
		_status_tree,
		branch_results,
		sync_results,
		_log_panel,
		_stash_panel,
	)
	# Switch/create (branch results) and pull (sync results) both move HEAD.
	branch_results.head_moved.connect(_git_engine.request_changed_files_since_switch)
	sync_results.head_moved.connect(_git_engine.request_changed_files_since_switch)
	branch_results.branches_parsed.connect(branches_parsed.emit)
	_result_router.files_changed.connect(_editor_sync.on_files_changed)
	_result_router.file_restored.connect(_editor_sync.on_file_restored)
	_result_router.status_parsed.connect(status_parsed.emit)


func _setup_push_flow() -> void:
	_push_flow = GitotPushFlow.new(_git_engine, _orchestrator, _repo_state, _tag_panel, %PushConfirmDialog)
	%PushButton.pressed.connect(_push_flow.start)
	if _orchestrator:
		%RetryTagPushButton.pressed.connect(_orchestrator.retry_tag_push)
	# No origin: Push asks for the URL first, and resumes once the router confirmed `remote add`.
	_remote_prompt = GitotRemotePrompt.new(_git_engine, %RemoteUrlDialog, %RemoteUrlEdit)
	_push_flow.remote_missing.connect(_remote_prompt.prompt)
	_result_router.origin_added.connect(_push_flow.start)


## "No repository" view: its button initializes git, then the folder is probed again like at startup.
func _setup_repo_init() -> void:
	_repo_init = GitotRepoInit.new(_git_engine, %InitRepoButton)
	_repo_init.initialized.connect(_probe_repo)


func _setup_settings() -> void:
	%SettingsToggleButton.icon = GitotUi.get_icon("GDScript")
	%SettingsToggleButton.pressed.connect(
		func() -> void:
			%SettingsPanel.visible = not %SettingsPanel.visible,
	)
	%SettingsPanel.stash_cap_changed.connect(_stash_panel.refresh_limits)
	%SettingsPanel.status_display_changed.connect(refresh_files) # One `git status` repaints the lists.
#endregion


## Auto-refreshes status when the editor window regains focus,
## gated by the "auto_refresh_on_focus" setting and the cooldown. The Refresh button never waits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if GitotSettings.get_value("auto_refresh_on_focus") and _focus_refresh_due(Time.get_ticks_msec(), _last_refresh_msec):
			refresh_status()


#region set instances
## Assigns the shared GitEngine instance.
func set_git_engine(engine: GitEngine) -> void:
	_git_engine = engine
	_git_engine.command_completed.connect(_on_command_completed)


## Assigns the shared GitLfs instance (Size Guard exemption).
func set_lfs(lfs: GitLfs) -> void:
	_lfs = lfs


## Assigns the push/tag sync orchestrator.
func set_sync_orchestrator(orchestrator: GitSyncOrchestrator) -> void:
	_orchestrator = orchestrator
	orchestrator.push_state_changed.connect(_on_push_state_changed)
	orchestrator.tag_retry_needed.connect(_on_tag_retry_needed)
	orchestrator.tag_conflict.connect(_on_tag_conflict)


## Assigns the shared GitotDiffGutter instance.
func set_diff_gutter(gutter: GitotDiffGutter) -> void:
	_diff_gutter = gutter
#endregion


## Full refresh: file lists, ahead/behind, branches, history and shelf. Does nothing until the
## GitEngine is injected (e.g. during editor startup).
## Without a confirmed repo it only re-probes (e.g. `git init` was run outside Gitot).
func refresh_status() -> void:
	if not _git_engine:
		return
	if not _repo_confirmed:
		_probe_repo()
		return
	_last_refresh_msec = Time.get_ticks_msec()
	refresh_files()
	_git_engine.get_ahead_behind()
	_git_engine.list_branches()
	_log_panel.refresh()
	_stash_panel.refresh()


## Refreshes ONLY the Staged/Unstaged lists (one `git status`). Used after file saves: a save
## cannot change branches, history or shelf, so the full refresh_status() would be wasted work.
func refresh_files() -> void:
	if _git_engine and _repo_confirmed:
		_git_engine.run_fast(GitEngine.Command.STATUS, GitEngine.STATUS_ARGS)


## Disconnects this dock from the shared GitEngine. Called by gitot.gd on exit.
func teardown() -> void:
	if _git_engine and _git_engine.command_completed.is_connected(_on_command_completed):
		_git_engine.command_completed.disconnect(_on_command_completed)
	if _git_engine and _git_engine.write_busy_changed.is_connected(_on_write_busy_changed):
		_git_engine.write_busy_changed.disconnect(_on_write_busy_changed)
	if _log_console:
		_log_console.teardown()


func _read_plugin_version() -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(PLUGIN_CONFIG_PATH) != OK:
		return ""
	return str(config.get_value("plugin", "version", ""))


## Triggers a diff gutter refresh.
## Manual fallback for unreliable save signal.
func _on_refresh_diff_pressed() -> void:
	_diff_gutter.refresh_current_script()


## Every finished command goes to the router (the only dispatch point). Reactions of widgets the dock
## owns (Pull, Commit, repo probe) are per-call on_done callbacks of the call that started them.
func _on_command_completed(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	_result_router.route(command, exit_code, output, context)


## Asks whether the project folder is inside a repository; _on_repo_probe answers.
## The router also warns from the same result if the project is not the repo root.
func _probe_repo() -> void:
	_git_engine.request_repo_prefix(_on_repo_probe)


## Result of the repo probe (`rev-parse --show-prefix`): exit 0 = inside a repository, so the panels load.
## Otherwise, with no ".git" entry, the folder has no repository yet: the "no repository" view replaces
## the panels. A ".git" entry that git still refuses (broken repo, "dubious ownership") is not offered an
## init: the panels load and their commands report git's own error.
func _on_repo_probe(exit_code: int, _output: Array[String]) -> void:
	if _repo_confirmed:
		return # A second probe was already in flight.
	var no_repo: bool = exit_code != 0 and not GitEngine.has_git_entry()
	%NoRepoPanel.visible = no_repo
	%ScrollContainer.visible = not no_repo
	if no_repo:
		return
	_repo_confirmed = true
	refresh_status() # Populate trees immediately instead of waiting for a manual refresh.
	_git_engine.request_remote_url() # Async: the router fills the "owner/repo" header.


## Commits currently staged files with the message from the input field.
func _on_commit_pressed() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	if %AmendCheckButton.button_pressed:
		_on_amend_pressed()
		return
	if message.is_empty():
		GitotLogger.w("Commit message is empty - nothing was committed.")
		return
	_git_engine.run_fast(GitEngine.Command.COMMIT, ["commit", "-m", message], { }, _on_commit_done)


## Confirms before amending. A commit already on origin (ahead == 0 with an upstream set means HEAD is
## on the upstream) always asks; a local-only commit asks when "confirm_amend" is on.
func _on_amend_pressed() -> void:
	var pushed: bool = _repo_state.has_upstream and _repo_state.ahead == 0
	if pushed or GitotSettings.get_value("confirm_amend"):
		%AmendConfirmDialog.dialog_text = GitotUi.amend_confirm_text(
			_repo_state.branch_label(),
			%CommitMessageInput.text.strip_edges(),
			pushed,
		)
		%AmendConfirmDialog.popup_centered()
		return
	_do_amend()


## Runs the amend, called directly or after the dialog is confirmed.
## Empty message keeps the existing one (--no-edit).
func _do_amend() -> void:
	var message: String = %CommitMessageInput.text.strip_edges()
	var args: PackedStringArray = (
		["commit", "--amend", "--no-edit"]
		if message.is_empty()
		else ["commit", "--amend", "-m", message]
	)
	_git_engine.run_fast(GitEngine.Command.AMEND, args, { }, _on_commit_done)


## Commit / amend answered. The input is kept on failure so the user can fix the cause and retry
## without retyping.
func _on_commit_done(exit_code: int, _output: Array[String]) -> void:
	if exit_code == 0:
		%CommitMessageInput.text = ""
		%AmendCheckButton.button_pressed = false


## Busy state from the runner's write lock: covers commit, amend, stage, stash... in one place.
func _on_write_busy_changed(busy: bool) -> void:
	_write_busy = busy
	_refresh_commit_ui()
	if _status_tree:
		_status_tree.set_busy(busy)


## Single place that decides the commit area's wording from two states: busy and amend mode.
## Amend is blocked while busy (a toggle mid-write would race the running command).
func _refresh_commit_ui() -> void:
	var amend: bool = %AmendCheckButton.button_pressed
	%CommitButton.disabled = _write_busy
	%AmendCheckButton.disabled = _write_busy
	%CommitButton.icon = GitotUi.get_icon("Time") if _write_busy else null
	if _write_busy:
		%CommitButton.text = "Working..."
	else:
		%CommitButton.text = "Amend!" if amend else "Commit"
		%CommitButton.tooltip_text = "Amend last commit" if amend else "Commit staged changes"
	%CommitMessageInput.placeholder_text = AMEND_PLACEHOLDER if amend else COMMIT_PLACEHOLDER


func _on_push_state_changed(pushing: bool) -> void:
	GitotUi.set_busy(%PushButton, pushing, "MoveUp")


func _on_tag_retry_needed(needed: bool) -> void:
	%RetryTagPushButton.visible = needed
	%PushButton.disabled = needed


## The push went through but the tag name is taken by another commit: the log line alone is easy to miss.
func _on_tag_conflict(tag_name: String) -> void:
	EditorInterface.get_editor_toaster().push_toast(
		"Gitot: Commits pushed, but tag '%s' already exists on another commit. Rename the tag and push again to tag it."
		% tag_name,
		EditorToaster.SEVERITY_ERROR,
	)


## Button that opens a web page: external-link icon, the URL as tooltip.
func _setup_link_button(button: Button, url: String) -> void:
	button.icon = GitotUi.get_icon("ExternalLink")
	button.tooltip_text = url
	button.pressed.connect(OS.shell_open.bind(url))


## Rebuilt on hover: says what Push will do now (counts come from the repo state, no git call).
func _refresh_push_tooltip() -> void:
	%PushButton.tooltip_text = GitotUi.push_tooltip(
		_repo_state.has_upstream,
		_repo_state.ahead,
		_repo_state.behind,
		_repo_state.has_origin,
	)


## Pulls latest changes from the remote tracking branch.
func _on_pull_pressed() -> void:
	GitotUi.set_busy(%PullButton, true, "MoveDown")
	_git_engine.pull(_on_pull_done)


## Pull answered (success or failure): the button is free again. The log is the sync results' job.
func _on_pull_done(_exit_code: int, _output: Array[String]) -> void:
	GitotUi.set_busy(%PullButton, false, "MoveDown")


func _on_kofibutton_pressed() -> void:
	OS.shell_open(KOFI_URL)
