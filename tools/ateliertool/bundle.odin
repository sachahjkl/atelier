package ateliertool

// bundle: the zip of the suite's programs for a platform (src/md/README.md, "The bundle"). For each program of
// programs.odin: the latest release's update manifest names its single file and the file's SHA-256; the file is
// downloaded and checked. The licence files come from the release's Linux archive (the same code on every platform):
// every file of it but the program, the README and the changelog. The logo is the repository's at the release's tag.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import archive "gt:archive"
import toolbox "gt:toolbox"

DOWNLOADS :: "build/downloads"

// What bundle.json says (src/md/README.md): the names are the JSON's.
Bundle_Licence :: struct {
	title: string `json:"title"`,
	file:  string `json:"file"`,
}

Bundle_Program :: struct {
	slug:       string `json:"slug"`,
	name:       string `json:"name"`,
	tagline:    string `json:"tagline"`,
	version:    string `json:"version"`,
	repository: string `json:"repository"`,
	site:       string `json:"site"`,
	file:       string `json:"file"`,
	size:       i64 `json:"size"`,
	sha256:     string `json:"sha256"`,
	logo:       string `json:"logo"`,
	licences:   []Bundle_Licence `json:"licences"`,
}

Bundle_Manifest :: struct {
	schema:   int `json:"schema"`,
	platform: string `json:"platform"`,
	made:     string `json:"made"`,
	programs: []Bundle_Program `json:"programs"`,
}

// A file the bundle will hold: its name in the zip and where it is on the disk.
@(private = "file")
Bundle_File :: struct {
	name: string,
	path: string,
	mode: u32,
}

// The update manifest of a program's latest release (update-<platform>.json, or -stable for a program with channels).
@(private = "file")
Release_File :: struct {
	version: string `json:"version"`,
	file:    string `json:"file"`,
	size:    i64 `json:"size"`,
	sha256:  string `json:"sha256"`,
}

// `bundle [platform] [--out file]`: build/bundle-<platform>.zip by default.
run_bundle :: proc(args: []string) -> int {
	platform, out := THIS_PLATFORM, ""
	for i := 0; i < len(args); i += 1 {
		switch {
		case args[i] == "--out" && i + 1 < len(args): i += 1; out = args[i]
		case strings.has_prefix(args[i], "--"): fmt.eprintfln("bundle: %s is not an option", args[i]); return 2
		case: platform = args[i]
		}
	}
	if out == "" { out = fmt.tprintf("build/bundle-%s.zip", platform) }
	return make_bundle(platform, out, "") ? 0 : 1
}

// Writes the bundle of `platform` to `out`, after the bytes of `host` when it is not "" (the atelier program: then `out`
// is the release's file). Says each program and its version.
make_bundle :: proc(platform, out, host: string) -> bool {
	_ = os.make_directory_all(DOWNLOADS)
	files := make([dynamic]Bundle_File, context.temp_allocator)
	programs := make([dynamic]Bundle_Program, context.temp_allocator)
	for p in PROGRAMS {
		entry, ok, carried := fetch_program(p, platform, &files)
		if !ok { return false }
		if !carried { fmt.printfln("%-16s no %s file: not carried", p.slug, platform); continue }
		append(&programs, entry)
		fmt.printfln("%-16s %s", p.slug, entry.version)
	}
	y, m, d := time.date(time.now())
	manifest := Bundle_Manifest{schema = 1, platform = platform, made = fmt.tprintf("%04d-%02d-%02d", y, int(m), d), programs = programs[:]}
	text, merr := json.marshal(manifest, {pretty = true}, context.temp_allocator)
	if merr != nil { fmt.eprintln("bundle: the manifest cannot be written"); return false }

	w: archive.Zip_Writer
	if err := archive.zip_begin(&w, out, after = host); err != .None { fmt.eprintfln("bundle: %s: %v", out, err); return false }
	archive.zip_add(&w, "atelier/bundle.json", text)
	for f in files {
		data, rerr := os.read_entire_file(f.path, context.allocator)
		if rerr != nil { fmt.eprintfln("bundle: %s cannot be read", f.path); archive.zip_end(&w); return false }
		archive.zip_add(&w, f.name, data, f.mode)
		delete(data)
	}
	if err := archive.zip_end(&w); err != .None { fmt.eprintfln("bundle: %s: %v", out, err); return false }
	fmt.printfln("bundle: %s, %d programs", out, len(programs))
	return true
}

// One program's files for the bundle. carried = false: its latest release has no file for the platform.
@(private = "file")
fetch_program :: proc(p: Suite_Program, platform: string, files: ^[dynamic]Bundle_File) -> (entry: Bundle_Program, ok: bool, carried: bool) {
	repo := fmt.tprintf("%s/%s", OWNER, p.repository)
	tag, tok := latest_tag(repo)
	if !tok { fmt.eprintfln("bundle: %s: no release", repo); return }
	release, found := release_file(repo, tag, platform)
	if !found { return {}, true, false }
	base := fmt.tprintf("https://github.com/%s/releases/download/%s", repo, tag)
	dir := fmt.tprintf("%s/%s-%s", DOWNLOADS, p.slug, release.version)
	program := fmt.tprintf("%s/%s", dir, release.file)
	if why := toolbox.download_pinned(fmt.tprintf("%s/%s", base, release.file), program, release.sha256, quiet = true); why != "" {
		fmt.eprintfln("bundle: %s", why)
		return
	}
	file := fmt.tprintf("%s/%s", p.slug, platform == "windows-x64" ? fmt.tprintf("%s.exe", p.slug) : p.slug)
	append(files, Bundle_File{name = file, path = program, mode = 0o755})

	logo := fmt.tprintf("%s/logo.png", dir)
	if !download(fmt.tprintf("https://raw.githubusercontent.com/%s/%s/assets/logo_64.png", repo, tag), logo) { return }
	append(files, Bundle_File{name = fmt.tprintf("%s/logo.png", p.slug), path = logo, mode = 0o644})

	licences, lok := fetch_licences(p, repo, tag, release.version, dir, files)
	if !lok { return }
	entry = {
		slug = p.slug, name = p.name, tagline = p.tagline, version = release.version,
		repository = fmt.tprintf("https://github.com/%s", repo), site = p.site,
		file = file, size = release.size, sha256 = release.sha256, logo = fmt.tprintf("%s/logo.png", p.slug),
		licences = licences,
	}
	return entry, true, true
}

