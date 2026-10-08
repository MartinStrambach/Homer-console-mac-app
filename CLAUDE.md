# Homer Console for Mac - Claude Code Guide

Native macOS client for Homer consoles: the `HomerFeature` Swift package (embedded by Bridge Commander as its Homer section) plus a standalone app in `App/`. SwiftUI + TCA (Composable Architecture).

## Tech Stack
- Swift 6.2+ toolchain (`swift-tools-version: 6.2`; Swift 6 language mode)
- SwiftUI, Composable Architecture (TCA), swift-dependencies, swift-sharing
- macOS 26.0+, Xcode 26.2+

## Structure

The module layout, how a host embeds the console and the notes that hold across modules are in `README.md`; each module's design notes and gotchas are in `Sources/<Module>/README.md` (the tests' in `Tests/README.md`) — **read the README of the module you are about to change before editing it**, and record new non-obvious decisions there.

- `Sources/<Module>/` — nine modules, layered: `HomerCore` → `HomerUI` → `HomerWorkflowGraph` → feature modules (`HomerSignIn`, `HomerProcessDetail`, `HomerAgents`, `HomerContinuations`, `HomerCosts`) → `HomerFeature`. A module never imports one below it; when two features need the same thing, it moves up (shared models and API helpers to `HomerCore`, shared views to `HomerUI/Components`)
- `Tests/<Module>Tests/` — one Swift Testing target per module
- `App/` — the standalone app; `HomerConsole.xcodeproj` is generated from `App/project.yml` by `xcodegen` (run in `App/`), never edited by hand

## Access control
- `HomerFeature` is the only product. What modules share among themselves is `package`; `public` is only for the console's API to a host (`HomerConsoleReducer`, `HomerConsoleView`, `HomerConsoleTitle`, `homerUIFontScale(_:)`, `HomerSymbols`) and the types its public state and actions expose
- A `package` view or struct used from another module needs an explicit `package init` — the memberwise one is internal
- `HomerFeature` re-exports `HomerUI` (`Sources/HomerFeature/Exports.swift`), so a host gets `homerUIFontScale(_:)` and `HomerSymbols` from `import HomerFeature` alone — a host with `MemberImportVisibility` on would otherwise need `import HomerUI`, a module that is not a product
- `HomerUI/DesignSystem` stays `package`: public extension members named like the host's own (`scaledFont`, `scaledBordered`, …) would make every call in the host ambiguous

## Patterns
- Reducers hold state and effects; state is mutated only in reducers; async work in `Effect.run`, sending result actions
- Each page adds its calls as a `HomerAPI` extension in its own file (`Homer<Page>API.swift`, through `HomerAPI.send`/`decode`) and its own `@DependencyClient` (`Homer<Page>Client.swift`), rather than growing `HomerClient`
- Text scaling in every view: `.scaledFont(.caption)` / `.scaledFont(size: 12)` instead of `.font(...)`, and `.buttonStyle(.scaledBordered)` / `.scaledBorderedProminent` / `.scaledAutomatic` on text buttons
- Indent with tabs

## Build & Test
- `swift build`, `swift test` (or `swift test --filter <Module>Tests`)
- Warnings are errors: every target, tests included (the loop at the end of `Package.swift`; a new target gets it automatically)
- Imports are explicit: the same loop enables `MemberImportVisibility` (and the app target `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, as Bridge Commander does), so a file imports every module whose members it uses — another file's import, or a module imported only transitively, no longer makes them visible
- In `TestStore` assertions, mutate `@Shared` state as `$0.$x.withLock { $0 = … }`
- Bridge Commander builds the package with TCA's `ComposableArchitecture2Deprecations` trait on, which a package build does not: build Bridge Commander against the checkout before tagging a release
- App: `xcodebuild -project App/HomerConsole.xcodeproj -scheme HomerConsole -destination 'platform=macOS' build` (add `-skipMacroValidation` from the command line)
- Known issues in a test run come from `skipInFlightEffects()` (TCA reports skipped effects that way) and are expected

## Release
- `make release` then `make publish` (RELEASE.md): Developer ID build, notarization, DMG, GitHub release with the Sparkle `appcast.xml`. The tag it creates is also the package's SwiftPM version — bump `MARKETING_VERSION` in `App/project.yml` (then `xcodegen`), never move a tag
- Sparkle (updates) is in the app target only (`App/HomerConsole/`), never in the package: Bridge Commander has its own updater
