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

// build, test and check are the toolkit's (toolbox.build_commands): atelier's program alone, its French catalogue checked.
build_options :: proc() -> toolbox.Build_Options {
	p := project()
	return {project = p, changelog_command = changelog.command(p), catalogues = I18N}
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
	if !toolbox.program_build(build_options(), release = true) { return .Failed }
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
