/// Every list of runs pages and refreshes alike: the process list and an agent's run history.
package enum HomerProcessListing {
	/// The console's own page size (`pagination.defaultLimit`).
	package static let pageSize = 50
	/// The console's own refresh cadence (`polling.processListInterval`).
	package static let pollInterval: Duration = .seconds(5)
}

/// What a list of runs can do to one of its rows, against the user's grants.
public enum HomerProcessAction: Equatable, Sendable {
	case kill
	case retry
}
