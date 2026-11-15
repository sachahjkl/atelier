package ateliertool

// build, test, check and package: the program and its tests, the same steps on a laptop and in the CI.

import "core:fmt"
import "core:os"
import "core:strings"
import archive "gt:archive"
import changelog "gt:changelog"
import cli "gt:cli"
import toolbox "gt:toolbox"
import update "gt:update"
import atelier_update "../../src/update"

DIST :: "build/dist"

run_build :: proc(args: []string) -> cli.Exit {
	p := project()
	release := len(args) > 0 && args[0] == "release"
	if !toolbox.build_native(p) { return .Failed }
	_ = os.make_directory("build")
	extra := make([dynamic]string, context.temp_allocator)
	append(&extra, fmt.tprintf("-out:%s", PROGRAM), release ? "-o:speed" : "-debug")
	// (Windows: no console of its own; `atelier list` and `install` write to the parent's through the launcher)
	when ODIN_OS == .Windows {
		if release { append(&extra, "-subsystem:windows") }
	}
	if !toolbox.run(toolbox.odin_command(p, "build", "", extra[:]), {echo = true}) { return .Failed }
	fmt.printfln("built %s", PROGRAM)
	return .Done
}

run_test :: proc(args: []string) -> cli.Exit {
	p := project()
	if !toolbox.build_native(p) { return .Failed }
	_ = os.make_directory("build")
	out := fmt.tprintf("-out:build/test_src%s", ODIN_OS == .Windows ? ".exe" : "")
	return toolbox.ended(toolbox.run(toolbox.odin_command(p, "test", "src", {out}), {echo = true}))
}

run_check :: proc(args: []string) -> cli.Exit {
	p := project()
	if !changelog_check(p) { return .Failed }
	if !toolbox.check_scopes("src") { return .Failed }
	// (a text of the code not in the catalogue, or not translated, shows in English to a French reader)
	if problem := toolbox.i18n_catalogue(I18N.dirs, "i18n/fr.txt", "fr", true); problem != "" { fmt.eprintln(problem); return .Failed }
	if !toolbox.run(toolbox.odin_command(p, "check"), {echo = true}) { return .Failed }
	when ODIN_OS != .Windows {
		if !toolbox.check_windows(p) { return .Failed }
	}
	if !toolbox.run({"odin", "check", "tools/ateliertool", fmt.tprintf("-collection:gt=%s/src", toolbox.toolkit_dir(p)), "-vet"}, {echo = true}) { return .Failed }
	if run_test(nil) != .Done { return .Failed }
	if run_build({"release"}) != .Done { return .Failed }
	return toolbox.ended(toolbox.check_launcher(p))
}

// `package [version]`: the release build, this platform's bundle written after it, its .sha256 beside it, and the
// update manifest of that whole file (update-<platform>.json and .sig) signed by $UPDATE_SIGNING_KEY. A version given (a
// tag, "v" or not) must be the sources', and needs the key: the installed ateliers update themselves from the release's
// manifest. Without a version and without the key, the file is unsigned (a try).
//
// The manifest names the whole file, not the program alone (as release.package_ would): the file's name is the one
// update.expected_file_name gives atelier's product, so an installed atelier that updates itself gets the bundle too.
run_package :: proc(args: []string) -> cli.Exit {
	p := project()
	version := toolbox.project_version(p)
	if version == "" { fmt.eprintln("package: the version of the sources cannot be read"); return .Failed }
	if len(args) > 0 {
		asked := strings.trim_prefix(args[0], "v")
		if asked != version { fmt.eprintfln("package: %s asked, the sources say %s", asked, version); return .Failed }
	}
	signed := os.get_env(toolbox.UPDATE_KEY_ENV, context.temp_allocator) != ""
	if len(args) > 0 && !signed { fmt.eprintfln("package: a release signs its update manifest: set %s", toolbox.UPDATE_KEY_ENV); return .Failed }
	if run_build({"release"}) != .Done { return .Failed }
	_ = os.make_directory_all(DIST)
	// (the name the updater expects of the release's file: atelier-<version>-<platform>, .exe on Windows)
	out := fmt.tprintf("%s/%s", DIST, update.expected_file_name(atelier_update.PRODUCT, version, update.PLATFORM, context.temp_allocator))
	if !make_bundle(THIS_PLATFORM, out, PROGRAM) { return .Failed }
	when ODIN_OS != .Windows {
		_ = os.chmod(out, {.Read_User, .Write_User, .Execute_User, .Read_Group, .Execute_Group, .Read_Other, .Execute_Other})
	}
	sum, sok := toolbox.sha256_file(out)
	if !sok { fmt.eprintfln("package: %s cannot be read", out); return .Failed }
	name := out[len(DIST) + 1:]
	if os.write_entire_file(fmt.tprintf("%s.sha256", out), transmute([]u8)fmt.tprintf("%s  %s\n", sum, name)) != nil { return .Failed }
	// (the manifest beside the file: what the release carries, read by `behind` without downloading the release)
	idx, ierr := archive.open_as(out, .Zip)
	if ierr != .None { fmt.eprintfln("package: %s does not read back: %v", out, ierr); return .Failed }
	defer archive.index_destroy(&idx)
	manifest, merr := archive.read(&idx, "atelier/bundle.json", allocator = context.temp_allocator)
	if merr != .None { fmt.eprintfln("package: %s has no manifest", out); return .Failed }
	if os.write_entire_file(fmt.tprintf("%s/atelier-%s-%s.json", DIST, version, THIS_PLATFORM), manifest) != nil { return .Failed }
	update_manifest := fmt.tprintf("%s/%s", DIST, update.manifest_name(update.PLATFORM, "", context.temp_allocator))
	if signed {
		if why := toolbox.update_manifest(atelier_update.PRODUCT, out, version, "", update_manifest); why != "" { fmt.eprintfln("package: %s", why); return .Failed }
	} else {
		// (an earlier signed package's manifest would name another file)
		_ = os.remove(update_manifest)
		_ = os.remove(fmt.tprintf("%s.sig", update_manifest))
	}
	fmt.printfln("package: %s%s", out, signed ? "" : " (unsigned: no update manifest)")
	return .Done
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
