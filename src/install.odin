package atelier

// The install of one program, on a worker (src/md/README.md, "The install of one program"): its file taken out of the
// bundle into atelier's scratch folder, its state read from `<file> --status`, then `<file> --install`. Nothing here
// runs on the window's thread: each procedure that reads or writes the disk, or starts a process, is a worker's.

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import archive "gt:archive"
import desktop "gt:desktop"
import i18n "gt:i18n"
import update "gt:update"

// The state of a program in atelier: what its box offers (src/md/README.md, "The states of a program in atelier").
State :: enum u8 {
	Reading,   // its status is not known yet
	Absent,    // not installed
	Older,     // an older version is installed
	Current,   // the same version is installed
	Newer,     // a newer version is installed: it updated itself
	Repair,    // the install is incomplete
	Unknown,   // the status could not be read: the file does not run here
}

// What `--status` of a carried file says.
Status :: struct {
	state:     State,
	installed: string,   // the installed copy's version ("": none, or not said)
	program:   string,   // the installed program's path ("": none)
	reason:    string,   // Unknown: why
}

status_destroy :: proc(s: ^Status) {
	delete(s.installed); delete(s.program); delete(s.reason)
	s^ = {}
}

// The exit codes of `<program> --status` (gt:setup's COMMAND_*).
STATUS_INSTALLED :: 0
STATUS_ABSENT    :: 1
STATUS_REPAIR    :: 2

// Whether a box of this state is ticked when its status comes: what the person most likely wants.
state_ticked :: proc(s: State) -> bool {
	return s == .Absent || s == .Older || s == .Repair
}

// Whether a box of this state can be ticked at all: a status not read yet, a newer copy (installing would go back), a
// file that does not run here.
state_choosable :: proc(s: State) -> bool {
	return s != .Reading && s != .Newer && s != .Unknown
}

// atelier's scratch folder: `<cache>/atelier`. Never the system's temporary folder: on many systems it is in memory, and
// a bundle is more than 100 MB. "": the system names no cache folder.
scratch_dir :: proc(allocator := context.allocator) -> string {
	cache, err := os.user_cache_dir(context.temp_allocator)
	if err != nil || cache == "" { return "" }
	return join(cache, APP_NAME, allocator)
}

// The folder of one program's file: `<cache>/atelier/<slug>-<version>`.
scratch_folder :: proc(p: Program, allocator := context.allocator) -> string {
	dir := scratch_dir(context.temp_allocator)
	if dir == "" { return "" }
	return join(dir, strings.concatenate({p.slug, "-", p.version}, context.temp_allocator), allocator)
}

// Takes a program's file out of the bundle into its scratch folder, runnable, and checks its SHA-256 against the
// manifest. `why` says what failed, in the language in use ("" when `path` is good).
take_out :: proc(b: ^Bundle, p: Program, allocator := context.allocator) -> (path: string, why: string) {
	folder := scratch_folder(p, context.temp_allocator)
	if folder == "" { return "", i18n.tr("this system names no cache folder") }
	data, err := archive.read(&b.index, p.file)
	if err != .None { return "", i18n.tr("the file cannot be read from the bundle") }
	defer delete(data)
	if i64(len(data)) != p.size || update.sha256_hex(data, context.temp_allocator) != p.sha256 {
		return "", i18n.tr("the file in the bundle is damaged: its size or its SHA-256 differs")
	}
	// (the programs are taken out side by side: another worker may make the shared parent first, an error then)
	if os.make_directory_all(folder) != nil && !os.is_dir(folder) { return "", i18n.tr("the scratch folder cannot be made") }
	out := join(folder, filepath.base(p.file), context.temp_allocator)
	if os.write_entire_file(out, data) != nil { return "", i18n.tr("the file cannot be written to the scratch folder") }
	if !make_runnable(out) { return "", i18n.tr("the file cannot be made runnable") }
	return strings.clone(out, allocator), ""
}

// Two parts of a path joined by the system's separator.
join :: proc(a, b: string, allocator := context.allocator) -> string {
	s, _ := filepath.join({a, b}, allocator)
	return s
}

// Deletes a program's scratch folder (after its install, and at atelier's end).
scratch_remove :: proc(p: Program) {
	folder := scratch_folder(p, context.temp_allocator)
	if folder != "" { _ = os.remove_all(folder) }
}

// At atelier's end: the scratch folder goes when it is empty (another atelier that runs keeps its own files there).
scratch_end :: proc() {
	if dir := scratch_dir(context.temp_allocator); dir != "" { _ = os.remove(dir) }
}