// The licence files of a release, from its Linux archive: what it holds beside the program, the README and the changelog.
@(private = "file")
fetch_licences :: proc(p: Suite_Program, repo, tag, version, dir: string, files: ^[dynamic]Bundle_File) -> (licences: []Bundle_Licence, ok: bool) {
	name := fmt.tprintf("%s-%s-linux-x64.tar.gz", p.slug, version)
	path := fmt.tprintf("%s/%s", dir, name)
	if !os.exists(path) && !download(fmt.tprintf("https://github.com/%s/releases/download/%s/%s", repo, tag, name), path) { return }
	idx, err := archive.open(path)
	if err != .None { fmt.eprintfln("bundle: %s: %v", path, err); return }
	defer archive.index_destroy(&idx)
	list := make([dynamic]Bundle_Licence, context.temp_allocator)
	for e in idx.entries {
		if e.dir { continue }
		base := filepath.base(e.name)
		upper := strings.to_upper(base, context.temp_allocator)
		if base == p.slug || strings.has_prefix(upper, "README") || strings.has_prefix(upper, "CHANGELOG") { continue }
		out := fmt.tprintf("%s/licences/%s", dir, base)
		if archive.extract(&idx, e.name, out) != .None { fmt.eprintfln("bundle: %s: %s cannot be taken out", path, e.name); return }
		text, _ := os.read_entire_file(out, context.temp_allocator)
		in_zip := fmt.tprintf("%s/%s", p.slug, base)
		append(&list, Bundle_Licence{title = licence_title(base, string(text)), file = in_zip})
		append(files, Bundle_File{name = in_zip, path = out, mode = 0o644})
	}
	// (the program's own licence first, the parts it includes after)
	for l, i in list { if filepath.base(l.file) == "LICENSE" && i > 0 { list[0], list[i] = list[i], list[0] } }
	return list[:], true
}

// What a licence file is to a reader. The program's own (LICENSE): its first line ("MIT License"). Another: what it is
// about, from its file's name, and the licence its first line names ("Lucide (ISC License)", "Third party notices").
licence_title :: proc(file, text: string) -> string {
	first := ""
	for line in strings.split_lines(text, context.temp_allocator) {
		t := strings.trim_space(line)
		if t == "" { continue }
		if len(t) <= 60 && !strings.has_suffix(t, ".") && strings.contains(strings.to_lower(t, context.temp_allocator), "licen") { first = t }
		break
	}
	if file == "LICENSE" { return first != "" ? first : "Licence" }
	name := strings.trim_suffix(strings.trim_suffix(file, ".txt"), ".md")
	for suffix in ([]string{"-LICENSE", "_LICENSE", "-LICENCE"}) { name = strings.trim_suffix(name, suffix) }
	b := strings.builder_make(context.temp_allocator)
	start := true
	for r in strings.to_lower(name, context.temp_allocator) {
		switch {
		case r == '-' || r == '_': strings.write_byte(&b, ' '); start = true
		case start:                strings.write_rune(&b, r - 32 if r >= 'a' && r <= 'z' else r); start = false
		case:                      strings.write_rune(&b, r)
		}
	}
	words := strings.to_string(b)
	return first != "" ? fmt.tprintf("%s (%s)", words, first) : words
}

// The tag of a repository's latest release ("v0.23.2").
latest_tag :: proc(repo: string) -> (tag: string, ok: bool) {
	out, code := toolbox.capture({"gh", "release", "view", "--repo", repo, "--json", "tagName", "--jq", ".tagName"})
	tag = strings.trim_space(out)
	return tag, code == 0 && tag != ""
}

// The update manifest of a release for a platform (the stable channel's for a program with channels).
@(private = "file")
release_file :: proc(repo, tag, platform: string) -> (r: Release_File, ok: bool) {
	names := [?]string{fmt.tprintf("update-%s.json", platform), fmt.tprintf("update-%s-stable.json", platform)}
	assets, code := toolbox.capture({"gh", "release", "view", tag, "--repo", repo, "--json", "assets", "--jq", ".assets[].name"})
	if code != 0 { return }
	for name in names {
		if !strings.contains(assets, fmt.tprintf("%s\n", name)) { continue }
		text, c := toolbox.capture({"gh", "release", "download", tag, "--repo", repo, "--pattern", name, "--output", "-"})
		if c != 0 { return }
		if json.unmarshal_string(text, &r, allocator = context.temp_allocator) != nil { return }
		return r, r.file != "" && len(r.sha256) == 64
	}
	return
}

// A file whose integrity nothing pins (a logo, a release's archive read for its licences): curl, with retries.
@(private = "file")
download :: proc(url, path: string) -> bool {
	_ = os.make_directory_all(filepath.dir(path))
	if toolbox.run({"curl", "-fsSL", "--retry", "5", "--retry-delay", "5", "-o", path, url}) { return true }
	fmt.eprintfln("bundle: %s cannot be downloaded", url)
	return false
}
