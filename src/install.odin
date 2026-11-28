package atelier

// The install of one program, on a worker (src/md/README.md, "The install of one program"): its file taken out of the
// bundle into atelier's scratch folder, its state read from `<file> --status`, then `<file> --install`. Nothing here
// runs on the window's thread: each procedure that reads or writes the disk, or starts a process, is a worker's.

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import archive "gt:archive"
import desktop "gt:desktop"
import i18n "gt:i18n"
import "gt:platform"
import process "gt:process"
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
	by_nix:    bool,     // installed by the Nix configuration: no box (atelier's own row)
	running:   bool,     // a copy of the program runs (its line `running: true`)
	quits:     bool,     // the installed copy says `quit: yes`: its --quit ends the copy that runs (open_read)
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

// Whether a program in this state is installed and can be uninstalled from Atelier.
state_uninstallable :: proc(s: State) -> bool {
	return s == .Older || s == .Current || s == .Newer || s == .Repair
}

// atelier's scratch folder: its cache folder (`<cache>/FromentSoftware/Atelier`). Never the system's temporary folder: on
// many systems it is in memory, and a bundle is more than 100 MB. "": the system names no cache folder.
scratch_dir :: proc(allocator := context.allocator) -> string {
	return platform.user_dir(.Cache, APP_FOLDER, allocator)
}