// Runs `<file> --status` and reads what it says.
status_read :: proc(path: string, carried: string, allocator := context.allocator) -> Status {
	code, out, ok := run_captured({path, "--status"})
	if !ok { return {state = .Unknown, reason = strings.clone(i18n.tr("the program does not start on this system"), allocator)} }
	return status_parse(code, out, carried, allocator)
}

// The state of a program from its `--status`: the exit code (0 installed, 2 to repair, 1 not installed), its lines
// `  version: X` and `  program: P`, and the version carried. Another exit code: the program could not answer.
status_parse :: proc(code: int, text: string, carried: string, allocator := context.allocator) -> (s: Status) {
	installed := status_field(text, "version")
	program := status_field(text, "program")
	switch code {
	case STATUS_ABSENT: s.state = .Absent
	case STATUS_REPAIR: s.state = .Repair
	case STATUS_INSTALLED:
		s.state = .Current
		// (an installed copy that does not say its version, or a version that does not read as one: installed, nothing
		// to offer; the box is not ticked and the person can still tick it)
		if order, ok := update.version_compare(installed, carried); ok {
			if order < 0 { s.state = .Older } else if order > 0 { s.state = .Newer }
		}
	case:
		s.state = .Unknown
		first := strings.trim_space(text)
		if nl := strings.index_byte(first, '\n'); nl >= 0 { first = first[:nl] }
		s.reason = strings.clone(first != "" ? first : i18n.tr("the program did not answer"), allocator)
	}
	s.installed = strings.clone(installed, allocator)
	s.program = strings.clone(program, allocator)
	return
}

// The value of a line `  <key>: <value>` of a --status text ("": none, or "-").
status_field :: proc(text: string, key: string) -> string {
	rest := text
	for line in strings.split_lines_iterator(&rest) {
		l := strings.trim_space(line)
		if !strings.has_prefix(l, key) { continue }
		after := l[len(key):]
		if !strings.has_prefix(after, ":") { continue }
		v := strings.trim_space(after[1:])
		return v == "-" ? "" : v
	}
	return ""
}

// Runs `<file> --install`: the program installs itself. `output` is what it said (owned), kept to show when it failed.
install_one :: proc(path: string, allocator := context.allocator) -> (ok: bool, output: string) {
	code, out, started := run_captured({path, "--install"})
	if !started { return false, strings.clone(i18n.tr("The program does not start on this system."), allocator) }
	return code == 0, strings.clone(strings.trim_space(out), allocator)
}

// Whether this system is NixOS, where a carried file does not run (its interpreter is not at /lib64).
nixos :: proc() -> bool { return desktop.is_nixos() }

// One start at a time, process-wide: a child started while another start is under way inherits what that start opened
// for its own child. The programs then run side by side: each writes to a file of its own, not to a pipe, so a file
// another child inherited holds nothing up (a pipe's reader waits for every writer to end).
@(private = "file")
start_lock: sync.Mutex

// Runs a program to its end; `out` is its standard output and its error output (temp memory), written to
// `<program>.out` beside it, then read and deleted.
@(private = "file")
run_captured :: proc(command: []string) -> (code: int, out: string, ok: bool) {
	path := strings.concatenate({command[0], ".out"}, context.temp_allocator)
	f, ferr := os.open(path, {.Write, .Create, .Trunc}, os.Permissions_Default_File)
	if ferr != nil { return 0, "", false }
	p: os.Process
	err: os.Error
	{
		sync.mutex_lock(&start_lock)
		defer sync.mutex_unlock(&start_lock)
		p, err = os.process_start({command = command, working_dir = filepath.dir(command[0]), stdout = f, stderr = f})
	}
	os.close(f)
	defer _ = os.remove(path)
	if err != nil { return 0, "", false }
	state, werr := os.process_wait(p)
	if werr != nil { return 0, "", false }
	text, _ := os.read_entire_file(path, context.temp_allocator)
	return state.exit_code, string(text), state.exited
}

// Checks again the file taken out at the start (it waited on the disk meanwhile): its size and its SHA-256. `why` ""
// when it is the bundle's.
check_scratch :: proc(path: string, p: Program) -> (why: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil { return i18n.tr("the file taken out cannot be read") }
	defer delete(data)
	if i64(len(data)) != p.size || update.sha256_hex(data, context.temp_allocator) != p.sha256 {
		return i18n.tr("the file taken out changed: its size or its SHA-256 differs")
	}
	return ""
}
