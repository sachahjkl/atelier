package atelier

// The bundle: a zip written after atelier's own bytes (src/md/README.md, "The bundle"). Its manifest, atelier/bundle.json,
// names each program, its file, its logo and its licences; the files stay in the zip until a worker takes one out.

import "core:encoding/json"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"
import archive "gt:archive"
import i18n "gt:i18n"
import update "gt:update"

// Where the manifest is in the zip.
MANIFEST :: "atelier/bundle.json"

// The schema of the manifest this atelier reads.
SCHEMA :: 1

// The most bytes of a manifest, a logo or a licence: none is near it, and a damaged zip cannot make atelier read
// gigabytes into memory.
SMALL_FILE_LIMIT :: 16 << 20

Licence :: struct {
	title: string,
	file:  string,   // its path in the zip
}

// A file of a program's release that goes beside it (Windows: the toolkit's gt_webp.dll, the console launcher
// <slug>.com): taken out with the program into its folder, so that its install copies it and the program loads it.
Beside :: struct {
	file:   string,   // its path in the zip; its name beside the program is the path's last part
	size:   i64,
	sha256: string,
}

Program :: struct {
	slug:       string,
	name:       string,
	tagline:    string,
	version:    string,   // the version of the file carried
	repository: string,   // https://github.com/<owner>/<name>
	site:       string,
	file:       string,   // its path in the zip
	size:       i64,
	sha256:     string,
	logo:       string,   // its path in the zip ("": none)
	licences:   []Licence,
	beside:     []Beside,   // what goes beside it in its folder (none on Linux)
	// atelier itself, the first row of the list (own.odin): its file is the running program, not the bundle's. Never
	// read from a manifest
	own:        bool `json:"-"`,
}

// The manifest, and the zip it came from. Its strings live in its arena: they are only read once the bundle is open, by
// the window's thread and by the workers alike.
Bundle :: struct {
	schema:   int,
	platform: string,
	made:     string,   // when the bundle was made (RFC 3339, UTC)
	made_ms:  i64,      // the same, in milliseconds since 1970 (0: it does not read as a time)
	programs: []Program,
	index:    archive.Index,
	arena:    virtual.Arena,
}

Bundle_Error :: enum u8 {
	None,
	No_Bundle,      // the file is no zip, or the zip has no manifest: a development build of atelier
	Bad_Manifest,   // a manifest this atelier cannot read
}

// Opens the bundle at `path` (atelier's own executable, or --bundle's file): its index and its manifest. Reads a few
// kilobytes at the end of the file, then the manifest.
bundle_open :: proc(path: string) -> (b: ^Bundle, err: Bundle_Error) {
	b = new(Bundle)
	ierr: archive.Error
	b.index, ierr = archive.open_as(path, .Zip)
	if ierr != .None {
		free(b)
		return nil, .No_Bundle
	}
	data, rerr := archive.read(&b.index, MANIFEST, SMALL_FILE_LIMIT, context.temp_allocator)
	if rerr == .Not_Found {
		bundle_destroy(b)
		return nil, .No_Bundle
	}
	if rerr != .None || !bundle_parse(b, data) {
		bundle_destroy(b)
		return nil, .Bad_Manifest
	}
	return b, .None
}

bundle_destroy :: proc(b: ^Bundle) {
	if b == nil { return }
	archive.index_destroy(&b.index)
	virtual.arena_destroy(&b.arena)
	free(b)
}

