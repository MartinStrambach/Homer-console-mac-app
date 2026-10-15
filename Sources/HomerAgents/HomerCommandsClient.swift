import ComposableArchitecture
import Foundation
import HomerCore

/// The command bar's part of the Homer API, addressed by the instance's base URL. Errors are
/// `HomerAPIError`s.
@DependencyClient
public struct HomerCommandsClient: Sendable {
	/// The connector's commands the user may run; nil when the server has no such endpoint.
	public var commands: @Sendable (_ baseURL: String) async throws -> HomerCommandList?
	/// Starts a run and returns its process id.
	public var run: @Sendable (_ baseURL: String, _ agentName: String, _ request: HomerAgentRunRequest) async throws -> Int
}

extension HomerCommandsClient: DependencyKey {
	public static let liveValue = HomerCommandsClient(
		commands: { try await HomerAPI.commands(baseURL: $0) },
		run: { try await HomerAPI.runAgent(baseURL: $0, name: $1, request: $2) }
	)
}

extension HomerCommandsClient: TestDependencyKey {
	public static let testValue = HomerCommandsClient()
}