// The folder of one program's file: `<scratch>/<slug>-<version>`.
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
	// (what its release puts beside it: its install copies it from there, the program loads it from there)
	if beside := take_out_beside(b, p, folder); beside != "" { return "", beside }
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
// `  version: X`, `  program: P` and `  running: true|false`, and the version carried. Another exit code: the program
// could not answer.
status_parse :: proc(code: int, text: string, carried: string, allocator := context.allocator) -> (s: Status) {
	installed := status_field(text, "version")
	program := status_field(text, "program")
	s.running = status_field(text, "running") == "true"
	// (the words of the first line say the state; a program built on gui_toolkit 0.278.0 or later exits 1 for "to
	// repair" as for "not installed", so the code alone no longer tells them apart. The code stays the answer of a
	// program whose first line says neither)
	first_line := strings.trim_space(text)
	if nl := strings.index_byte(first_line, '\n'); nl >= 0 { first_line = first_line[:nl] }
	code := code
	s.by_nix = strings.has_suffix(first_line, ": installed by Nix")
	switch {
	case strings.has_suffix(first_line, ": installed, to repair"):  code = STATUS_REPAIR
	case strings.has_suffix(first_line, ": not installed"), strings.has_suffix(first_line, ": uninstalled"): code = STATUS_ABSENT
	}
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

// The status of a program right before its install (src/md/README.md, "A program that runs"): `--status` of the carried
// file, then, when a copy runs, the installed copy's own `--status`: its `quit: yes` says that the copy that runs
// understands --quit. A program built before the toolkit's --quit has no such line, and its --quit would open its window.
open_read :: proc(path: string, carried: string, allocator := context.allocator) -> Status {
	s := status_read(path, carried, allocator)
	if s.running && s.program != "" {
		// (its output beside the carried file: nothing is written in the program's own folder)
		_, out, ok := run_captured({s.program, "--status"}, strings.concatenate({path, ".installed.out"}, context.temp_allocator))
		s.quits = ok && status_field(out, "quit") == "yes"
	}
	return s
}

// How long the Close phase waits for each of its acts: the copy asked to end, the processes ended, the file freed; and
// how often it looks.
CLOSE_WAIT :: 10 * time.Second
CLOSE_POLL :: 50 * time.Millisecond

// Closes the copy of a program that runs before its file `exe` (the installed copy) is replaced: its --quit when it has
// one (`quits`), then the processes that still run that file are ended, then the file must be free. `scratch`: the
// carried file, beside which the output of --quit is written. why: "" when the file is free (in the language in use).
close_program :: proc(exe: string, quits: bool, scratch: string) -> (why: string) {
	// (no installed copy: nothing holds the file that the install writes; a copy run from elsewhere ends with its --quit)
	if exe == "" { return "" }
	if quits {
		// (its exit code is not the last word: the processes are looked at anyway)
		_, _, _ = run_captured({exe, "--quit"}, strings.concatenate({scratch, ".quit.out"}, context.temp_allocator))
	}
	if !processes_end(exe, .Terminate) && !processes_end(exe, .Kill) { return i18n.tr("the program that runs does not end") }
	if !wait_until(CLOSE_WAIT, exe, file_free) { return i18n.tr("the program's file stays in use") }
	return ""
}

// Ends the processes that run `exe` with `sig`, then waits until none runs it (bounded). True when none runs.
@(private = "file")
processes_end :: proc(exe: string, sig: process.Signal) -> bool {
	sent := false
	deadline := time.tick_add(time.tick_now(), CLOSE_WAIT)
	for {
		found := process.processes_of(exe, context.temp_allocator)
		if len(found) == 0 { return true }
		if !sent {
			for p in found { _, _ = process.signal_process(p.pid, p.start_time, sig) }
			sent = true
		}
		if time.tick_diff(time.tick_now(), deadline) <= 0 { return false }
		time.sleep(CLOSE_POLL)
	}
}

// Whether `cond(arg)` came true within `limit`, looked at every CLOSE_POLL.
@(private = "file")
wait_until :: proc(limit: time.Duration, arg: string, cond: proc(arg: string) -> bool) -> bool {
	deadline := time.tick_add(time.tick_now(), limit)
	for {
		if cond(arg) { return true }
		if time.tick_diff(time.tick_now(), deadline) <= 0 { return false }
		time.sleep(CLOSE_POLL)
	}
}

// Whether the file can be opened for writing: no process runs it any more (Windows holds a running program's file;
// Linux refuses to write a running file, ETXTBSY). A file that is not there is free.
@(private = "file")
file_free :: proc(path: string) -> bool {
	if !os.exists(path) { return true }
	f, err := os.open(path, {.Write})
	if err != nil { return false }
	os.close(f)
	return true
}

// Runs `<file> --install`: the program installs itself. `output` is what it said (owned), kept to show when it failed;
// `exit_code` its exit code (nil: it did not start).
install_one :: proc(path: string, allocator := context.allocator) -> (ok: bool, output: string, exit_code: Maybe(int)) {
	code, out, started := run_captured({path, "--install"})
	if !started { return false, strings.clone(i18n.tr("The program does not start on this system."), allocator), nil }
	return code == 0, strings.clone(strings.trim_space(out), allocator), code
}

// Runs `<path> --uninstall` to its end. Same return shape as install_one.
uninstall_one :: proc(path: string, allocator := context.allocator) -> (ok: bool, output: string, exit_code: Maybe(int)) {
	code, out, started := run_captured({path, "--uninstall"})
	if !started { return false, strings.clone(i18n.tr("The program does not start on this system."), allocator), nil }
	return code == 0, strings.clone(strings.trim_space(out), allocator), code
}

// The lines of an install's output that are advice, not a cause: never the reason of a failure.
@(private = "file", rodata)
NOISE := [?]string{"a Nix package is the better install"}

@(private = "file")
first_reason_line :: proc(output: string) -> string {
	rest := output
	lines: for line in strings.split_lines_iterator(&rest) {
		l := strings.trim_space(line)
		if l == "" { continue }
		for n in NOISE { if strings.contains(l, n) { continue lines } }
		return l
	}
	return ""
}

// Why a phase failed, in one line (src/md/README.md, "A failed install, again"): the first line of `output` that says
// something, advice skipped; when there is none, the phase and the exit code. In the temporary memory.
failure_reason :: proc(output: string, phase: Install_Phase, exit_code: Maybe(int)) -> string {
	if l := first_reason_line(output); l != "" { return l }
	code, ran := exit_code.?
	if !ran { return fmt.tprintf(i18n.tr("The %s phase failed: Atelier has no reason for it."), phase_words(phase)) }
	return fmt.tprintf(i18n.tr("The install did not finish: the program gave no reason. Its exit code: %s"), exit_code_words(code))
}

// Why an uninstall failed, in one line. In the temporary memory.
uninstall_failure_reason :: proc(output: string, exit_code: Maybe(int)) -> string {
	if l := first_reason_line(output); l != "" { return l }
	code, ran := exit_code.?
	if !ran { return i18n.tr("The uninstall did not finish: the program gave no reason.") }
	return fmt.tprintf(i18n.tr("The uninstall did not finish: the program gave no reason. Its exit code: %s"), exit_code_words(code))
}

// A phase's name, as its stepper's node says it.
phase_words :: proc(phase: Install_Phase, own := false) -> string {
	switch phase {
	case .Close:   return i18n.tr("Close")
	case .Unpack:  return i18n.tr("Unpack")
	case .Install: return own ? i18n.tr("Copy") : i18n.tr("Install")
	case .Check:   return i18n.tr("Check")
	}
	return ""
}

// An exit code as a person can look it up: a Windows NTSTATUS (above 255, or negative once read as a signed 32-bit code)
// in hex, with its meaning when it is a common one; a small code in decimal. In the temporary memory.
exit_code_words :: proc(code: int) -> string {
	if code >= 0 && code <= 255 { return fmt.tprintf("%d", code) }
	status := u32(i64(code) & 0xffff_ffff)
	meaning: string
	switch status {
	case 0xC0000135: meaning = i18n.tr("a DLL that it needs is missing")
	case 0xC000007B: meaning = i18n.tr("a DLL that it needs is not for this system")
	case 0xC0000005: meaning = i18n.tr("it crashed")
	case 0xC0000409: meaning = i18n.tr("it crashed")
	}
	if meaning == "" { return fmt.tprintf("0x%08X", status) }
	return fmt.tprintf("0x%08X (%s)", status, meaning)
}

// Whether this system is NixOS, where a carried file does not run (its interpreter is not at /lib64).
nixos :: proc() -> bool { return desktop.is_nixos() }

// Runs a program to its end; `out` is its standard output and its error output (temp memory), written to `out_path`
// (default: `<program>.out` beside it), then read and deleted. One file for both keeps their lines in the order the
// program wrote them. process.start holds the toolkit's lock around the spawn: the programs run side by side.
@(private = "file")
run_captured :: proc(command: []string, out_path := "") -> (code: int, out: string, ok: bool) {
	path := out_path != "" ? out_path : strings.concatenate({command[0], ".out"}, context.temp_allocator)
	f, ferr := os.open(path, {.Write, .Create, .Trunc}, os.Permissions_Default_File)
	if ferr != nil { return 0, "", false }
	p, err := process.start({command = command, working_dir = filepath.dir(command[0]), env = child_env(), stdout = f, stderr = f})
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