// Reads a manifest into `b` (its arena). False when it is not JSON, has another schema, or a program lacks what atelier
// needs to install it.
bundle_parse :: proc(b: ^Bundle, data: []u8) -> bool {
	Manifest :: struct {
		schema:   int,
		platform: string,
		made:     string,
		programs: []Program,
	}
	m: Manifest
	if json.unmarshal(data, &m, allocator = virtual.arena_allocator(&b.arena)) != nil { return false }
	if m.schema != SCHEMA { return false }
	for &p in m.programs {
		// (a file without its size and SHA-256 cannot be checked once taken out: such a manifest is refused whole. The
		// slug atelier is atelier's own row, on the command line too)
		if p.slug == "" || p.name == "" || p.version == "" || p.file == "" || p.size <= 0 || !slug_ok(p.slug) || !sha256_ok(p.sha256) || p.slug == APP_NAME { return false }
		for x in p.beside {
			name := x.file[strings.last_index_byte(x.file, '/') + 1:]
			if x.size < 0 || !sha256_ok(x.sha256) || !slug_ok(strings.trim_suffix(strings.trim_suffix(strings.trim_suffix(name, ".dll"), ".com"), ".exe")) { return false }
		}
		p.own = false   // (the key "-" of a manifest would set it)
	}
	b.schema, b.platform, b.made, b.programs = m.schema, m.platform, m.made, m.programs
	if t, n := time.rfc3339_to_time_utc(m.made); n > 0 { b.made_ms = time.to_unix_nanoseconds(t) / 1_000_000 }
	return true
}

// A slug names a folder of the scratch space: letters, digits, '-' and '_' only.
@(private = "file")
slug_ok :: proc(s: string) -> bool {
	for c in transmute([]u8)s {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
		case: return false
		}
	}
	return true
}

// Takes the files that go beside a program out of the bundle into `folder` (its scratch folder, beside its file), each
// checked against its size and SHA-256. why: "" when they are all there (in the language in use).
take_out_beside :: proc(b: ^Bundle, p: Program, folder: string) -> (why: string) {
	for x in p.beside {
		data, err := archive.read(&b.index, x.file, allocator = context.allocator)
		if err != .None { return i18n.tr("a file that goes beside the program cannot be read from the bundle") }
		defer delete(data)
		if i64(len(data)) != x.size || update.sha256_hex(data, context.temp_allocator) != x.sha256 {
			return i18n.tr("a file that goes beside the program is damaged in the bundle")
		}
		out := join(folder, x.file[strings.last_index_byte(x.file, '/') + 1:], context.temp_allocator)
		if os.write_entire_file(out, data) != nil { return i18n.tr("a file that goes beside the program cannot be written to the scratch folder") }
	}
	return ""
}

// A small file of the bundle (a logo, a licence), whole, on the heap; `failed`: it cannot be read.
bundle_read :: proc(b: ^Bundle, name: string, allocator := context.allocator) -> (data: []u8, failed: bool) {
	d, err := archive.read(&b.index, name, SMALL_FILE_LIMIT, allocator)
	return d, err != .None
}

// 64 lower-case hexadecimal digits, as update.sha256_hex writes them.
@(private = "file")
sha256_ok :: proc(s: string) -> bool {
	if len(s) != 64 { return false }
	for c in transmute([]u8)s {
		switch c {
		case '0' ..= '9', 'a' ..= 'f':
		case: return false
		}
	}
	return true
}

// The program of that slug, or nil.
program_of :: proc(b: ^Bundle, slug: string) -> ^Program {
	for &p in b.programs { if p.slug == slug { return &p } }
	return nil
}

// The flake reference of a program's repository ("github:sachahjkl/papier"), for the line that installs it on NixOS.
// "": the repository is not on GitHub.
flake_of :: proc(p: Program, allocator := context.temp_allocator) -> string {
	PREFIX :: "https://github.com/"
	if !strings.has_prefix(p.repository, PREFIX) { return "" }
	rest := strings.trim_right(p.repository[len(PREFIX):], "/")
	rest = strings.trim_suffix(rest, ".git")
	if rest == "" { return "" }
	return strings.concatenate({"github:", rest}, allocator)
}

// What a person on NixOS types to install a program.
nix_line :: proc(p: Program, allocator := context.temp_allocator) -> string {
	flake := flake_of(p, context.temp_allocator)
	if flake == "" { return "" }
	return strings.concatenate({"nix profile add ", flake}, allocator)
}
