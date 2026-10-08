/// `HomerUI`'s public pieces — `homerUIFontScale(_:)`, `HomerLogo` — are part of the console's
/// API to a host, which imports only `HomerFeature`. With `MemberImportVisibility` (a host's or
/// these modules' own) an extension member is visible only through an import of its defining
/// module, so `HomerFeature` re-exports `HomerUI`. Its `DesignSystem` stays `package`, so nothing
/// that would clash with a host's own helpers comes along.
@_exported public import HomerUI
