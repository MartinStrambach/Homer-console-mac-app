import ComposableArchitecture
import Foundation
import HomerCore

/// The maintenance-mode toggle's part of the Homer API, for admins. Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerMaintenanceClient: Sendable {
	/// The mode with its start time and queue.
	public var maintenance: @Sendable (_ baseURL: String) async throws -> HomerMaintenance
	/// Turns the mode on or off and answers its new state.
	public var setMaintenance: @Sendable (_ baseURL: String, _ enabled: Bool) async throws -> HomerMaintenance
}

extension HomerMaintenanceClient: DependencyKey {
	public static let liveValue = HomerMaintenanceClient(
		maintenance: { try await HomerAPI.maintenance(baseURL: $0) },
		setMaintenance: { try await HomerAPI.setMaintenance(baseURL: $0, enabled: $1) }
	)
}

extension HomerMaintenanceClient: TestDependencyKey {
	public static let testValue = HomerMaintenanceClient()
}
