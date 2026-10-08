// swift-tools-version: 6.2
import PackageDescription

/// The Homer console: a native client for any number of Homer instances, as the `HomerFeature`
/// library (embedded by Bridge Commander) and the standalone app in `App/`.
///
/// Layered, each module depending only on the ones above it:
/// - `HomerCore`: the API, sessions and cookies, instance endpoints, shared models and formats
/// - `HomerUI`: text scaling and the views several pages share
/// - `HomerWorkflowGraph`: LangGraph workflow models, their layered layout and the graph views
/// - `HomerSignIn`, `HomerProcessDetail`, `HomerAgents`, `HomerContinuations`, `HomerCosts`:
///   one feature each
/// - `HomerFeature`: the console and its instances, the process list and questions, composing
///   the rest
let package = Package(
	name: "HomerConsole",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "HomerFeature", targets: ["HomerFeature"]),
	],
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.26.1"),
		.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.15.0"),
	],
	targets: [
		.target(
			name: "HomerCore",
			dependencies: [
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		.target(
			name: "HomerUI",
			dependencies: ["HomerCore"]
		),
		.target(
			name: "HomerWorkflowGraph",
			dependencies: ["HomerCore", "HomerUI"]
		),
		.target(
			name: "HomerSignIn",
			dependencies: [
				"HomerCore",
				"HomerUI",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		.target(
			name: "HomerProcessDetail",
			dependencies: [
				"HomerCore",
				"HomerUI",
				"HomerWorkflowGraph",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		.target(
			name: "HomerAgents",
			dependencies: [
				"HomerCore",
				"HomerUI",
				"HomerWorkflowGraph",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		.target(
			name: "HomerContinuations",
			dependencies: [
				"HomerCore",
				"HomerUI",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		.target(
			name: "HomerCosts",
			dependencies: [
				"HomerCore",
				"HomerUI",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		.target(
			name: "HomerFeature",
			dependencies: [
				"HomerCore",
				"HomerUI",
				"HomerSignIn",
				"HomerProcessDetail",
				"HomerAgents",
				"HomerContinuations",
				"HomerCosts",
				.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			]
		),
		testTarget("HomerCore"),
		testTarget("HomerWorkflowGraph"),
		testTarget("HomerSignIn"),
		testTarget("HomerProcessDetail"),
		testTarget("HomerAgents"),
		testTarget("HomerContinuations"),
		testTarget("HomerCosts"),
		testTarget("HomerFeature"),
	]
)

/// `<module>Tests`, with the `.dependencies` trait (DependenciesTestSupport), which gives each
/// test its own `@Shared` app storage.
func testTarget(_ module: String) -> Target {
	.testTarget(
		name: "\(module)Tests",
		dependencies: [
			.byName(name: module),
			.product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
			.product(name: "DependenciesTestSupport", package: "swift-dependencies"),
		]
	)
}

for target in package.targets {
	target.swiftSettings = (target.swiftSettings ?? []) + [
		.treatAllWarnings(as: .error),
		.enableUpcomingFeature("MemberImportVisibility"),
	]
	// Each module's design notes (`Sources/<Module>/README.md`), not a resource.
	if target.type == .regular {
		target.exclude += ["README.md"]
	}
}
