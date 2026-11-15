package atelier

import "core:fmt"
import "core:os"
import "core:testing"
import archive "gt:archive"
import testkit "gt:testkit"
import update "gt:update"

// A manifest of one program, its file of `size` bytes and SHA-256 `sha` (src/md/README.md, "The bundle").
@(private = "file")
manifest_of :: proc(size: int, sha: string) -> string {
	return fmt.tprintf(`{{"schema": 1, "platform": "linux-x64", "made": "2026-11-15",
 "programs": [{{"slug": "papier", "name": "Papier", "tagline": "A fast clipboard history.",
   "version": "0.23.2", "repository": "https://github.com/sachahjkl/papier", "site": "https://papier.froment.software/",
   "file": "papier/papier", "size": %d, "sha256": "%s", "logo": "papier/logo.png",
   "licences": [{{"title": "MIT License", "file": "papier/LICENSE"}}]}}]}}`, size, sha)
}

// A bundle written after a stand-in for atelier's own bytes, as `ateliertool package` writes it.
@(private = "file")
bundle_write :: proc(t: ^testing.T, dir: string, manifest: string, program: []u8, beside: []u8 = nil) -> string {
	host := join(dir, "host", context.temp_allocator)
	testing.expect(t, os.write_entire_file(host, transmute([]u8)string("\x7fELF stand-in for atelier's bytes")) == nil)
	out := join(dir, "atelier", context.temp_allocator)
	w: archive.Zip_Writer
	archive.zip_begin(&w, out, after = host)
	if manifest != "" { archive.zip_add(&w, MANIFEST, transmute([]u8)manifest) }
	archive.zip_add(&w, "papier/papier", program, mode = 0o755)
	if beside != nil { archive.zip_add(&w, "papier/gt_webp.dll", beside) }
	archive.zip_add(&w, "papier/LICENSE", transmute([]u8)string("MIT License\n\nCopyright (c) 2026\n"))
	testing.expect_value(t, archive.zip_end(&w), archive.Error.None)
	return out
}

@(test)
a_bundle_after_the_program_is_read_back :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "atelier")   // (its cleanup frees it)
	program := transmute([]u8)string("the program's bytes")
	path := bundle_write(t, dir, manifest_of(len(program), update.sha256_hex(program, context.temp_allocator)), program)
	b, err := bundle_open(path)
	testing.expect_value(t, err, Bundle_Error.None)
	if b == nil { return }
	defer bundle_destroy(b)
	testing.expect_value(t, b.platform, "linux-x64")
	testing.expect_value(t, len(b.programs), 1)
	p := b.programs[0]
	testing.expect_value(t, p.slug, "papier")
	testing.expect_value(t, p.version, "0.23.2")
	testing.expect_value(t, len(p.licences), 1)
	testing.expect_value(t, p.licences[0].title, "MIT License")
	text, failed := bundle_read(b, p.licences[0].file)
	defer delete(text)
	testing.expect(t, !failed && string(text) == "MIT License\n\nCopyright (c) 2026\n", "the licence's text is the bundle's")
	data, rerr := archive.read(&b.index, p.file, allocator = context.temp_allocator)
	testing.expect(t, rerr == .None && string(data) == "the program's bytes", "the program's file is the bundle's")
	testing.expect(t, program_of(b, "papier") != nil && program_of(b, "classeur") == nil, "a program is found by its slug")
}

@(test)
a_copy_without_a_bundle_says_so :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "atelier")   // (its cleanup frees it)
	// (a development build: the program's bytes and no zip after them)
	plain := join(dir, "plain", context.temp_allocator)
	testing.expect(t, os.write_entire_file(plain, transmute([]u8)string("\x7fELF no zip here")) == nil)
	b, err := bundle_open(plain)
	testing.expect(t, b == nil && err == .No_Bundle, "a file with no zip carries no programs")
	// (a zip without the manifest)
	path := bundle_write(t, dir, "", transmute([]u8)string("x"))
	b, err = bundle_open(path)
	testing.expect(t, b == nil && err == .No_Bundle, "a zip without the manifest carries no programs")
}

