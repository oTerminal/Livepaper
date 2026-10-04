# Releasing Livepaper

How a green build becomes a disk image a stranger can download and open, a zip Sparkle updates from, and an entry in the appcast every installed copy reads. Nothing is notarized: there is no paid Apple Developer account, so each release is signed with the project's own self-signed certificate, which keeps every version the same app to macOS.

## Once, by the owner

Both scripts walk through their steps one at a time, and both refuse to run a second time: another certificate would make every later release a different app to macOS, and another key would make every installed copy refuse every update.

1. `Tools/release/make-cert.sh` makes the self-signed "Livepaper Release" certificate (ten years). It writes `designated-requirement.txt` and the README's copy of it, which you commit. The `.p12` and its password go into your password manager, and into the `release` environment's secrets `LIVEPAPER_SIGNING_P12` (base64) and `LIVEPAPER_SIGNING_P12_PASSWORD`. They go nowhere else.
2. `Tools/release/sparkle-keys.sh` makes Sparkle's EdDSA key pair. The public key goes into `project.yml` as `SUPublicEDKey`, which you commit. The private key goes into your password manager and the secret `SPARKLE_ED_PRIVATE_KEY`, and is then taken out of the login keychain. The script also makes the orphan `appcast` branch and serves it with GitHub Pages at `https://oterminal.github.io/Livepaper/appcast.xml`.

Losing the certificate's private key changes the app's identity for every user. Losing the EdDSA key strands every installed copy on its version.

## Each release

1. Raise the version in `project.yml`, in `settings.base`, which is the only place it lives. Set `MARKETING_VERSION` to the new `X.Y.Z`, and raise `CURRENT_PROJECT_VERSION` by one in the same commit. Sparkle orders updates by the build.
2. Write the release's `## X.Y.Z` section in `CHANGELOG.md`. It becomes the release's notes on GitHub and in Sparkle's update window.
3. Run `make notices` and commit what it writes. The notices name the release, whose GitHub release carries ffmpeg's source, and also the helpers, Sparkle and the samples.
4. Run `make release-dry-run`, then merge.
5. Tag the merge `vX.Y.Z` and push the tag. Nothing else starts a release: `.github/workflows/release.yml` runs `release.sh` in the `release` environment.

The workflow refuses, with the reason in its log and nothing published, when any of these hold:

- the tag is not `v` plus `MARKETING_VERSION`
- the build is not above the appcast's last
- the release exists already
- the signature is ad-hoc or by another certificate
- a secret is missing
- `CHANGELOG.md` has no section for the version
- the notices in `Credits.rtf` or the README are stale
- anything `verify.sh` refuses

## The scripts

| Script | Does |
|---|---|
| `release.sh [--dry-run]` | Runs the release in order: the refusals, a Release build, the certificate in a run-scoped keychain (deleted on any exit), sign, package, verify, the appcast, then the GitHub release and the appcast branch. `--dry-run` runs every step except publishing, signs ad-hoc with a throwaway EdDSA key, and writes into `build/release/`. CI runs it on every pull request |
| `sign.sh <app> --identity <name\|->` | Signs inside-out, in the order `release-kit signing-order` prints. It never uses `--deep` or the hardened runtime. It refuses a Mach-O the order does not place and a certificate it has no record of, and finishes with `codesign --verify --strict` and `-R` against the recorded requirements |
| `package.sh <app> --out <dir>` | Makes `Livepaper-<version>.dmg`, holding the app, an `Applications` link and `Licenses/`, using `diskutil image create` where the Mac has it, else `hdiutil`. Also makes `Livepaper-<version>.zip` for Sparkle. Refuses anything over the 50 MB budget |
| `verify.sh <dmg> <zip>` | Mounts the image and checks it: the signature and both requirements; the extension's two entitlements, and none on the app; each helper against its `BUILD-INFO.txt`; the samples against `PROVENANCE.md`; the notices and `Licenses/`; that the zip has the same cdhash; and, with `--install` on CI, `pluginkit` after an install |
| `appcast.sh fetch \| make \| publish \| init` | Reads the published feed, signs a release's zip with `generate_appcast` and merges it in, and pushes the `appcast` branch |
| `make-cert.sh`, `sparkle-keys.sh` | The owner's one-time steps above |

`release-kit` (`Sources/`) is the logic the scripts call, test-first in `ReleaseKit` (`swift test --package-path Tools/release`, in `make test`). It covers the signing order, the requirement, the version rules, the appcast and its notes, and the notices. `sparkle.env` pins Sparkle's tool archive by sha256, at the same version `project.yml` pins the package.

Secrets reach the scripts only as environment variables. No script runs under `set -x`, and none prints a secret. A key lives in a file only for the step that reads it, in a folder only the runner can read.
