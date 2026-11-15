// What atelier is to the toolkit's update package (gt:update, docs/update.md): its name in the manifests and the release's
// file names, what its signatures cover, and the public half of its update key (ateliertool update keygen; the private
// half is in secrets/production.yaml and the release workflow's secret UPDATE_SIGNING_KEY). The program checks with it (updates.odin), ateliertool signs
// with it (ateliertool package).
package atelier_update

import update "gt:update"

PRODUCT :: update.Product{
	name         = "atelier",
	sign_context = "atelier-update-v1\n",
	public_key   = "ehDAC3cvEY1h1oKGWn_ZThoEQXuPbqE84puuPfjrRf4",
	// (the update is the release's whole file: the program and the bundle of every program after it, which grows with
	// the suite past the toolkit's 256 MiB bound for a program alone)
	max_binary   = 1 << 30,
}