@(test)
a_manifest_that_cannot_be_checked_is_refused :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "atelier")   // (its cleanup frees it)
	program := transmute([]u8)string("the program's bytes")
	for manifest in ([]string{manifest_of(len(program), "not a digest"), manifest_of(0, update.sha256_hex(program, context.temp_allocator)), `{"schema": 2, "programs": []}`, "not JSON"}) {
		path := bundle_write(t, dir, manifest, program)
		b, err := bundle_open(path)
		testing.expectf(t, b == nil && err == .Bad_Manifest, "%q is refused", manifest)
		bundle_destroy(b)
	}
}

// A manifest of one program with one file beside it (src/md/README.md, "What goes beside a program").
@(private = "file")
manifest_beside :: proc(program: []u8, beside_size: int, beside_sha: string) -> string {
	return fmt.tprintf(`{{"schema": 1, "platform": "windows-x64", "made": "2026-11-15",
 "programs": [{{"slug": "papier", "name": "Papier", "tagline": "A fast clipboard history.",
   "version": "0.23.2", "repository": "https://github.com/sachahjkl/papier", "site": "https://papier.froment.software/",
   "file": "papier/papier", "size": %d, "sha256": "%s",
   "beside": [{{"file": "papier/gt_webp.dll", "size": %d, "sha256": "%s"}}],
   "licences": [{{"title": "MIT License", "file": "papier/LICENSE"}}]}}]}}`, len(program), update.sha256_hex(program, context.temp_allocator), beside_size, beside_sha)
}

@(test)
what_goes_beside_a_program_is_taken_out_checked :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "atelier")   // (its cleanup frees it)
	program := transmute([]u8)string("the program's bytes")
	dll := transmute([]u8)string("MZ the library's bytes")
	path := bundle_write(t, dir, manifest_beside(program, len(dll), update.sha256_hex(dll, context.temp_allocator)), program, dll)
	b, err := bundle_open(path)
	testing.expect_value(t, err, Bundle_Error.None)
	if b == nil { return }
	defer bundle_destroy(b)
	p := b.programs[0]
	testing.expect_value(t, len(p.beside), 1)
	if len(p.beside) != 1 { return }
	testing.expect_value(t, p.beside[0].file, "papier/gt_webp.dll")
	// (written beside the program, under its last name)
	good := join(dir, "good", context.temp_allocator)
	testing.expect(t, os.make_directory(good) == nil)
	testing.expect_value(t, take_out_beside(b, p, good), "")
	written, rerr := os.read_entire_file(join(good, "gt_webp.dll", context.temp_allocator), context.temp_allocator)
	testing.expect(t, rerr == nil && string(written) == string(dll), "the file beside is the bundle's")

	// (a SHA-256 that is not the file's: refused, and nothing written)
	wrong := join(dir, "wrong", context.temp_allocator)
	testing.expect(t, os.make_directory(wrong) == nil)
	other := update.sha256_hex(transmute([]u8)string("another file"), context.temp_allocator)
	bad_dir := join(dir, "bad", context.temp_allocator)
	testing.expect(t, os.make_directory(bad_dir) == nil)
	bad_path := bundle_write(t, bad_dir, manifest_beside(program, len(dll), other), program, dll)
	bad, berr := bundle_open(bad_path)
	testing.expect_value(t, berr, Bundle_Error.None)
	if bad == nil { return }
	defer bundle_destroy(bad)
	testing.expect(t, take_out_beside(bad, bad.programs[0], wrong) != "", "a file beside whose SHA-256 differs is refused")
	testing.expect(t, !os.exists(join(wrong, "gt_webp.dll", context.temp_allocator)), "a refused file is not written")
}

@(test)
the_nix_line_names_the_repository :: proc(t: ^testing.T) {
	testing.expect_value(t, nix_line({repository = "https://github.com/sachahjkl/papier"}), "nix profile add github:sachahjkl/papier")
	testing.expect_value(t, nix_line({repository = "https://github.com/sachahjkl/opencode-native/"}), "nix profile add github:sachahjkl/opencode-native")
	testing.expect_value(t, nix_line({repository = "https://example.org/x"}), "")
}
