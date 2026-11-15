# secrets

SOPS files, encrypted for the maintainer's age key (`.sops.yaml`). Read one with `sops -d secrets/production.yaml`.

| Key | What it is |
|---|---|
| `UPDATE_SIGNING_KEY` | the private half of atelier's update key (Ed25519, base64url of its 32 bytes). The release workflow has it as the repository's secret of the same name: `ateliertool package` signs the update manifests with it. Its public half is `PRODUCT.public_key` in `src/update/product.odin`. |

The age identity is the maintainer's, outside every repository: `~/.config/sops/age/keys.txt`.
