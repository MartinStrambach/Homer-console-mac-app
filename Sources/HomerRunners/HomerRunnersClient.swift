import ComposableArchitecture
import Foundation
import HomerCore

/// The Runners page's calls, addressed by the instance's base URL. Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerRunnersClient: Sendable {
	/// Every configured runner, with the external ones' live instances.
	public var runners: @Sendable (_ baseURL: String) async throws -> HomerRunners
	/// The runs waiting for a runner to claim them.
	public var queue: @Sendable (_ baseURL: String) async throws -> HomerRunnerQueue
}

extension HomerRunnersClient: DependencyKey {
	public static let liveValue = HomerRunnersClient(
		runners: { try await HomerAPI.runners(baseURL: $0) },
		queue: { try await HomerAPI.runnerQueue(baseURL: $0) }
	)
}

extension HomerRunnersClient: TestDependencyKey {
	public static let testValue = HomerRunnersClient()
}
