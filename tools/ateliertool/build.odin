package ateliertool

// build, test, check and package: the program and its tests, the same steps on a laptop and in the CI.

import "core:fmt"
import "core:os"
import "core:strings"
import archive "gt:archive"
import changelog "gt:changelog"
import toolbox "gt:toolbox"

DIST :: "build/dist"

run_build :: proc(args: []string) -> int {
	p := project()
	release := len(args) > 0 && args[0] == "release"
	if !toolbox.build_native(p) { return 1 }
	_ = os.make_directory("build")
	extra := make([dynamic]string, context.temp_allocator)
	append(&extra, fmt.tprintf("-out:%s", PROGRAM), release ? "-o:speed" : "-debug")
	// (Windows: no console of its own; `atelier list` and `install` write to the parent's through the launcher)
	when ODIN_OS == .Windows {
		if release { append(&extra, "-subsystem:windows") }
	}
	if !toolbox.run(toolbox.odin_command(p, "build", "", extra[:]), {echo = true}) { return 1 }
	fmt.printfln("built %s", PROGRAM)
	return 0
}

run_test :: proc(args: []string) -> int {
	p := project()
	if !toolbox.build_native(p) { return 1 }
	_ = os.make_directory("build")
	out := fmt.tprintf("-out:build/test_src%s", ODIN_OS == .Windows ? ".exe" : "")
	return toolbox.run(toolbox.odin_command(p, "test", "src", {out}), {echo = true}) ? 0 : 1
}

run_check :: proc(args: []string) -> int {
	p := project()
	if !changelog_check(p) { return 1 }
	if !toolbox.check_scopes("src") { return 1 }
	// (a text of the code not in the catalogue, or not translated, shows in English to a French reader)
	if problem := toolbox.i18n_catalogue(I18N.dirs, "i18n/fr.txt", "fr", true); problem != "" { fmt.eprintln(problem); return 1 }
	if !toolbox.run(toolbox.odin_command(p, "check"), {echo = true}) { return 1 }
	when ODIN_OS != .Windows {
		if !toolbox.check_windows(p) { return 1 }
	}
	if !toolbox.run({"odin", "check", "tools/ateliertool", fmt.tprintf("-collection:gt=%s/src", toolbox.toolkit_dir(p)), "-vet"}, {echo = true}) { return 1 }
	if run_test(nil) != 0 { return 1 }
	if run_build({"release"}) != 0 { return 1 }
	return toolbox.check_launcher(p) ? 0 : 1
}

// `package [version]`: the release build, this platform's bundle written after it, its .sha256 beside it. A version
// given (a tag, "v" or not) must be the sources'.
run_package :: proc(args: []string) -> int {
	p := project()
	version := toolbox.project_version(p)
	if version == "" { fmt.eprintln("package: the version of the sources cannot be read"); return 1 }
	if len(args) > 0 {
		asked := strings.trim_prefix(args[0], "v")
		if asked != version { fmt.eprintfln("package: %s asked, the sources say %s", asked, version); return 1 }
	}
	if run_build({"release"}) != 0 { return 1 }
	_ = os.make_directory_all(DIST)
	out := fmt.tprintf("%s/atelier-%s-%s%s", DIST, version, THIS_PLATFORM, ODIN_OS == .Windows ? ".exe" : "")
	if !make_bundle(THIS_PLATFORM, out, PROGRAM) { return 1 }
	when ODIN_OS != .Windows {
		_ = os.chmod(out, {.Read_User, .Write_User, .Execute_User, .Read_Group, .Execute_Group, .Read_Other, .Execute_Other})
	}
	sum, sok := toolbox.sha256_file(out)
	if !sok { fmt.eprintfln("package: %s cannot be read", out); return 1 }
	name := out[len(DIST) + 1:]
	if os.write_entire_file(fmt.tprintf("%s.sha256", out), transmute([]u8)fmt.tprintf("%s  %s\n", sum, name)) != nil { return 1 }
	// (the manifest beside the file: what the release carries, read by `behind` without downloading the release)
	idx, ierr := archive.open_as(out, .Zip)
	if ierr != .None { fmt.eprintfln("package: %s does not read back: %v", out, ierr); return 1 }
	defer archive.index_destroy(&idx)
	manifest, merr := archive.read(&idx, "atelier/bundle.json", allocator = context.temp_allocator)
	if merr != .None { fmt.eprintfln("package: %s has no manifest", out); return 1 }
	if os.write_entire_file(fmt.tprintf("%s/atelier-%s-%s.json", DIST, version, THIS_PLATFORM), manifest) != nil { return 1 }
	fmt.printfln("package: %s", out)
	return 0
}

// The fragments of changelog.d/ and the roadmap, as `changelog check` says them.
@(private = "file")
changelog_check :: proc(p: toolbox.Project) -> bool {
	q := p
	errors, n := changelog.check(changelog.project_options(&q))
	for e in errors { fmt.eprintln("changelog:", e) }
	if len(errors) == 0 { fmt.printfln("changelog: %d fragments, all well formed", n) }
	return len(errors) == 0
}
