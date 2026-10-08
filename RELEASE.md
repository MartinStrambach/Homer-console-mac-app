# Releasing Homer Console

Produces a Developer ID signed, notarized, stapled `.dmg`, published as a GitHub release with the Sparkle feed (`appcast.xml`) that installed copies update from. Same pipeline as Bridge Commander's.

**A release tag is also the package's SwiftPM version** (Bridge Commander depends on `HomerFeature` by version), so app and package share one version line: every release of the app is a release of the package, and a tag is never moved.

## One-time setup

The same credentials as Bridge Commander's release — if that one works on this Mac, so does this:

1. `brew install create-dmg gh`, then `gh auth login`
2. A **Developer ID Application** certificate in the login keychain (`security find-identity -p codesigning -v` lists it as `Developer ID Application: … (TEAMID)`)
3. A notarytool keychain profile:
   ```sh
   xcrun notarytool store-credentials bridge-commander-notary \
     --apple-id <your-apple-id> --team-id <TEAMID>
   ```
   (an [app-specific password](https://support.apple.com/en-us/102654) when prompted). Bridge Commander's profile serves both apps
4. The Sparkle signing key in the login keychain. Both apps use the same key (keychain account `ed25519`, generate_keys' default), so `SUPublicEDKey` in `App/HomerConsole/Info.plist` is Bridge Commander's. After the first `make build-release` the tools are in `build/SourcePackages/artifacts/sparkle/Sparkle/bin/`:
   ```sh
   generate_keys -p          # prints the public key if present
   generate_keys -x key.txt  # back the key up somewhere safe
   generate_keys -f key.txt  # import it on another machine
   ```
   **Losing this key means no installed copy can ever be updated again** — of either app. To give this app a key of its own: `generate_keys --account homer-console`, put the printed public key in `App/HomerConsole/Info.plist`, and set `SPARKLE_KEY_ACCOUNT=homer-console` in `.env.release` (copies already installed keep trusting the old key, so they would need one manual install)
5. `cp .env.release.example .env.release` and fill it in (or copy Bridge Commander's)

## Release

```sh
make check-tools    # verify prerequisites
make release        # check-tools → build-release → notarize-app → dmg → notarize-dmg
make publish        # tag, push the tag, create the GitHub release with the DMG and appcast.xml
```

Output: `dist/HomerConsole-<version>.dmg`. `DRAFT=1 make publish` creates a draft release, to edit the notes first; installed copies are not offered it until it is published.

`make publish` does not rebuild. It refuses if the working tree is dirty, `HEAD` is not pushed, the DMG is missing, unstapled or built from another commit (`dist/.build-revision`), the keychain's Sparkle key is not the app's `SUPublicEDKey`, a release for the version exists, or the version's tag exists on another commit. Release notes are GitHub's generated notes plus the commits pushed straight to `main`; they also go into the appcast, as Markdown in the update dialog.

Installed copies read the feed from `releases/latest/download/appcast.xml` (`SUFeedURL`), which GitHub resolves to the newest published release — publishing is what offers the update.

| Target | Output |
|---|---|
| `make build-release` | `dist/Homer Console.app` (signed, not notarized) |
| `make notarize-app` | same `.app`, stapled |
| `make dmg` | `dist/HomerConsole-<version>.dmg` (signed, not notarized) |
| `make notarize-dmg` | same DMG, stapled |
| `make publish` | GitHub release + tag, with the DMG and `appcast.xml` attached |
| `make clean` | removes `build/` and `dist/` |

## Version bump

Edit `MARKETING_VERSION` in `App/project.yml` and run `xcodegen` in `App/` (`make check-tools` fails while the project disagrees with the YAML). `CFBundleVersion` is `$(MARKETING_VERSION)`: Sparkle compares versions by it, so it must grow with every release. Use semver (`0.3.0`, `0.2.1`): the tag is a SwiftPM version too.

Then, in Bridge Commander, raise the requirement in `Packages/RepositoryFeature/Package.swift` (or File ▸ Packages ▸ Update to Latest Package Versions within the current major) to pick up the package's changes.

## Notes

- `build-release.sh` passes `-skipMacroValidation`: Xcode asks to trust each package macro again whenever its version changes, only interactively, so a command-line build after a dependency bump would fail. The versions are pinned in the app's committed `Package.resolved`
- The app and the package keep separate `Package.resolved` files: the app's (with Sparkle) in `App/HomerConsole.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`, the package's at the root. Without its own, Xcode wrote the app's pins — Sparkle included — into the root file, which `swift build` then pruned again, leaving the tree dirty for `make publish`
- The updater starts only in Release builds; a Debug build runs from DerivedData, where installing an update would replace the build being worked on
- **Notarization rejected** — the scripts print the notarytool log; usual causes are an unsigned binary in the bundle or a revoked certificate
- **Gatekeeper still warns after install** — `xcrun stapler validate "dist/Homer Console.app"` and `xcrun stapler validate dist/HomerConsole-<version>.dmg`
