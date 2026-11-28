package ateliertool

// The site, made when it is deployed (.github/workflows/pages.yml) so that it cannot be behind a release. The steps are the
// toolkit's (gt:site); this file says what this site is. {{version}} in the home page is the last version of CHANGELOG.md.

import tk_site "gt:site"
import toolbox "gt:toolbox"

VERSION_MARK :: "{{version}}"

// The home page's download, for the reader's system (Windows first: what a phone or an unknown system is offered).
@(rodata)
SITE_DOWNLOADS := [?]tk_site.Download{
	{os = "windows", label = "Windows", href = "https://github.com/sachahjkl/atelier/releases/download/v{{version}}/atelier-{{version}}-windows-x64.exe", detail = "v{{version}} · Windows 10 / 11 · x64 · .exe"},
	{os = "linux", label = "Linux", href = "https://github.com/sachahjkl/atelier/releases/download/v{{version}}/atelier-{{version}}-linux-x64", detail = "v{{version}} · x64 · one executable"},
}

@(rodata)
SITE_LD := [?][2]string{
	{"applicationCategory", "UtilitiesApplication"},
	{"operatingSystem", "Windows, Linux"},
	{"license", "https://opensource.org/license/mit"},
}

site_meta :: proc() -> tk_site.Meta {
	m := tk_site.meta_default("Atelier", "https://atelier.froment.software/", REPOSITORY, "Installer and updater for Froment Software apps", "#111113", "#ec7a43")
	m.ld_fields = SITE_LD[:]
	return m
}

site_command :: proc() -> toolbox.Command {
	return tk_site.command({meta = site_meta(), pages = {version_mark = VERSION_MARK, downloads = SITE_DOWNLOADS[:]}, images = tk_site.images_default()})
}
