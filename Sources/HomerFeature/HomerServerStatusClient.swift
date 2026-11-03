import ComposableArchitecture
import Foundation
import HomerCore

/// The account menu's server state, for admins. Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerServerStatusClient: Sendable {
	/// When the server started, its clock and its newest run.
	public var status: @Sendable (_ baseURL: String) async throws -> HomerServerStatus
}

extension HomerServerStatusClient: DependencyKey {
	public static let liveValue = HomerServerStatusClient(
		status: { try await HomerAPI.serverStatus(baseURL: $0) }
	)
}

extension HomerServerStatusClient: TestDependencyKey {
	public static let testValue = HomerServerStatusClient()
}
